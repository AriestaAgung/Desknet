import AppKit
import Foundation

final class DesknetLogViewController: NSViewController {
    private let store: DesknetStore
    private var entries: [NetworkLogEntry] = []
    private var selectedEntryID: UUID?
    private var didSetInitialSplitPosition = false

    private let tableView = NSTableView(frame: .zero)
    private let tableScrollView = NSScrollView()
    private let detailView: NSTextView = {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 480))
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesFindPanel = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 8, height: 8)

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        return textView
    }()
    private let detailScrollView = NSScrollView()
    private let splitView = NSSplitView()
    private let requestCountLabel = NSTextField(labelWithString: "0 requests")
    private let rowCellIdentifier = NSUserInterfaceItemIdentifier("desknet.request.cell")
    private let rowIconTag = 1001
    private let rowTextTag = 1002

    init(store: DesknetStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        view = NSView()
        buildUI()
        registerObservers()
        reloadData()
        DesknetDiagnostics.log("UI", "log view loaded")
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        guard !didSetInitialSplitPosition else { return }
        let width = splitView.bounds.width
        guard width > 0 else { return }

        let leftPaneWidth = min(max(360, width * 0.42), width - 260)
        splitView.setPosition(leftPaneWidth, ofDividerAt: 0)
        didSetInitialSplitPosition = true
        DesknetDiagnostics.log("UI", "initial split configured totalWidth=\(width) leftPane=\(leftPaneWidth)")
    }

    private func buildUI() {
        let header = NSStackView()
        header.orientation = .horizontal
        header.distribution = .fill
        header.spacing = 10
        header.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Desknet")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)

        let shortcutLabel = NSTextField(labelWithString: "Toggle shortcut: ⌘⌃Z")
        shortcutLabel.textColor = .secondaryLabelColor

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearPressed))

        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(shortcutLabel)
        header.addArrangedSubview(spacer)
        header.addArrangedSubview(requestCountLabel)
        header.addArrangedSubview(clearButton)

        let methodColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("request"))
        methodColumn.title = "Requests"
        methodColumn.minWidth = 300
        tableView.addTableColumn(methodColumn)
        tableView.headerView = nil
        tableView.rowHeight = 44
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(tableRowClicked)
        tableView.focusRingType = .none

        tableScrollView.documentView = tableView
        tableScrollView.hasVerticalScroller = true
        tableScrollView.translatesAutoresizingMaskIntoConstraints = false

        detailScrollView.documentView = detailView
        detailScrollView.hasVerticalScroller = true
        detailScrollView.hasHorizontalScroller = false
        detailScrollView.autohidesScrollers = true
        detailScrollView.borderType = .noBorder
        detailScrollView.drawsBackground = true
        detailScrollView.backgroundColor = .textBackgroundColor
        detailScrollView.translatesAutoresizingMaskIntoConstraints = false

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(tableScrollView)
        splitView.addArrangedSubview(detailScrollView)
        splitView.autosaveName = "Desknet.MainSplit"

        view.addSubview(header)
        view.addSubview(splitView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            splitView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func registerObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeDidUpdate),
            name: .desknetStoreDidUpdate,
            object: nil
        )
    }

    @objc private func storeDidUpdate() {
        DesknetDiagnostics.log("UI", "store did update notification received")
        reloadData()
    }

    @objc private func clearPressed() {
        DesknetDiagnostics.log("UI", "clear pressed")
        store.clear()
    }

    private func reloadData() {
        let selectedIDFromTable: UUID?
        if entries.indices.contains(tableView.selectedRow) {
            selectedIDFromTable = entries[tableView.selectedRow].id
        } else {
            selectedIDFromTable = nil
        }

        entries = store.snapshot()
        requestCountLabel.stringValue = "\(entries.count) requests"
        tableView.reloadData()
        DesknetDiagnostics.log(
            "UI",
            "reloadData entries=\(entries.count) selectedRowBefore=\(tableView.selectedRow)"
        )

        if entries.isEmpty {
            selectedEntryID = nil
            detailView.string = "No captured requests yet.\nUse ⌘⌃Z to toggle this window."
            return
        }

        let preferredID = selectedEntryID ?? selectedIDFromTable
        if let preferredID,
           let index = entries.firstIndex(where: { $0.id == preferredID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            DesknetDiagnostics.log("UI", "restored selection row=\(index)")
            updateDetails(for: index)
        } else {
            selectedEntryID = nil
            tableView.deselectAll(nil)
            detailView.string = "Select an API call from the list to view request/response details."
            DesknetDiagnostics.log("UI", "no previous selection, keeping detail pane in placeholder mode")
        }
    }

    private func updateDetails(for row: Int) {
        guard entries.indices.contains(row) else {
            DesknetDiagnostics.log("UI", "updateDetails skipped invalid row=\(row)")
            return
        }
        let entry = entries[row]
        selectedEntryID = entry.id

        let title = DesknetDetailFormatter.summaryTitle(for: entry)
        let body = DesknetDetailFormatter.format(entry: entry)
        let attributed = NSMutableAttributedString(
            string: "\(title)\n\n",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        attributed.append(
            NSAttributedString(
                string: body,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.labelColor,
                ]
            )
        )
        detailView.textStorage?.setAttributedString(attributed)

        detailView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        detailView.needsDisplay = true
        DesknetDiagnostics.log(
            "UI",
            "details updated row=\(row) id=\(entry.id.uuidString) textLength=\(detailView.string.count) detailFrame=\(detailView.frame)"
        )
    }

    @objc private func tableRowClicked() {
        let clicked = tableView.clickedRow
        DesknetDiagnostics.log("UI", "tableRowClicked clickedRow=\(clicked) selectedRow=\(tableView.selectedRow)")
        if entries.indices.contains(clicked) {
            updateDetails(for: clicked)
            return
        }

        updateDetails(for: tableView.selectedRow)
    }
}

extension DesknetLogViewController: NSTableViewDataSource, NSTableViewDelegate {
    func tableViewSelectionDidChange(_ notification: Notification) {
        DesknetDiagnostics.log("UI", "selection changed selectedRow=\(tableView.selectedRow)")
        updateDetails(for: tableView.selectedRow)
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        DesknetDiagnostics.log("UI", "shouldSelectRow row=\(row)")
        return true
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row) else { return nil }
        let entry = entries[row]
        let endpointText = endpointTitle(for: entry)
        if let cell = tableView.makeView(withIdentifier: rowCellIdentifier, owner: self) as? NSTableCellView {
            if let iconView = cell.viewWithTag(rowIconTag) as? NSImageView {
                configure(iconView: iconView, for: entry)
            }
            if let textField = cell.viewWithTag(rowTextTag) as? NSTextField {
                textField.stringValue = endpointText
            }
            return cell
        }

        let cell = NSTableCellView()
        cell.identifier = rowCellIdentifier

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tag = rowIconTag
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)

        let textField = NSTextField(labelWithString: endpointText)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byTruncatingTail
        textField.tag = rowTextTag
        cell.textField = textField
        cell.addSubview(iconView)
        cell.addSubview(textField)
        configure(iconView: iconView, for: entry)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            textField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func endpointTitle(for entry: NetworkLogEntry) -> String {
        let path = entry.url.path
        if path.isEmpty || path == "/" {
            return entry.url.host ?? entry.url.absoluteString
        }
        return path
    }

    private func configure(iconView: NSImageView, for entry: NetworkLogEntry) {
        if entry.errorDescription != nil || (entry.statusCode ?? 0) >= 400 {
            iconView.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Error")
            iconView.contentTintColor = .systemRed
        } else {
            iconView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Success")
            iconView.contentTintColor = .systemGreen
        }
    }
}
