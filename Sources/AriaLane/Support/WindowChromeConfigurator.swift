import AppKit
import SwiftUI

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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindowIfAvailable()
    }

    func configureWindowIfAvailable() {
        guard let window, configuredWindow !== window else {
            return
        }
        configuredWindow = window

        let storedFrameKey = "NSWindow Frame \(autosaveName)"
        if UserDefaults.standard.string(forKey: storedFrameKey) != nil {
            _ = window.setFrameUsingName(autosaveName)
        }
        _ = window.setFrameAutosaveName(autosaveName)
    }
}

private final class WindowChromeProbeView: NSView {
    private static let highlightIdentifier = NSUserInterfaceItemIdentifier(
        "AriaLane.TopInsetHighlight"
    )

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindowIfAvailable()
    }

    func configureWindowIfAvailable() {
        guard let window else { return }

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
