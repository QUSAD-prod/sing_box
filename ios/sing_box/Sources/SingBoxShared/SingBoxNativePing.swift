import Darwin
import dnssd
import Foundation

/// TCP handshake and ICMP echo latency for `pingServer` (see
/// `doc/platform_channel.md`). The app measures while the tunnel is stopped,
/// the extension while it runs: there `interfaceIndex` is the physical
/// interface, so the name is resolved by that network's DNS servers (not by
/// the tunnel, e.g. with FakeIP addresses) and the sockets are bound to it.
/// Blocking: call off the main thread.
public enum SingBoxNativePing {
    public enum Method: String {
        case tcp
        case icmp
    }

    /// The method of a `pingServer` call; throws for invalid arguments.
    public static func method(_ name: String, port: Int?) throws -> Method {
        guard let method = Method(rawValue: name) else {
            throw SingBoxError("Unknown ping method \"\(name)\"")
        }
        if method == .tcp, !(1 ... 65535).contains(port ?? 0) {
            throw SingBoxError("Missing or invalid argument \"port\"")
        }
        return method
    }

    /// Measures `host` (`port` is required for `.tcp`). Failures are part of
    /// the result map: `success`, `ping` (ms), `address` (IP used), `error`.
    public static func ping(
        _ method: Method,
        host: String,
        port: Int?,
        timeoutMs: Int,
        interfaceIndex: UInt32 = 0
    ) -> [String: Any] {
        let deadline = now() + UInt64(max(timeoutMs, 1)) * 1_000_000
        let address: Address
        do {
            address = try resolve(host, interfaceIndex: interfaceIndex, deadline: deadline)
        } catch {
            return failure("Cannot resolve \(host): \(error.localizedDescription)", nil)
        }
        do {
            let nanoseconds = method == .tcp
                ? try tcp(address.with(port: UInt16(port ?? 0)), interfaceIndex: interfaceIndex, deadline: deadline)
                : try icmp(address, interfaceIndex: interfaceIndex, deadline: deadline)
            return ["success": true, "ping": Int(nanoseconds / 1_000_000), "address": address.description]
        } catch {
            return failure(error.localizedDescription, address)
        }
    }

    private static func failure(_ error: String, _ address: Address?) -> [String: Any] {
        var result: [String: Any] = ["success": false, "error": error]
        if let address {
            result["address"] = address.description
        }
        return result
    }

    // MARK: - Addresses

    private struct Address: CustomStringConvertible {
        var storage = sockaddr_storage()

        var family: Int32 {
            Int32(storage.ss_family)
        }

        var length: socklen_t {
            socklen_t(family == AF_INET6 ? MemoryLayout<sockaddr_in6>.size : MemoryLayout<sockaddr_in>.size)
        }

        init?(literal: String) {
            var host = literal
            if host.hasPrefix("["), host.hasSuffix("]") {
                host = String(host.dropFirst().dropLast())
            }
            var v4 = in_addr()
            var v6 = in6_addr()
            if inet_pton(AF_INET, host, &v4) == 1 {
                var address = sockaddr_in()
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                address.sin_family = sa_family_t(AF_INET)
                address.sin_addr = v4
                Swift.withUnsafeBytes(of: address) { bytes in
                    Swift.withUnsafeMutableBytes(of: &storage) { $0.copyMemory(from: bytes) }
                }
            } else if inet_pton(AF_INET6, host, &v6) == 1 {
                var address = sockaddr_in6()
                address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
                address.sin6_family = sa_family_t(AF_INET6)
                address.sin6_addr = v6
                Swift.withUnsafeBytes(of: address) { bytes in
                    Swift.withUnsafeMutableBytes(of: &storage) { $0.copyMemory(from: bytes) }
                }
            } else {
                return nil
            }
        }

        init(_ pointer: UnsafePointer<sockaddr>) {
            let length = min(Int(pointer.pointee.sa_len), MemoryLayout<sockaddr_storage>.size)
            Swift.withUnsafeMutableBytes(of: &storage) {
                $0.copyMemory(from: UnsafeRawBufferPointer(start: pointer, count: length))
            }
        }

        func with(port: UInt16) -> Address {
            var copy = self
            Swift.withUnsafeMutableBytes(of: &copy.storage) { bytes in
                // sin_port and sin6_port are both at offset 2.
                bytes.storeBytes(of: port.bigEndian, toByteOffset: 2, as: UInt16.self)
            }
            return copy
        }

        func withSockaddr<T>(_ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
            var copy = storage
            return Swift.withUnsafePointer(to: &copy) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, length) }
            }
        }

        var description: String {
            let capacity = Int(NI_MAXHOST)
            var host = [CChar](repeating: 0, count: capacity)
            let status = withSockaddr { address, length in
                getnameinfo(address, length, &host, socklen_t(capacity), nil, 0, NI_NUMERICHOST)
            }
            return status == 0 ? String(cString: host) : "?"
        }
    }

    /// Resolves `host` (IPv4 preferred), scoped to `interfaceIndex` when it
    /// is not 0.
    private static func resolve(_ host: String, interfaceIndex: UInt32, deadline: UInt64) throws -> Address {
        if let literal = Address(literal: host) {
            return literal
        }
        let v4 = try lookup(host, DNSServiceProtocol(kDNSServiceProtocol_IPv4), interfaceIndex, deadline)
        if let address = v4.first {
            return address
        }
        let v6 = try lookup(host, DNSServiceProtocol(kDNSServiceProtocol_IPv6), interfaceIndex, deadline)
        guard let address = v6.first else {
            throw SingBoxError("no address")
        }
        return address
    }

    private final class Lookup {
        var addresses: [Address] = []
        var error: DNSServiceErrorType = DNSServiceErrorType(kDNSServiceErr_NoError)
        var finished = false
    }

    /// One `DNSServiceGetAddrInfo` query; a negative answer is an empty list.
    private static func lookup(
        _ host: String,
        _ proto: DNSServiceProtocol,
        _ interfaceIndex: UInt32,
        _ deadline: UInt64
    ) throws -> [Address] {
        let lookup = Lookup()
        var reference: DNSServiceRef?
        let status = DNSServiceGetAddrInfo(
            &reference,
            // Report "no such record" instead of waiting for the timeout.
            DNSServiceFlags(kDNSServiceFlagsReturnIntermediates),
            interfaceIndex,
            proto,
            host,
            { _, flags, _, errorCode, _, address, _, context in
                guard let context else { return }
                let lookup = Unmanaged<Lookup>.fromOpaque(context).takeUnretainedValue()
                if errorCode == DNSServiceErrorType(kDNSServiceErr_NoError), let address,
                   address.pointee.sa_family == sa_family_t(AF_INET) || address.pointee.sa_family == sa_family_t(AF_INET6)
                {
                    lookup.addresses.append(Address(address))
                } else if errorCode != DNSServiceErrorType(kDNSServiceErr_NoSuchRecord) {
                    lookup.error = errorCode
                }
                if flags & DNSServiceFlags(kDNSServiceFlagsMoreComing) == 0 {
                    lookup.finished = true
                }
            },
            Unmanaged.passUnretained(lookup).toOpaque()
        )
        guard status == DNSServiceErrorType(kDNSServiceErr_NoError), let reference else {
            throw SingBoxError("DNS error \(status)")
        }
        defer { DNSServiceRefDeallocate(reference) }
        let fd = DNSServiceRefSockFD(reference)
        while !lookup.finished {
            guard try wait(fd, events: POLLIN, deadline: deadline) else {
                throw SingBoxError("Timed out")
            }
            let result = DNSServiceProcessResult(reference)
            if result != DNSServiceErrorType(kDNSServiceErr_NoError) {
                throw SingBoxError("DNS error \(result)")
            }
        }
        if lookup.addresses.isEmpty, lookup.error != DNSServiceErrorType(kDNSServiceErr_NoError) {
            throw SingBoxError("DNS error \(lookup.error)")
        }
        return lookup.addresses
    }

    // MARK: - Measurements

    private static func tcp(_ address: Address, interfaceIndex: UInt32, deadline: UInt64) throws -> UInt64 {
        let fd = socket(address.family, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            throw posixError(errno)
        }
        defer { close(fd) }
        try bind(fd, family: address.family, interfaceIndex: interfaceIndex)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let start = now()
        if address.withSockaddr({ connect(fd, $0, $1) }) != 0 {
            guard errno == EINPROGRESS else {
                throw posixError(errno)
            }
            guard try wait(fd, events: POLLOUT, deadline: deadline) else {
                throw SingBoxError("Timed out")
            }
            var error: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length)
            if error != 0 {
                throw posixError(error)
            }
        }
        return now() - start
    }

    /// One echo request over an unprivileged ICMP datagram socket (like
    /// Apple's SimplePing).
    private static func icmp(_ address: Address, interfaceIndex: UInt32, deadline: UInt64) throws -> UInt64 {
        let v6 = address.family == AF_INET6
        let fd = socket(address.family, SOCK_DGRAM, v6 ? IPPROTO_ICMPV6 : IPPROTO_ICMP)
        guard fd >= 0 else {
            throw SingBoxError("ICMP is not available: \(posixError(errno).message)")
        }
        defer { close(fd) }
        try bind(fd, family: address.family, interfaceIndex: interfaceIndex)
        let identifier = UInt16.random(in: 1 ... UInt16.max)
        let sequence: UInt16 = 1
        // Type, code, checksum, identifier, sequence and some payload.
        var request = [UInt8](repeating: 0, count: 16)
        request[0] = v6 ? echoRequestV6 : echoRequestV4
        request[4] = UInt8(identifier >> 8)
        request[5] = UInt8(identifier & 0xFF)
        request[6] = UInt8(sequence >> 8)
        request[7] = UInt8(sequence & 0xFF)
        if !v6 {
            // The kernel computes the ICMPv6 checksum, not the ICMPv4 one.
            let sum = checksum(request)
            request[2] = UInt8(sum >> 8)
            request[3] = UInt8(sum & 0xFF)
        }
        let start = now()
        let sent = address.withSockaddr { sendto(fd, request, request.count, 0, $0, $1) }
        guard sent == request.count else {
            throw posixError(errno)
        }
        let capacity = 1500
        var reply = [UInt8](repeating: 0, count: capacity)
        while true {
            guard try wait(fd, events: POLLIN, deadline: deadline) else {
                throw SingBoxError("No ICMP reply")
            }
            let read = recv(fd, &reply, capacity, 0)
            if read < 0 {
                if errno == EINTR || errno == EAGAIN {
                    continue
                }
                throw posixError(errno)
            }
            // ICMPv4 datagram sockets receive the IP header too.
            var offset = 0
            if !v6, read >= 20, reply[0] >> 4 == 4 {
                offset = Int(reply[0] & 0x0F) * 4
            }
            guard read - offset >= 8 else {
                continue
            }
            let type = reply[offset]
            let replyIdentifier = UInt16(reply[offset + 4]) << 8 | UInt16(reply[offset + 5])
            let replySequence = UInt16(reply[offset + 6]) << 8 | UInt16(reply[offset + 7])
            // Every ICMP socket of the host may see the reply: match ours.
            if type == (v6 ? echoReplyV6 : echoReplyV4), replyIdentifier == identifier, replySequence == sequence {
                return now() - start
            }
        }
    }

    // MARK: - Helpers

    private static let echoRequestV4: UInt8 = 8
    private static let echoReplyV4: UInt8 = 0
    private static let echoRequestV6: UInt8 = 128
    private static let echoReplyV6: UInt8 = 129

    private static func now() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }

    /// Binds the socket to the interface (`IP_BOUND_IF`) so it bypasses the
    /// tunnel; no-op for 0.
    private static func bind(_ fd: Int32, family: Int32, interfaceIndex: UInt32) throws {
        guard interfaceIndex != 0 else {
            return
        }
        var index = interfaceIndex
        let size = socklen_t(MemoryLayout<UInt32>.size)
        let result = family == AF_INET6
            ? setsockopt(fd, IPPROTO_IPV6, IPV6_BOUND_IF, &index, size)
            : setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &index, size)
        if result != 0 {
            throw posixError(errno)
        }
    }

    /// Waits for `events` until `deadline`; `false` on timeout.
    private static func wait(_ fd: Int32, events: Int32, deadline: UInt64) throws -> Bool {
        while true {
            let current = now()
            guard current < deadline else {
                return false
            }
            var request = pollfd(fd: fd, events: Int16(events), revents: 0)
            let timeout = Int32(min((deadline - current + 999_999) / 1_000_000, UInt64(Int32.max)))
            let result = poll(&request, 1, timeout)
            if result > 0 {
                return true
            }
            if result < 0, errno != EINTR {
                throw posixError(errno)
            }
        }
    }

    private static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count {
            sum += UInt32(bytes[index]) << 8
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return ~UInt16(sum)
    }

    private static func posixError(_ code: Int32) -> SingBoxError {
        SingBoxError(String(cString: strerror(code)))
    }
}
