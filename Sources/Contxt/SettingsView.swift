// Settings window: general options plus sheets for each kind of ring item.

import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Building blocks

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct NavRow: View {
    let symbol: String
    let color: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 26, height: 26)
                    .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Thin matte slider: slim track, accent fill, white thumb.
private struct MatteSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.14)).frame(height: 5)
                Capsule().fill(Color.accentColor).frame(width: max(5, (width - 18) * t + 9), height: 5)
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .frame(width: 18, height: 18)
                    .offset(x: (width - 18) * t)
            }
            .frame(height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let p = min(max(0, (drag.location.x - 9) / max(1, width - 18)), 1)
                    value = range.lowerBound + p * (range.upperBound - range.lowerBound)
                }
            )
        }
        .frame(height: 18)
    }
}

// MARK: - Hotkey recorder

final class HotKeyRecorderView: NSView {
    var onCapture: ((HotKey) -> Void)?
    var display = "" { didSet { needsDisplay = true } }
    private var recording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 118, height: 26) }

    override func mouseDown(with event: NSEvent) {
        recording = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        recording ? capture(event) : false
    }

    override func keyDown(with event: NSEvent) {
        if !(recording && capture(event)) { super.keyDown(with: event) }
    }

    private func capture(_ event: NSEvent) -> Bool {
        if event.keyCode == UInt16(kVK_Escape) {
            recording = false
            window?.makeFirstResponder(nil)
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }

        let label: String
        switch Int(event.keyCode) {
        case kVK_Space: label = "Space"
        case kVK_Return: label = "↩"
        case kVK_Tab: label = "⇥"
        default: label = event.charactersIgnoringModifiers?.uppercased() ?? ""
        }
        guard modifiers != 0, !label.isEmpty else {
            NSSound.beep()
            return true
        }

        recording = false
        window?.makeFirstResponder(nil)
        onCapture?(HotKey(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: label))
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.18) : NSColor.labelColor.withAlphaComponent(0.08)).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()

        let text = (recording ? "Type shortcut…" : display) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }
}

private struct HotKeyField: NSViewRepresentable {
    @ObservedObject var prefs: Preferences

    func makeNSView(context: Context) -> HotKeyRecorderView {
        let view = HotKeyRecorderView()
        view.onCapture = { hotKey in Preferences.shared.setHotKey(hotKey) }
        view.display = prefs.hotKey.display
        return view
    }

    func updateNSView(_ view: HotKeyRecorderView, context: Context) {
        view.display = prefs.hotKey.display
    }
}

// MARK: - Main view

struct SettingsView: View {
    private enum Sheet: String, Identifiable {
        case folders, apps, contacts, shortcuts, order, dropZone
        var id: String { rawValue }
    }

    @ObservedObject private var store = DestinationStore.shared
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var dropZone = DropZoneStore.shared
    @ObservedObject private var updater = Updater.shared
    @State private var sheet: Sheet?

    private func count(_ kinds: DestinationRecord.Kind...) -> Int {
        store.records.filter { kinds.contains($0.kind) }.count
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 76, height: 76)
                Text("Contxt").font(.system(size: 20, weight: .bold))
                Text("Drag-and-drop everything").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("\(store.records.count) items configured. Press \(prefs.hotKey.display) to activate")
                        .font(.caption)
                }
                .padding(.top, 2)
            }
            .padding(.top, 4)

            Card {
                SettingRow(title: "Start at Login", subtitle: "Launch Contxt when you sign in") {
                    Toggle("", isOn: Binding(get: { prefs.launchAtLogin }, set: { prefs.setLaunchAtLogin($0) }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                Divider().padding(.leading, 12)
                SettingRow(title: "Appearance", subtitle: "Ring and settings theme") {
                    Picker("", selection: $prefs.theme) {
                        ForEach(Theme.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                Divider().padding(.leading, 12)
                SettingRow(title: "Orb Size", subtitle: "Size of the circles on the ring") {
                    MatteSlider(value: $prefs.orbScale, range: 0.8...1.3).frame(width: 130)
                }
                Divider().padding(.leading, 12)
                SettingRow(title: "Activation Hotkey", subtitle: "Show the ring from anywhere") {
                    HStack(spacing: 8) {
                        HotKeyField(prefs: prefs).frame(width: 118, height: 26)
                        Image(systemName: prefs.hotKeyOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(prefs.hotKeyOK ? Color.green : Color.red)
                            .help(prefs.hotKeyOK ? "Hotkey active" : "That combination is already taken")
                    }
                }
            }

            Card {
                SettingRow(title: "Check for Updates", subtitle: "From GitHub releases") {
                    Picker("", selection: $prefs.updateInterval) {
                        ForEach(UpdateInterval.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                Divider().padding(.leading, 12)
                SettingRow(title: "Install Automatically", subtitle: "Restart to update when Contxt is idle") {
                    Toggle("", isOn: $prefs.autoInstallUpdates).toggleStyle(.switch).labelsHidden()
                }
                Divider().padding(.leading, 12)
                SettingRow(title: "Version \(updater.currentVersion)", subtitle: updater.statusText) {
                    if case .ready = updater.state {
                        Button("Restart & Update") { updater.installAndRelaunch() }
                    } else {
                        Button("Check Now") { updater.check(userInitiated: true) }
                            .disabled(updater.state == .checking)
                    }
                }
            }

            Card {
                NavRow(symbol: "tray.and.arrow.down.fill", color: .teal, title: "Drop Zone",
                       subtitle: "\(dropZone.urls.count) files stacked") { sheet = .dropZone }
                Divider().padding(.leading, 50)
                NavRow(symbol: "folder.fill", color: .blue, title: "Folders & Locations",
                       subtitle: "\(count(.folder)) folders configured") { sheet = .folders }
                Divider().padding(.leading, 50)
                NavRow(symbol: "app.badge.fill", color: .orange, title: "Applications & Scripts",
                       subtitle: "\(count(.app, .script, .action)) configured") { sheet = .apps }
                Divider().padding(.leading, 50)
                NavRow(symbol: "wand.and.stars", color: .purple, title: "Shortcuts",
                       subtitle: "\(count(.shortcut)) shortcuts configured") { sheet = .shortcuts }
                Divider().padding(.leading, 50)
                NavRow(symbol: "person.crop.circle.fill", color: .green, title: "Contacts",
                       subtitle: "\(count(.contact)) contacts configured") { sheet = .contacts }
                Divider().padding(.leading, 50)
                NavRow(symbol: "arrow.up.arrow.down", color: .pink, title: "Ring Order",
                       subtitle: "Drag to arrange the circles") { sheet = .order }
            }
        }
        .padding(18)
        .frame(width: 400)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .folders: FoldersSheet()
            case .apps: AppsSheet()
            case .contacts: ContactsSheet()
            case .shortcuts: ShortcutsSheet()
            case .order: OrderSheet()
            case .dropZone: DropZoneSheet()
            }
        }
    }
}

// MARK: - Sheets

private struct SheetFrame<Content: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    var scrolls = true
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            Divider()
            if scrolls {
                ScrollView {
                    VStack(spacing: 12) { content }.padding(16)
                }
            } else {
                content
            }
            Divider()
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .padding(12)
        }
        .frame(width: 460, height: 500)
    }
}

private func binding(_ record: DestinationRecord) -> Binding<DestinationRecord> {
    Binding(
        get: { DestinationStore.shared.records.first { $0.id == record.id } ?? record },
        set: { updated in
            if let index = DestinationStore.shared.records.firstIndex(where: { $0.id == updated.id }) {
                DestinationStore.shared.records[index] = updated
            }
        }
    )
}

private func removeButton(_ record: DestinationRecord) -> some View {
    Button {
        DestinationStore.shared.records.removeAll { $0.id == record.id }
    } label: {
        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
    }
    .buttonStyle(.borderless)
    .help("Remove")
}

private func pickURLs(folders: Bool = false, apps: Bool = false) -> [URL] {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    if folders {
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
    } else if apps {
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
    }
    return panel.runModal() == .OK ? panel.urls : []
}

private struct FoldersSheet: View {
    @ObservedObject private var store = DestinationStore.shared

    var body: some View {
        SheetFrame(symbol: "folder.fill", title: "Folders & Locations", subtitle: "Where dropped files are moved or copied") {
            Card {
                let folders = store.records.filter { $0.kind == .folder }
                if folders.isEmpty {
                    Text("No folders yet").font(.caption).foregroundStyle(.secondary).padding(14)
                }
                ForEach(folders) { record in
                    let rec = binding(record)
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: record.path)).resizable().frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Name", text: rec.name).textFieldStyle(.plain).font(.system(size: 13, weight: .medium))
                            Text(record.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 6)
                        Picker("", selection: rec.mode) {
                            ForEach(DropMode.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 120)
                        removeButton(record)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    if record.id != folders.last?.id { Divider().padding(.leading, 52) }
                }
            }
            Text("The selected action is the default. Hold ⌥ while dropping to do the other one.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Add Folder…") {
                for url in pickURLs(folders: true) {
                    store.records.append(DestinationRecord(kind: .folder, name: url.lastPathComponent, path: url.path))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AppsSheet: View {
    @ObservedObject private var store = DestinationStore.shared

    var body: some View {
        SheetFrame(symbol: "app.badge.fill", title: "Applications & Scripts", subtitle: "Open, share or process dropped files") {
            Card {
                ForEach(CommonAction.allCases, id: \.self) { action in
                    HStack(spacing: 10) {
                        Image(nsImage: Destination.action(id: "", label: "", action: action).iconImage())
                            .resizable().frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(action.title).font(.system(size: 13, weight: .medium))
                            Text(action.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { store.hasAction(action) }, set: { store.setAction(action, enabled: $0) }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    if action != CommonAction.allCases.last { Divider().padding(.leading, 50) }
                }
            }

            Card {
                let custom = store.records.filter { $0.kind == .app || $0.kind == .script }
                if custom.isEmpty {
                    Text("No custom apps or scripts yet").font(.caption).foregroundStyle(.secondary).padding(14)
                }
                ForEach(custom) { record in
                    let rec = binding(record)
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: record.path)).resizable().frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Name", text: rec.name).textFieldStyle(.plain).font(.system(size: 13, weight: .medium))
                            Text(record.kind == .app ? "Open with this app" : "Run with files as arguments")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        removeButton(record)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    if record.id != custom.last?.id { Divider().padding(.leading, 50) }
                }
            }

            HStack {
                Button("Add App…") {
                    for url in pickURLs(apps: true) {
                        store.records.append(DestinationRecord(kind: .app, name: url.deletingPathExtension().lastPathComponent, path: url.path))
                    }
                }
                Button("Add Script…") {
                    for url in pickURLs() {
                        store.records.append(DestinationRecord(kind: .script, name: url.deletingPathExtension().lastPathComponent, path: url.path))
                    }
                }
                Spacer()
            }
        }
    }
}

private struct ContactsSheet: View {
    @ObservedObject private var store = DestinationStore.shared
    @State private var picking = false

    var body: some View {
        SheetFrame(symbol: "person.crop.circle.fill", title: "Contacts", subtitle: "Send dropped files to a person") {
            Card {
                let contacts = store.records.filter { $0.kind == .contact }
                if contacts.isEmpty {
                    Text("No contacts yet").font(.caption).foregroundStyle(.secondary).padding(14)
                }
                ForEach(contacts) { record in
                    let rec = binding(record)
                    HStack(spacing: 10) {
                        Image(nsImage: ContactAvatar.image(name: record.name, path: record.avatarPath))
                            .resizable().frame(width: 30, height: 30)
                        Text(record.name).font(.system(size: 13, weight: .medium))
                        Spacer(minLength: 6)
                        Picker("", selection: Binding(get: { rec.wrappedValue.channel ?? .message }, set: { rec.wrappedValue.channel = $0 })) {
                            ForEach(ContactChannel.allCases.filter { channel in
                                switch channel {
                                case .message: return true
                                case .email: return record.email != nil || rec.wrappedValue.channel == .email
                                case .whatsapp: return record.phone != nil || rec.wrappedValue.channel == .whatsapp
                                case .telegram: return record.phone != nil || rec.wrappedValue.channel == .telegram
                                }
                            }, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 270)
                        removeButton(record)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    if record.id != contacts.last?.id { Divider().padding(.leading, 52) }
                }
            }
            Button("Add Contact…") { picking = true }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $picking) { ContactPickerSheet() }
    }
}

private struct ContactPickerSheet: View {
    @StateObject private var loader = ContactsLoader()
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [ContactEntry] {
        query.isEmpty ? loader.entries : loader.entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Contact").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding(14)
            Divider()

            switch loader.access {
            case .unknown:
                ProgressView("Waiting for Contacts access…").frame(maxHeight: .infinity)
            case .denied:
                VStack(spacing: 10) {
                    Text("Contxt needs access to your contacts.").font(.system(size: 13, weight: .medium))
                    Text("Allow it under Privacy & Security → Contacts.").font(.caption).foregroundStyle(.secondary)
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            case .granted:
                TextField("Search", text: $query).textFieldStyle(.roundedBorder).padding(12)
                List(filtered) { entry in
                    Button { add(entry) } label: {
                        HStack(spacing: 10) {
                            Image(nsImage: entry.photo.flatMap { NSImage(data: $0) } ?? ContactAvatar.image(name: entry.name, path: nil))
                                .resizable().scaledToFill().frame(width: 28, height: 28).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.name).font(.system(size: 13, weight: .medium))
                                Text(entry.phone ?? entry.email ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 400, height: 460)
        .onAppear { loader.load() }
    }

    private func add(_ entry: ContactEntry) {
        let id = UUID()
        var record = DestinationRecord(id: id, kind: .contact, name: entry.name)
        record.email = entry.email
        record.phone = entry.phone
        record.channel = entry.phone != nil ? .message : .email
        record.avatarPath = entry.photo.flatMap { DestinationStore.shared.saveAvatar($0, for: id) }
        DestinationStore.shared.records.append(record)
        dismiss()
    }
}

final class ShortcutsLoader: ObservableObject {
    @Published var names: [String] = []
    @Published var loaded = false

    func load() {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            let output = Pipe()
            process.standardOutput = output

            var found: [String] = []
            if (try? process.run()) != nil {
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                found = (String(data: data, encoding: .utf8) ?? "")
                    .split(separator: "\n")
                    .map(String.init)
                    .filter { !$0.isEmpty }
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            }
            DispatchQueue.main.async {
                self.names = found
                self.loaded = true
            }
        }
    }
}

private struct ShortcutsSheet: View {
    @ObservedObject private var store = DestinationStore.shared
    @StateObject private var loader = ShortcutsLoader()

    private func isOn(_ name: String) -> Binding<Bool> {
        Binding(
            get: { store.records.contains { $0.kind == .shortcut && $0.path == name } },
            set: { enabled in
                if enabled {
                    store.records.append(DestinationRecord(kind: .shortcut, name: name, path: name))
                } else {
                    store.records.removeAll { $0.kind == .shortcut && $0.path == name }
                }
            }
        )
    }

    var body: some View {
        SheetFrame(symbol: "wand.and.stars", title: "Shortcuts", subtitle: "Run a shortcut with dropped files as input") {
            Card {
                if !loader.loaded {
                    ProgressView().padding(14)
                } else if loader.names.isEmpty {
                    Text("No shortcuts found. Create one in the Shortcuts app.")
                        .font(.caption).foregroundStyle(.secondary).padding(14)
                }
                ForEach(loader.names, id: \.self) { name in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: "/System/Applications/Shortcuts.app"))
                            .resizable().frame(width: 24, height: 24)
                        Text(name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Spacer()
                        Toggle("", isOn: isOn(name)).toggleStyle(.switch).labelsHidden()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    if name != loader.names.last { Divider().padding(.leading, 46) }
                }
            }
        }
        .onAppear { loader.load() }
    }
}

private struct OrderSheet: View {
    @ObservedObject private var store = DestinationStore.shared

    private func kindTitle(_ kind: DestinationRecord.Kind) -> String {
        switch kind {
        case .folder: return "Folder"
        case .app: return "App"
        case .script: return "Script"
        case .contact: return "Contact"
        case .action: return "Action"
        case .shortcut: return "Shortcut"
        }
    }

    var body: some View {
        SheetFrame(symbol: "arrow.up.arrow.down", title: "Ring Order", subtitle: "Drag rows to reorder, clockwise from the top", scrolls: false) {
            List {
                ForEach(store.records) { record in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        Image(nsImage: record.destination.iconImage()).resizable().frame(width: 26, height: 26)
                        Text(record.name).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(kindTitle(record.kind)).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { store.records.move(fromOffsets: $0, toOffset: $1) }
            }
        }
    }
}

private struct DropZoneSheet: View {
    @ObservedObject private var dropZone = DropZoneStore.shared

    var body: some View {
        SheetFrame(symbol: "tray.and.arrow.down.fill", title: "Drop Zone", subtitle: "The center circle collects files for later") {
            Text("Drop files on the center circle to stack them. Drag the circle into any Finder folder to move everything out at once. Files stay where they are until then.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Card {
                if dropZone.urls.isEmpty {
                    Text("Nothing stacked").font(.caption).foregroundStyle(.secondary).padding(14)
                }
                ForEach(dropZone.urls, id: \.path) { url in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24)
                        Text(url.lastPathComponent).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { dropZone.remove(url) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }

            Button("Clear All") { dropZone.clear() }
                .disabled(dropZone.urls.isEmpty)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Window

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Contxt Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
