import Combine
import Darwin
import Foundation

final class RoonDiscoveryService: ObservableObject {
    @Published private(set) var discoveredCores: [RoonCore] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastError: String?

    private var receiveSocket: Int32 = -1
    private var sendSocket: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var sendReadSource: DispatchSourceRead?
    private var scanTimer: DispatchSourceTimer?
    private var targetHosts: Set<String> = []
    private let queue = DispatchQueue(label: "RoonLyric.RoonDiscoveryService")

    func startScanning() {
        AppLogger.info("Discovery", "start scanning requested")
        queue.async { [weak self] in
            self?.startLocked()
        }
    }

    func stopScanning() {
        AppLogger.info("Discovery", "stop scanning requested")
        queue.async { [weak self] in
            self?.stopLocked()
        }
    }

    func sendQuery() {
        AppLogger.info("Discovery", "send query requested")
        queue.async { [weak self] in
            self?.sendQueryLocked()
        }
    }

    func setTargetHosts(_ hosts: [String]) {
        queue.async { [weak self] in
            self?.targetHosts = Set(hosts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            AppLogger.info("Discovery", "target hosts updated count=\(self?.targetHosts.count ?? 0)")
        }
    }

    func sendQuery(to host: String) {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        AppLogger.info("Discovery", "send directed query requested host=\(target)")
        queue.async { [weak self] in
            guard !target.isEmpty else { return }
            self?.targetHosts.insert(target)
            self?.sendQueryLocked()
        }
    }

    private func startLocked() {
        guard !isScanning else {
            sendQueryLocked()
            return
        }

        do {
            try openSockets()
            AppLogger.info("Discovery", "discovery sockets opened")
            DispatchQueue.main.async {
                self.isScanning = true
                self.lastError = nil
            }
            sendQueryLocked()

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 2, repeating: 10)
            timer.setEventHandler { [weak self] in
                self?.sendQueryLocked()
            }
            timer.resume()
            scanTimer = timer
        } catch {
            DispatchQueue.main.async {
                self.lastError = error.localizedDescription
                self.isScanning = false
            }
            AppLogger.error("Discovery", "failed to start scanning error=\(error.localizedDescription)")
            closeSockets()
        }
    }

    private func stopLocked() {
        scanTimer?.cancel()
        scanTimer = nil
        readSource?.cancel()
        readSource = nil
        sendReadSource?.cancel()
        sendReadSource = nil
        closeSockets()
        AppLogger.info("Discovery", "discovery stopped")
        DispatchQueue.main.async {
            self.isScanning = false
        }
    }

    private func openSockets() throws {
        receiveSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard receiveSocket >= 0 else { throw POSIXError(.ENOTSOCK) }
        setNonBlocking(receiveSocket)

        var yes: Int32 = 1
        setsockopt(receiveSocket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(receiveSocket, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))

        var receiveAddress = sockaddr_in()
        receiveAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        receiveAddress.sin_family = sa_family_t(AF_INET)
        receiveAddress.sin_port = in_port_t(SOODPacket.port).bigEndian
        receiveAddress.sin_addr.s_addr = INADDR_ANY.bigEndian

        let bindResult = withUnsafePointer(to: &receiveAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(receiveSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL) }

        var membership = ip_mreq()
        membership.imr_multiaddr.s_addr = inet_addr(SOODPacket.multicastAddress)
        membership.imr_interface.s_addr = INADDR_ANY
        setsockopt(receiveSocket, IPPROTO_IP, IP_ADD_MEMBERSHIP, &membership, socklen_t(MemoryLayout<ip_mreq>.size))

        sendSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sendSocket >= 0 else { throw POSIXError(.ENOTSOCK) }
        setNonBlocking(sendSocket)
        setsockopt(sendSocket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(sendSocket, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        var ttl: UInt8 = 1
        setsockopt(sendSocket, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))

        var sendAddress = sockaddr_in()
        sendAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sendAddress.sin_family = sa_family_t(AF_INET)
        sendAddress.sin_port = 0
        sendAddress.sin_addr.s_addr = INADDR_ANY.bigEndian

        let sendBindResult = withUnsafePointer(to: &sendAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sendSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sendBindResult == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL) }

        let receiveFileDescriptor = receiveSocket
        let source = DispatchSource.makeReadSource(fileDescriptor: receiveFileDescriptor, queue: queue)
        source.setEventHandler { [weak self] in
            self?.receivePackets(from: receiveFileDescriptor)
        }
        source.resume()
        readSource = source

        let sendFileDescriptor = sendSocket
        let sendSource = DispatchSource.makeReadSource(fileDescriptor: sendFileDescriptor, queue: queue)
        sendSource.setEventHandler { [weak self] in
            self?.receivePackets(from: sendFileDescriptor)
        }
        sendSource.resume()
        sendReadSource = sendSource
    }

    private func sendQueryLocked() {
        guard sendSocket >= 0 else { return }
        let data = SOODPacket.queryData()
        let targets = queryTargets()
        for target in targets {
            send(data, to: target, port: SOODPacket.port)
        }
        AppLogger.debug("Discovery", "sood query sent targets=\(targets.joined(separator: ","))")
    }

    private func queryTargets() -> [String] {
        var targets = [SOODPacket.multicastAddress, "255.255.255.255"]
        targets.append(contentsOf: localBroadcastAddresses())
        targets.append(contentsOf: targetHosts)
        return Array(Set(targets)).sorted()
    }

    private func localBroadcastAddresses() -> [String] {
        var results: [String] = []
        var interfaces: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            return results
        }
        defer { freeifaddrs(interfaces) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                  interface.ifa_netmask.pointee.sa_family == UInt8(AF_INET),
                  (interface.ifa_flags & UInt32(IFF_UP)) != 0,
                  (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else {
                continue
            }

            let address = interface.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let netmask = interface.ifa_netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let broadcast = UInt32(bigEndian: address) | ~UInt32(bigEndian: netmask)
            var broadcastAddress = in_addr(s_addr: broadcast.bigEndian)
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))

            if inet_ntop(AF_INET, &broadcastAddress, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                let value = String(cString: buffer)
                if value != "255.255.255.255" {
                    results.append(value)
                }
            }
        }

        return results
    }

    private func send(_ data: Data, to host: String, port: UInt16) {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr.s_addr = inet_addr(host)

        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = Darwin.sendto(sendSocket, baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private func receivePackets(from socket: Int32) {
        while true {
            var buffer = [UInt8](repeating: 0, count: 65_535)
            var address = sockaddr_in()
            var addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(socket, &buffer, buffer.count, 0, $0, &addressLength)
                }
            }

            if count <= 0 {
                break
            }

            let ip = String(cString: inet_ntoa(address.sin_addr))
            let port = UInt16(bigEndian: address.sin_port)
            let data = Data(buffer.prefix(count))
            AppLogger.debug("Discovery", "sood packet received from=\(ip):\(port) bytes=\(count)")

            guard let core = SOODPacket.parse(data, address: ip, port: port) else {
                AppLogger.debug("Discovery", "ignored non-core sood packet from=\(ip):\(port)")
                continue
            }
            DispatchQueue.main.async {
                self.merge(core)
            }
        }
    }

    private func setNonBlocking(_ socket: Int32) {
        let flags = fcntl(socket, F_GETFL, 0)
        guard flags >= 0 else { return }
        _ = fcntl(socket, F_SETFL, flags | O_NONBLOCK)
    }

    private func merge(_ core: RoonCore) {
        if let index = discoveredCores.firstIndex(where: { $0.id == core.id }) {
            discoveredCores[index] = core
        } else {
            discoveredCores.append(core)
            AppLogger.info("Discovery", "discovered core name=\(core.name) endpoint=\(core.endpoint)")
        }
        discoveredCores.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func closeSockets() {
        if sendSocket >= 0 {
            Darwin.close(sendSocket)
            sendSocket = -1
        }
        if receiveSocket >= 0 {
            Darwin.close(receiveSocket)
            receiveSocket = -1
        }
    }

    deinit {
        stopScanning()
    }
}
