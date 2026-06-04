import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List {
                Section("自动发现") {
                    ForEach(model.discovery.discoveredCores) { core in
                        CoreRow(core: core, isConnected: model.connection.connectedCore?.id == core.id) {
                            model.connect(core)
                        }
                    }

                    if model.discovery.discoveredCores.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("暂未发现 Roon Core")
                                .font(.headline)
                            Text("如果局域网屏蔽了组播，请在右侧手动输入 Core 地址。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section("手动配置") {
                    ForEach(model.manualStore.cores) { core in
                        CoreRow(core: core, isConnected: model.connection.connectedCore?.id == core.id) {
                            model.connect(core)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    connectionCard
                    manualCoreCard
                    playbackCard
                    lyricsCard
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Roon Lyric")
                    .font(.system(size: 30, weight: .semibold))
                Text("Roon 桌面歌词同步工具")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.discovery.sendQuery()
            } label: {
                Label("扫描", systemImage: "dot.radiowaves.left.and.right")
            }
            Button {
                model.showLyricsWindow()
            } label: {
                Label("桌面歌词", systemImage: "text.bubble")
            }
        }
    }

    private var connectionCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(model.connection.phase.label, systemImage: statusIcon)
                        .font(.headline)
                    Spacer()
                    if model.discovery.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let core = model.connection.connectedCore {
                    Text("当前 Core：\(core.name)  \(core.endpoint)")
                        .foregroundStyle(.secondary)
                } else {
                    Text("优先自动发现 Roon Core；发现失败时使用手动 Core 连接。")
                        .foregroundStyle(.secondary)
                }

                if let error = model.discovery.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .padding(6)
        } label: {
            Label("连接状态", systemImage: "network")
        }
    }

    private var manualCoreCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("名称，例如 Roon Nucleus", text: $model.manualCoreName)
                    TextField("Host 或 IP", text: $model.manualCoreHost)
                    TextField("端口", text: $model.manualCorePort)
                        .frame(width: 90)
                    Button {
                        model.saveManualCoreAndConnect()
                    } label: {
                        Label("保存并连接", systemImage: "plus.circle")
                    }
                    .disabled(model.manualCoreHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("端口通常由自动发现返回；如果组播不可用，请从 Roon Core 所在机器或日志中确认 WebSocket 端口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
        } label: {
            Label("手动 Roon Core", systemImage: "server.rack")
        }
    }

    private var playbackCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if !model.connection.zones.isEmpty {
                    Picker("Zone", selection: Binding(
                        get: { model.connection.selectedZoneID ?? model.connection.activeZone?.id ?? "" },
                        set: { id in
                            model.connection.selectZone(model.connection.zones.first(where: { $0.id == id }))
                        }
                    )) {
                        ForEach(model.connection.zones) { zone in
                            Text(zone.displayName).tag(zone.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let zone = model.connection.activeZone,
                   let nowPlaying = zone.nowPlaying {
                    Text(nowPlaying.title)
                        .font(.title2.weight(.semibold))
                    Text([nowPlaying.artist, nowPlaying.album].filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(zone.state)
                        Text((nowPlaying.seekPosition ?? 0).mmss)
                        Text("/")
                        Text((nowPlaying.length ?? 0).mmss)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text("连接并播放 Roon 音乐后，这里会显示当前曲目。")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(6)
        } label: {
            Label("当前播放", systemImage: "music.note.list")
        }
    }

    private var lyricsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.syncEngine.currentLine?.text ?? model.syncEngine.statusText)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let next = model.syncEngine.nextLine?.text {
                    Text(next)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button {
                        model.showLyricsWindow()
                    } label: {
                        Label("显示", systemImage: "eye")
                    }
                    Button {
                        model.hideLyricsWindow()
                    } label: {
                        Label("隐藏", systemImage: "eye.slash")
                    }
                }
            }
            .padding(6)
        } label: {
            Label("歌词预览", systemImage: "quote.bubble")
        }
    }

    private var statusIcon: String {
        switch model.connection.phase {
        case .connected:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .connecting, .waitingForAuthorization, .scanning:
            return "clock"
        case .disconnected:
            return "circle"
        }
    }
}

private struct CoreRow: View {
    var core: RoonCore
    var isConnected: Bool
    var connect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: core.source == .manual ? "server.rack" : "dot.radiowaves.left.and.right")
                .foregroundStyle(isConnected ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(core.name)
                    .lineLimit(1)
                Text(core.endpoint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("连接", action: connect)
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
