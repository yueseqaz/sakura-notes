import SwiftUI
import Combine

/// A macro-free replacement for SwiftUI's `@State`, required because this
/// project must compile with the Command-Line-Tools toolchain, which does not
/// ship the SwiftUI macros plugin (full Xcode CI is unaffected and can keep
/// using @State).
///
/// Storage lives in a process-wide store keyed by the property's declaration
/// site (`#fileID` + `#line`) — or by an explicit key for views instantiated
/// multiple times. Semantics match @State: the initial value is used only the
/// first time; changes trigger view updates; the projected value is a Binding.
///
/// Views that can appear multiple times concurrently MUST pass an explicit
/// `key:` derived from their identity.
final class VSBox<Value>: ObservableObject {
    @Published var value: Value
    nonisolated init(_ value: sending Value) {
        self.value = value
    }
}

@MainActor
final class ViewStateStorage {
    static let shared = ViewStateStorage()
    private var boxes: [String: Any] = [:]

    func box<Value>(for key: String, default initial: Value) -> VSBox<Value> {
        if let existing = boxes[key] as? VSBox<Value> {
            return existing
        }
        let created = VSBox(initial)
        boxes[key] = created
        return created
    }

    func clearAll() {
        boxes.removeAll()
    }
}

@propertyWrapper
struct VS<Value>: DynamicProperty {
    @ObservedObject private var box: VSBox<Value>

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    init(wrappedValue value: Value, key: String? = nil, file: String = #fileID, line: UInt = #line) {
        let storageKey = key ?? "\(file):\(line)"
        _box = ObservedObject(wrappedValue: MainActor.assumeIsolated {
            ViewStateStorage.shared.box(for: storageKey, default: value)
        })
    }

    var projectedValue: Binding<Value> {
        Binding(get: { box.value }, set: { box.value = $0 })
    }
}
