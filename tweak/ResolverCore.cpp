#include "ResolverCore.hpp"
#ifdef SH_USE_GUM
#ifdef __arm64e__
#include "../vendor/frida-gum/arm64e/frida-gum.h"
#else
#include "../vendor/frida-gum/arm64/frida-gum.h"
#endif
#else
#include <capstone/capstone.h>
#endif
#include <algorithm>
#include <array>
#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <set>

namespace shresolve {
// Check whether the entire byte span fits in one mapped range. Subtraction-based
// bounds checks avoid overflowing the requested end address.
bool Image::contains(Address a, size_t n) const {
    for (auto &r : ranges)
        if (a >= r.address && n <= r.size && a - r.address <= r.size - n)
            return true;
    return false;
}
// Accept only four-byte-aligned AArch64 instruction addresses inside a code range.
bool Image::code(Address a) const {
    for (auto &r : ranges)
        if (r.code && a >= r.address && a - r.address < r.size)
            return a % 4 == 0;
    return false;
}
// Read one 64-bit pointer through the image reader, then apply pointer cleanup.
// Return zero on read failure; range validation is left to the reader/caller.
Address Image::pointer(Address a) const {
    Address v = 0;
    if (!read(a, &v, 8))
        return 0;
    return clean(v);
}
// Read a bounded, NUL-terminated printable ASCII string from mapped image bytes.
// Return an empty string for unreadable, non-ASCII or unterminated input (and for "").
std::string Image::string(Address a, size_t max) const {
    std::string s;
    for (size_t i = 0; i < max; i++) {
        char c;
        if (!contains(a + i) || !read(a + i, &c, 1))
            return {};
        if (!c)
            return s;
        if ((unsigned char)c < 32 || (unsigned char)c > 126)
            return {};
        s += c;
    }
    return {};
}
// Record a discovered address/offset and its evidence for diagnostics. A zero value
// records a missing-result error instead of installing an unusable plan entry.
void Plan::set(const std::string &k, Address v, const std::string &s) {
    if (!v) {
        errors.push_back(k + ": missing");
        return;
    }
    values[k] = v;
    sources[k] = s;
}
struct D {
    unsigned id;
    Address address;
    cs_arm64 a;
};
class Decoder {
  public:
    csh cs = 0;
    // Initialize an ARM64 Capstone handle with operand details enabled. Allocation
    // callbacks and optional devkit architecture registration are configured once.
    Decoder() {
        // Frida's devkit requires explicit architecture registration and memory setup.
        // Configure only Capstone; no Gum/GLib initialization or process-wide cache.
        static const bool configured = []() {
#ifdef SH_USE_GUM
            cs_arch_register_arm64();
#endif
            cs_opt_mem memory = {malloc, calloc, realloc, free, vsnprintf};
            return cs_option(0, CS_OPT_MEM, (size_t)&memory) == CS_ERR_OK;
        }();
        if (configured && cs_open(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN, &cs) == CS_ERR_OK)
            cs_option(cs, CS_OPT_DETAIL, CS_OPT_ON);
    }
    // Release this decoder's Capstone handle if initialization opened one.
    ~Decoder() {
        if (cs)
            cs_close(&cs);
    }
    // Copy and decode a byte window, retaining only instruction IDs, PCs and ARM64
    // details. Return an empty result on read/allocation failure; decoding may stop
    // before the end of the window when Capstone cannot decode the next instruction.
    std::vector<D> bytes(const Image &m, Address a, size_t n) {
        std::vector<uint8_t> b(n);
        if (!n || !m.read(a, b.data(), n))
            return {};
        const uint8_t *code = b.data();
        size_t remaining = n;
        uint64_t pc = a;
        cs_insn *instruction = cs_malloc(cs);
        if (!instruction)
            return {};
        std::vector<D> out;
        // Keep one Capstone detail object instead of an allocated array for the full
        // function. This bounds decoder overhead inside CommCenter's memory budget.
        while (cs_disasm_iter(cs, &code, &remaining, &pc, instruction))
            if (instruction->detail)
                out.push_back({instruction->id, instruction->address, instruction->detail->arm64});
        cs_free(instruction, 1);
        return out;
    }
    // Decode from a code address up to the next sorted function boundary, with a
    // 64 KiB limit. Missing boundaries or invalid code addresses yield no instructions.
    std::vector<D> function(const Image &m, Address a) {
        if (!m.code(a))
            return {};
        auto it = std::upper_bound(m.functions.begin(), m.functions.end(), a);
        if (it == m.functions.end() || *it - a > 65536)
            return {};
        return bytes(m, a, *it - a);
    }
    // Normalize supported W/X register aliases to indices 0..31 (SP is 31).
    // Return -1 for registers outside this lightweight tracker's model.
    int reg(unsigned r) {
        if (r == ARM64_REG_SP || r == ARM64_REG_WSP)
            return 31;
        if (r == ARM64_REG_X29)
            return 29;
        if (r == ARM64_REG_X30)
            return 30;
        if (r >= ARM64_REG_X0 && r <= ARM64_REG_X28)
            return r - ARM64_REG_X0;
        if (r >= ARM64_REG_W0 && r <= ARM64_REG_W30)
            return r - ARM64_REG_W0;
        return -1;
    }
};
// Identify an explicit register operand before accessing its register identifier.
static bool regop(const cs_arm64_op &o) { return o.type == ARM64_OP_REG; }
// Identify an immediate operand before interpreting its integer value.
static bool immop(const cs_arm64_op &o) { return o.type == ARM64_OP_IMM; }
// Accept base-plus-displacement memory operands without a register index, matching
// the field-access patterns understood by the trackers below.
static bool memop(const cs_arm64_op &o) {
    return o.type == ARM64_OP_MEM && o.mem.index == ARM64_REG_INVALID;
}
// Infer the modeled access width from byte/halfword opcodes or a W/X register.
// For LDP this describes one loaded element, not the combined pair width.
static int width(const D &i, unsigned reg) {
    if (i.id == ARM64_INS_LDRB || i.id == ARM64_INS_STRB || i.id == ARM64_INS_STURB)
        return 1;
    if (i.id == ARM64_INS_LDRH || i.id == ARM64_INS_STRH || i.id == ARM64_INS_STURH)
        return 2;
    if (reg >= ARM64_REG_W0 && reg <= ARM64_REG_W30)
        return 4;
    return 8;
}
// Apply Capstone's shift amount to an immediate used by modeled ADD instructions.
static Address shifted(const cs_arm64_op &o) { return (Address)o.imm << o.shift.value; }
// Collect addresses modeled by ADR/ADRP, immediate ADD and register MOV in linear
// instruction order. Clear caller-saved values at BL and modeled load destinations;
// this limited tracker does not prove references across control-flow paths.
static std::vector<Address> refs(Decoder &d, const std::vector<D> &ins) {
    std::array<Address, 32> v{};
    std::vector<Address> out;
    for (auto &i : ins) {
        auto &a = i.a;
        int r = a.op_count && regop(a.operands[0]) ? d.reg(a.operands[0].reg) : -1;
        if ((i.id == ARM64_INS_ADR || i.id == ARM64_INS_ADRP) && r >= 0 && a.op_count >= 2) {
            v[r] = a.operands[1].imm;
            out.push_back(v[r]);
        } else if (i.id == ARM64_INS_ADD && r >= 0 && a.op_count == 3 && regop(a.operands[1]) &&
                   immop(a.operands[2])) {
            int b = d.reg(a.operands[1].reg);
            v[r] = b >= 0 && v[b] ? v[b] + shifted(a.operands[2]) : 0;
            if (v[r])
                out.push_back(v[r]);
        } else if (i.id == ARM64_INS_MOV && r >= 0 && a.op_count == 2 && regop(a.operands[1])) {
            int b = d.reg(a.operands[1].reg);
            v[r] = b >= 0 ? v[b] : 0;
        } else if (i.id == ARM64_INS_BL) {
            for (int j = 0; j < 19; j++)
                v[j] = 0;
        } else if ((i.id == ARM64_INS_LDR || i.id == ARM64_INS_LDRB || i.id == ARM64_INS_LDP) &&
                   r >= 0) {
            v[r] = 0;
            if (i.id == ARM64_INS_LDP && a.op_count > 1) {
                int b = d.reg(a.operands[1].reg);
                if (b >= 0)
                    v[b] = 0;
            }
        }
    }
    return out;
}
// Try to resolve a 32-byte ADR[P]/ADD/LDR indirect branch stub, including PAC branch
// forms. Return the original target if no tracked branch destination is recovered.
static Address stub(Decoder &d, const Image &m, Address target) {
    if (!m.code(target))
        return target;
    auto ins = d.bytes(m, target, 32);
    std::array<Address, 32> v{};
    for (auto &i : ins) {
        auto &a = i.a;
        int r = a.op_count && regop(a.operands[0]) ? d.reg(a.operands[0].reg) : -1;
        if ((i.id == ARM64_INS_ADRP || i.id == ARM64_INS_ADR) && r >= 0)
            v[r] = a.operands[1].imm;
        else if (i.id == ARM64_INS_ADD && r >= 0 && a.op_count == 3 && immop(a.operands[2])) {
            int b = d.reg(a.operands[1].reg);
            v[r] = b >= 0 && v[b] ? v[b] + shifted(a.operands[2]) : 0;
        } else if (i.id == ARM64_INS_LDR && r >= 0 && a.op_count == 2 && memop(a.operands[1])) {
            int b = d.reg(a.operands[1].mem.base);
            v[r] = b >= 0 && v[b] ? m.pointer(v[b] + a.operands[1].mem.disp) : 0;
        } else if ((i.id == ARM64_INS_BR || i.id == ARM64_INS_BRAA || i.id == ARM64_INS_BRAAZ ||
                    i.id == ARM64_INS_BRAB || i.id == ARM64_INS_BRABZ) &&
                   r >= 0 && v[r])
            return v[r];
    }
    return target;
}
struct Use {
    int argument;
    int displacement;
    int bytes;
    unsigned id;
    Address pc;
};
// Track MOV aliases of incoming arguments x0..x7 and record supported loads from
// them as argument/offset/width evidence. Clear modeled overwritten registers and
// caller-saved origins at BL; this is a linear heuristic, not control-flow analysis.
static std::vector<Use> loads(Decoder &d, const std::vector<D> &ins) {
    std::array<int, 32> origin;
    origin.fill(-1);
    for (int i = 0; i < 8; i++)
        origin[i] = i;
    std::vector<Use> out;
    for (auto &i : ins) {
        auto &a = i.a;
        int r = a.op_count && regop(a.operands[0]) ? d.reg(a.operands[0].reg) : -1;
        if (i.id == ARM64_INS_MOV && r >= 0 && a.op_count == 2) {
            int b = regop(a.operands[1]) ? d.reg(a.operands[1].reg) : -1;
            origin[r] = b >= 0 ? origin[b] : -1;
        } else if (i.id == ARM64_INS_LDR || i.id == ARM64_INS_LDRB || i.id == ARM64_INS_LDRH ||
                   i.id == ARM64_INS_LDP) {
            int mi = i.id == ARM64_INS_LDP ? 2 : 1;
            if (a.op_count > mi && memop(a.operands[mi])) {
                auto &m = a.operands[mi].mem;
                int b = d.reg(m.base);
                if (b >= 0 && origin[b] >= 0)
                    out.push_back(
                        {origin[b], m.disp, width(i, a.operands[0].reg), i.id, i.address});
            }
            if (r >= 0)
                origin[r] = -1;
            if (i.id == ARM64_INS_LDP) {
                int b = d.reg(a.operands[1].reg);
                if (b >= 0)
                    origin[b] = -1;
            }
        } else if (i.id == ARM64_INS_BL) {
            for (int j = 0; j < 19; j++)
                origin[j] = -1;
        } else if ((i.id == ARM64_INS_ADD || i.id == ARM64_INS_SUB || i.id == ARM64_INS_ADRP ||
                    i.id == ARM64_INS_ADR || i.id == ARM64_INS_MOVK) &&
                   r >= 0)
            origin[r] = -1;
    }
    return out;
}
// Collapse duplicate evidence and require exactly one distinct candidate. Record
// an ambiguity/missing-candidate error and return zero otherwise.
static Address only(Plan &p, const std::vector<Address> &v, const std::string &label) {
    std::set<Address> s(v.begin(), v.end());
    if (s.size() != 1) {
        p.errors.push_back(label + ": expected unique candidate, got " + std::to_string(s.size()));
        return 0;
    }
    return *s.begin();
}
struct Table {
    Address address;
    std::string name;
    std::vector<Address> entries;
};
// Find selected controller/APDU-closure RTTI records in non-code ranges, then
// recover primary vtable address points with zero offset-to-top and 4..96 contiguous
// executable entries. Return only the tables relevant to this transport adapter.
static std::vector<Table> tables(const Image &m) {
    std::map<Address, std::string> types;
    for (auto &r : m.ranges) {
        if (r.code)
            continue;
        for (Address a = (r.address + 7) & ~Address(7); a + 8 <= r.address + r.size; a += 8) {
            Address p = m.pointer(a);
            if (!m.contains(p) || !m.pointer(a - 8))
                continue;
            char first = 0;
            if (!m.read(p, &first, 1) || (first != 'N' && first != '2'))
                continue;
            auto name = m.string(p);
            if (name == "23SubscriberSimController" ||
                (name.find("__function6__func") != std::string::npos &&
                 name.find("sendSimSingleApduCommand_sync") != std::string::npos))
                types[a - 8] = name;
        }
    }
    std::vector<Table> out;
    for (auto &r : m.ranges) {
        if (r.code)
            continue;
        for (Address a = (r.address + 7) & ~Address(7); a + 24 <= r.address + r.size; a += 8) {
            auto it = types.find(m.pointer(a));
            if (it == types.end())
                continue;
            Address top = 1;
            if (!m.read(a - 8, &top, 8) || top)
                continue;
            Table t{a + 8, it->second, {}};
            for (size_t j = 0; j < 96; j++) {
                Address fn = m.pointer(t.address + j * 8);
                if (!m.code(fn))
                    break;
                t.entries.push_back(fn);
            }
            if (t.entries.size() >= 4)
                out.push_back(t);
        }
    }
    return out;
}
// Test whether the modeled PC-relative references in a function include target.
// A false result also covers functions that cannot be decoded.
static bool hasref(Decoder &d, const Image &m, Address fn, Address target) {
    auto r = refs(d, d.function(m, fn));
    return std::find(r.begin(), r.end(), target) != r.end();
}
// Build a static transport plan from driver symbols, callback load patterns, RTTI
// and CommCenter instruction references. Require unique candidates and compatible
// driver signatures; failures return a partial plan with errors and complete=false.
// This does not install hooks, invoke private functions or infer live-object fields.
Plan resolve(const Image &cc, const Image &dr, const std::vector<Symbol> &symbols, Address ready) {
    Plan p;
    Decoder d;
    if (!d.cs) {
        p.errors.push_back("Capstone ARM64 initialization failed");
        return p;
    }
    std::vector<Address> start, command, close, callbacks;
    // Normalize demangled signature whitespace before comparing adapter ABI shapes.
    // The predicate removes only spaces, tabs and newlines.
    auto signature = [](std::string name) {
        name.erase(
            std::remove_if(name.begin(), name.end(),
                           [](unsigned char c) { return c == ' ' || c == '\t' || c == '\n'; }),
            name.end());
        return name;
    };
    // These are interface shapes used by this adapter, not firmware signatures.
    const std::string prefix = "subscriber::EURSimCommandDriver::";
    const std::string vector = "std::__1::vector<unsignedchar,std::__1::allocator<unsignedchar>>";
    const std::string function = "std::__1::function<void(bool)>";
    const std::string startSignature =
        prefix + "sendSimApdu_start(subscriber::HardwareSimSlot," + vector +
        "const&,void(subscriber::HardwareSimSlot,unsignedchar)block_pointer," + function + ")";
    const std::string commandSignature =
        prefix + "sendSimApdu_command(subscriber::HardwareSimSlot,unsignedchar,unsignedchar," +
        vector + "&," + function + ")";
    const std::string closeSignature =
        prefix + "sendSimApdu_close(subscriber::HardwareSimSlot,unsignedchar,bool," + function +
        ")";
    for (auto &s : symbols) {
        if (!dr.code(s.address) ||
            !std::binary_search(dr.functions.begin(), dr.functions.end(), s.address) ||
            s.name.find("subscriber::EURSimCommandDriver::") == std::string::npos)
            continue;
        bool block = s.name.find("block in") != std::string::npos;
        if (!block && s.name.find("::sendSimApdu_start(") != std::string::npos) {
            if (signature(s.name) != startSignature)
                p.errors.push_back(
                    "driverStart parameter signature is incompatible with the transport adapter");
            start.push_back(s.address);
        }
        if (!block && s.name.find("::sendSimApdu_command(") != std::string::npos) {
            if (signature(s.name) != commandSignature)
                p.errors.push_back(
                    "driverCommand parameter signature is incompatible with the transport adapter");
            command.push_back(s.address);
        }
        if (!block && s.name.find("::sendSimApdu_close(") != std::string::npos) {
            if (signature(s.name) != closeSignature)
                p.errors.push_back(
                    "driverClose parameter signature is incompatible with the transport adapter");
            close.push_back(s.address);
        }
        if (block && s.name.find("::sendSimApdu_command(") != std::string::npos)
            callbacks.push_back(s.address);
    }
    p.set("driverStart", only(p, start, "driverStart"),
          "Module-scoped private symbol + image/function boundary");
    p.set("driverCommand", only(p, command, "driverCommand"),
          "Module-scoped private symbol + image/function boundary");
    p.set("driverClose", only(p, close, "driverClose"),
          "Module-scoped private symbol + image/function boundary");
    if (!p.errors.empty())
        return p;
    p.signaturesValidated = true;
    // Classify command callbacks by response-vector loads, slot captures and QMI
    // error/close behavior before deriving their captured-field offsets.
    std::vector<Address> encoders, responses, qmis;
    std::map<Address, std::vector<Use>> uses;
    for (Address f : callbacks) {
        auto ins = d.function(dr, f);
        auto u = loads(d, ins);
        uses[f] = u;
        bool vec0 = false, vec8 = false, slot = false, qmiError = false, closeCall = false;
        for (auto &v : u) {
            if (v.argument == 1 && v.id == ARM64_INS_LDP && v.displacement == 0)
                vec0 = true;
            if (v.argument == 1 && v.id == ARM64_INS_LDP && v.displacement == 8)
                vec8 = true;
            if (v.argument == 0 && v.bytes == 4 && v.displacement > 0)
                slot = true;
            if (v.argument == 1 && v.bytes == 4 && v.id == ARM64_INS_LDR && v.displacement >= 0 &&
                v.displacement < 32)
                qmiError = true;
        }
        for (auto &i : ins)
            if (i.id == ARM64_INS_BL && i.a.operands[0].imm == (int64_t)p.values["driverClose"])
                closeCall = true;
        if (vec8)
            encoders.push_back(f);
        if (vec0 && slot)
            responses.push_back(f);
        if (qmiError && closeCall)
            qmis.push_back(f);
    }
    p.set("encoder", only(p, encoders, "encoder"), "command block + vector tail + byte capture");
    p.set("response", only(p, responses, "response"),
          "command block + vector span + hardware slot load");
    p.set("qmi", only(p, qmis, "qmi"), "command block + QMI result + close call graph");
    if (!p.errors.empty())
        return p;
    for (auto key : {"encoder", "response", "qmi"}) {
        std::vector<Address> bytes, words;
        for (auto &u : uses[p.values[key]]) {
            if (u.argument == (std::string(key) == "qmi" ? 1 : 0) && u.displacement > 0) {
                if (u.bytes == 1)
                    bytes.push_back(u.displacement);
                if (u.bytes == 4)
                    words.push_back(u.displacement);
            }
        }
        if (std::string(key) == "encoder") {
            std::set<Address> pair(bytes.begin(), bytes.end());
            if (pair.size() != 2 || *pair.rbegin() != *pair.begin() + 1) {
                p.errors.push_back(
                    "encoder channel/instruction captures are not a unique byte pair");
                return p;
            }
            p.set("encoderChannel", *std::min_element(bytes.begin(), bytes.end()),
                  "Capstone LDRB from encoder block");
        }
        if (std::string(key) == "response") {
            p.set("responseSlot", only(p, words, "response slot"),
                  "Capstone slot load from APDU response block");
            std::set<Address> pair(bytes.begin(), bytes.end());
            if (pair.size() != 2 || *pair.begin() != p.values["responseSlot"] + 4 ||
                *pair.rbegin() != *pair.begin() + 1) {
                p.errors.push_back("response slot/channel/instruction captures disagree");
                return p;
            }
            p.set("responseChannel", *std::min_element(bytes.begin(), bytes.end()),
                  "Capstone response block channel/instruction byte captures");
        }
        if (std::string(key) == "qmi")
            p.set("qmiError", only(p, words, "QMI error field"),
                  "Capstone word load from QMI response argument");
    }
    if (!p.errors.empty())
        return p;
    // Connect controller and closure RTTI to completion, sender and worker code.
    auto ts = tables(cc);
    std::vector<Address> controller, voidTasks, boolTasks;
    for (auto &t : ts) {
        if (t.name == "23SubscriberSimController")
            controller.push_back(t.address);
        else if (t.name.find("__funcIZZN") != std::string::npos)
            boolTasks.push_back(t.address);
        else if (t.name.find("__funcIZN") != std::string::npos &&
                 t.name.find("Fvv") != std::string::npos)
            voidTasks.push_back(t.address);
    }
    p.set("controllerVtable", only(p, controller, "controller vtable"),
          "C++ RTTI name + zero offset-to-top + executable entries");
    Address task = only(p, voidTasks, "APDU task RTTI");
    Address boolean = only(p, boolTasks, "APDU completion RTTI");
    if (!p.errors.empty())
        return p;
    std::vector<Address> complete;
    // Select the previously validated completion table by its address point.
    auto bt = std::find_if(ts.begin(), ts.end(), [&](auto &t) { return t.address == boolean; });
    for (Address f : bt->entries)
        for (auto &i : d.function(cc, f))
            if (i.id == ARM64_INS_LDRB && i.a.op_count == 2 && d.reg(i.a.operands[0].reg) == 1 &&
                memop(i.a.operands[1]) && d.reg(i.a.operands[1].mem.base) == 1 &&
                i.a.operands[1].mem.disp == 0)
                complete.push_back(f);
    p.set("completion", only(p, complete, "completion invoke"),
          "APDU bool closure RTTI + bool-reference invoke instruction");
    if (!p.errors.empty())
        return p;
    // Select the unique controller table whose methods can reference the APDU task.
    auto ct = std::find_if(ts.begin(), ts.end(),
                           [&](auto &t) { return t.address == p.values["controllerVtable"]; });
    std::vector<Address> senders, workers;
    for (Address f : ct->entries) {
        for (Address target : refs(d, d.function(cc, f))) {
            if (!cc.code(target) ||
                !std::binary_search(cc.functions.begin(), cc.functions.end(), target))
                continue;
            if (hasref(d, cc, target, task)) {
                senders.push_back(f);
                workers.push_back(target);
            }
        }
    }
    p.set("sender", only(p, senders, "sender"),
          "controller virtual method -> worker -> named APDU task RTTI");
    p.set("worker", only(p, workers, "worker"),
          "PC-relative worker reference + named task constructor");
    p.set("isReady", ready, "exported subscriber::isSimReady");
    if (!p.errors.empty())
        return p;
    // The call immediately preceding isSimReady supplies the SimInfo state getter.
    auto worker = d.function(cc, p.values["worker"]);
    std::vector<Address> states;
    Address previous = 0;
    for (auto &i : worker)
        if (i.id == ARM64_INS_BL) {
            Address call = i.a.operands[0].imm;
            if (stub(d, cc, call) == ready && previous && cc.code(previous))
                states.push_back(previous);
            previous = call;
        }
    p.set("simState", only(p, states, "SimInfo state getter"),
          "worker call immediately preceding exported isSimReady");
    if (!p.errors.empty())
        return p;
    // Recognize vector-bound loads followed by a shared-pointer pointee load and
    // logical-slot word load, then require unique member displacements.
    std::vector<Address> vectors, logical;
    for (size_t i = 0; i < worker.size(); i++) {
        auto &a = worker[i].a;
        if (worker[i].id != ARM64_INS_LDP || a.op_count != 3 || !memop(a.operands[2]) ||
            d.reg(a.operands[2].mem.base) == 31 || a.operands[2].mem.disp <= 0)
            continue;
        int cursor = d.reg(a.operands[0].reg);
        for (size_t j = i + 1; j < std::min(worker.size(), i + 8); j++) {
            auto &b = worker[j].a;
            if (worker[j].id != ARM64_INS_LDR || b.op_count != 2 || !memop(b.operands[1]) ||
                d.reg(b.operands[1].mem.base) != cursor || b.operands[1].mem.disp)
                continue;
            int object = d.reg(b.operands[0].reg);
            for (size_t k = j + 1; k < std::min(worker.size(), j + 4); k++) {
                auto &c = worker[k].a;
                if (worker[k].id == ARM64_INS_LDR && c.op_count == 2 && memop(c.operands[1]) &&
                    d.reg(c.operands[1].mem.base) == object &&
                    width(worker[k], c.operands[0].reg) == 4 && c.operands[1].mem.disp > 0) {
                    vectors.push_back(a.operands[2].mem.disp);
                    logical.push_back(c.operands[1].mem.disp);
                }
            }
        }
    }
    p.set("simVector", only(p, vectors, "SimInfo vector"),
          "worker LDP vector bounds -> shared_ptr node -> slot comparison");
    p.set("logicalSlot", only(p, logical, "logical slot"), "worker slot comparison load");
    p.complete = p.errors.empty();
    return p;
}
// Search readable registry pointer chains for one object with the resolved vtable.
// Inspect 32 root words and eight words per node, capped at 512 steps per chain and
// 2,048 visited nodes overall. Clean pointers without invoking candidate objects;
// return zero for an invalid root, failed root read, no match or ambiguous matches.
Address findController(Address root, Address vtable,
                       const std::function<bool(Address, void *, size_t)> &read,
                       const std::function<Address(Address)> &clean) {
    if (!root || !vtable)
        return 0;
    Address roots[32] = {};
    if (!read(root, roots, sizeof roots))
        return 0;
    std::set<Address> visited, found;
    // Follow potential unordered-map chains, inspecting pointer-sized value members.
    // No Registry/STL member offset is assumed, and no candidate is invoked.
    for (Address raw : roots) {
        Address node = clean(raw);
        for (size_t depth = 0; depth < 512 && visited.size() < 2048; depth++) {
            if (node < 0x10000 || node % 8 || !visited.insert(node).second)
                break;
            Address words[8] = {};
            if (!read(node, words, sizeof words))
                break;
            if (clean(words[0]) == vtable)
                found.insert(node);
            for (Address value : words) {
                Address candidate = clean(value), head = 0;
                if (candidate >= 0x10000 && candidate % 8 == 0 && read(candidate, &head, 8) &&
                    clean(head) == vtable)
                    found.insert(candidate);
            }
            node = clean(words[0]);
        }
    }
    return found.size() == 1 ? *found.begin() : 0;
}
} // namespace shresolve
