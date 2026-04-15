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
