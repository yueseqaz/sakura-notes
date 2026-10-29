import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Floating quick-capture panel, toggled by a global hotkey. Appends text to
/// the configured capture note without activating the main window.
@MainActor
final class QuickCaptureController {

    static let shared = QuickCaptureController()

    private var panel: NSPanel?
    private var hostView: NSHostingView<QuickCaptureContentView>?

    func toggle(environment: AppEnvironment) {
        if panel?.isVisible == true {
            dismiss()
        } else {
            present(environment: environment)
        }
    }

    private func present(environment: AppEnvironment) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 180),
                styleMask: [.titled, .nonactivatingPanel, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = "Quick Capture"
            panel.level = .floating
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            self.panel = panel

            let content = QuickCaptureContentView(
                environment: environment,
                onSubmit: { [weak self] text in
                    self?.save(text: text, environment: environment)
                    self?.dismiss()
                },
                onClose: { [weak self] in
                    self?.dismiss()
                }
            )
            let host = NSHostingView(rootView: content)
            panel.contentView = host
            hostView = host
        }
        guard let panel else { return }
        // Center horizontally near the top of the main screen.
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let frame = panel.frame
            panel.setFrameOrigin(NSPoint(
                x: screenFrame.midX - frame.width / 2,
                y: screenFrame.maxY - frame.height - 80
            ))
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(firstTextView)
    }

    private var firstTextView: NSView? {
        hostView?.subviews.first?.subviews.compactMap { $0 as? NSTextView }.first
    }

    func dismiss() {
        panel?.orderOut(nil)
    }

    private func save(text: String, environment: AppEnvironment) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let vault = environment.vault else { return }
        let folder = environment.settings.quickCaptureTargetFolder
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let bullet = trimmed
            .components(separatedBy: "\n")
            .map { "- \($0)" }
            .joined(separator: "\n")
        let entry = "\(formatter.string(from: Date()))\n\n\(bullet)\n"

        let targetPath = "\(folder)/Quick Notes.md"
        var content = ""
        if vault.noteEntry(at: targetPath) != nil {
            content = (try? vault.readNote(targetPath)) ?? ""
        }
        do {
            let newContent = content.isEmpty ? "# Quick Notes\n\n\(entry)" : content + "\n" + entry
            try vault.writeNote(targetPath, content: newContent)
            NSSound.beep() // subtle confirmation; a full sound could be annoying
        } catch {
            environment.presentError(error)
        }
    }
}

/// The quick capture panel's content.
struct QuickCaptureContentView: View {
    let environment: AppEnvironment
    let onSubmit: (String) -> Void
    let onClose: () -> Void
    @VS private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.spaceS) {
            HStack {
                Image(systemName: "lightbulb")
                    .foregroundColor(DS.accentColor(environment.settings.accentColorName))
                Text("Quick Capture — saves to “\(environment.settings.quickCaptureTargetFolder)/Quick Notes.md”")
                    .font(DS.caption())
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: DS.radiusM).fill(Color.primary.opacity(0.05)))
            HStack {
                Text("⌘⏎ to save · Esc to close")
                    .font(DS.caption())
                    .foregroundColor(.secondary)
                Spacer()
                Button("Save") {
                    onSubmit(text)
                    text = ""
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(DS.spaceM)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand { onClose() }
        .onSubmit {
            onSubmit(text)
            text = ""
        }
    }
}

// MARK: - Global hotkey (Carbon)

/// Registers a system-wide hotkey. RegisterEventHotKey does not require
/// accessibility permissions.
final class GlobalHotkey {
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let callback: () -> Void
    private var currentKey: UInt32 = 0
    private var currentMods: UInt32 = 0

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()
        currentKey = keyCode
        currentMods = modifiers

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let context = Unmanaged.passRetained(HotkeyContext(callback: callback)).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return noErr }
                let context = Unmanaged<HotkeyContext>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    context.callback()
                }
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandler
        )
        guard status == noErr else {
            Unmanaged<HotkeyContext>.fromOpaque(context).release()
            return
        }

        var hotkeyID = EventHotKeyID(signature: OSType(0x534B4E54) /* 'SKNT' */, id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        _ = hotkeyID
        if registerStatus != noErr {
            hotkeyRef = nil
        }
    }

    func unregister() {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private final class HotkeyContext {
        let callback: () -> Void
        init(callback: @escaping () -> Void) {
            self.callback = callback
        }
    }
}
