import Foundation
import SwiftUI
import Carbon.HIToolbox
import SakuraStorage
import SakuraSearch
import SakuraAI

/// All user-adjustable app settings, persisted in UserDefaults.
final class SettingsStore: ObservableObject {

    private let defaults: UserDefaults
    static let prefix = "sakura."

    // MARK: - Appearance

    enum AppearanceMode: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: return "Match System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }

    @Published var appearanceMode: AppearanceMode {
        didSet { save(); applyAppearance() }
    }

    @Published var accentColorName: String {
        didSet { save(); objectWillChange.send() }
    }

    static let accentColorNames = ["System", "Sakura Pink", "Blue", "Purple", "Green", "Orange", "Graphite"]

    // MARK: - Editor

    @Published var editorFontName: String {
        didSet { save() }
    }
    @Published var editorFontSize: Double {
        didSet { save() }
    }
    @Published var editorLineSpacing: Double {
        didSet { save() }
    }
    @Published var writingWidth: Double {
        didSet { save() }
    }
    @Published var spellCheckEnabled: Bool {
        didSet { save() }
    }
    @Published var autosaveDelay: Double {
        didSet { save() }
    }

    static let editorFontChoices = ["System Design", "New York", "Helvetica Neue", "Menlo", "SF Mono", "Monaco", "Georgia", "Times New Roman", "Osaka"]

    // MARK: - Workspace behavior

    @Published var showsHiddenFiles: Bool {
        didSet { save() }
    }
    @Published var dailyNotesFolder: String {
        didSet { save() }
    }
    @Published var templatesFolder: String {
        didSet { save() }
    }
    @Published var attachmentsFolder: String {
        didSet { save() }
    }
    @Published var quickCaptureTargetFolder: String {
        didSet { save() }
    }

    // MARK: - Layout state

    @Published var showsSidebar: Bool { didSet { save() } }
    @Published var showsNoteList: Bool { didSet { save() } }
    @Published var showsAIPanel: Bool { didSet { save() } }
    @Published var showsBacklinks: Bool { didSet { save() } }
    @Published var showsOutline: Bool { didSet { save() } }

    // MARK: - AI

    @Published var aiProviders: [AIProviderConfig] {
        didSet { save() }
    }
    @Published var activeAIProviderID: String {
        didSet { save() }
    }
    @Published var aiContextBudget: Int {
        didSet { save() }
    }
    @Published var aiTranslationLanguage: String {
        didSet { save() }
    }

    // MARK: - Quick capture

    @Published var quickCaptureKeyCode: UInt32 {
        didSet { save() }
    }
    @Published var quickCaptureModifiers: UInt32 {
        didSet { save() }
    }

    // MARK: - Privacy / consent

    /// Records that the user has seen the "what will be sent" explanation.
    @Published var aiConsentAcknowledged: Bool {
        didSet { save() }
    }

    // MARK: - Init & persistence

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = defaults
        let p = Self.prefix

        func string(_ key: String, _ fallback: String) -> String { d.string(forKey: p + key) ?? fallback }
        func double(_ key: String, _ fallback: Double) -> Double { d.object(forKey: p + key) == nil ? fallback : d.double(forKey: p + key) }
        func bool(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: p + key) == nil ? fallback : d.bool(forKey: p + key) }
        func int(_ key: String, _ fallback: Int) -> Int { d.object(forKey: p + key) == nil ? fallback : d.integer(forKey: p + key) }
        func uInt32(_ key: String, _ fallback: UInt32) -> UInt32 {
            d.object(forKey: p + key) == nil ? fallback : UInt32(d.integer(forKey: p + key))
        }

        self.appearanceMode = AppearanceMode(rawValue: string("appearance", "system")) ?? .system
        self.accentColorName = string("accent", "System")
        self.editorFontName = string("editorFont", "System Design")
        self.editorFontSize = double("editorFontSize", 15)
        self.editorLineSpacing = double("editorLineSpacing", 6)
        self.writingWidth = double("writingWidth", 680)
        self.spellCheckEnabled = bool("spellCheck", true)
        self.autosaveDelay = double("autosaveDelay", 0.8)
        self.showsHiddenFiles = bool("showsHiddenFiles", false)
        self.dailyNotesFolder = string("dailyFolder", "Daily")
        self.templatesFolder = string("templatesFolder", "Templates")
        self.attachmentsFolder = string("attachmentsFolder", "Attachments")
        self.quickCaptureTargetFolder = string("quickCaptureFolder", "Inbox")
        self.showsSidebar = bool("showsSidebar", true)
        self.showsNoteList = bool("showsNoteList", true)
        self.showsAIPanel = bool("showsAIPanel", false)
        self.showsBacklinks = bool("showsBacklinks", false)
        self.showsOutline = bool("showsOutline", false)

        let decodedProviders: [AIProviderConfig]
        if let data = d.data(forKey: p + "aiProviders"),
           let providers = try? JSONDecoder().decode([AIProviderConfig].self, from: data), !providers.isEmpty {
            decodedProviders = providers
        } else {
            decodedProviders = [AIProviderConfig()]
        }
        self.aiProviders = decodedProviders
        self.activeAIProviderID = string("activeAIProvider", decodedProviders.first?.id ?? "")
        self.aiContextBudget = int("aiContextBudget", AIContextBuilder.defaultContextBudget)
        self.aiTranslationLanguage = string("aiLanguage", "English")
        self.quickCaptureKeyCode = uInt32("hotkeyKeyCode", 49) // Space
        self.quickCaptureModifiers = uInt32("hotkeyModifiers", UInt32(cmdKey | shiftKey))
        self.aiConsentAcknowledged = bool("aiConsent", false)
    }

    private func save() {
        let d = defaults
        let p = Self.prefix
        d.set(appearanceMode.rawValue, forKey: p + "appearance")
        d.set(accentColorName, forKey: p + "accent")
        d.set(editorFontName, forKey: p + "editorFont")
        d.set(editorFontSize, forKey: p + "editorFontSize")
        d.set(editorLineSpacing, forKey: p + "editorLineSpacing")
        d.set(writingWidth, forKey: p + "writingWidth")
        d.set(spellCheckEnabled, forKey: p + "spellCheck")
        d.set(autosaveDelay, forKey: p + "autosaveDelay")
        d.set(showsHiddenFiles, forKey: p + "showsHiddenFiles")
        d.set(dailyNotesFolder, forKey: p + "dailyFolder")
        d.set(templatesFolder, forKey: p + "templatesFolder")
        d.set(attachmentsFolder, forKey: p + "attachmentsFolder")
        d.set(quickCaptureTargetFolder, forKey: p + "quickCaptureFolder")
        d.set(showsSidebar, forKey: p + "showsSidebar")
        d.set(showsNoteList, forKey: p + "showsNoteList")
        d.set(showsAIPanel, forKey: p + "showsAIPanel")
        d.set(showsBacklinks, forKey: p + "showsBacklinks")
        d.set(showsOutline, forKey: p + "showsOutline")
        if let data = try? JSONEncoder().encode(aiProviders) {
            d.set(data, forKey: p + "aiProviders")
        }
        d.set(activeAIProviderID, forKey: p + "activeAIProvider")
        d.set(aiContextBudget, forKey: p + "aiContextBudget")
        d.set(aiTranslationLanguage, forKey: p + "aiLanguage")
        d.set(Int(quickCaptureKeyCode), forKey: p + "hotkeyKeyCode")
        d.set(Int(quickCaptureModifiers), forKey: p + "hotkeyModifiers")
        d.set(aiConsentAcknowledged, forKey: p + "aiConsent")
    }

    private func applyAppearance() {
        DispatchQueue.main.async {
            switch self.appearanceMode {
            case .system: NSApp.appearance = nil
            case .light: NSApp.appearance = NSAppearance(named: .aqua)
            case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }

    /// The active AI provider configuration, if any.
    var activeAIProvider: AIProviderConfig? {
        aiProviders.first { $0.id == activeAIProviderID } ?? aiProviders.first
    }
}
