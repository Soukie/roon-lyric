import Combine
import Foundation

final class AppModel: ObservableObject {
    @Published var manualCoreName = ""
    @Published var manualCoreHost = ""
    @Published var manualCorePort = "9100"

    let discovery = RoonDiscoveryService()
    let manualStore = ManualCoreStore()
    let connection = RoonConnectionService()
    let displayStore = DisplayPreferencesStore()
    let lyricsProviderStore: LyricsProviderSettingsStore
    let syncEngine: LyricsSyncEngine
    let desktopLyrics = DesktopLyricsWindowController()

    private var cancellables: Set<AnyCancellable> = []

    init() {
        let lyricsProviderStore = LyricsProviderSettingsStore()
        self.lyricsProviderStore = lyricsProviderStore
        self.syncEngine = LyricsSyncEngine(
            resolver: LyricsResolver(settingsProvider: { lyricsProviderStore.settings })
        )

        AppLogger.startSession()
        AppLogger.info("Lifecycle", "app model initialized")
        forwardChildObjectChanges()
        discovery.setTargetHosts(manualStore.cores.map(\.host))
        discovery.startScanning()

        manualStore.$cores
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cores in
                self?.discovery.setTargetHosts(cores.map(\.host))
            }
            .store(in: &cancellables)

        connection.$zones
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncEngine.update(zone: self?.connection.activeZone)
            }
            .store(in: &cancellables)

        connection.$selectedZoneID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncEngine.update(zone: self?.connection.activeZone)
            }
            .store(in: &cancellables)

        connection.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                AppLogger.info("Roon", "connection phase changed: \(phase.label)")
                guard case .connected = phase,
                      let core = self?.connection.connectedCore,
                      core.source == .manual else {
                    return
                }
                self?.manualStore.markConnected(core)
            }
            .store(in: &cancellables)

        syncEngine.$currentLine
            .combineLatest(syncEngine.$nextLine, syncEngine.$statusText, displayStore.$preferences)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] current, next, status, preferences in
                self?.desktopLyrics.update(current: current, next: next, status: status, preferences: preferences)
            }
            .store(in: &cancellables)
    }

    private func forwardChildObjectChanges() {
        discovery.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        manualStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        connection.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        displayStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        lyricsProviderStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        syncEngine.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var allCores: [RoonCore] {
        let discoveredEndpoints = Set(discovery.discoveredCores.map(\.endpoint))
        return discovery.discoveredCores + manualStore.cores.filter { !discoveredEndpoints.contains($0.endpoint) }
    }

    func connect(_ core: RoonCore) {
        AppLogger.info("Roon", "user requested connect core=\(core.name) endpoint=\(core.endpoint) source=\(core.source.rawValue)")
        connection.connect(to: core)
    }

    func saveManualCoreAndConnect() {
        guard let port = Int(manualCorePort) else { return }
        AppLogger.info("Roon", "saving manual core host=\(manualCoreHost.trimmingCharacters(in: .whitespacesAndNewlines)) port=\(port)")
        manualStore.upsert(name: manualCoreName, host: manualCoreHost, port: port)
        discovery.sendQuery(to: manualCoreHost)
        guard let core = manualStore.cores.first(where: { $0.id == "manual:\(manualCoreHost.trimmingCharacters(in: .whitespacesAndNewlines)):\(port)" }) else {
            AppLogger.warning("Roon", "manual core was not found after save")
            return
        }
        connect(core)
    }

    func showLyricsWindow() {
        AppLogger.info("Windowing", "show desktop lyrics requested")
        desktopLyrics.show()
    }

    func hideLyricsWindow() {
        AppLogger.info("Windowing", "hide desktop lyrics requested")
        desktopLyrics.hide()
    }
}
