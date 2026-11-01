#pragma once
#include "Protocol.hpp"
#include <sys/socket.h>
#include <cerrno>

namespace shjson {
constexpr size_t MaximumFrameBytes = 262144; // Includes the terminating LF.
inline bool writeJSON(int fd, const JSON &value) {
    std::string frame = dump(value);
    if (frame.size() >= MaximumFrameBytes)
        return false;
    frame += '\n';
    size_t offset = 0;
    while (offset < frame.size()) {
#ifdef MSG_NOSIGNAL
        constexpr int flags = MSG_NOSIGNAL;
#else
        constexpr int flags = 0;
#endif
        ssize_t count = send(fd, frame.data() + offset, frame.size() - offset, flags);
        if (count < 0 && errno == EINTR)
            continue;
        if (count <= 0)
            return false;
        offset += size_t(count);
    }
    return true;
}
template <class T> bool writeMessage(int fd, const T &value) { return writeJSON(fd, JSON(value)); }
inline bool readJSON(int fd, JSON &out) {
    std::string frame;
    char byte;
    while (frame.size() < MaximumFrameBytes) {
        ssize_t count = recv(fd, &byte, 1, 0);
        if (count < 0 && errno == EINTR)
            continue;
        if (count != 1)
            return false;
        if (byte == '\n')
            return parse(frame.data(), frame.size(), out, MaximumFrameBytes - 1);
        frame += byte;
    }
    return false;
}
template <class T> std::optional<T> readMessage(int fd) {
    JSON value;
    T result{};
    if (!readJSON(fd, value) || !read(value, result))
        return std::nullopt;
    return result;
}
inline std::optional<Reply> readReply(int fd, Operation operation) {
    JSON value;
    Reply reply;
    if (!readJSON(fd, value) || !readReply(value, operation, reply))
        return std::nullopt;
    return reply;
}
} // namespace shjson
