import SwiftUI
import AppKit
import SakuraCore
import SakuraStorage

/// Left sidebar: workspace name, folder tree, tags, recents, and tools.
struct SidebarView: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            workspaceHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    quickActions
                    SectionHeader(title: "Folders", actionTitle: "plus") {
                        NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "newFolder"])
                    }
                    FolderTreeView(
                        environment: environment,
                        model: model,
                        node: environment.vault?.rootFolder,
                        depth: 0
                    )
                    SectionHeader(title: "Tags")
                    TagListView(environment: environment, model: model)
                    SectionHeader(title: "Recent")
                    RecentListView(environment: environment, model: model)
                }
                .padding(.bottom, DS.spaceXL)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var workspaceHeader: some View {
        HStack(spacing: DS.spaceS) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 13))
                .foregroundColor(DS.accentColor(settings.accentColorName))
            Menu {
                ForEach(environment.workspaceStore.workspaces) { workspace in
                    Button(workspace.name) {
                        environment.openWorkspace(at: URL(fileURLWithPath: workspace.path))
                    }
                }
                Divider()
                Button("Add Workspace…") { WorkspacePicker.openAndSelect(environment: environment) }
                Button("Settings…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            } label: {
                HStack(spacing: DS.spaceXS) {
                    Text(environment.workspaceName.isEmpty ? "Sakura Notes" : environment.workspaceName)
                        .font(DS.title(13))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal, DS.spaceM)
        .padding(.vertical, DS.spaceM)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 2) {
            sidebarButton("pencil.line", "All Notes") {
                model.selectSidebarFolder(nil)
                model.selectSidebarTag(nil)
            }
            sidebarButton("calendar", "Today's Note") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "dailyNote"])
            }
            sidebarButton("checklist", "Tasks") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "tasks"])
            }
            sidebarButton("circle.hexagongrid", "Graph") {
                NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: ["command": "graph"])
            }
        }
        .padding(.horizontal, DS.spaceS)
        .padding(.top, DS.spaceS)
    }

    private func sidebarButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.spaceS) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .frame(width: 16)
                    .foregroundColor(.secondary)
                Text(label)
                    .font(DS.body(13))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.spaceS)
        .padding(.vertical, 3)
        .cornerRadius(DS.radiusS)
    }
}

// MARK: - Folder tree

struct FolderTreeView: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var model: WorkspaceModel
    let node: FolderNode?
    let depth: Int

    var body: some View {
        if let node {
            if depth == 0 {
                ForEach(node.children.filter(folderFilter)) { child in
                    if case .folder(let folder) = child {
                        FolderRow(environment: environment, model: model, folder: folder, depth: depth)
                    }
                }
            } else {
                FolderRow(environment: environment, model: model, folder: node, depth: depth)
            }
        }
    }

    private func folderFilter(_ node: VaultNode) -> Bool {
        if case .folder = node { return true }
        return false
    }
}

struct FolderRow: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var model: WorkspaceModel
    let folder: FolderNode
    let depth: Int
    @VS private var isExpanded: Bool = true

    init(environment: AppEnvironment, model: WorkspaceModel, folder: FolderNode, depth: Int) {
        self.environment = environment
        self.model = model
        self.folder = folder
        self.depth = depth
        _isExpanded = VS(wrappedValue: true, key: "folder.expand." + folder.relativePath)
    }

    private var isSelected: Bool { model.selectedFolder == folder.relativePath }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.spaceXS) {
                if folder.children.contains(where: { if case .folder = $0 { return true } else { return false } }) {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 12)
                }
                Image(systemName: isSelected ? "folder.fill" : "folder")
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? DS.accentColor(environment.settings.accentColorName) : .secondary)
                Text(folder.name)
                    .font(DS.body(13))
                    .lineLimit(1)
                Spacer()
                Text("\(noteCount(in: folder))")
                    .font(DS.caption())
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.leading, CGFloat(depth) * 14 + DS.spaceS)
            .padding(.trailing, DS.spaceS)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .background(isSelected ? Color.primary.opacity(0.07) : Color.clear)
            .onTapGesture {
                model.selectSidebarFolder(folder.relativePath)
            }
            .contextMenu {
                Button("New Note Here") {
                    if let entry = environment.createNote(inFolder: folder.relativePath, title: "Untitled") {
                        model.openNote(path: entry.relativePath)
                    }
                }
                Button("New Subfolder…") {
                    NotificationCenter.default.post(name: .sakuraCommand, object: nil, userInfo: [
                        "command": "newFolderIn",
                        "parent": folder.relativePath,
                    ])
                }
                Divider()
                Button("Rename…") {
                    NotificationCenter.default.post(name: .sakuraRenameFolder, object: nil, userInfo: ["path": folder.relativePath])
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([environment.vault!.absoluteURL(for: folder.relativePath)])
                }
                Divider()
                Button("Delete", role: .destructive) { deleteFolder() }
            }

            if isExpanded {
                ForEach(folder.children) { child in
                    switch child {
                    case .folder(let sub):
                        FolderRow(environment: environment, model: model, folder: sub, depth: depth + 1)
                    case .note:
                        EmptyView()
                    }
                }
            }
        }
    }

    private func noteCount(in folder: FolderNode) -> Int {
        var count = 0
        for child in folder.children {
            if case .note = child { count += 1 }
            if case .folder(let sub) = child { count += noteCount(in: sub) }
        }
        return count
    }

    private func deleteFolder() {
        guard let vault = environment.vault else { return }
        // Only allow trashing when the folder is empty of notes, to keep the
        // destructive path predictable.
        let hasNotes = vault.notes.contains { $0.relativePath.hasPrefix(folder.relativePath + "/") }
        if hasNotes {
            environment.presentError(VaultError.invalidPath("Move or delete the notes inside “\(folder.name)” first."))
            return
        }
        do {
            try vault.trash(folder.relativePath)
            if model.selectedFolder == folder.relativePath {
                model.selectSidebarFolder(nil)
            }
        } catch {
            environment.presentError(error)
        }
    }
}

// MARK: - Tags

struct TagListView: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        let tags = environment.tagSummaries()
        if tags.isEmpty {
            Text("No tags yet — add #tags in your notes.")
                .font(DS.caption())
                .foregroundColor(.secondary)
                .padding(.horizontal, DS.spaceM)
        } else {
            ForEach(tags.prefix(30)) { tag in
                Button {
                    if model.selectedTag == tag.name {
                        model.selectSidebarTag(nil)
                    } else {
                        model.selectSidebarTag(tag.name)
                    }
                } label: {
                    HStack {
                        Image(systemName: "number")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(tag.name)
                            .font(DS.body(12.5))
                            .lineLimit(1)
                        Spacer()
                        Text("\(tag.count)")
                            .font(DS.caption())
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .padding(.horizontal, DS.spaceM)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(model.selectedTag == tag.name ? Color.primary.opacity(0.07) : Color.clear)
            }
        }
    }
}

// MARK: - Recent files

struct RecentListView: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        let recents = environment.workspaceStore.recentFiles(forWorkspace: environment.vault?.rootURL.path ?? "")
        if recents.isEmpty {
            Text("Notes you open appear here.")
                .font(DS.caption())
                .foregroundColor(.secondary)
                .padding(.horizontal, DS.spaceM)
        } else {
            ForEach(recents.prefix(8), id: \.self) { path in
                Button {
                    model.openNote(path: path)
                } label: {
                    Text(((path as NSString).lastPathComponent as NSString).deletingPathExtension)
                        .font(DS.body(12.5))
                        .lineLimit(1)
                        .padding(.horizontal, DS.spaceM)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
