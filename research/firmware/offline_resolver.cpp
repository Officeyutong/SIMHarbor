// Replay ResolverCore against modeled firmware memory; never execute target code.
#include "../../tweak/ResolverCore.hpp"
#include "../../vendor/nlohmann/json.hpp"
#include <cstring>
#include <fstream>
#include <iostream>
#include <memory>
using Json = nlohmann::json;
struct Region {
    uint64_t address;
    std::vector<uint8_t> bytes;
};
int main(int argc, char **argv) {
    if (argc != 2)
        return 2;
    try {
        std::ifstream metadata(argv[1]);
        Json input = Json::parse(metadata);
        auto regions = std::make_shared<std::vector<Region>>();
        for (const auto &item : input.at("regions")) {
            std::ifstream stream(item.at("file").get<std::string>(), std::ios::binary);
            if (!stream)
                throw std::runtime_error("Cannot read replay region");
            std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(stream)), {});
            if (bytes.empty() || bytes.size() > 64 * 1024 * 1024)
                throw std::runtime_error("Invalid replay region size");
            regions->push_back({item.at("address").get<uint64_t>(), std::move(bytes)});
        }
        auto makeImage = [&](const Json &description) {
            shresolve::Image image;
            image.name = description.at("name");
            image.base = description.at("base");
            image.functions = description.at("functions").get<std::vector<uint64_t>>();
            for (const auto &range : description.at("ranges"))
                image.ranges.push_back({range.at("address"), range.at("size"), range.at("code")});
            image.read = [regions](uint64_t address, void *out, size_t size) {
                for (const auto &r : *regions)
                    if (address >= r.address && size <= r.bytes.size() &&
                        address - r.address <= r.bytes.size() - size) {
                        memcpy(out, r.bytes.data() + address - r.address, size);
                        return true;
                    }
                return false;
            };
            image.clean = [](uint64_t address) {
                return address;
            }; // Fixup PAC bits were decoded by the preparer.
            return image;
        };
        std::vector<shresolve::Symbol> symbols;
        for (const auto &symbol : input.at("symbols"))
            symbols.push_back({symbol.at("address"), symbol.at("name")});
        auto plan = shresolve::resolve(makeImage(input.at("cc")), makeImage(input.at("driver")),
                                       symbols, input.at("ready"));
        std::cout << Json{{"complete", plan.complete},
                          {"signatures_validated", plan.signaturesValidated},
                          {"values", plan.values},
                          {"sources", plan.sources},
                          {"errors", plan.errors}}
                         .dump(2)
                  << '\n';
        return 0; // An unresolved plan is an analysis result, not a crashed harness.
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 2;
    }
}
