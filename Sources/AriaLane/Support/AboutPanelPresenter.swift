import AppKit
import SwiftUI

@MainActor
enum AboutPanelPresenter {
    private static var windowController: NSWindowController?

    static func show() {
        let controller = windowController ?? makeWindowController()
        windowController = controller

        controller.window?.contentView = NSHostingView(rootView: AboutPanelView())
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func makeWindowController() -> NSWindowController {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 568, height: 340),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .windowBackgroundColor
        panel.contentView = NSHostingView(rootView: AboutPanelView())
        return NSWindowController(window: panel)
    }
}

private struct AboutPanelView: View {
    private let xHandle = "@rinran223"

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 30)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 88, height: 88)
                .accessibilityLabel("AriaLane")

            Text("AriaLane")
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 20)

            Text(versionTitle)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            VStack(spacing: 8) {
                Link(destination: xURL) {
                    HStack(spacing: 5) {
                        XLogo(size: 13)
                        Text(xHandle)
                    }
                }
                .accessibilityLabel("X \(xHandle)")

                Text(
                    "Copyright © 2026 rinran (a@rinran.me) · GPL-3.0-only"
                )
            }
            .font(.system(size: 14))
            .padding(.top, 20)

            Spacer(minLength: 30)
        }
        .frame(width: 568, height: 340)
    }

    private var versionTitle: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? L10n.string("开发版")
        return L10n.string("版本 \(version)")
    }

    private var xURL: URL {
        URL(string: "https://x.com/rinran223")!
    }
}
