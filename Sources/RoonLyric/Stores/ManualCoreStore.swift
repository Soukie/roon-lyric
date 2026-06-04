import Combine
import Foundation

final class ManualCoreStore: ObservableObject {
    @Published private(set) var cores: [RoonCore] = []

    private let key = "manualRoonCores"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func upsert(name: String, host: String, port: Int) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, port > 0 else { return }

        let id = "manual:\(trimmedHost):\(port)"
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let core = RoonCore(
            id: id,
            name: displayName.isEmpty ? trimmedHost : displayName,
            host: trimmedHost,
            port: port,
            source: .manual,
            lastSeen: nil,
            lastConnected: nil
        )

        if let index = cores.firstIndex(where: { $0.id == id }) {
            cores[index] = core
        } else {
            cores.append(core)
        }
        save()
    }

    func markConnected(_ core: RoonCore) {
        guard let index = cores.firstIndex(where: { $0.id == core.id }) else { return }
        cores[index].lastConnected = Date()
        save()
    }

    func delete(_ core: RoonCore) {
        cores.removeAll { $0.id == core.id }
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: key) else { return }
        cores = (try? JSONDecoder().decode([RoonCore].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(cores) else { return }
        defaults.set(data, forKey: key)
    }
}
