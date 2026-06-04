import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            roonSettings
                .tabItem {
                    Label("Roon", systemImage: "network")
                }

            lyricSettings
                .tabItem {
                    Label("歌词", systemImage: "text.quote")
                }

            displaySettings
                .tabItem {
                    Label("显示", systemImage: "paintpalette")
                }
        }
        .padding(20)
    }

    private var roonSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Roon Core")
                .font(.title2.weight(.semibold))

            Text(model.connection.phase.label)
                .foregroundStyle(.secondary)

            List {
                Section("自动发现") {
                    ForEach(model.discovery.discoveredCores) { core in
                        SettingsCoreRow(core: core) {
                            model.connect(core)
                        }
                    }
                }

                Section("手动 Core") {
                    ForEach(model.manualStore.cores) { core in
                        SettingsCoreRow(core: core) {
                            model.connect(core)
                        }
                        .contextMenu {
                            Button("删除") {
                                model.manualStore.delete(core)
                            }
                        }
                    }
                }
            }

            HStack {
                Button {
                    model.discovery.sendQuery()
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
                Button {
                    model.connection.disconnect()
                } label: {
                    Label("断开连接", systemImage: "xmark.circle")
                }
            }
        }
    }

    private var lyricSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("歌词源")
                    .font(.title2.weight(.semibold))

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("启用 LRCLIB", isOn: lrclibEnabledBinding)
                        Text("默认公开同步歌词源，优先用于 LRC 歌词匹配。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                } label: {
                    Label("LRCLIB", systemImage: "checkmark.circle")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("启用 QQ 音乐官方/授权渠道", isOn: qqMusicEnabledBinding)
                        TextField("授权 API Base URL", text: qqMusicBaseURLBinding)
                        TextField("App ID", text: qqMusicAppIDBinding)
                        SecureField("Access Token", text: qqMusicAccessTokenBinding)
                        Text("QQ 音乐未提供稳定公开歌词 API；这里仅用于配置你已获得授权的官方或合作方接口。默认不会使用逆向接口。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                } label: {
                    Label("QQ 音乐", systemImage: "music.mic")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("启用 Spotify 元数据匹配", isOn: spotifyEnabledBinding)
                        TextField("Client ID", text: spotifyClientIDBinding)
                        SecureField("Client Secret", text: spotifyClientSecretBinding)
                        TextField("Market，例如 US", text: spotifyMarketBinding)
                            .frame(maxWidth: 160)
                        Text("Spotify 官方 Web API 可用于搜索曲目和 ISRC 等元数据匹配，但没有公开歌词获取 endpoint。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(6)
                } label: {
                    Label("Spotify", systemImage: "waveform")
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var displaySettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("桌面歌词")
                .font(.title2.weight(.semibold))

            Slider(value: fontSizeBinding, in: 18...60) {
                Text("字号")
            } minimumValueLabel: {
                Text("18")
            } maximumValueLabel: {
                Text("60")
            }

            Slider(value: opacityBinding, in: 0.35...1.0) {
                Text("透明度")
            }

            Toggle("显示下一句", isOn: showNextLineBinding)

            ColorPicker("文字颜色", selection: Binding(
                get: { model.displayStore.preferences.color },
                set: { color in
                    let nsColor = NSColor(color)
                    model.displayStore.preferences.red = Double(nsColor.redComponent)
                    model.displayStore.preferences.green = Double(nsColor.greenComponent)
                    model.displayStore.preferences.blue = Double(nsColor.blueComponent)
                }
            ))

            Button {
                model.showLyricsWindow()
            } label: {
                Label("预览桌面歌词", systemImage: "eye")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { model.displayStore.preferences.fontSize },
            set: { model.displayStore.preferences.fontSize = $0 }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { model.displayStore.preferences.opacity },
            set: { model.displayStore.preferences.opacity = $0 }
        )
    }

    private var showNextLineBinding: Binding<Bool> {
        Binding(
            get: { model.displayStore.preferences.showNextLine },
            set: { model.displayStore.preferences.showNextLine = $0 }
        )
    }

    private var lrclibEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.lyricsProviderStore.settings.lrclibEnabled },
            set: { model.lyricsProviderStore.settings.lrclibEnabled = $0 }
        )
    }

    private var qqMusicEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.lyricsProviderStore.settings.qqMusicEnabled },
            set: { model.lyricsProviderStore.settings.qqMusicEnabled = $0 }
        )
    }

    private var qqMusicBaseURLBinding: Binding<String> {
        Binding(
            get: { model.lyricsProviderStore.settings.qqMusicBaseURL },
            set: { model.lyricsProviderStore.settings.qqMusicBaseURL = $0 }
        )
    }

    private var qqMusicAppIDBinding: Binding<String> {
        Binding(
            get: { model.lyricsProviderStore.settings.qqMusicAppID },
            set: { model.lyricsProviderStore.settings.qqMusicAppID = $0 }
        )
    }

    private var qqMusicAccessTokenBinding: Binding<String> {
        Binding(
            get: { model.lyricsProviderStore.settings.qqMusicAccessToken },
            set: { model.lyricsProviderStore.settings.qqMusicAccessToken = $0 }
        )
    }

    private var spotifyEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.lyricsProviderStore.settings.spotifyEnabled },
            set: { model.lyricsProviderStore.settings.spotifyEnabled = $0 }
        )
    }

    private var spotifyClientIDBinding: Binding<String> {
        Binding(
            get: { model.lyricsProviderStore.settings.spotifyClientID },
            set: { model.lyricsProviderStore.settings.spotifyClientID = $0 }
        )
    }

    private var spotifyClientSecretBinding: Binding<String> {
        Binding(
            get: { model.lyricsProviderStore.settings.spotifyClientSecret },
            set: { model.lyricsProviderStore.settings.spotifyClientSecret = $0 }
        )
    }

    private var spotifyMarketBinding: Binding<String> {
        Binding(
            get: { model.lyricsProviderStore.settings.spotifyMarket },
            set: { model.lyricsProviderStore.settings.spotifyMarket = $0 }
        )
    }
}

private struct SettingsCoreRow: View {
    var core: RoonCore
    var connect: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(core.name)
                Text(core.endpoint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("连接", action: connect)
        }
        .padding(.vertical, 3)
    }
}
