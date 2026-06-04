import AppKit
import SwiftUI

final class DesktopLyricsWindowController {
    private var panel: NSPanel?
    private var state = DesktopLyricsState()
    private var isVisible = false

    func show() {
        let wasVisible = isVisible
        isVisible = true
        if panel == nil {
            createPanel()
        }
        if !wasVisible {
            AppLogger.info("Windowing", "desktop lyrics panel shown")
        }
        panel?.orderFrontRegardless()
    }

    func hide() {
        isVisible = false
        AppLogger.info("Windowing", "desktop lyrics panel hidden")
        panel?.orderOut(nil)
    }

    func update(current: LyricLine?, next: LyricLine?, status: String, preferences: DisplayPreferences) {
        state.current = current?.text ?? status
        state.next = next?.text
        state.preferences = preferences
        if isVisible {
            show()
        }
    }

    private func createPanel() {
        let frame = NSRect(x: 280, y: 120, width: 980, height: 148)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.ignoresMouseEvents = false

        let view = DesktopLyricsView(state: state)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = frame
        panel.contentView = hosting
        self.panel = panel
        AppLogger.info("Windowing", "desktop lyrics panel created")
    }
}

final class DesktopLyricsState: ObservableObject {
    @Published var current = "Roon Lyric"
    @Published var next: String?
    @Published var preferences = DisplayPreferences.defaults
}

struct DesktopLyricsView: View {
    @ObservedObject var state: DesktopLyricsState

    var body: some View {
        VStack(spacing: 6) {
            Text(state.current)
                .font(.system(size: state.preferences.fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(state.preferences.color)
                .shadow(color: .black.opacity(0.9), radius: 4, x: 0, y: 2)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .frame(maxWidth: .infinity)

            if state.preferences.showNextLine, let next = state.next {
                Text(next)
                    .font(.system(size: max(15, state.preferences.fontSize * 0.48), weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(.black.opacity(0.001))
    }
}
