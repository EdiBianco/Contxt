// Replaces the Electron prototype's createRing/showRing/hideRing in
// src/main/index.ts. A non-activating NSPanel at .statusBar level: it never
// steals focus from Finder and still receives drag events via
// NSDraggingDestination on its content view. (.screenSaver level was skipped
// by drag-destination lookup, so don't raise it.)

import AppKit

final class RingController {
    private let panel: NSPanel
    private let ringView: RingView

    init() {
        let size = RingView.ringSize
        let rect = NSRect(x: 0, y: 0, width: size, height: size)

        panel = NSPanel(contentRect: rect, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true

        ringView = RingView(frame: rect)
        panel.contentView = ringView
        ringView.onDismiss = { [weak self] in self?.hide() }
        DestinationStore.shared.onChange = { [weak ringView] in ringView?.rebuildAll() }
        Preferences.shared.onRingLayoutChange = { [weak ringView] in ringView?.rebuildAll() }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        let size = RingView.ringSize
        let cursor = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: cursor.x - size / 2, y: cursor.y - size / 2))
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        ringView.reset()
        panel.orderFrontRegardless()
        ringView.beginTracking()
        contxtLog("show() frame=\(panel.frame)")
    }

    func hide() {
        ringView.endTracking()
        panel.orderOut(nil)
    }
}
