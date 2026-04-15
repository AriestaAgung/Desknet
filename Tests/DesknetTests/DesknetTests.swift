import Foundation
import Testing
@testable import Desknet

@Test func requestFilterIgnoresConfiguredPattern() {
    let filter = DesknetRequestFilter()
    filter.addIgnoredPattern("example.com")

    let ignoredRequest = URLRequest(url: URL(string: "https://example.com/path")!)
    let acceptedRequest = URLRequest(url: URL(string: "https://api.service.com/users")!)

    #expect(filter.shouldCapture(ignoredRequest) == false)
    #expect(filter.shouldCapture(acceptedRequest) == true)
}

@Test func detailFormatterPrintsHeadersAndBody() {
    let entry = NetworkLogEntry(
        id: UUID(),
        startedAt: Date(timeIntervalSince1970: 1),
        endedAt: Date(timeIntervalSince1970: 2),
        method: "POST",
        url: URL(string: "https://api.example.com/todos?source=ios&debug=true")!,
        requestHeaders: ["Content-Type": "application/json"],
        requestBody: Data("{\"task\":\"ship\"}".utf8),
        statusCode: 201,
        responseHeaders: ["X-Trace": "abc123"],
        responseBody: Data("{\"ok\":true}".utf8),
        mimeType: "application/json",
        errorDescription: nil
    )

    let text = DesknetDetailFormatter.format(entry: entry)

    #expect(text.contains("Method: POST"))
    #expect(text.contains("URL: https://api.example.com/todos?source=ios&debug=true"))
    #expect(text.contains("Status: 201"))
    #expect(text.contains("source: ios"))
    #expect(text.contains("Content-Type: application/json"))
    #expect(text.contains("\"ok\" : true"))
    #expect(text.contains("cURL"))
    #expect(text.contains("curl -X 'POST'"))
}

@MainActor
@Test func swiftUIViewModelFiltersAndKeepsSelection() {
    let store = DesknetStore()
    let refreshID = captureRequest(
        store: store,
        url: "https://localhost:3000/api/apps/auth/refresh",
        method: "POST",
        statusCode: 200,
        responseBody: #"{"message":"ok"}"#
    )
    _ = captureRequest(
        store: store,
        url: "https://localhost:3000/api/apps/subscription/validate",
        method: "POST",
        statusCode: 401,
        responseBody: #"{"error":"invalid token"}"#
    )

    let viewModel = DesknetMonitorViewModel(store: store)
    viewModel.selectedEntryID = refreshID

    viewModel.query = "refresh"

    #expect(viewModel.entries.count == 1)
    #expect(viewModel.entries.first?.id == refreshID)
    #expect(viewModel.selectedEntryID == refreshID)
}

@MainActor
@Test func swiftUIViewModelAutoSelectsFirstEntryAndSupportsSections() {
    let store = DesknetStore()
    _ = captureRequest(
        store: store,
        url: "https://localhost:3000/api/apps/subscription/validate",
        method: "POST",
        statusCode: 200,
        responseBody: #"{"ok":true}"#
    )

    let viewModel = DesknetMonitorViewModel(store: store)
    #expect(viewModel.selectedEntry != nil)
    #expect(viewModel.requestCountText == "1 requests")

    #expect(viewModel.isSectionExpanded(.requestHeaders) == false)
    viewModel.setSectionExpanded(.requestHeaders, isExpanded: true)
    #expect(viewModel.isSectionExpanded(.requestHeaders) == true)
}

private func captureRequest(
    store: DesknetStore,
    url: String,
    method: String,
    statusCode: Int,
    responseBody: String
) -> UUID {
    var request = URLRequest(url: URL(string: url)!)
    request.httpMethod = method
    request.allHTTPHeaderFields = ["Content-Type": "application/json"]
    request.httpBody = Data("{}".utf8)

    let id = store.begin(request: request)!
    let response = HTTPURLResponse(
        url: request.url!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    store.recordResponse(for: id, response: response)
    store.appendResponseBody(for: id, data: Data(responseBody.utf8))
    store.finish(for: id, error: nil)
    return id
}
