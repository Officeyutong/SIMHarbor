#include "../shared/Framing.hpp"
#include <cassert>
#include <thread>
#include <unistd.h>
#include <iostream>
using namespace shjson;
static JSON parseJSON(const std::string &text) {
    JSON j;
    assert(parse(text.data(), text.size(), j));
    return j;
}
static bool request(const std::string &text) {
    JSON j;
    Request out;
    return parse(text.data(), text.size(), j) && read(j, out);
}
static void schemas() {
    auto id = [](Request r) {
        r.id = "fixture-request";
        return r;
    };
    std::vector<Request> requests = {id(Request::make(Operation::Resolver)),
                                     id(Request::make(Operation::Slots)),
                                     id(Request::status(1)),
                                     id(Request::open(2, "a0000005591010ffffffff8900000100")),
                                     id(Request::transmit("80e2910006bf3e035c015a")),
                                     id(Request::make(Operation::Close))};
    for (const auto &r : requests) {
        Request out;
        JSON j = r;
        assert(read(j, out));
        assert(JSON(out) == j);
    }
    for (const auto &text :
         {"null", "[]", "{}", R"({"id":"x","op":"unknown"})", R"({"id":"x","op":0})",
          R"({"id":1,"op":"close"})", R"({"id":"x","op":"open","slot":true,"aid":"aa"})",
          R"({"id":"x","op":"open","slot":1.1,"aid":"aa"})",
          R"({"id":"x","op":"open","slot":4294967297,"aid":"aa"})",
          R"({"id":"x","op":"open","slot":-1,"aid":"aa"})",
          R"({"id":"x","op":"open","slot":null,"aid":"aa"})", R"({"id":"x","op":"open","slot":1})",
          R"({"id":"x","op":"transmit","hex":123})", R"({"id":"x","op":"transmit","hex":"9000"})",
          R"({"id":"x","op":"transmit","hex":"not hex!"})"})
        assert(!request(text));
    assert(request(R"({"id":"x","op":"status","unknown":{"future":true}})"));
    Request reused = Request::status(2);
    assert(read(parseJSON(R"({"id":"x","op":"status"})"), reused) && !reused.slot);
    Authentication auth;
    assert(!read(parseJSON(R"({"mac":true})"), auth));
    assert(!read(JSON{{"mac", std::string(64, 'z')}}, auth));
    Challenge challenge;
    assert(read(JSON(Challenge{std::string(64, 'a')}), challenge));
    Slot slot;
    assert(!read(parseJSON(R"({"logicalSlot":0,"hardwareSlot":3,"simReady":false})"), slot));
    assert(!read(parseJSON(R"({"logicalSlot":1,"hardwareSlot":1,"simReady":1})"), slot));
    std::vector<std::pair<Operation, Reply>> replies = {
        {Operation::Resolver, Reply::success(ResolverReply{})},
        {Operation::Slots, Reply::success(SlotsReply{{{1, 1, true}, {2, 2, false}}, Phase::Idle})},
        {Operation::Status, Reply::success(StatusReply{})},
        {Operation::Open, Reply::success(OpenReply{1, 1, 1})},
        {Operation::Transmit, Reply::success(TransmitReply{"6115"})},
        {Operation::Close, Reply::success()},
        {Operation::Open, Reply::failure("fixture failure")}};
    for (auto &[op, r] : replies) {
        r.id = "fixture-reply";
        Reply decoded;
        JSON j = r;
        assert(readReply(j, op, decoded));
        assert(JSON(decoded) == j);
    }
    Reply out;
    assert(!readReply(parseJSON(R"({"id":"x","ok":1})"), Operation::Close, out));
    assert(!readReply(parseJSON(R"({"id":"x","ok":false,"error":{}})"), Operation::Close, out));
    assert(!readReply(
        parseJSON(R"({"id":"x","ok":true,"channel":-1,"logicalSlot":1,"hardwareSlot":1})"),
        Operation::Open, out));
    assert(!readReply(parseJSON(R"({"id":"x","ok":true,"slots":[],"phase":5})"), Operation::Slots,
                      out));
    assert(!readReply(
        parseJSON(
            R"({"id":"x","ok":true,"slots":[{"logicalSlot":1,"hardwareSlot":1,"simReady":true},{"logicalSlot":1,"hardwareSlot":2,"simReady":false}],"phase":0})"),
        Operation::Slots, out));
    ResolverReport report;
    report.state = "resolved";
    report.details.emplace();
    report.details->values["driverMember"] = {uint64_t(64), "fixture", std::nullopt};
    ResolverReport decoded;
    JSON reportJSON = report;
    assert(read(reportJSON, decoded));
    assert(JSON(decoded) == reportJSON);
    reportJSON["abiCompatible"] = 1;
    assert(!read(reportJSON, decoded));
    HTTPEnvelope http;
    assert(read(
        parseJSON(
            R"({"header":{"functionExecutionStatus":{"status":"Failed","statusCodeData":{"subjectCode":"8.2.6","reasonCode":"3.8"}}}})"),
        http));
    assert(http.header->functionExecutionStatus->status == "Failed");
    assert(!read(parseJSON(R"({"header":{"functionExecutionStatus":{"status":true}}})"), http));
    std::vector<Article> articles;
    assert(read(parseJSON(R"([{"id":"guide","title":"Guide","body":"text"}])"), articles));
    assert(!read(parseJSON(R"([{"id":"guide","title":"Guide","body":{}}])"), articles));
}
static void parser() {
    JSON j;
    for (const auto &text : {"{", "{bad}", "{\"id\":\"x\",\"id\":\"y\"}",
                             "{\"a\":{\"x\":1,\"x\":2}}", "{} trailing", "1e100000"})
        assert(!parse(text, strlen(text), j));
    std::string invalid = "{\"x\":\"";
    invalid += char(0xff);
    invalid += "\"}";
    assert(!parse(invalid.data(), invalid.size(), j));
    std::string deep(65, '[');
    deep += '0';
    deep += std::string(65, ']');
    assert(!parse(deep.data(), deep.size(), j));
    std::string braces = R"({"text":"[\\\"{}]"})";
    assert(parse(braces.data(), braces.size(), j));
    std::string large(MaximumFrameBytes, ' ');
    assert(!parse(large.data(), large.size(), j));
}
static void framing() {
    int sockets[2];
    assert(!socketpair(AF_UNIX, SOCK_STREAM, 0, sockets));
    std::thread writer([&] {
        std::string wire = R"({"id":"fragmented","op":"close"})";
        wire += '\n';
        for (char c : wire)
            assert(send(sockets[0], &c, 1, 0) == 1);
    });
    auto r = readMessage<Request>(sockets[1]);
    assert(r && r->id == "fragmented" && r->op == Operation::Close);
    writer.join();
    close(sockets[0]);
    close(sockets[1]);
    assert(!socketpair(AF_UNIX, SOCK_STREAM, 0, sockets));
    JSON largest =
        std::string(MaximumFrameBytes - 3, 'x'); // Quotes plus LF fill the frame exactly.
    writer = std::thread([&] { assert(writeJSON(sockets[0], largest)); });
    JSON decoded;
    assert(readJSON(sockets[1], decoded) && decoded == largest);
    writer.join();
    assert(!writeJSON(sockets[0], JSON(std::string(MaximumFrameBytes - 2, 'x'))));
    std::string partial = "{\"id\":\"x\"}";
    assert(send(sockets[0], partial.data(), partial.size(), 0) == ssize_t(partial.size()));
    shutdown(sockets[0], SHUT_WR);
    assert(!readJSON(sockets[1], decoded));
    close(sockets[0]);
    close(sockets[1]);
}
int main() {
    static_assert(NLOHMANN_JSON_VERSION_MAJOR == 3 && NLOHMANN_JSON_VERSION_MINOR == 12 &&
                  NLOHMANN_JSON_VERSION_PATCH == 0);
    schemas();
    parser();
    framing();
    std::cout
        << "PASS: typed JSON schemas, malformed types/ranges, duplicate/deep input, legacy wire fields, fragmented frames and size bounds\n";
}
