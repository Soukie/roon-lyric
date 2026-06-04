import Combine
import Foundation

final class RoonConnectionService: ObservableObject {
    @Published private(set) var phase: RoonConnectionPhase = .disconnected
    @Published private(set) var connectedCore: RoonCore?
    @Published private(set) var zones: [RoonZone] = []
    @Published private(set) var selectedZoneID: String?

    private let tokenStore: RoonTokenStore
    private var client: MOOClient?
    private var subscriptionKey = 0
    private let selectedZoneKey = "selectedZoneID"

    init(tokenStore: RoonTokenStore = RoonTokenStore()) {
        self.tokenStore = tokenStore
        selectedZoneID = UserDefaults.standard.string(forKey: selectedZoneKey)
    }

    var activeZone: RoonZone? {
        if let selectedZoneID,
           let selected = zones.first(where: { $0.id == selectedZoneID }) {
            return selected
        }
        return zones.first(where: { $0.isPlaying }) ?? zones.first
    }

    func connect(to core: RoonCore) {
        disconnect()
        AppLogger.info("Roon", "connecting to core name=\(core.name) endpoint=\(core.endpoint) source=\(core.source.rawValue)")
        phase = .connecting
        connectedCore = core

        let client = MOOClient(host: core.host, port: core.port)
        self.client = client

        client.onOpen = { [weak self] in
            self?.register()
        }
        client.onClose = { [weak self] in
            DispatchQueue.main.async {
                if self?.phase == .connected {
                    AppLogger.warning("Roon", "roon websocket closed while connected")
                    self?.phase = .failed("连接已断开")
                }
            }
        }
        client.onRequest = { [weak self] message in
            self?.handleIncomingRequest(message)
        }

        client.connect()
    }

    func disconnect() {
        AppLogger.info("Roon", "disconnect requested")
        client?.close()
        client = nil
        zones = []
        connectedCore = nil
        phase = .disconnected
    }

    func selectZone(_ zone: RoonZone?) {
        AppLogger.info("Roon", "selected zone id=\(zone?.id ?? "none") name=\(zone?.displayName ?? "none")")
        selectedZoneID = zone?.id
        UserDefaults.standard.set(zone?.id, forKey: selectedZoneKey)
    }

    private func register() {
        AppLogger.info("Roon", "requesting registry info")
        client?.sendRequest("com.roonlabs.registry:1/info") { [weak self] message in
            guard let self else { return }
            guard let body = message.body,
                  let coreID = body["core_id"] as? String else {
                DispatchQueue.main.async {
                    self.phase = .failed("无法读取 Roon Core 信息")
                }
                AppLogger.error("Roon", "registry info missing core_id")
                return
            }

            var registration = self.registrationInfo()
            var hasSavedToken = false
            if let token = self.tokenStore.token(for: coreID) {
                registration["token"] = token
                hasSavedToken = true
                AppLogger.info("Roon", "using saved token for coreID=\(coreID)")
            } else {
                AppLogger.info("Roon", "no saved token for coreID=\(coreID); waiting for authorization")
            }

            if !hasSavedToken {
                DispatchQueue.main.async {
                    self.phase = .waitingForAuthorization
                }
            }

            self.client?.sendRequest("com.roonlabs.registry:1/register", body: registration) { [weak self] response in
                self?.handleRegistration(response)
            }
        }
    }

    private func registrationInfo() -> [String: Any] {
        [
            "extension_id": "com.soukie.RoonLyric",
            "display_name": "Roon Lyric",
            "display_version": "0.1.0",
            "publisher": "Soukie",
            "email": "roon-lyric@example.local",
            "website": "https://example.local/roon-lyric",
            "required_services": ["com.roonlabs.transport:2"],
            "optional_services": [],
            "provided_services": ["com.roonlabs.pairing:1", "com.roonlabs.ping:1"]
        ]
    }

    private func handleRegistration(_ response: MOOMessage) {
        guard response.name == "Registered",
              let body = response.body,
              let coreID = body["core_id"] as? String,
              let token = body["token"] as? String else {
            DispatchQueue.main.async {
                self.phase = .waitingForAuthorization
            }
            AppLogger.info("Roon", "registration not complete response=\(response.name)")
            return
        }

        tokenStore.save(token: token, for: coreID)
        AppLogger.info("Roon", "registered coreID=\(coreID); token persisted")
        DispatchQueue.main.async {
            self.phase = .connected
            if var core = self.connectedCore {
                core.id = coreID
                core.lastConnected = Date()
                self.connectedCore = core
            }
        }
        subscribeZones()
    }

    private func subscribeZones() {
        let key = subscriptionKey
        subscriptionKey += 1
        AppLogger.info("Roon", "subscribing zones key=\(key)")

        client?.sendRequest(
            "com.roonlabs.transport:2/subscribe_zones",
            body: ["subscription_key": key]
        ) { [weak self] message in
            self?.handleZones(message)
        }
    }

    private func handleZones(_ message: MOOMessage) {
        guard let body = message.body else { return }
        DispatchQueue.main.async {
            if message.name == "Subscribed",
               let zoneBodies = body["zones"] as? [[String: Any]] {
                self.zones = zoneBodies.compactMap(Self.zone(from:))
                AppLogger.info("Roon", "zones subscribed count=\(self.zones.count)")
            } else if message.name == "Changed" {
                self.applyZoneChange(body)
            }
        }
    }

    private func applyZoneChange(_ body: [String: Any]) {
        AppLogger.debug("Roon", "zone change received")
        if let removed = body["zones_removed"] as? [String] {
            zones.removeAll { removed.contains($0.id) }
            AppLogger.info("Roon", "zones removed count=\(removed.count)")
        }

        if let added = body["zones_added"] as? [[String: Any]] {
            for zone in added.compactMap(Self.zone(from:)) {
                upsert(zone)
            }
            AppLogger.info("Roon", "zones added count=\(added.count)")
        }

        if let changed = body["zones_changed"] as? [[String: Any]] {
            for zone in changed.compactMap(Self.zone(from:)) {
                upsert(zone)
            }
            AppLogger.debug("Roon", "zones changed count=\(changed.count)")
        }

        if let seekChanged = body["zones_seek_changed"] as? [[String: Any]] {
            for item in seekChanged {
                guard let zoneID = item["zone_id"] as? String,
                      let index = zones.firstIndex(where: { $0.id == zoneID }) else {
                    continue
                }
                if let seek = item["seek_position"] as? Double {
                    zones[index].nowPlaying?.seekPosition = seek
                    zones[index].lastSeekUpdate = Date()
                }
            }
            AppLogger.debug("Roon", "zones seek changed count=\(seekChanged.count)")
        }
    }

    private func upsert(_ zone: RoonZone) {
        if let index = zones.firstIndex(where: { $0.id == zone.id }) {
            zones[index] = zone
        } else {
            zones.append(zone)
        }
    }

    private func handleIncomingRequest(_ message: MOOMessage) {
        guard let client else { return }

        switch (message.service, message.name) {
        case ("com.roonlabs.ping:1", "ping"):
            client.sendComplete(requestID: message.requestID, name: "Success")
        case ("com.roonlabs.pairing:1", "get_pairing"):
            client.sendComplete(requestID: message.requestID, name: "Success", body: pairingBody())
        case ("com.roonlabs.pairing:1", "subscribe_pairing"):
            client.sendContinue(requestID: message.requestID, name: "Subscribed", body: pairingBody())
        case ("com.roonlabs.pairing:1", "pair"):
            client.sendComplete(requestID: message.requestID, name: "Success")
        default:
            client.sendComplete(requestID: message.requestID, name: "InvalidRequest", body: ["error": "Unsupported request"])
        }
    }

    private func pairingBody() -> [String: Any] {
        if let coreID = connectedCore?.id {
            return ["paired_core_id": coreID]
        }
        return [:]
    }

    private static func zone(from body: [String: Any]) -> RoonZone? {
        guard let id = body["zone_id"] as? String else { return nil }
        let name = body["display_name"] as? String ?? "Roon Zone"
        let state = body["state"] as? String ?? "stopped"

        var nowPlaying: RoonNowPlaying?
        if let now = body["now_playing"] as? [String: Any] {
            let threeLine = now["three_line"] as? [String: Any]
            let twoLine = now["two_line"] as? [String: Any]
            let title = (threeLine?["line1"] as? String) ?? (twoLine?["line1"] as? String) ?? ""
            let artist = (threeLine?["line2"] as? String) ?? (twoLine?["line2"] as? String) ?? ""
            let album = (threeLine?["line3"] as? String) ?? ""
            nowPlaying = RoonNowPlaying(
                title: title,
                artist: artist,
                album: album,
                length: now["length"] as? Double,
                seekPosition: now["seek_position"] as? Double
            )
        }

        return RoonZone(id: id, displayName: name, state: state, nowPlaying: nowPlaying, lastSeekUpdate: Date())
    }
}
