import AppKit

/// Floating, non-activating panel showing wiki-link completion suggestions
/// under the editor caret.
final class WikiLinkCompletionController: NSObject, NSTableViewDelegate, NSTableViewDataSource {

    private var panel: NSPanel?
    private var tableView: NSTableView?
    private weak var textView: EditorTextView?
    private var items: [String] = []
    private var selectedIndex: Int = 0

    func present(items: [String], near screenRect: NSRect, textView: EditorTextView) {
        self.textView = textView
        self.items = items
        self.selectedIndex = min(selectedIndex, max(0, items.count - 1))

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 10),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.becomesKeyOnlyIfNeeded = true
            self.panel = panel
        }
        guard let panel else { return }

        let contentView = NSVisualEffectView()
        contentView.material = .popover
        contentView.state = .active
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 8
        contentView.layer?.borderWidth = 0.5
        contentView.layer?.borderColor = NSColor.separatorColor.cgColor

        let table = NSTableView()
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 24
        table.intercellSpacing = NSSize(width: 0, height: 0)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("suggestion"))
        column.width = 300
        table.addTableColumn(column)
        table.delegate = self
        table.dataSource = self
        table.selectionHighlightStyle = .regular
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        contentView.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            scroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
        ])

        panel.contentView = contentView
        let height = CGFloat(min(items.count, 8)) * table.rowHeight + 8
        panel.setContentSize(NSSize(width: 320, height: height))

        let originX = screenRect.minX
        let originY = screenRect.minY - height - 4
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))

        if !panel.isVisible {
            panel.orderFront(nil)
        }
        table.reloadData()
        if !items.isEmpty {
            table.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
            table.scrollRowToVisible(selectedIndex)
        }
        self.tableView = table
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        tableView = nil
        items = []
        selectedIndex = 0
    }

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: - Keyboard integration

    /// Called from the editor's keyDown for arrow navigation / return.
    func handleNavigation(keyCode: Int) {
        guard isVisible, !items.isEmpty else { return }
        switch keyCode {
        case 125: selectedIndex = min(items.count - 1, selectedIndex + 1)
        case 126: selectedIndex = max(0, selectedIndex - 1)
        default: return
        }
        tableView?.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView?.scrollRowToVisible(selectedIndex)
    }

    func acceptSelected() {
        guard isVisible, selectedIndex < items.count, let textView else {
            dismiss()
            return
        }
        let item = items[selectedIndex]
        dismiss()
        textView.acceptCompletion(item)
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: items[row])
        cell.lineBreakMode = .byTruncatingMiddle
        cell.font = .systemFont(ofSize: 12)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if let row = tableView?.selectedRow, row >= 0 {
            selectedIndex = row
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }
}
