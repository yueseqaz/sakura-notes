import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers
import SakuraCore
import SakuraStorage

// MARK: - Welcome / onboarding

/// Shown when no workspace is open: create or open a folder, or pick a recent one.
struct WelcomeView: View {
    @ObservedObject var environment: AppEnvironment

    var body: some View {
        VStack(spacing: DS.spaceXXL) {
            Spacer()
            VStack(spacing: DS.spaceM) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 52, weight: .light))
                    .foregroundColor(DS.accentColor(environment.settings.accentColorName))
                Text("Sakura Notes")
                    .font(.system(size: 30, weight: .bold, design: .default))
                Text("A calm home for your Markdown notes — plain files,\npowerful search, and links that grow with you.")
                    .font(DS.body(13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: DS.spaceS) {
                Button {
                    WorkspacePicker.createAndOpen(environment: environment)
                } label: {
                    Label("Create a New Workspace", systemImage: "folder.badge.plus")
                        .frame(width: 260, height: 30)
                }
                .controlSize(.large)

                Button {
                    WorkspacePicker.openAndSelect(environment: environment)
                } label: {
                    Label("Open Existing Folder…", systemImage: "folder")
                        .frame(width: 260, height: 30)
                }
                .controlSize(.large)
            }
            if !environment.workspaceStore.workspaces.isEmpty {
                VStack(alignment: .leading, spacing: DS.spaceS) {
                    Text("RECENT WORKSPACES")
                        .font(DS.caption())
                        .foregroundColor(.secondary)
                        .kerning(0.4)
                    ForEach(environment.workspaceStore.workspaces.prefix(4)) { workspace in
                        Button {
                            environment.openWorkspace(at: URL(fileURLWithPath: workspace.path))
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundColor(.secondary)
                                Text(workspace.name)
                                    .font(DS.body(13))
                                Spacer()
                                Text(workspace.path)
                                    .font(DS.caption())
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                            .padding(.horizontal, DS.spaceM)
                            .padding(.vertical, DS.spaceS)
                            .frame(width: 420)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(RoundedRectangle(cornerRadius: DS.radiusM).fill(Color.primary.opacity(0.04)))
                    }
                }
            }
            if let error = environment.lastVaultError {
                Text(error)
                    .font(DS.caption())
                    .foregroundColor(.red)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Export / Import

enum ExportController {

    enum ExportFormat { case html, pdf, markdown }

    /// Exports the given note session with a save panel.
    @MainActor
    static func export(session: NoteSession, vault: VaultStore, kind: ExportFormat, settings: SettingsStore) {
        let panel = NSSavePanel()
        let baseName = session.displayTitle
        switch kind {
        case .html:
            panel.allowedContentTypes = [.html]
            panel.nameFieldStringValue = baseName + ".html"
        case .pdf:
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = baseName + ".pdf"
        case .markdown:
            panel.allowedContentTypes = [UTType.plainText]
            panel.nameFieldStringValue = baseName + ".md"
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do {
                    switch kind {
                    case .html:
                        let html = PreviewBuilder.buildForExport(markdown: session.text, title: session.displayTitle)
                        try html.write(to: url, atomically: true, encoding: .utf8)
                    case .pdf:
                        let data = try await renderPDF(markdown: session.text, title: session.displayTitle, vaultFolder: vault.absoluteURL(for: session.path).deletingLastPathComponent(), vault: vault)
                        try data.write(to: url)
                    case .markdown:
                        try session.text.write(to: url, atomically: true, encoding: .utf8)
                    }
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } catch {
                    await MainActor.run {
                        AppEnvironment.shared.presentError(error)
                    }
                }
            }
        }
    }

    /// Renders markdown to PDF via the same WebKit pipeline as the preview.
    static func renderPDF(markdown: String, title: String, vaultFolder: URL, vault: VaultStore) async throws -> Data {
        var html = PreviewBuilder.buildForExport(markdown: markdown, title: title)
        let noteFolder = vaultFolder.path.hasPrefix(vault.rootURL.path)
            ? vault.relativePath(for: vaultFolder) ?? ""
            : ""
        html = PreviewSchemeHandler.rewriteImageSources(html, noteFolder: noteFolder)
        let configuration = WKWebViewConfiguration()
        let handler = PreviewSchemeHandler()
        handler.vault = vault
        handler.htmlProvider = { html }
        configuration.setURLSchemeHandler(handler, forURLScheme: PreviewSchemeHandler.scheme)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 794, height: 1123), configuration: configuration) // A4 @96dpi
        webView.load(URLRequest(url: URL(string: "\(PreviewSchemeHandler.scheme)://doc/content.html")!))
        // Wait for the load (and rendering of math/diagrams) to settle.
        try await waitForLoad(webView: webView)
        try await Task.sleep(nanoseconds: 600_000_000)
        return try await withCheckedThrowingContinuation { continuation in
            webView.createPDF(configuration: WKPDFConfiguration()) { result in
                switch result {
                case .success(let data): continuation.resume(returning: data)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func waitForLoad(webView: WKWebView) async throws {
        for _ in 0..<200 {
            if !webView.isLoading {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Imports a folder of Markdown files into the vault, preserving structure.
    @MainActor
    static func importFolder(into vault: VaultStore, environment: AppEnvironment) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Import"
        panel.message = "Markdown files inside this folder (and subfolders) will be copied into the workspace. Nothing is moved or deleted from the source."
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            let destinationName = sourceURL.lastPathComponent
            var created = 0
            var skipped = 0
            var conflicts = 0

            // Unique destination folder in the vault.
            var targetRelative = destinationName
            var counter = 2
            while vault.folderNode(at: targetRelative) != nil {
                targetRelative = "\(destinationName) \(counter)"
                counter += 1
            }
            let targetURL = vault.rootURL.appendingPathComponent(targetRelative)

            func enumerate(directory: URL, relative: String) {
                let contents = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
                for item in contents {
                    let name = item.lastPathComponent
                    if name.hasPrefix(".") { skipped += 1; continue }
                    let childRelative = relative.isEmpty ? name : "\(relative)/\(name)"
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                        enumerate(directory: item, relative: childRelative)
                    } else {
                        let ext = (name as NSString).pathExtension.lowercased()
                        guard ["md", "markdown", "txt", "text"].contains(ext) else {
                            skipped += 1
                            continue
                        }
                        let destURL = targetURL.appendingPathComponent(childRelative)
                        if fileManager.fileExists(atPath: destURL.path) {
                            conflicts += 1
                            continue
                        }
                        do {
                            try fileManager.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                            try fileManager.copyItem(at: item, to: destURL)
                            created += 1
                        } catch {
                            skipped += 1
                        }
                    }
                }
            }
            enumerate(directory: sourceURL, relative: "")
            DispatchQueue.main.async {
                vault.rescan()
                environment.lastVaultError = created > 0
                    ? "Imported \(created) note(s)\(skipped > 0 ? ", skipped \(skipped) file(s)" : "")\(conflicts > 0 ? ", \(conflicts) name conflict(s)" : "") into “\(targetRelative)”."
                    : "Nothing imported — no Markdown files found in the selected folder."
            }
        }
    }
}

