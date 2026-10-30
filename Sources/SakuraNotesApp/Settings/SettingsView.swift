import SwiftUI
import AppKit
import Carbon.HIToolbox
import SakuraAI
import SakuraStorage

/// Hotkey recorder: click, press a combination, done.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    @VS private var isRecording = false

    func makeNSView(context: Context) -> HotkeyButton {
        let button = HotkeyButton()
        button.keyCode = keyCode
        button.modifiers = modifiers
        button.onCapture = { code, mods in
            keyCode = code
            modifiers = mods
            NotificationCenter.default.post(name: NSNotification.Name("sakura.settings.hotkeyChanged"), object: nil)
        }
        return button
    }

    func updateNSView(_ view: HotkeyButton, context: Context) {
        view.keyCode = keyCode
        view.modifiers = modifiers
    }

    final class HotkeyButton: NSButton {
        var keyCode: UInt32 = 49
        var modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        var onCapture: ((UInt32, UInt32) -> Void)?

        init() {
            super.init(frame: .zero)
            title = Self.description(keyCode: keyCode, modifiers: modifiers)
            bezelStyle = .rounded
            isBordered = true
            font = .systemFont(ofSize: 12)
            target = self
            action = #selector(clicked)
        }

        required init?(coder: NSCoder) { fatalError() }

        @objc private func clicked() {
            title = "Press keys…"
            window?.makeFirstResponder(self)
        }

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard event.keyCode != 53 else { // Escape cancels
                title = Self.description(keyCode: keyCode, modifiers: modifiers)
                return
            }
            keyCode = UInt32(event.keyCode)
            // Strip the numeric pad / function flags we don't care about.
            var mods = event.modifierFlags
            mods.remove([.numericPad, .function, .capsLock])
            modifiers = UInt32(mods.rawValue & (NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.option.rawValue | NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.shift.rawValue))
            title = Self.description(keyCode: keyCode, modifiers: modifiers)
            onCapture?(keyCode, modifiers)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            title = Self.description(keyCode: keyCode, modifiers: modifiers)
        }

        static func description(keyCode: UInt32, modifiers: UInt32) -> String {
            var parts: [String] = []
            if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
            if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
            if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
            if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
            parts.append(Self.keyName(keyCode))
            return parts.joined()
        }

        static func keyName(_ code: UInt32) -> String {
            switch code {
            case 49: return "Space"
            case 36: return "Return"
            case 48: return "Tab"
            case 51: return "Delete"
            case 53: return "Esc"
            case 122: return "F1"
            case 118: return "F4"
            default:
                let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
                if let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
                    let layout = unsafeBitCast(data, to: CFData.self)
                    var deadKeys: UInt32 = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    var length = 0
                    if UCKeyTranslate(
                        CFDataGetBytePtr(layout).map { UnsafeRawPointer($0).assumingMemoryBound(to: UCKeyboardLayout.self) },
                        UInt16(code),
                        UInt16(kUCKeyActionDown),
                        0,
                        UInt32(LMGetKbdType()),
                        UInt32(kUCKeyTranslateNoDeadKeysBit),
                        &deadKeys,
                        4,
                        &length,
                        &chars
                    ) == noErr {
                        let string = String(utf16CodeUnits: chars, count: length)
                        if let first = string.uppercased().first {
                            return String(first)
                        }
                    }
                }
                return "Key \(code)"
            }
        }
    }
}

/// Main settings window.
struct SettingsView: View {
    @ObservedObject var environment = AppEnvironment.shared
    @ObservedObject var settings: SettingsStore

    init() {
        _settings = ObservedObject(wrappedValue: AppEnvironment.shared.settings)
    }

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            editorTab.tabItem { Label("Editor", systemImage: "textformat") }
            appearanceTab.tabItem { Label("Appearance", systemImage: "paintbrush") }
            aiTab.tabItem { Label("AI Assistant", systemImage: "sparkles") }
            advancedTab.tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 640, height: 520)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("Workspace") {
                Toggle("Reopen last workspace at launch", isOn: $reopenLast)
                Toggle("Show hidden files (dotfiles)", isOn: Binding(
                    get: { settings.showsHiddenFiles },
                    set: { newValue in
                        settings.showsHiddenFiles = newValue
                        environment.vault?.showsHiddenFiles = newValue
                    }
                ))
                LabeledContent("Current workspaces") {
                    Button("Add Workspace…") { WorkspacePicker.openAndSelect(environment: environment) }
                }
            }
            Section("Folders") {
                LabeledContent("Daily notes") {
                    TextField("", text: $settings.dailyNotesFolder, prompt: Text("Daily"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }
                LabeledContent("Templates") {
                    TextField("", text: $settings.templatesFolder, prompt: Text("Templates"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }
                LabeledContent("Attachments") {
                    TextField("", text: $settings.attachmentsFolder, prompt: Text("Attachments"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }
            }
            Section {
                LabeledContent("Global shortcut") {
                    HotkeyRecorder(keyCode: $settings.quickCaptureKeyCode, modifiers: $settings.quickCaptureModifiers)
                        .frame(width: 150)
                }
                LabeledContent("Save captures to") {
                    TextField("", text: $settings.quickCaptureTargetFolder, prompt: Text("Inbox"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }
            } header: {
                Text("Quick Capture")
            } footer: {
                Text("The shortcut works system-wide. If it doesn't respond, another app may already own that combination.")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    @AppStorage("sakura.reopenLastWorkspace") private var reopenLast: Bool = true

    // MARK: - Editor

    private var editorTab: some View {
        Form {
            Section("Typography") {
                LabeledContent("Font") {
                    Picker("", selection: $settings.editorFontName) {
                        ForEach(SettingsStore.editorFontChoices, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                LabeledContent("Size") {
                    HStack(spacing: DS.spaceS) {
                        Slider(value: $settings.editorFontSize, in: 11...28, step: 0.5)
                        Text("\(Int(settings.editorFontSize)) pt")
                            .frame(width: 46, alignment: .trailing)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
                LabeledContent("Line spacing") {
                    HStack(spacing: DS.spaceS) {
                        Slider(value: $settings.editorLineSpacing, in: 0...14, step: 1)
                        Text("\(Int(settings.editorLineSpacing)) pt")
                            .frame(width: 46, alignment: .trailing)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
                LabeledContent("Writing width") {
                    HStack(spacing: DS.spaceS) {
                        Slider(value: $settings.writingWidth, in: 480...1100, step: 20)
                        Text("\(Int(settings.writingWidth)) pt")
                            .frame(width: 46, alignment: .trailing)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
            }
            Section("Behavior") {
                Toggle("Check spelling", isOn: $settings.spellCheckEnabled)
                LabeledContent("Autosave delay") {
                    HStack(spacing: DS.spaceS) {
                        Slider(value: $settings.autosaveDelay, in: 0.2...3, step: 0.1)
                        Text(String(format: "%.1f s", settings.autosaveDelay))
                            .frame(width: 46, alignment: .trailing)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
            }
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text("# Heading\nSome **bold** and *italic* text with `code` and a [link](https://example.com).")
                        .font(.system(size: settings.editorFontSize))
                        .lineSpacing(settings.editorLineSpacing)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                }
            } header: {
                Text("Sample")
            } footer: {
                Text("A live preview of the typography settings above.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        Form {
            Section("Theme") {
                LabeledContent("Appearance") {
                    Picker("", selection: $settings.appearanceMode) {
                        ForEach(SettingsStore.AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }
                LabeledContent("Accent color") {
                    Picker("", selection: $settings.accentColorName) {
                        ForEach(SettingsStore.accentColorNames, id: \.self) { name in
                            HStack {
                                Circle().fill(DS.accentColor(name)).frame(width: 12, height: 12)
                                Text(name)
                            }
                            .tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }
            Section {
                Text("The preview follows the app appearance and your editor writing width. Code blocks use GitHub-style highlighting in matching light/dark variants.")
            } footer: {
                Text("Changes apply immediately across the editor, note list, and rendered preview.")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - AI

    @VS private var selectedProviderIndex: Int = 0
    @VS private var fetchedModels: [String] = []
    @VS private var testingConnection = false
    @VS private var testResult: String?

    private var aiTab: some View {
        Form {
            if settings.aiProviders.isEmpty {
                Section("Provider") {
                    Text("No AI provider configured yet.")
                    Button("Add Provider") {
                        settings.aiProviders.append(AIProviderConfig(name: "New Provider"))
                        selectedProviderIndex = settings.aiProviders.count - 1
                    }
                }
            } else {
                Section("Provider") {
                    LabeledContent("Active provider") {
                        Picker("", selection: $selectedProviderIndex) {
                            ForEach(settings.aiProviders.indices, id: \.self) { index in
                                Text(settings.aiProviders[index].name).tag(index)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                    .onChange(of: selectedProviderIndex) { newValue in
                        settings.activeAIProviderID = settings.aiProviders[newValue].id
                    }
                }
                if selectedProviderIndex < settings.aiProviders.count {
                    let binding = $settings.aiProviders[selectedProviderIndex]
                    Section("Endpoint") {
                        LabeledContent("Name") {
                            TextField("", text: binding.name, prompt: Text("Provider name"))
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: .infinity)
                        }
                        LabeledContent("Base URL") {
                            TextField("", text: binding.baseURL, prompt: Text("https://api.openai.com/v1"))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity)
                        }
                        LabeledContent("Model") {
                            HStack(spacing: DS.spaceS) {
                                TextField("", text: binding.model, prompt: Text("model id"))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity)
                                Button("Fetch Models") { fetchModels(provider: binding.wrappedValue) }
                                    .disabled(testingConnection)
                            }
                        }
                        if !fetchedModels.isEmpty {
                            LabeledContent("Available models") {
                                Picker("", selection: binding.model) {
                                    ForEach(fetchedModels, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 260)
                            }
                        }
                    }
                    Section {
                        LabeledContent("API key") {
                            HStack(spacing: DS.spaceS) {
                                SecureField("", text: $apiKeyDraft, prompt: Text("Paste API key"))
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity)
                                Button("Save") { saveKey(provider: binding.wrappedValue) }
                                    .disabled(apiKeyDraft.isEmpty)
                                Button("Remove") { removeKey(provider: binding.wrappedValue) }
                            }
                        }
                    } header: {
                        Text("API Key")
                    } footer: {
                        Text(keyStatus(for: binding.wrappedValue) + " Keys are stored in the macOS Keychain and never written to notes or logs.")
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Section("Behavior") {
                        LabeledContent("Temperature") {
                            HStack(spacing: DS.spaceS) {
                                Slider(value: binding.temperature, in: 0...1.5, step: 0.05)
                                Text(String(format: "%.2f", binding.wrappedValue.temperature))
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                                    .foregroundColor(.secondary)
                            }
                        }
                        LabeledContent("Request timeout") {
                            HStack(spacing: DS.spaceS) {
                                Slider(value: Binding(
                                    get: { binding.wrappedValue.requestTimeout },
                                    set: { binding.wrappedValue.requestTimeout = $0 }
                                ), in: 10...180, step: 5)
                                Text("\(Int(binding.wrappedValue.requestTimeout)) s")
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                                    .foregroundColor(.secondary)
                            }
                        }
                        LabeledContent("Context budget") {
                            HStack(spacing: DS.spaceS) {
                                Slider(value: Binding(
                                    get: { Double(settings.aiContextBudget) },
                                    set: { settings.aiContextBudget = Int($0) }
                                ), in: 4000...80000, step: 2000)
                                Text("\(settings.aiContextBudget / 1000)k")
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                                    .foregroundColor(.secondary)
                            }
                        }
                        LabeledContent("Translate into") {
                            TextField("", text: $settings.aiTranslationLanguage, prompt: Text("English"))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                        }
                    }
                    Section {
                        LabeledContent("Connection") {
                            HStack(spacing: DS.spaceS) {
                                Button(testingConnection ? "Testing…" : "Test Connection") {
                                    testConnection(provider: binding.wrappedValue)
                                }
                                .disabled(testingConnection)
                                Button("Remove Provider", role: .destructive) {
                                    removeKey(provider: binding.wrappedValue)
                                    settings.aiProviders.remove(at: selectedProviderIndex)
                                    selectedProviderIndex = 0
                                }
                                Spacer()
                                Button("Add Provider") {
                                    settings.aiProviders.append(AIProviderConfig(name: "New Provider"))
                                    selectedProviderIndex = settings.aiProviders.count - 1
                                }
                            }
                        }
                    } footer: {
                        Group {
                            if let testResult {
                                Text(testResult)
                            } else {
                                Text("Sends a one-word completion to verify the endpoint and key work.")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Section {
                Text("Sakura Notes never sends your notes anywhere on its own. Note content is transmitted only when you run an AI action or ask a question, using the endpoint and key configured here. API keys are stored in the macOS Keychain and never written to notes or logs.")
            } header: {
                Text("Privacy")
            } footer: {
                Text("")
            }
        }
        .formStyle(.grouped)
    }

    @VS private var apiKeyDraft: String = ""

    private func keyStatus(for provider: AIProviderConfig) -> String {
        environment.keychain.get(forAccount: "ai.\(provider.id)") != nil ? "A key is saved for this provider." : "No key saved yet."
    }

    private func saveKey(provider: AIProviderConfig) {
        do {
            try environment.keychain.set(apiKeyDraft, forAccount: "ai.\(provider.id)")
            apiKeyDraft = ""
            testResult = "✓ Key saved."
        } catch {
            testResult = "✗ Could not save to Keychain."
        }
    }

    private func removeKey(provider: AIProviderConfig) {
        environment.keychain.delete(forAccount: "ai.\(provider.id)")
        testResult = nil
    }

    private func fetchModels(provider: AIProviderConfig) {
        guard let apiKey = environment.keychain.get(forAccount: "ai.\(provider.id)") else {
            testResult = "✗ Save an API key first."
            return
        }
        testingConnection = true
        let client = environment.client
        Task {
            do {
                let models = try await client.listModels(config: provider, apiKey: apiKey)
                fetchedModels = models
                testResult = models.isEmpty ? "Provider returned no models." : "✓ \(models.count) models available."
            } catch {
                testResult = "✗ \(error.localizedDescription)"
            }
            testingConnection = false
        }
    }

    private func testConnection(provider: AIProviderConfig) {
        guard let apiKey = environment.keychain.get(forAccount: "ai.\(provider.id)") else {
            testResult = "✗ Save an API key first."
            return
        }
        testingConnection = true
        let client = environment.client
        Task {
            do {
                let result = try await client.complete(
                    messages: [AIMessage(.user, "Reply with the single word: ok")],
                    config: provider,
                    apiKey: apiKey
                )
                testResult = result.text.isEmpty ? "✓ Connected (empty reply)." : "✓ Connected — model replied: \(result.text.prefix(40))"
            } catch {
                testResult = "✗ \(error.localizedDescription)"
            }
            testingConnection = false
        }
    }

    // MARK: - Advanced

    private var advancedTab: some View {
        Form {
            Section {
                LabeledContent("Indexed notes") {
                    HStack(spacing: DS.spaceS) {
                        Text("\(environment.searchCoordinator?.noteCount ?? 0)")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                        Button("Rebuild Index") {
                            if let vault = environment.vault {
                                environment.searchCoordinator?.rebuildAll(vault: vault)
                            }
                        }
                    }
                }
            } header: {
                Text("Search Index")
            } footer: {
                Text("The index is derived data stored in Application Support; it can be rebuilt from your files at any time.")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                LabeledContent("Stored snapshots") {
                    Text("\(environment.snapshotStore.totalCount()) · up to \(SnapshotStore.maxSnapshotsPerNote) per note")
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Version History")
            }
            Section("Reset") {
                LabeledContent("Recent files") {
                    Button("Clear", role: .destructive) {
                        environment.workspaceStore.clearRecentFiles()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
