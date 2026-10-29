import SwiftUI
import AppKit
import SakuraCore
import SakuraStorage

/// Folder picker + workspace opener used by the welcome view and the sidebar menu.
@MainActor
enum WorkspacePicker {

    static func openAndSelect(environment: AppEnvironment) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use as Workspace"
        panel.message = "Sakura Notes keeps your notes as ordinary Markdown files inside this folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        environment.openWorkspace(at: url)
    }

    static func createAndOpen(environment: AppEnvironment) {
        let panel = NSSavePanel()
        panel.title = "Create Workspace Folder"
        panel.prompt = "Create"
        panel.nameFieldStringValue = "My Notes"
        panel.message = "A new folder will be created for your Markdown notes."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            environment.openWorkspace(at: url)
        } catch {
            environment.presentError(error)
        }
    }
}

/// Middle column: search field, sorting, and the note list.
struct NoteListView: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: WorkspaceModel
    @VS private var sortMenuShown = false

    var body: some View {
        VStack(spacing: 0) {
            header
            HairlineDivider()
            noteList
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: DS.spaceS) {
            HStack(spacing: DS.spaceS) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("Filter notes", text: $model.searchQuery)
                        .textFieldStyle(.plain)
                        .font(DS.body(13))
                    if !model.searchQuery.isEmpty {
                        Button {
                            model.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DS.spaceS)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: DS.radiusM).fill(Color.primary.opacity(0.055)))

                Menu {
                    Picker("Sort", selection: $model.sortMode) {
                        ForEach(NoteSortMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(spacing: DS.spaceS) {
                Text(scopeTitle)
                    .font(DS.caption())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Menu {
                    Button("New Note") { createNote() }
                    Menu("From Template…") {
                        let templates = environment.templateFiles()
                        if templates.isEmpty {
                            Text("No templates in “\(settings.templatesFolder)”")
                        } else {
                            ForEach(templates) { template in
                                Button(template.displayName) {
                                    let title = template.displayName + " " + Self.dateStamp()
                                    if let entry = environment.newNoteFromTemplate(template, title: title, inFolder: model.selectedFolder ?? "") {
                                        model.openNote(path: entry.relativePath)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12))
                        .foregroundColor(DS.accentColor(settings.accentColorName))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, DS.spaceM)
        .padding(.vertical, DS.spaceS)
    }

    static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return formatter.string(from: Date())
    }

    private var scopeTitle: String {
        if let tag = model.selectedTag {
            return "#\(tag)"
        }
        if let folder = model.selectedFolder {
            return (folder as NSString).lastPathComponent
        }
        return "All Notes"
    }

    private var visibleNotes: [NoteEntry] {
        model.visibleNotes(from: environment.vault?.notes ?? [])
    }

    private var noteList: some View {
        Group {
            if visibleNotes.isEmpty {
                EmptyStateView(
                    symbol: "tray",
                    title: model.searchQuery.isEmpty ? "No notes here yet" : "No matches",
                    message: model.searchQuery.isEmpty
                        ? "Create your first note in this folder."
                        : "Try a different filter or clear the search field.",
                    actions: model.searchQuery.isEmpty ? [("New Note", { createNote() })] : []
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(visibleNotes) { entry in
                            NoteRow(
                                environment: environment,
                                model: model,
                                entry: entry
                            )
                        }
                    }
                    .padding(.horizontal, DS.spaceS)
                    .padding(.bottom, DS.spaceXL)
                }
            }
        }
    }

    private func createNote() {
        let folder = model.selectedFolder ?? ""
        var title = "Untitled Note"
        var counter = 2
        while environment.vault?.noteEntry(at: folder.isEmpty ? "\(title).md" : "\(folder)/\(title).md") != nil {
            title = "Untitled Note \(counter)"
            counter += 1
        }
        if let entry = environment.createNote(inFolder: folder, title: title) {
            model.openNote(path: entry.relativePath)
        }
    }
}

struct NoteRow: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var model: WorkspaceModel
    let entry: NoteEntry

    private var isActive: Bool {
        model.activeTab?.path == entry.relativePath
    }

    var body: some View {
        Button {
            model.openNote(path: entry.relativePath)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName)
                    .font(DS.body(13))
                    .fontWeight(isActive ? .semibold : .regular)
                    .lineLimit(1)
                HStack(spacing: DS.spaceXS) {
                    Text(entry.folderPath.isEmpty ? "·" : entry.folderPath)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Text("·")
                    Text(Self.relativeDate(entry.modificationDate))
                }
                .font(DS.caption())
                .foregroundColor(.secondary)
                if let excerpt = environment.factsCache[entry.relativePath]?.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(DS.caption())
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, DS.spaceS)
            .padding(.vertical, DS.spaceS)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusS)
                .fill(isActive ? Color.primary.opacity(0.075) : Color.clear)
        )
        .contextMenu {
            Button("Open in New Tab") { model.openNote(path: entry.relativePath, forceNewTab: true) }
            Divider()
            Button("Duplicate") { duplicate() }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([environment.vault!.absoluteURL(for: entry.relativePath)])
            }
            Divider()
            Button("Move to Trash", role: .destructive) { trash() }
        }
    }

    private func duplicate() {
        guard let vault = environment.vault else { return }
        _ = try? vault.duplicate(entry.relativePath)
    }

    private func trash() {
        guard let vault = environment.vault else { return }
        do {
            try vault.trash(entry.relativePath)
            if let tab = model.tabs.first(where: { $0.path == entry.relativePath }) {
                model.closeTab(id: tab.id)
            }
        } catch {
            environment.presentError(error)
        }
    }

    static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
