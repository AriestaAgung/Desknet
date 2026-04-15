import AppKit
import Foundation
import SwiftUI

@MainActor
final class DesknetLogViewController: NSViewController {
    private let viewModel: DesknetMonitorViewModel
    private let hostingController: NSHostingController<DesknetMonitorRootView>

    init(store: DesknetStore) {
        let viewModel = DesknetMonitorViewModel(store: store)
        self.viewModel = viewModel
        self.hostingController = NSHostingController(rootView: DesknetMonitorRootView(viewModel: viewModel))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: .zero)
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        DesknetDiagnostics.log("UI", "swiftui log view loaded")
    }
}

@MainActor
final class DesknetMonitorViewModel: ObservableObject {
    enum DetailSection: Int, CaseIterable, Hashable {
        case requestHeaders
        case requestBody
        case responseHeaders
        case responseBody

        var title: String {
            switch self {
            case .requestHeaders: return "Request Headers"
            case .requestBody: return "Request Body"
            case .responseHeaders: return "Response Headers"
            case .responseBody: return "Response Body"
            }
        }
    }

    @Published var query = "" {
        didSet { applyFilterAndSelection() }
    }
    @Published private(set) var allEntries: [NetworkLogEntry] = []
    @Published private(set) var entries: [NetworkLogEntry] = []
    @Published var selectedEntryID: UUID? {
        didSet { DesknetDiagnostics.log("UI", "selection changed id=\(selectedEntryID?.uuidString ?? "-")") }
    }
    @Published var collapsedSections: Set<DetailSection> = [.requestHeaders, .responseHeaders]

    private let store: DesknetStore
    private var observer: NSObjectProtocol?

    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.includesUnit = true
        return formatter
    }()

    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy, hh:mm:ss.SSS a"
        return formatter
    }()

    init(store: DesknetStore) {
        self.store = store
        observer = NotificationCenter.default.addObserver(
            forName: .desknetStoreDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reload()
            }
        }
        reload()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var selectedEntry: NetworkLogEntry? {
        guard let selectedEntryID else { return nil }
        return entries.first { $0.id == selectedEntryID }
    }

    var requestCountText: String {
        "\(entries.count) requests"
    }

    var emptyStateText: String {
        entries.isEmpty ? "No requests found." : "Select an API call from the list to view request/response details."
    }

    func clear() {
        store.clear()
    }

    func reload() {
        allEntries = store.snapshot()
        applyFilterAndSelection()
        DesknetDiagnostics.log("UI", "reloaded entries count=\(entries.count)")
    }

    func setSectionExpanded(_ section: DetailSection, isExpanded: Bool) {
        if isExpanded {
            collapsedSections.remove(section)
        } else {
            collapsedSections.insert(section)
        }
    }

    func isSectionExpanded(_ section: DetailSection) -> Bool {
        !collapsedSections.contains(section)
    }

    func sectionBinding(_ section: DetailSection) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.isSectionExpanded(section) ?? false },
            set: { [weak self] in self?.setSectionExpanded(section, isExpanded: $0) }
        )
    }

    func isError(_ entry: NetworkLogEntry) -> Bool {
        entry.errorDescription != nil || (entry.statusCode ?? 0) >= 400
    }

    func statusText(for entry: NetworkLogEntry) -> String {
        if let statusCode = entry.statusCode {
            if isError(entry) {
                return "\(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized)"
            }
            return "\(statusCode) OK"
        }
        return "Running"
    }

    func endpointTitle(for entry: NetworkLogEntry) -> String {
        let path = entry.url.path
        if path.isEmpty || path == "/" {
            return entry.url.host ?? entry.url.absoluteString
        }
        return path
    }

    func baseURLText(for entry: NetworkLogEntry) -> String {
        guard let scheme = entry.url.scheme,
              let host = entry.url.host else {
            return entry.url.absoluteString
        }

        if let port = entry.url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    func endpointDetailText(for entry: NetworkLogEntry) -> String {
        var endpoint = entry.url.path.isEmpty ? "/" : entry.url.path

        if let query = entry.url.query, !query.isEmpty {
            endpoint += "?\(query)"
        }
        if let fragment = entry.url.fragment, !fragment.isEmpty {
            endpoint += "#\(fragment)"
        }
        return endpoint
    }

    func durationText(for entry: NetworkLogEntry) -> String {
        guard let duration = entry.duration else { return "-" }
        return String(format: "%.3fms", duration * 1_000)
    }

    func sizeText(for entry: NetworkLogEntry) -> String {
        byteFormatter.string(fromByteCount: Int64(entry.responseBody.count))
    }

    func metricRows(for entry: NetworkLogEntry) -> [(String, String)] {
        [
            ("Duration", durationText(for: entry)),
            ("Request Size", byteFormatter.string(fromByteCount: Int64(entry.requestBody.count))),
            ("Response Size", byteFormatter.string(fromByteCount: Int64(entry.responseBody.count))),
        ]
    }

    func timestampText(for entry: NetworkLogEntry) -> String {
        timestampFormatter.string(from: entry.startedAt)
    }

    func headers(for section: DetailSection, entry: NetworkLogEntry) -> [String: String] {
        switch section {
        case .requestHeaders:
            return entry.requestHeaders
        case .responseHeaders:
            return entry.responseHeaders
        case .requestBody, .responseBody:
            return [:]
        }
    }

    func bodyText(for section: DetailSection, entry: NetworkLogEntry) -> String {
        switch section {
        case .requestBody:
            return bodyText(from: entry.requestBody, contentType: entry.requestHeaders["Content-Type"])
        case .responseBody:
            return bodyText(from: entry.responseBody, contentType: entry.responseHeaders["Content-Type"])
        case .requestHeaders, .responseHeaders:
            return "{}"
        }
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        DesknetDiagnostics.log("UI", "copied text length=\(text.count)")
    }

    private func applyFilterAndSelection() {
        let previousSelection = selectedEntryID
        entries = filteredEntries(from: allEntries, query: query)

        if let previousSelection,
           entries.contains(where: { $0.id == previousSelection }) {
            selectedEntryID = previousSelection
            return
        }

        selectedEntryID = entries.first?.id
    }

    private func filteredEntries(from source: [NetworkLogEntry], query: String) -> [NetworkLogEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return source }

        return source.filter { entry in
            let status = entry.statusCode.map(String.init) ?? ""
            let haystack = [
                entry.url.absoluteString,
                entry.url.path,
                entry.url.host ?? "",
                entry.method,
                status,
                entry.errorDescription ?? "",
            ].joined(separator: " ").lowercased()
            return haystack.contains(trimmed)
        }
    }

    private func bodyText(from data: Data, contentType: String?) -> String {
        guard !data.isEmpty else { return "{}" }

        if let object = try? JSONSerialization.jsonObject(with: data),
           JSONSerialization.isValidJSONObject(object),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return text
        }

        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }

        if (contentType ?? "").localizedCaseInsensitiveContains("json"),
           let text = String(data: data, encoding: .ascii),
           !text.isEmpty {
            return text
        }

        return "Binary body (\(data.count) bytes)"
    }
}

struct DesknetMonitorRootView: View {
    @ObservedObject var viewModel: DesknetMonitorViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            HSplitView {
                sidebarView
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)
                detailView
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesknetPalette.windowBackground)
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Desknet")
                    .font(.system(size: 17, weight: .bold))
                Text("Network Logger")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 16)

            Text(viewModel.requestCountText)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(DesknetPalette.controlBackground)
                .clipShape(Capsule())

            Button("Clear") {
                viewModel.clear()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(minHeight: 82)
    }

    private var sidebarView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search requests...", text: $viewModel.query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DesknetPalette.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.entries) { entry in
                        Button {
                            viewModel.selectedEntryID = entry.id
                        } label: {
                            DesknetRequestRowView(
                                entry: entry,
                                isSelected: viewModel.selectedEntryID == entry.id,
                                viewModel: viewModel
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .background(DesknetPalette.windowBackground)
    }

    @ViewBuilder
    private var detailView: some View {
        if let selectedEntry = viewModel.selectedEntry {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DesknetSummaryCard(entry: selectedEntry, viewModel: viewModel)
                    ForEach(DesknetMonitorViewModel.DetailSection.allCases, id: \.self) { section in
                        DesknetSectionCard(
                            section: section,
                            entry: selectedEntry,
                            isExpanded: viewModel.sectionBinding(section),
                            viewModel: viewModel
                        )
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(viewModel.emptyStateText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(24)
        }
    }
}

private struct DesknetRequestRowView: View {
    let entry: NetworkLogEntry
    let isSelected: Bool
    @ObservedObject var viewModel: DesknetMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle()
                    .fill(viewModel.isError(entry) ? .red : .green)
                    .frame(width: 8, height: 8)

                DesknetPill(
                    text: entry.method,
                    textColor: viewModel.isError(entry) ? Color.red : Color.green,
                    fillColor: (viewModel.isError(entry) ? Color.red : Color.green).opacity(0.15)
                )
                .font(.system(size: 12, weight: .bold))

                Text(entry.statusCode.map(String.init) ?? "-")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(viewModel.isError(entry) ? Color.red : Color.green)
            }

            Text(viewModel.endpointTitle(for: entry))
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)

            Text("◷ \(viewModel.durationText(for: entry))   \(viewModel.sizeText(for: entry))")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isSelected
                    ? DesknetPalette.controlBackground.opacity(0.96)
                    : DesknetPalette.controlBackground.opacity(0.68)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected
                    ? DesknetPalette.selectionBorder.opacity(0.55)
                    : Color.clear,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
}

private struct DesknetSummaryCard: View {
    let entry: NetworkLogEntry
    @ObservedObject var viewModel: DesknetMonitorViewModel

    var body: some View {
        let methodAccent = viewModel.isError(entry) ? Color.red : Color.green

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                DesknetPill(
                    text: entry.method,
                    textColor: methodAccent,
                    fillColor: methodAccent.opacity(0.15)
                )
                    .font(.system(size: 13, weight: .bold))
                DesknetPill(
                    text: viewModel.statusText(for: entry),
                    textColor: .white,
                    fillColor: viewModel.isError(entry) ? .red.opacity(0.85) : .green.opacity(0.85)
                )
                .font(.system(size: 13, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 8) {
                makeURLLine(title: "Base URL", value: viewModel.baseURLText(for: entry))
                makeURLLine(title: "Endpoint", value: viewModel.endpointDetailText(for: entry))
            }

            let columns = [GridItem(.adaptive(minimum: 180), spacing: 14)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(viewModel.metricRows(for: entry), id: \.0) { metric in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(metric.0)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(metric.1)
                            .font(.system(size: 16, weight: .bold))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Timestamp")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(viewModel.timestampText(for: entry))
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesknetPalette.windowBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DesknetPalette.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func makeURLLine(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .desknetTextSelectionEnabled()
        }
    }
}

private struct DesknetSectionCard: View {
    let section: DesknetMonitorViewModel.DetailSection
    let entry: NetworkLogEntry
    @Binding var isExpanded: Bool
    @ObservedObject var viewModel: DesknetMonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(section.title)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                sectionContent
                    .padding(.top, 4)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesknetPalette.windowBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DesknetPalette.separator, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .requestHeaders, .responseHeaders:
            let headers = viewModel.headers(for: section, entry: entry)
            if headers.isEmpty {
                Text("No headers")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(headers.sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }), id: \.key) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top) {
                                Text(item.key)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button {
                                    viewModel.copyToPasteboard(item.value)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.secondary)
                            }
                            Text(item.value)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .desknetTextSelectionEnabled()
                                .lineLimit(3)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(sectionContentBackground(for: section))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(sectionContentBorder(for: section), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        case .requestBody, .responseBody:
            let text = viewModel.bodyText(for: section, entry: entry)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Button {
                        viewModel.copyToPasteboard(text)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                Text(text)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .desknetTextSelectionEnabled()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(sectionContentBackground(for: section))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(sectionContentBorder(for: section), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func sectionContentBackground(for section: DesknetMonitorViewModel.DetailSection) -> Color {
        switch section {
        case .requestHeaders:
            return Color.green.opacity(0.10)
        case .requestBody:
            return DesknetPalette.teal.opacity(0.10)
        case .responseHeaders:
            return Color.blue.opacity(0.10)
        case .responseBody:
            return Color.orange.opacity(0.10)
        }
    }

    private func sectionContentBorder(for section: DesknetMonitorViewModel.DetailSection) -> Color {
        switch section {
        case .requestHeaders:
            return Color.green.opacity(0.22)
        case .requestBody:
            return DesknetPalette.teal.opacity(0.22)
        case .responseHeaders:
            return Color.blue.opacity(0.22)
        case .responseBody:
            return Color.orange.opacity(0.22)
        }
    }
}

private struct DesknetPill: View {
    let text: String
    let textColor: Color
    let fillColor: Color
    private var currentFont = Font.system(size: 12, weight: .semibold)

    init(text: String, textColor: Color, fillColor: Color) {
        self.text = text
        self.textColor = textColor
        self.fillColor = fillColor
    }

    var body: some View {
        Text(text)
            .font(currentFont)
            .foregroundColor(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(fillColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    func font(_ font: Font) -> DesknetPill {
        var copy = self
        copy.currentFont = font
        return copy
    }
}

private enum DesknetPalette {
    static let windowBackground = Color(red: 0.12, green: 0.12, blue: 0.13)
    static let controlBackground = Color.white.opacity(0.08)
    static let separator = Color.white.opacity(0.14)
    static let selectionBorder = Color.white.opacity(0.40)
    static let teal = Color(red: 0.23, green: 0.70, blue: 0.64)
}

private extension View {
    @ViewBuilder
    func desknetTextSelectionEnabled() -> some View {
        if #available(macOS 12.0, *) {
            textSelection(.enabled)
        } else {
            self
        }
    }
}
