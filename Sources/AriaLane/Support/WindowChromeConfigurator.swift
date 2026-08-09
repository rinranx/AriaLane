import AppKit
import SwiftUI

enum WindowLayoutPersistence {
    static let mainWindowFrameAutosaveName = "AriaLane.MainWindow"
    static let mainSidebarWidthKey = "AriaLane.MainSidebarWidth"
    static let mainSidebarCollapsedKey = "AriaLane.MainSidebarCollapsed"
    static let mainSidebarManualSelectionKey =
        "AriaLane.MainSidebarHasManualSelection"

    static func windowFrame(
        named name: String,
        defaults: UserDefaults = .standard
    ) -> NSRect? {
        guard let value = defaults.string(forKey: windowFrameKey(named: name)) else {
            return nil
        }

        let frame = NSRectFromString(value)
        guard frame.origin.x.isFinite,
              frame.origin.y.isFinite,
              frame.width.isFinite,
              frame.height.isFinite,
              frame.width > 0,
              frame.height > 0 else {
            return nil
        }
        return frame
    }

    static func saveWindowFrame(
        _ frame: NSRect,
        named name: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(
            NSStringFromRect(frame),
            forKey: windowFrameKey(named: name)
        )
    }

    private static func windowFrameKey(named name: String) -> String {
        "AriaLane.WindowFrame.\(name)"
    }
}

struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowChromeProbeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let probe = nsView as? WindowChromeProbeView else { return }
        probe.configureWindowIfAvailable()
    }
}

struct WindowFrameAutosaveConfigurator: NSViewRepresentable {
    let autosaveName: String

    func makeNSView(context: Context) -> NSView {
        WindowFrameAutosaveProbeView(autosaveName: autosaveName)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let probe = nsView as? WindowFrameAutosaveProbeView else {
            return
        }
        probe.configureWindowIfAvailable()
    }
}

private final class WindowFrameAutosaveProbeView: NSView {
    private let autosaveName: String
    private weak var configuredWindow: NSWindow?

    init(autosaveName: String) {
        self.autosaveName = autosaveName
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard let newWindow else {
            stopObservingWindow()
            return
        }
        configure(window: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindowIfAvailable()
    }

    func configureWindowIfAvailable() {
        guard let window else { return }
        configure(window: window)
    }

    private func configure(window: NSWindow) {
        guard configuredWindow !== window else { return }
        stopObservingWindow()
        configuredWindow = window

        if let frame = WindowLayoutPersistence.windowFrame(named: autosaveName) {
            let matchingScreen = NSScreen.screens.first {
                $0.visibleFrame.intersects(frame)
            } ?? window.screen ?? NSScreen.main
            let restoredFrame = window.constrainFrameRect(
                frame,
                to: matchingScreen
            )
            window.setFrame(restoredFrame, display: false)
        } else if UserDefaults.standard.string(
            forKey: "NSWindow Frame \(autosaveName)"
        ) != nil {
            _ = window.setFrameUsingName(autosaveName)
        }

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(windowFrameDidChange(_:)),
            name: NSWindow.didMoveNotification,
            object: window
        )
        center.addObserver(
            self,
            selector: #selector(windowFrameDidChange(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )
        center.addObserver(
            self,
            selector: #selector(windowFrameDidChange(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    @objc
    private func windowFrameDidChange(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              configuredWindow === window else {
            return
        }
        WindowLayoutPersistence.saveWindowFrame(
            window.frame,
            named: autosaveName
        )
    }

    private func stopObservingWindow() {
        if let configuredWindow {
            WindowLayoutPersistence.saveWindowFrame(
                configuredWindow.frame,
                named: autosaveName
            )
        }
        NotificationCenter.default.removeObserver(self)
        configuredWindow = nil
    }
}

private final class WindowChromeProbeView: NSView {
    private static let highlightIdentifier = NSUserInterfaceItemIdentifier(
        "AriaLane.TopInsetHighlight"
    )

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard let newWindow else { return }
        configure(window: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindowIfAvailable()
    }

    func configureWindowIfAvailable() {
        guard let window else { return }
        configure(window: window)
    }

    private func configure(window: NSWindow) {
        window.animationBehavior = .none
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        window.titleVisibility = .hidden
        window.toolbar?.sizeMode = .small

        guard let frameView = window.contentView?.superview else { return }
        guard !frameView.subviews.contains(where: {
            $0.identifier == Self.highlightIdentifier
        }) else {
            return
        }

        let highlight = NSView()
        highlight.identifier = Self.highlightIdentifier
        highlight.translatesAutoresizingMaskIntoConstraints = false
        highlight.wantsLayer = true
        highlight.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        highlight.setAccessibilityElement(false)

        frameView.addSubview(highlight, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            highlight.topAnchor.constraint(equalTo: frameView.topAnchor),
            highlight.leadingAnchor.constraint(equalTo: frameView.leadingAnchor),
            highlight.trailingAnchor.constraint(equalTo: frameView.trailingAnchor),
            highlight.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }
}
