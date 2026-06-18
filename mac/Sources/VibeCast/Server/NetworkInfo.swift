// 局域网地址发现（用于显示「手机访问地址」）。PRD 7.3 / 5.8。

import Foundation

enum NetworkInfo {
    /// 返回首选 IPv4 局域网地址（en0/en1 优先），无则 nil。
    static func primaryLANAddress() -> String? {
        var candidates: [(iface: String, ip: String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let flags = Int32(cur.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addr = cur.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(cur.pointee.ifa_addr.pointee.sa_len)
            if getnameinfo(cur.pointee.ifa_addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let name = String(cString: cur.pointee.ifa_name)
                let ip = String(cString: host)
                if ip.hasPrefix("169.254.") { continue } // 跳过自配 IP
                candidates.append((name, ip))
            }
        }

        // en0/en1 优先（通常是 Wi-Fi/有线），否则取第一个。
        if let preferred = candidates.first(where: { $0.iface == "en0" })
            ?? candidates.first(where: { $0.iface == "en1" }) {
            return preferred.ip
        }
        return candidates.first?.ip
    }
}
