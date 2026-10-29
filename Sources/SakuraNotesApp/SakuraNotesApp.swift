import SwiftUI
import AppKit

@main
struct SakuraNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var environment = AppEnvironment.shared

    var body: some Scene {
        WindowGroup("Sakura Notes") {
            WorkspaceRootView(environment: environment)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "newNote"])
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Tab") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "newTab"])
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("New Folder…") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "newFolder"])
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()
                Menu("New from Template…") {
                    let templates = AppEnvironment.shared.templateFiles()
                    if templates.isEmpty {
                        Text("No templates in the Templates folder")
                    } else {
                        ForEach(templates) { template in
                            Button(template.displayName) {
                                AppEnvironment.shared.newNoteFromTemplateAndOpen(template)
                            }
                        }
                    }
                }

                Divider()
                Button("Open Today's Note") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "dailyNote"])
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }

            CommandGroup(after: .newItem) {
                Button("Open Workspace…") {
                    WorkspacePicker.openAndSelect(environment: AppEnvironment.shared)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Open Workspace in Terminal") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "openInTerminal"])
                }
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    AppEnvironment.shared.flushAllSessions()
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            CommandGroup(replacing: .undoRedo) {} // handled natively by the text view

            CommandMenu("Go") {
                Button("Quick Switcher…") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "quickSwitcher"])
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Command Palette…") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "commandPalette"])
                }
                .keyboardShortcut("p", modifiers: .command)

                Divider()
                Button("Knowledge Graph") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "graph"])
                }
                .keyboardShortcut("g", modifiers: [.command, .option])

                Button("All Tasks") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "tasks"])
                }
                .keyboardShortcut("t", modifiers: [.command, .option])

                Divider()
                Button("Reveal Note in Finder") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "revealNote"])
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Button("Rename Note…") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "renameNote"])
                }
                Button("Duplicate Note") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "duplicateNote"])
                }
                Button("Move Note to Trash") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "trashNote"])
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }

            CommandMenu("Format") {
                Button("Bold") {
                    NSApp.sendAction(#selector(EditorTextView.toggleBold(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Italic") {
                    NSApp.sendAction(#selector(EditorTextView.toggleItalic(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("Strikethrough") {
                    NSApp.sendAction(#selector(EditorTextView.toggleStrikethrough(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])

                Divider()
                Button("Link…") {
                    NSApp.sendAction(#selector(EditorTextView.makeLink(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Wiki Link") {
                    NSApp.sendAction(#selector(EditorTextView.insertWikiLink(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .control])

                Divider()
                Menu("Heading") {
                    Button("Plain Text") {
                        NSApp.sendAction(#selector(EditorTextView.toggleHeading(_:)), to: nil, from: Self.menuItem(tag: 0))
                    }
                    .keyboardShortcut("0", modifiers: [.command, .option])
                    ForEach(1..<7) { level in
                        Button("Heading \(level)") {
                            NSApp.sendAction(#selector(EditorTextView.toggleHeading(_:)), to: nil, from: Self.menuItem(tag: level))
                        }
                        .keyboardShortcut(KeyEquivalent(Character(String(level))), modifiers: [.command, .option])
                    }
                }

                Divider()
                Button("Task Item") {
                    NSApp.sendAction(#selector(EditorTextView.toggleTaskItem(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Code Block") {
                    NSApp.sendAction(#selector(EditorTextView.insertCodeBlock(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])

                Menu("Insert Table") {
                    Button("2 × 2") { NSApp.sendAction(#selector(EditorTextView.insertTable(_:)), to: nil, from: Self.menuItem(object: "2x2")) }
                    Button("3 × 3") { NSApp.sendAction(#selector(EditorTextView.insertTable(_:)), to: nil, from: Self.menuItem(object: "3x3")) }
                    Button("4 × 4") { NSApp.sendAction(#selector(EditorTextView.insertTable(_:)), to: nil, from: Self.menuItem(object: "4x4")) }
                }
            }

            CommandMenu("Panels") {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "toggleSidebar"])
                }
                .keyboardShortcut("s", modifiers: [.command, .option])

                Button("Toggle Note List") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "toggleNoteList"])
                }
                .keyboardShortcut("l", modifiers: [.command, .option])

                Divider()
                Button("Editor Mode") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "togglePreview"])
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()
                Button("Show Outline") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "toggleOutline"])
                }
                .keyboardShortcut("o", modifiers: [.command, .control])

                Button("Show Backlinks") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "toggleBacklinks"])
                }
                .keyboardShortcut("u", modifiers: [.command, .option])

                Button("AI Assistant") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "toggleAIPanel"])
                }
                .keyboardShortcut("a", modifiers: [.command, .option])

                Divider()
                Button("Version History…") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "history"])
                }
                .keyboardShortcut("h", modifiers: [.command, .option])
            }

            CommandMenu("AI") {
                Button("Summarize Note") {
                    NotificationCenter.default.post(name: .sakuraRunAIAction, object: nil, userInfo: ["action": "summarize"])
                }
                Button("Proofread Selection") {
                    NotificationCenter.default.post(name: .sakuraRunAIAction, object: nil, userInfo: ["action": "proofread"])
                }
                Button("Explain Selection") {
                    NotificationCenter.default.post(name: .sakuraRunAIAction, object: nil, userInfo: ["action": "explainSelection"])
                }
                Divider()
                Button("Translate Selection…") {
                    NotificationCenter.default.post(name: .sakuraRunAIAction, object: nil, userInfo: ["action": "translate"])
                }
                Button("Generate Flashcards") {
                    NotificationCenter.default.post(name: .sakuraRunAIAction, object: nil, userInfo: ["action": "generateFlashcards"])
                }
            }

            CommandGroup(after: .help) {
                Button("Sakura Notes on GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/yueseqaz/sakura-notes")!)
                }
            }
        }

        Settings {
            SettingsView()
        }
    }

    static func menuItem(tag: Int) -> NSMenuItem {
        let item = NSMenuItem()
        item.tag = tag
        return item
    }

    static func menuItem(object: Any?) -> NSMenuItem {
        let item = NSMenuItem()
        item.representedObject = object
        return item
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let hotkey = GlobalHotkey(callback: {
        DispatchQueue.main.async {
            QuickCaptureController.shared.toggle(environment: AppEnvironment.shared)
        }
    })
    private var settingsObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment.shared
        // Bare executables (swift run) default to a background policy; the
        // packaged .app is regular via its Info.plist. Keep behavior identical.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        registerHotkey()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("sakura.settings.hotkeyChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.registerHotkey()
        }

        // Dev/test hook: open a workspace directly from the environment.
        if let devPath = ProcessInfo.processInfo.environment["SAKURA_DEV_WORKSPACE"] {
            environment.openWorkspace(at: URL(fileURLWithPath: devPath))
            if let openPath = ProcessInfo.processInfo.environment["SAKURA_DEV_OPEN"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    NotificationCenter.default.post(name: .sakuraOpenNote, object: nil, userInfo: ["path": openPath])
                }
            }
        } else if UserDefaults.standard.object(forKey: "sakura.reopenLastWorkspace") == nil
            || UserDefaults.standard.bool(forKey: "sakura.reopenLastWorkspace") {
            if let url = environment.lastWorkspaceURL {
                environment.openWorkspace(at: url)
            }
        }
    }

    @MainActor private func registerHotkey() {
        let settings = AppEnvironment.shared.settings
        hotkey.register(keyCode: settings.quickCaptureKeyCode, modifiers: settings.quickCaptureModifiers)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running so the global quick-capture shortcut stays available.
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Flush pending autosaves before quitting; autosave means dirty
        // buffers are transient, but never lose the last keystroke.
        AppEnvironment.shared.flushAllSessions()
        return .terminateNow
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                AppEnvironment.shared.openWorkspace(at: url)
                return true
            } else if url.pathExtension.lowercased() == "md" {
                // Open the containing folder as the workspace, then the note.
                AppEnvironment.shared.openWorkspace(at: url.deletingLastPathComponent())
                NotificationCenter.default.post(name: .sakuraOpenNote, object: nil, userInfo: ["path": url.lastPathComponent])
                return true
            }
        }
        return false
    }
}
