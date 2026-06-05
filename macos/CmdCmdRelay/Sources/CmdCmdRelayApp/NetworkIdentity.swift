import Darwin
import Foundation

enum NetworkIdentity {
    static func privateIPv4Address() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            return nil
        }
        defer { freeifaddrs(interfaces) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let address = current.pointee.ifa_addr
            guard address?.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let flags = Int32(current.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address!.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else {
                continue
            }

            let ip = String(cString: host)
            if isPrivateIPv4(ip) {
                return ip
            }
        }

        return nil
    }

    private static func isPrivateIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else {
            return false
        }

        if parts[0] == 10 {
            return true
        }
        if parts[0] == 172, (16...31).contains(parts[1]) {
            return true
        }
        if parts[0] == 192, parts[1] == 168 {
            return true
        }
        return false
    }
}

