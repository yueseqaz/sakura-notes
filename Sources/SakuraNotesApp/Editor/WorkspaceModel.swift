import Foundation
import Combine
import AppKit
import SakuraStorage

/// One open editor tab.
struct NoteTab: Identifiable, Equatable {
    let id = UUID()
    var path: String
    var pinned: Bool = false

    static func == (lhs: NoteTab, rhs: NoteTab) -> Bool { lhs.id == rhs.id }
}

/// Sorting for the note list.
enum NoteSortMode: String, CaseIterable, Identifiable {
    case dateDesc, dateAsc, titleAsc, titleDesc, pathAsc
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dateDesc: return "Date Modified ↓"
        case .dateAsc: return "Date Modified ↑"
        case .titleAsc: return "Title A–Z"
        case .titleDesc: return "Title Z–A"
        case .pathAsc: return "Path A–Z"
        }
    }
}

/// Owns the tab state and sidebar navigation state for a workspace window.
@MainActor
final class WorkspaceModel: ObservableObject {

    @Published var tabs: [NoteTab] = []
    @Published var activeTabID: UUID?
    @Published var selectedFolder: String?
    @Published var selectedTag: String?
    @Published var searchQuery: String = ""
    @Published var sortMode: NoteSortMode = .dateDesc
    @Published var showsSearchResults: Bool = false
    @Published var editorMode: EditorMode {
        didSet { UserDefaults.standard.set(editorMode.rawValue, forKey: "sakura.editorMode") }
    }
    @Published var showsHistorySheet: Bool = false

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        self.editorMode = EditorMode(rawValue: UserDefaults.standard.string(forKey: "sakura.editorMode") ?? "") ?? .edit
    }

    // MARK: - Tabs

    @discardableResult
    func openNote(path: String, forceNewTab: Bool = false) -> NoteSession? {
        guard let session = environment.makeSession(for: path) else { return nil }
        if !forceNewTab, let index = tabs.firstIndex(where: { $0.path == path }) {
            activeTabID = tabs[index].id
            return session
        }
        if !forceNewTab, let activeIndex = tabs.firstIndex(where: { $0.id == activeTabID }), !tabs[activeIndex].pinned {
            tabs[activeIndex].path = path
            activeTabID = tabs[activeIndex].id
            return session
        }
        let tab = NoteTab(path: path)
        if let activeIndex = tabs.firstIndex(where: { $0.id == activeTabID }) {
            tabs.insert(tab, at: activeIndex + 1)
        } else {
            tabs.append(tab)
        }
        activeTabID = tab.id
        return session
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        if let session = environment.session(for: tab.path), session.isDirty {
            session.saveNow(showErrors: false)
        }
        tabs.remove(at: index)
        if activeTabID == id {
            // Activate the neighbor tab.
            if index < tabs.count {
                activeTabID = tabs[index].id
            } else if index > 0 {
                activeTabID = tabs[index - 1].id
            } else {
                activeTabID = nil
            }
        }
        // Drop the cached session when no other tab needs it and it's clean.
        if !tabs.contains(where: { $0.path == tab.path }) {
            if let session = environment.session(for: tab.path), !session.isDirty {
                environment.dropSession(for: tab.path)
            }
        }
    }

    func closeOtherTabs(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        for other in tabs where other.id != id {
            closeTab(id: other.id)
        }
        activeTabID = tab.id
    }

    func togglePin(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].pinned.toggle()
    }

    func moveTab(id: UUID, to index: Int) {
        guard let currentIndex = tabs.firstIndex(where: { $0.id == id }), currentIndex != index else { return }
        let tab = tabs.remove(at: currentIndex)
        let target = min(max(0, index), tabs.count)
        tabs.insert(tab, at: target)
    }

    var activeTab: NoteTab? {
        tabs.first { $0.id == activeTabID }
    }

    var activeSession: NoteSession? {
        guard let path = activeTab?.path else { return nil }
        return environment.session(for: path)
    }

    // MARK: - Filtering

    /// Notes shown in the note list given the current sidebar selection,
    /// search query, and sort mode.
    func visibleNotes(from notes: [NoteEntry]) -> [NoteEntry] {
        var result = notes
        if let tag = selectedTag {
            let allowed = Set(environment.notes(withTag: tag))
            result = result.filter { allowed.contains($0.relativePath) }
        } else if let folder = selectedFolder {
            let prefix = folder + "/"
            result = result.filter { $0.relativePath.hasPrefix(prefix) }
        }
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            let lowered = query.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(lowered)
                    || $0.relativePath.lowercased().contains(lowered)
            }
        }
        switch sortMode {
        case .dateDesc: result.sort { $0.modificationDate > $1.modificationDate }
        case .dateAsc: result.sort { $0.modificationDate < $1.modificationDate }
        case .titleAsc: result.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .titleDesc: result.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedDescending }
        case .pathAsc: result.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        }
        return result
    }

    func selectSidebarFolder(_ path: String?) {
        selectedFolder = path
        selectedTag = nil
    }

    func selectSidebarTag(_ tag: String?) {
        selectedTag = tag
        selectedFolder = nil
    }
}
