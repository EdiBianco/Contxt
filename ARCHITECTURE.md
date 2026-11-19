# Architecture

Contxt is a native Swift/AppKit app built with Swift Package Manager (no Xcode project). It targets macOS 13+ and runs as a menu bar agent (`LSUIElement`).

## Layout

| File | Role |
| --- | --- |
| `main.swift`, `AppDelegate.swift` | App entry, menu bar item, hotkey registration (Carbon `RegisterEventHotKey`) |
| `RingWindow.swift` | `RingController`: a non-activating `NSPanel` at `.statusBar` level that shows the ring under the cursor |
| `RingView.swift` | Ring rendering with `CALayer`s, hover and hit-testing, drag destination, reorder, Drop Zone drag-out, center pill |
| `Geometry.swift` | Angle math for placing items around the ring (ported from Kando, MIT) |
| `Destinations.swift`, `DestinationStore.swift` | Destination model (folder, app, script, shortcut, contact, action) and its JSON persistence |
| `DropActions.swift` | What a drop does for each destination kind |
| `DropZoneStore.swift` | References to files stacked in the center circle |
| `Preferences.swift` | Theme, orb size, hotkey, login item |
| `SettingsView.swift`, `ContactsSupport.swift` | SwiftUI settings window and sheets, Contacts access |
| `Permissions.swift`, `Toast.swift`, `Log.swift` | Folder-access prompts, transient HUD, `os.Logger` helper |

## Decisions worth knowing

- **The ring panel must stay at `.statusBar` level.** At `.screenSaver` level, AppKit never delivered drag callbacks to it.
- **The panel never takes focus.** It is `.nonactivatingPanel`, so Finder stays active during a drag, and it still receives `NSDraggingDestination` events.
- **The hotkey is a Carbon system hotkey**, not an `NSEvent` global monitor, so no Input Monitoring or Accessibility permission is needed. Escape is registered only while the ring is visible.
- **The Drop Zone holds references, not copies.** Nothing moves until the stack is dragged out into a Finder folder.
- **Dragging the Drop Zone out** makes the ring invisible and click-through for the duration of the drag so it does not intercept the drop.
- **Hover geometry** is circle hit-testing, and a hovered circle scales in place around its own center.
- **Logging:** `NSLog` text is redacted in this build, so use `contxtLog` (`os.Logger`, public privacy). Read it with `log show --predicate 'subsystem == "com.contxt.app"'`.

## Build and signing

GitHub Actions builds a universal binary, assembles the `.app`, and signs it with a stable self-signed identity stored in the `SIGNING_P12_BASE64` and `SIGNING_P12_PASSWORD` secrets. The stable designated requirement keeps macOS permission grants across updates. Local builds are not part of the workflow.
