import SwiftUI
import AppKit
import SakuraCore
import SakuraStorage
import SakuraAI

/// Root view of the main workspace window: welcome state or the three-pane
/// workspace with tabs, editor, preview, and panels.
struct WorkspaceRootView: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var settings: SettingsStore
    @StateObject private var model: WorkspaceModel

    // Overlays
    @VS private var showsQuickSwitcher = false
    @VS private var showsCommandPalette = false
    @VS private var showsGraph = false
    @VS private var showsTasks = false
    @VS private var showsHistory = false
    @VS private var showsRenameAlert = false
    @VS private var renameTarget: String?
    @VS private var renameIsFolder = false
    @VS private var renameText: String = ""
    @VS private var showsNewFolderAlert = false
    @VS private var newFolderParent: String = ""
    @VS private var newFolderName: String = ""
    @VS private var showsNewNoteTitleAlert = false
    @VS private var pendingWikiTitle: String = ""
    @VS private var pendingWikiNewNoteText: String = ""

    init(environment: AppEnvironment) {
        self.environment = environment
        self.settings = environment.settings
        _model = StateObject(wrappedValue: WorkspaceModel(environment: environment))
    }

    var body: some View {
        Group {
            if environment.vault == nil {
                WelcomeView(environment: environment)
            } else {
                workspaceContent
            }
        }
        .frame(minWidth: 940, minHeight: 600)
        .onAppear { model.activeTabID = model.activeTabID ?? model.tabs.first?.id }
        .onReceive(NotificationCenter.default.publisher(for: .sakuraOpenNote)) { note in
            if let path = note.userInfo?["path"] as? String {
                model.openNote(path: path)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sakuraCreateNoteWithTitle)) { note in
            if let title = note.userInfo?["title"] as? String {
                pendingWikiTitle = title
                pendingWikiNewNoteText = "Create “\(title)”?"
                showsNewNoteTitleAlert = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sakuraCommand)) { note in
            guard let command = note.userInfo?["command"] as? String else { return }
            if command == "newFolderIn" {
                newFolderParent = note.userInfo?["parent"] as? String ?? ""
                newFolderName = ""
                showsNewFolderAlert = true
            } else {
                handleCommand(command)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sakuraRenameFolder)) { note in
            if let path = note.userInfo?["path"] as? String {
                renameTarget = path
                renameIsFolder = true
                renameText = (path as NSString).lastPathComponent
                showsRenameAlert = true
            }
        }
        .alert("New Note", isPresented: $showsNewNoteTitleAlert) {
            TextField("Title", text: $pendingWikiTitle)
            Button("Create") {
                if let entry = environment.createNote(inFolder: model.selectedFolder ?? "", title: pendingWikiTitle) {
                    model.openNote(path: entry.relativePath)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will create “\(pendingWikiTitle)” in the current folder.")
        }
        .sheet(item: firstConflict) { conflict in
            ConflictResolutionSheet(environment: environment, conflict: conflict) {
                environment.conflicts.removeAll { $0.id == conflict.id }
            }
        }
    }

    private var firstConflict: Binding<ConflictInfo?> {
        Binding(
            get: { environment.conflicts.first },
            set: { newValue in
                if newValue == nil, let current = environment.conflicts.first {
                    environment.conflicts.removeAll { $0.id == current.id }
                }
            }
        )
    }

    // MARK: - Workspace layout

    private var workspaceContent: some View {
        HSplitView {
            if settings.showsSidebar {
                SidebarView(environment: environment, settings: settings, model: model)
                    .frame(minWidth: 190, maxWidth: 300)
            }
            if settings.showsNoteList {
                NoteListView(environment: environment, settings: settings, model: model)
                    .frame(minWidth: 230, maxWidth: 380)
            }
            EditorArea(
                environment: environment,
                settings: settings,
                model: model,
                showsQuickSwitcher: $showsQuickSwitcher
            )
            .frame(minWidth: 420)
        }
        .overlay(alignment: .top) {
            if let error = environment.lastVaultError {
                errorBanner(error)
            }
        }
        .overlay {
            if showsQuickSwitcher {
                QuickSwitcherView(model: model, environment: environment, isPresented: $showsQuickSwitcher)
            }
            if showsCommandPalette {
                CommandPaletteView(model: model, environment: environment, isPresented: $showsCommandPalette)
            }
        }
        .sheet(isPresented: $showsGraph) {
            GraphWindowSheet(environment: environment, isPresented: $showsGraph)
        }
        .sheet(isPresented: $showsTasks) {
            TasksSheet(environment: environment, isPresented: $showsTasks)
        }
        .sheet(isPresented: $showsHistory) {
            HistorySheet(environment: environment, model: model, isPresented: $showsHistory)
        }
        .alert("Rename", isPresented: $showsRenameAlert) {
            TextField("New name", text: $renameText)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New Folder", isPresented: $showsNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") { commitNewFolder() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: DS.spaceS) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(DS.secondary(12))
                .lineLimit(2)
            Spacer()
            Button {
                environment.lastVaultError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.spaceL)
        .padding(.vertical, DS.spaceS)
        .background(.bar)
        .transition(.move(edge: .top))
    }

    // MARK: - Commands

    private func handleCommand(_ command: String) {
        switch command {
        case "quickSwitcher": showsQuickSwitcher = true
        case "commandPalette": showsCommandPalette = true
        case "graph": showsGraph = true
        case "tasks": showsTasks = true
        case "history": showsHistory = true
        case "newTab":
            if let path = model.activeTab?.path {
                model.openNote(path: path, forceNewTab: true)
            }
        case "biggerFont": settings.editorFontSize = min(28, settings.editorFontSize + 1)
        case "smallerFont": settings.editorFontSize = max(11, settings.editorFontSize - 1)
        case "toggleSidebar": settings.showsSidebar.toggle()
        case "toggleNoteList": settings.showsNoteList.toggle()
        case "toggleAIPanel": settings.showsAIPanel.toggle()
        case "toggleBacklinks": settings.showsBacklinks.toggle()
        case "toggleOutline": settings.showsOutline.toggle()
        case "togglePreview": cycleEditorMode()
        case "newNote": createNewNote()
        case "newFolder": requestNewFolder()
        case "dailyNote": openDaily()
        case "reindex":
            if let vault = environment.vault {
                environment.searchCoordinator?.rebuildAll(vault: vault)
            }
        case "revealNote": revealCurrentNote()
        case "openInTerminal": openWorkspaceInTerminal()
        case "renameNote": requestRename()
        case "duplicateNote": duplicateCurrent()
        case "trashNote": trashCurrent()
        case "closeTab": closeActiveTab()
        case "exportHTML": exportCurrent(.html)
        case "exportPDF": exportCurrent(.pdf)
        case "exportMarkdown": exportCurrent(.markdown)
        case "importFolder": importFolder()
        case "aiSummarize": runAIAction(.summarize)
        case "aiProofread": runAIAction(.proofread)
        case "aiTranslate": runAIAction(.translate)
        case "aiExplain": runAIAction(.explainSelection)
        default: break
        }
    }

    private func cycleEditorMode() {
        model.editorMode = model.editorMode.next
    }

    private func createNewNote() {
        let folder = model.selectedFolder ?? ""
        let baseTitle = "Untitled Note"
        var title = baseTitle
        var counter = 2
        while environment.vault?.noteEntry(at: folder.isEmpty ? "\(title).md" : "\(folder)/\(title).md") != nil {
            title = "\(baseTitle) \(counter)"
            counter += 1
        }
        if let entry = environment.createNote(inFolder: folder, title: title) {
            model.openNote(path: entry.relativePath)
        }
    }

    private func openDaily() {
        if let path = environment.openTodayNote() {
            model.openNote(path: path)
        }
    }

    private func requestNewFolder() {
        newFolderParent = model.selectedFolder ?? ""
        newFolderName = ""
        showsNewFolderAlert = true
    }

    private func commitNewFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let target = newFolderParent.isEmpty ? name : "\(newFolderParent)/\(name)"
        do {
            _ = try environment.vault?.createFolder(target)
        } catch {
            environment.presentError(error)
        }
    }

    private func requestRename() {
        guard let path = model.activeTab?.path else { return }
        renameTarget = path
        renameIsFolder = false
        renameText = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        showsRenameAlert = true
    }

    private func commitRename() {
        guard let target = renameTarget, let vault = environment.vault else { return }
        do {
            if renameIsFolder {
                _ = try vault.rename(target, to: renameText)
            } else {
                let ext = (target as NSString).pathExtension
                let newName = ext.isEmpty ? renameText : "\(renameText).\(ext)"
                let newPath = try vault.rename(target, to: newName)
                model.openNote(path: newPath, forceNewTab: false)
            }
        } catch {
            environment.presentError(error)
        }
    }

    private func duplicateCurrent() {
        guard let path = model.activeTab?.path, let vault = environment.vault else { return }
        do {
            let entry = try vault.duplicate(path)
            model.openNote(path: entry.relativePath)
        } catch {
            environment.presentError(error)
        }
    }

    private func trashCurrent() {
        guard let path = model.activeTab?.path, let vault = environment.vault else { return }
        do {
            try vault.trash(path)
            if let tab = model.tabs.first(where: { $0.path == path }) {
                model.closeTab(id: tab.id)
            }
        } catch {
            environment.presentError(error)
        }
    }

    private func closeActiveTab() {
        if let id = model.activeTabID {
            model.closeTab(id: id)
        }
    }

    private func revealCurrentNote() {
        guard let path = model.activeTab?.path, let vault = environment.vault else { return }
        NSWorkspace.shared.activateFileViewerSelecting([vault.absoluteURL(for: path)])
    }

    private func openWorkspaceInTerminal() {
        guard let vault = environment.vault else { return }
        let url: URL
        if let folder = model.selectedFolder {
            url = vault.absoluteURL(for: folder)
        } else {
            url = vault.rootURL
        }
        let escaped = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            do script "cd \\"\(escaped)\\""
            activate
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if error != nil {
            environment.lastVaultError = "Could not open Terminal. macOS may need permission: System Settings → Privacy & Security → Automation."
        }
    }

    // MARK: - Export / Import

    private func exportCurrent(_ kind: ExportController.ExportFormat) {
        guard let session = model.activeSession, let vault = environment.vault else { return }
        ExportController.export(session: session, vault: vault, kind: kind, settings: settings)
    }

    private func importFolder() {
        guard let vault = environment.vault else { return }
        ExportController.importFolder(into: vault, environment: environment)
    }

    private func runAIAction(_ action: AIAction) {
        settings.showsAIPanel = true
        NotificationCenter.default.post(name: .sakuraRunAIAction, object: nil, userInfo: ["action": action])
    }
}

/// Small helper namespace for editor mode cycling.
enum EditorMode: String, CaseIterable {
    case edit, split, preview

    var next: EditorMode {
        switch self {
        case .edit: return .split
        case .split: return .preview
        case .preview: return .edit
        }
    }

    var label: String {
        switch self {
        case .edit: return "Editor"
        case .split: return "Split"
        case .preview: return "Preview"
        }
    }
}

