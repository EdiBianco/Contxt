// Small transient HUD for messages that have no other place to appear.

import AppKit

enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ text: String, seconds: TimeInterval = 3.5) {
        DispatchQueue.main.async {
            panel?.orderOut(nil)

            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.textColor = .white
            label.sizeToFit()

            let size = NSSize(width: label.frame.width + 40, height: 38)
            let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            effect.material = .hudWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = size.height / 2
            effect.layer?.masksToBounds = true
            label.frame.origin = NSPoint(x: 20, y: (size.height - label.frame.height) / 2)
            effect.addSubview(label)

            let toast = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            toast.isOpaque = false
            toast.backgroundColor = .clear
            toast.hasShadow = true
            toast.level = .statusBar
            toast.ignoresMouseEvents = true
            toast.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            toast.contentView = effect

            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                toast.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 60))
            }
            toast.orderFrontRegardless()
            panel = toast

            hideWork?.cancel()
            let work = DispatchWorkItem { toast.orderOut(nil) }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        }
    }
}
