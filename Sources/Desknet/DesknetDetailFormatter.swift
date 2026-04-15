import Foundation

enum DesknetDetailFormatter {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func format(entry: NetworkLogEntry) -> String {
        var lines: [String] = []
        lines.append("Overview")
        lines.append("Method: \(entry.method)")
        lines.append("URL: \(entry.url.absoluteString)")

        if let statusCode = entry.statusCode {
            lines.append("Status: \(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode))")
        } else {
            lines.append("Status: -")
        }

        lines.append("Started: \(timestamp(entry.startedAt))")
        if let endedAt = entry.endedAt {
            lines.append("Finished: \(timestamp(endedAt))")
        }

        if let duration = entry.duration {
            lines.append(String(format: "Duration: %.3fs", duration))
        } else {
            lines.append("Duration: running")
        }

        lines.append("Request Size: \(byteString(entry.requestBody.count))")
        lines.append("Response Size: \(byteString(entry.responseBody.count))")

        if let mimeType = entry.mimeType {
            lines.append("MIME: \(mimeType)")
        }

        if let errorDescription = entry.errorDescription {
            lines.append("Error: \(errorDescription)")
        }

        lines.append("")
        lines.append("Query Parameters")
        lines.append(contentsOf: queryLines(for: entry.url))

        lines.append("")
        lines.append("Request Headers")
        lines.append(contentsOf: headerLines(entry.requestHeaders))

        lines.append("")
        lines.append("Request Body")
        lines.append(stringBody(from: entry.requestBody, contentType: entry.requestHeaders["Content-Type"]))

        lines.append("")
        lines.append("Response Headers")
        lines.append(contentsOf: headerLines(entry.responseHeaders))

        lines.append("")
        lines.append("Response Body")
        lines.append(stringBody(from: entry.responseBody, contentType: entry.responseHeaders["Content-Type"]))

        lines.append("")
        lines.append("cURL")
        lines.append(curlString(for: entry))

        return lines.joined(separator: "\n")
    }

    private static func headerLines(_ headers: [String: String]) -> [String] {
        if headers.isEmpty {
            return ["-"]
        }

        return headers
            .sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending })
            .map { "\($0.key): \($0.value)" }
    }

    private static func queryLines(for url: URL) -> [String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems,
              !items.isEmpty else {
            return ["-"]
        }

        return items.map { item in
            "\(item.name): \(item.value ?? "")"
        }
    }

    private static func stringBody(from data: Data, contentType: String?) -> String {
        guard !data.isEmpty else { return "-" }

        if let prettyJSON = prettyJSONString(from: data) {
            return prettyJSON
        }

        if let text = String(data: data, encoding: .utf8) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "-" : text
        }

        if (contentType ?? "").localizedCaseInsensitiveContains("json"),
           let fallback = String(data: data, encoding: .ascii),
           !fallback.isEmpty {
            return fallback
        }

        return "Binary body (\(data.count) bytes)"
    }

    private static func prettyJSONString(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: formatted, encoding: .utf8) else {
            return nil
        }

        return text
    }

    private static func curlString(for entry: NetworkLogEntry) -> String {
        var components: [String] = []
        components.append("curl -X \(shellEscape(entry.method))")

        for (header, value) in entry.requestHeaders.sorted(by: { $0.key < $1.key }) {
            components.append("-H \(shellEscape("\(header): \(value)"))")
        }

        if !entry.requestBody.isEmpty,
           let body = String(data: entry.requestBody, encoding: .utf8) {
            components.append("--data \(shellEscape(body))")
        }

        components.append(shellEscape(entry.url.absoluteString))
        return components.joined(separator: " ")
    }

    private static func shellEscape(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    private static func byteString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }

    private static func timestamp(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }
}
