import Foundation

final class NetworkSettingsStore {
    private let fileURL: URL
    private(set) var settings: NetworkSettings

    init(fileURL: URL? = nil) {
        let fm = FileManager.default
        if let fileURL {
            self.fileURL = fileURL
            try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } else {
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("VibeCast", isDirectory: true)
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
            self.fileURL = base.appendingPathComponent("network.json")
        }
        self.settings = NetworkSettingsStore.load(from: self.fileURL)
    }

    @discardableResult
    func update(_ next: NetworkSettings) -> NetworkSettings {
        settings = NetworkSettingsStore.normalized(next)
        save()
        return settings
    }

    func normalizedForCurrentInterfaces() -> NetworkSettings {
        let normalized = NetworkSettingsStore.normalized(settings)
        guard normalized.bindMode == .address else { return normalized }
        let interfaces = NetworkInfo.localInterfaces()
        if let address = normalized.bindAddress,
           interfaces.contains(where: { $0.address == address }) {
            return normalized
        }
        var fallback = normalized
        fallback.bindAddress = interfaces.first(where: { $0.isPreferred })?.address ?? interfaces.first?.address
        settings = fallback
        save()
        return fallback
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    private static func load(from url: URL) -> NetworkSettings {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(NetworkSettings.self, from: data) {
            return normalized(decoded)
        }
        let address = NetworkInfo.primaryLANAddress()
        return NetworkSettings(bindMode: address == nil ? .all : .address,
                               bindAddress: address,
                               port: NetworkSettings.defaultPort)
    }

    static func normalized(_ value: NetworkSettings) -> NetworkSettings {
        let port = (1...65535).contains(Int(value.port)) ? value.port : NetworkSettings.defaultPort
        switch value.bindMode {
        case .all:
            return NetworkSettings(bindMode: .all, bindAddress: nil, port: port)
        case .address:
            let address = value.bindAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
            return NetworkSettings(bindMode: .address, bindAddress: address?.isEmpty == false ? address : NetworkInfo.primaryLANAddress(), port: port)
        }
    }
}

enum PortAvailability {
    static func check(settings: NetworkSettings) -> PortCheckResult {
        guard settings.port != 0 else {
            return PortCheckResult(bindMode: settings.bindMode, bindAddress: settings.bindAddress,
                                   port: settings.port, status: .invalid, message: "端口范围必须是 1-65535")
        }
        let normalized = NetworkSettingsStore.normalized(settings)
        guard normalized.bindMode == .all || normalized.bindAddress != nil else {
            return PortCheckResult(bindMode: normalized.bindMode, bindAddress: normalized.bindAddress,
                                   port: normalized.port, status: .invalid, message: "未选择绑定 IP")
        }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return PortCheckResult(bindMode: normalized.bindMode, bindAddress: normalized.bindAddress,
                                   port: normalized.port, status: .unavailable, message: "无法创建端口检测 socket")
        }
        defer { close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = normalized.port.bigEndian
        let host = normalized.bindMode == .all ? "0.0.0.0" : (normalized.bindAddress ?? "")
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
            return PortCheckResult(bindMode: normalized.bindMode, bindAddress: normalized.bindAddress,
                                   port: normalized.port, status: .invalid, message: "绑定 IP 无效")
        }

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result == 0 {
            return PortCheckResult(bindMode: normalized.bindMode, bindAddress: normalized.bindAddress,
                                   port: normalized.port, status: .available, message: "端口可用")
        }
        return PortCheckResult(bindMode: normalized.bindMode, bindAddress: normalized.bindAddress,
                               port: normalized.port, status: .unavailable, message: "端口已被占用或无法绑定")
    }
}
