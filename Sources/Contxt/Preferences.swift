// App-wide settings: appearance, orb size, activation hotkey, login item.

import AppKit
import Carbon.HIToolbox
import ServiceManagement

enum Theme: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon modifier mask
    var label: String

    static let standard = HotKey(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey | shiftKey), label: "D")

    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + label
    }
}

final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    @Published var orbScale: Double {
        didSet {
            defaults.set(orbScale, forKey: "orbScale")
            onRingLayoutChange?()
        }
    }

    @Published var theme: Theme {
        didSet {
            defaults.set(theme.rawValue, forKey: "theme")
            applyTheme()
        }
    }

    @Published var updateInterval: UpdateInterval {
        didSet { defaults.set(updateInterval.rawValue, forKey: "updateInterval") }
    }

    @Published var autoInstallUpdates: Bool {
        didSet { defaults.set(autoInstallUpdates, forKey: "autoInstallUpdates") }
    }

    var lastUpdateCheck: Date? {
        get { defaults.object(forKey: "lastUpdateCheck") as? Date }
        set {
            defaults.set(newValue, forKey: "lastUpdateCheck")
            objectWillChange.send()
        }
    }

    @Published private(set) var hotKey: HotKey
    @Published var hotKeyOK = true

    /// Set by the ring so it re-lays out when the orb size changes.
    var onRingLayoutChange: (() -> Void)?
    /// Set by the app delegate; returns false if the combination is taken.
    var registerToggleHotKey: ((HotKey) -> Bool)?

    private init() {
        let scale = defaults.double(forKey: "orbScale")
        orbScale = scale == 0 ? 1.0 : scale
        theme = Theme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
        updateInterval = UpdateInterval(rawValue: defaults.string(forKey: "updateInterval") ?? "") ?? .weekly
        autoInstallUpdates = defaults.object(forKey: "autoInstallUpdates") as? Bool ?? true
        if let data = defaults.data(forKey: "hotKey"), let saved = try? JSONDecoder().decode(HotKey.self, from: data) {
            hotKey = saved
        } else {
            hotKey = .standard
        }
    }

    func applyTheme() {
        switch theme {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    @discardableResult
    func setHotKey(_ new: HotKey) -> Bool {
        if new == hotKey {
            hotKeyOK = true
            return true
        }
        let ok = registerToggleHotKey?(new) ?? false
        hotKeyOK = ok
        if ok {
            hotKey = new
            if let data = try? JSONEncoder().encode(new) { defaults.set(data, forKey: "hotKey") }
        }
        return ok
    }

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            contxtLog("launch at login failed: \(error)")
        }
        objectWillChange.send()
    }
}
