import SwiftUI
import AppKit
import SakuraCore
import SakuraAI

/// Right-side AI assistant panel: actions on the current note, streaming
/// output, diff review before applying, and workspace Q&A with citations.
struct AIPanelView: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var settings: SettingsStore
    @ObservedObject var session: NoteSession
    @StateObject private var runner = AIActionRunner()
    @VS private var question: String = ""
    @VS private var proposedReplacement: AIEditProposal?
    @VS private var selectedContextScope: ContextScope = .currentNote
    @VS private var translationLanguage: String = "English"
    @FocusState private var questionFocused: Bool

    enum ContextScope: String, CaseIterable, Identifiable {
        case currentNote
        case currentAndLinked
        case wholeWorkspaceSelection
        var id: String { rawValue }
        var label: String {
            switch self {
            case .currentNote: return "Current note"
            case .currentAndLinked: return "Note + linked notes"
            case .wholeWorkspaceSelection: return "All notes"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HairlineDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.spaceM) {
                    if let config = environment.activeProviderConfig {
                        providerStatus(config)
                        actionSection(config)
                        if runner.phase != .idle {
                            outputSection
                        }
                        if let proposal = proposedReplacement {
                            proposalSection(proposal)
                        }
                        questionSection(config)
                    } else {
                        configurePrompt
                    }
                }
                .padding(DS.spaceM)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .leading) { HairlineDivider() }
        .onReceive(NotificationCenter.default.publisher(for: .sakuraRunAIAction)) { note in
            if let raw = note.userInfo?["action"] as? String, let action = AIAction(rawValue: raw) {
                run(action)
            }
        }
        .onDisappear {
            runner.cancel()
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundColor(DS.accentColor(settings.accentColorName))
            Text("AI Assistant")
                .font(DS.title(13))
            Spacer()
            Button {
                settings.showsAIPanel = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close panel")
        }
        .padding(.horizontal, DS.spaceM)
        .padding(.vertical, DS.spaceS)
    }

    private func providerStatus(_ config: AIProviderConfig) -> some View {
        HStack(spacing: DS.spaceXS) {
            Circle()
                .fill(environment.apiKey() != nil ? Color.green.opacity(0.8) : Color.orange)
                .frame(width: 7, height: 7)
            Text("\(config.name) · \(config.model)")
                .font(DS.caption())
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
        }
    }

    // MARK: - Actions

    private func actionSection(_ config: AIProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: DS.spaceS) {
            Picker("Context", selection: $selectedContextScope) {
                ForEach(ContextScope.allCases) { scope in
                    Text(scope.label).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .font(DS.caption())

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: DS.spaceS)], spacing: DS.spaceS) {
                ForEach(AIAction.allCases) { action in
                    Button {
                        run(action)
                    } label: {
                        HStack(spacing: DS.spaceXS) {
                            Image(systemName: action.symbolName)
                                .font(.system(size: 10))
                            Text(action.label)
                                .font(DS.secondary(11.5))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, DS.spaceS)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: DS.radiusS).fill(Color.primary.opacity(0.05)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Output

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: DS.spaceS) {
            HStack {
                switch runner.phase {
                case .streaming:
                    HStack(spacing: DS.spaceXS) {
                        ProgressView().controlSize(.mini)
                        Text("Generating…").font(DS.caption()).foregroundColor(.secondary)
                    }
                case .finished:
                    Text("Done").font(DS.caption()).foregroundColor(.green)
                case .failed(let message):
                    Text(message).font(DS.caption()).foregroundColor(.red)
                case .cancelled:
                    Text("Cancelled").font(DS.caption()).foregroundColor(.secondary)
                case .idle:
                    EmptyView()
                }
                Spacer()
                if runner.isBusy {
                    Button("Stop") { runner.cancel() }
                        .font(DS.caption())
                        .buttonStyle(.plain)
                }
            }
            Text(runner.streamedText.isEmpty && runner.phase == .streaming ? "…" : runner.streamedText)
                .font(DS.mono(11))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.spaceM)
        .background(RoundedRectangle(cornerRadius: DS.radiusM).fill(Color.primary.opacity(0.04)))
    }

    // MARK: - Diff proposal

    private func proposalSection(_ proposal: AIEditProposal) -> some View {
        VStack(alignment: .leading, spacing: DS.spaceS) {
            HStack {
                Text("Proposed change")
                    .font(DS.caption())
                    .fontWeight(.semibold)
                Text("+\(proposal.diff.addedCount) / −\(proposal.diff.removedCount) lines")
                    .font(DS.caption())
                    .foregroundColor(.secondary)
                Spacer()
            }
            ScrollView {
                Text(proposal.diffPreview)
                    .font(DS.mono(10.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            HStack {
                Spacer()
                Button("Reject", role: .destructive) {
                    proposedReplacement = nil
                }
                Button("Accept") {
                    apply(proposal)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.spaceM)
        .background(RoundedRectangle(cornerRadius: DS.radiusM).fill(Color.primary.opacity(0.04)))
    }

    // MARK: - Workspace Q&A

    private func questionSection(_ config: AIProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: DS.spaceS) {
            SectionHeader(title: "Ask your notes")
            HStack(spacing: DS.spaceS) {
                TextField("Ask about your notes…", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .font(DS.body(12.5))
                    .focused($questionFocused)
                    .onSubmit {
                        ask(config)
                    }
                Button("Ask") {
                    ask(config)
                }
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || runner.isBusy)
            }
            if !settings.aiConsentAcknowledged {
                Text("When you ask a question, the selected notes' text is sent to \(config.name) using your API key. Nothing is sent until you press Ask.")
                    .font(DS.caption())
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Got it") {
                    settings.aiConsentAcknowledged = true
                }
                .font(DS.caption())
                .buttonStyle(.plain)
            }
        }
    }

    private var configurePrompt: some View {
        VStack(spacing: DS.spaceM) {
            EmptyStateView(
                symbol: "sparkles",
                title: "No AI provider configured",
                message: "Add an OpenAI-compatible endpoint and API key in Settings. Your notes never leave this Mac unless you run an action.",
                actions: [("Open Settings", {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                })]
            )
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Running actions

    private func contextNotes(_ config: AIProviderConfig) -> [AIContextNote] {
        guard let vault = environment.vault else { return [] }
        let primary = AIContextNote(
            title: session.facts.title ?? session.displayTitle,
            path: session.path,
            content: session.text
        )
        var extras: [AIContextNote] = []
        switch selectedContextScope {
        case .currentNote:
            break
        case .currentAndLinked:
            let backlinks = environment.linkIndex.backlinks(to: session.path)
            let outgoing = environment.linkIndex.outgoingLinks(from: session.path).compactMap(\.resolvedPath)
            for path in Array(Set(backlinks).union(outgoing)).sorted().prefix(6) {
                if let content = try? vault.readNote(path) {
                    extras.append(AIContextNote(title: ((path as NSString).lastPathComponent as NSString).deletingPathExtension, path: path, content: content))
                }
            }
        case .wholeWorkspaceSelection:
            for entry in vault.notes.prefix(12) where entry.relativePath != session.path {
                if let content = try? vault.readNote(entry.relativePath) {
                    extras.append(AIContextNote(title: entry.displayName, path: entry.relativePath, content: content))
                }
            }
        }
        return AIContextBuilder.selectContext(
            primary: primary,
            extras: extras,
            budget: settings.aiContextBudget
        )
    }

    private func run(_ action: AIAction) {
        guard let config = environment.activeProviderConfig, let apiKey = environment.apiKey() else {
            NSSound.beep()
            return
        }
        proposedReplacement = nil
        let selection = session.selectedText
        if action.requiresSelection && selection.isEmpty {
            environment.lastVaultError = "Select some text first for “\(action.label)”."
            return
        }
        let noteContent = session.text
        let title = session.facts.title ?? session.displayTitle
        runner.run(
            action: action,
            selection: selection,
            noteTitle: title,
            noteContent: noteContent,
            language: settings.aiTranslationLanguage,
            config: config,
            apiKey: apiKey,
            contextNotes: action.requiresSelection ? [] : contextNotes(config)
        )
        // When the run finishes, build a proposal for replace-style actions.
        observeCompletion(action: action, originalSelection: selection)
    }

    private func observeCompletion(action: AIAction, originalSelection: String) {
        // Poll-free: Combine subscription created per run.
        var cancellable: Any?
        cancellable = runner.$phase
            .receive(on: DispatchQueue.main)
            .sink { phase in
                guard case .finished = phase else { return }
                defer { cancellable = nil }
                let result = runner.streamedText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !result.isEmpty else { return }
                switch action.resultMode {
                case .displayOnly:
                    break
                case .appendToNote:
                    let appended = session.text + "\n\n## " + action.label + "\n\n" + result + "\n"
                    session.textDidChange(appended)
                case .replaceSelection:
                    let original = originalSelection.isEmpty ? session.text : originalSelection
                    let updated: String
                    if originalSelection.isEmpty {
                        updated = result
                    } else if let range = Range(session.selectedRange, in: session.text) {
                        updated = session.text.replacingCharacters(in: range, with: result)
                    } else {
                        updated = session.text
                    }
                    let diff = LineDiff.diff(original, result)
                    proposedReplacement = AIEditProposal(
                        action: action,
                        originalText: original,
                        newText: result,
                        diff: diff,
                        fullUpdatedText: updated
                    )
                }
            }
    }

    private func apply(_ proposal: AIEditProposal) {
        // Snapshot before applying so AI edits are reversible.
        if let vault = environment.vault {
            _ = environment.snapshotStore.capture(vaultRoot: vault.rootURL, relativePath: session.path, content: session.text)
        }
        session.textDidChange(proposal.fullUpdatedText)
        session.saveNow(showErrors: true)
        proposedReplacement = nil
    }

    private func ask(_ config: AIProviderConfig) {
        guard let apiKey = environment.apiKey() else {
            NSSound.beep()
            return
        }
        let trimmed = question.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        proposedReplacement = nil
        runner.ask(question: trimmed, contextNotes: contextNotes(config), config: config, apiKey: apiKey)
        question = ""
    }
}

/// A pending AI-suggested replacement awaiting user review.
struct AIEditProposal {
    let action: AIAction
    let originalText: String
    let newText: String
    let diff: LineDiff.Result
    let fullUpdatedText: String

    var diffPreview: String {
        var lines: [String] = []
        for op in diff.operations {
            switch op {
            case .equal(let shared):
                lines.append(contentsOf: shared.prefix(2).map { "  \($0)" })
                if shared.count > 2 { lines.append("  …") }
            case .insert(let inserted, _):
                lines.append(contentsOf: inserted.map { "+ \($0)" })
            case .delete(let deleted, _):
                lines.append(contentsOf: deleted.map { "− \($0)" })
            }
        }
        return lines.joined(separator: "\n")
    }
}
