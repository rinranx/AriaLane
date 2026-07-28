import AppKit

@MainActor
final class DockProgressController {
    private let progressView = DockProgressView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))

    func update(with transfers: [TransferItem]) {
        let snapshot = DockProgressSnapshot(transfers: transfers)
        guard snapshot.liveCount > 0 else {
            NSApp.dockTile.contentView = nil
            NSApp.dockTile.badgeLabel = nil
            NSApp.dockTile.display()
            return
        }

        progressView.icon = NSApp.applicationIconImage
        progressView.progress = snapshot.progress
        NSApp.dockTile.contentView = progressView
        NSApp.dockTile.badgeLabel = snapshot.activeCount > 0
            ? String(snapshot.activeCount)
            : nil
        NSApp.dockTile.display()
    }

    func clear() {
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.badgeLabel = nil
        NSApp.dockTile.display()
    }
}

private final class DockProgressView: NSView {
    var icon: NSImage? {
        didSet { needsDisplay = true }
    }

    var progress: Double = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        icon?.draw(
            in: bounds,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )

        let trackRect = NSRect(x: 13, y: 9, width: 102, height: 12)
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: 6, yRadius: 6)
        NSColor.black.withAlphaComponent(0.46).setFill()
        trackPath.fill()

        let innerRect = trackRect.insetBy(dx: 2, dy: 2)
        let fillWidth = innerRect.width * min(max(progress, 0), 1)
        guard fillWidth > 0 else { return }

        let fillRect = NSRect(
            x: innerRect.minX,
            y: innerRect.minY,
            width: max(fillWidth, innerRect.height),
            height: innerRect.height
        )
        let fillPath = NSBezierPath(
            roundedRect: fillRect,
            xRadius: innerRect.height / 2,
            yRadius: innerRect.height / 2
        )
        NSColor.controlAccentColor.setFill()
        fillPath.fill()
    }
}
