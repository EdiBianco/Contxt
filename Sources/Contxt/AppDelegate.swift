// Replaces the Electron prototype's globalShortcut registration in
// src/main/index.ts. Electron's globalShortcut is backed by Carbon's
// RegisterEventHotKey, not an NSEvent global monitor — that's why it worked
// there with zero permission prompts. RegisterEventHotKey is a true
// OS-level hotkey: no Input Monitoring/Accessibility grant needed, no TCC
// involved at all. Escape is only grabbed while the ring is visible — it's
// too common a key to intercept globally all the time.

import AppKit
import Carbon.HIToolbox
import Combine

private func fourCharCode(_ string: String) -> FourCharCode {
    var result: FourCharCode = 0
    for byte in string.utf8 { result = (result << 8) + FourCharCode(byte) }
    return result
}

private func hotKeyEventHandler(_ nextHandler: EventHandlerCallRef?, _ eventRef: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    delegate.handleHotKey(id: hotKeyID.id)
    return noErr
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var ring: RingController!
    private var statusItem: NSStatusItem!
    private var updateItem: NSMenuItem!
    private var updateObserver: AnyCancellable?

    private var eventHandlerRef: EventHandlerRef?
    private var toggleHotKeyRef: EventHotKeyRef?
    private var escapeHotKeyRef: EventHotKeyRef?

    private let toggleHotKeyID = EventHotKeyID(signature: fourCharCode("CTX1"), id: 1)
    private let escapeHotKeyID = EventHotKeyID(signature: fourCharCode("CTX2"), id: 2)

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateDuplicateInstances()

        Preferences.shared.applyTheme()
        ring = RingController()
        installHotKeyHandler()
        Preferences.shared.registerToggleHotKey = { [weak self] in self?.registerToggle($0) ?? false }
        Preferences.shared.hotKeyOK = registerToggle(Preferences.shared.hotKey)
        setUpStatusItem()
        Permissions.checkAndPrompt()

        Updater.shared.isSafeToRestart = { [weak self] in
            !(self?.ring.isVisible ?? false) && !SettingsWindowController.shared.isVisible
        }
        Updater.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let toggleHotKeyRef { UnregisterEventHotKey(toggleHotKeyRef) }
        if let escapeHotKeyRef { UnregisterEventHotKey(escapeHotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    /// Repeated test builds get launched without quitting the last one —
    /// kill any other running copy so only this process holds the hotkey.
    private func terminateDuplicateInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let myPID = ProcessInfo.processInfo.processIdentifier

        for app in NSWorkspace.shared.runningApplications
        where app.bundleIdentifier == bundleID && app.processIdentifier != myPID {
            app.forceTerminate()
        }
    }

    private func installHotKeyHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &eventType, selfPtr, &eventHandlerRef)
    }

    /// Registers the new combination before releasing the old one, so a taken
    /// combination leaves the working hotkey in place.
    private func registerToggle(_ hotKey: HotKey) -> Bool {
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, toggleHotKeyID, GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr else {
            contxtLog("hotkey \(hotKey.display) not registered: status \(status)")
            return false
        }
        if let toggleHotKeyRef { UnregisterEventHotKey(toggleHotKeyRef) }
        toggleHotKeyRef = newRef
        return true
    }

    fileprivate func handleHotKey(id: UInt32) {
        switch id {
        case toggleHotKeyID.id:
            ring.toggle()
            syncEscapeHotKey()
        case escapeHotKeyID.id:
            ring.hide()
            syncEscapeHotKey()
        default:
            break
        }
    }

    private func syncEscapeHotKey() {
        if ring.isVisible {
            guard escapeHotKeyRef == nil else { return }
            RegisterEventHotKey(UInt32(kVK_Escape), 0, escapeHotKeyID, GetApplicationEventTarget(), 0, &escapeHotKeyRef)
        } else if let ref = escapeHotKeyRef {
            UnregisterEventHotKey(ref)
            escapeHotKeyRef = nil
        }
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = Self.makeMenuBarIcon(size: 18)
        icon.isTemplate = true // macOS tints this for light/dark menu bars
        statusItem.button?.image = icon

        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        updateItem = NSMenuItem(title: "Restart to Update", action: #selector(installUpdate), keyEquivalent: "")
        updateItem.target = self
        updateItem.isHidden = true
        menu.addItem(updateItem)
        updateObserver = Updater.shared.$state.receive(on: DispatchQueue.main).sink { [weak self] state in
            if case .ready(let version) = state {
                self?.updateItem.title = "Restart to Update to \(version)"
                self?.updateItem.isHidden = false
            } else {
                self?.updateItem.isHidden = true
            }
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Contxt", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func installUpdate() {
        Updater.shared.installAndRelaunch()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Same ring motif as RingView: a center dot with items around it.
    /// Drawn in code (not loaded from a bundled asset) so there's no
    /// resource-lookup failure path that leaves the menu bar item blank.
    private static func makeMenuBarIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = size * 0.32
            let dotDiameter = size * 0.22
            let centerDiameter = size * 0.26

            NSColor.black.setFill()
            NSBezierPath(ovalIn: CGRect(
                x: center.x - centerDiameter / 2, y: center.y - centerDiameter / 2,
                width: centerDiameter, height: centerDiameter
            )).fill()

            for i in 0..<6 {
                let angle = CGFloat(i) * 2 * .pi / 6 - .pi / 2
                let x = center.x + cos(angle) * radius
                let y = center.y + sin(angle) * radius
                NSBezierPath(ovalIn: CGRect(
                    x: x - dotDiameter / 2, y: y - dotDiameter / 2,
                    width: dotDiameter, height: dotDiameter
                )).fill()
            }
            return true
        }
    }
}
