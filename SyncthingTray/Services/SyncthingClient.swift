import Foundation

actor SyncthingClient {
    private struct StatusProbe: Decodable {}

    private let session: URLSession
    private let decoder: JSONDecoder

    private var baseURL: URL
    private var apiKey: String = ""
    private var lastEventID = 0

    init(session: URLSession = .shared, baseURL: URL = URL(string: "http://127.0.0.1:8384")!) {
        self.session = session
        self.baseURL = baseURL

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let stringValue = try container.decode(String.self)
            if let date = Self.parseDate(stringValue) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported date format: \(stringValue)")
        }
        self.decoder = decoder
    }

    func configure(baseURL: URL, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    func fetchSnapshot() async throws -> SyncthingRemoteSnapshot {
        async let _: StatusProbe = getJSON("/rest/system/status")
        async let folderIDs = fetchConfiguredFolderIDs()
        async let errors = fetchSystemErrors()
        async let logs = fetchSystemLogs()

        let resolvedFolderIDs = try await folderIDs
        let statuses = try await fetchFolderStatuses(folderIDs: resolvedFolderIDs)

        return SyncthingRemoteSnapshot(
            folderStatuses: statuses,
            errors: try await errors,
            logs: try await logs
        )
    }

    func performMonitorOnlyHealthCheck() async -> Bool {
        do {
            let _: StatusProbe = try await getJSON("/rest/system/status")
            let folderIDs = try await fetchConfiguredFolderIDs()
            if folderIDs.isEmpty == false {
                _ = try await fetchFolderStatuses(folderIDs: folderIDs)
            }
            _ = try await fetchSystemErrors()
            return true
        } catch {
            return false
        }
    }

    func pollEvents() async throws -> [SyncthingEvent] {
        let responseData = try await getData(
            "/rest/events",
            queryItems: [
                URLQueryItem(name: "since", value: String(lastEventID)),
                URLQueryItem(name: "timeout", value: "60")
            ]
        )

        guard let rawObjects = try JSONSerialization.jsonObject(with: responseData) as? [[String: Any]] else {
            return []
        }

        var parsedEvents: [SyncthingEvent] = []
        for rawObject in rawObjects {
            guard let id = rawObject["id"] as? Int,
                  let type = rawObject["type"] as? String else {
                continue
            }

            let timeString = rawObject["time"] as? String ?? ""
            let timestamp = Self.parseDate(timeString) ?? Date()

            let data = rawObject["data"] as? [String: Any]
            let kind: SyncthingEventKind

            switch type {
            case "StateChanged":
                kind = .stateChanged(
                    folder: data?["folder"] as? String ?? "",
                    toState: data?["to"] as? String ?? data?["state"] as? String ?? ""
                )
            case "FolderErrors":
                kind = .folderErrors(folder: data?["folder"] as? String ?? "")
            case "FolderSummary":
                kind = .folderSummary(folder: data?["folder"] as? String ?? "")
            default:
                kind = .unknown(type: type)
            }

            parsedEvents.append(SyncthingEvent(id: id, timestamp: timestamp, kind: kind))
        }

        if let latestID = parsedEvents.map(\.id).max() {
            lastEventID = latestID
        }

        return parsedEvents
    }

    private func fetchConfiguredFolderIDs() async throws -> [String] {
        if let config: SyncthingSystemConfiguration = try? await getJSON("/rest/config") {
            return config.folders.map(\.id)
        }

        let config: SyncthingSystemConfiguration = try await getJSON("/rest/system/config")
        return config.folders.map(\.id)
    }

    private func fetchFolderStatuses(folderIDs: [String]) async throws -> [FolderStatus] {
        try await withThrowingTaskGroup(of: FolderStatus.self) { group in
            for folderID in folderIDs {
                group.addTask {
                    let response: SyncthingFolderStatusResponse = try await self.getJSON(
                        "/rest/db/status",
                        queryItems: [URLQueryItem(name: "folder", value: folderID)]
                    )
                    return FolderStatus(
                        id: response.folder ?? folderID,
                        state: response.state,
                        needBytes: response.needBytes,
                        pullErrors: response.pullErrors,
                        lastChanged: response.stateChanged
                    )
                }
            }

            var statuses: [FolderStatus] = []
            for try await status in group {
                statuses.append(status)
            }
            return statuses.sorted { $0.id < $1.id }
        }
    }

    private func fetchSystemErrors() async throws -> [SyncthingSystemError] {
        if let envelope: SyncthingSystemErrorEnvelope = try? await getJSON("/rest/system/error") {
            return envelope.errors ?? []
        }
        return try await getJSON("/rest/system/error")
    }

    private func fetchSystemLogs() async throws -> [SyncthingLogMessage] {
        if let envelope: SyncthingSystemLogEnvelope = try? await getJSON("/rest/system/log") {
            return envelope.messages ?? []
        }
        return try await getJSON("/rest/system/log")
    }

    private func getData(_ path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        let request = try buildRequest(path: path, queryItems: queryItems)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return data
    }

    private func getJSON<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        let data = try await getData(path, queryItems: queryItems)
        return try decoder.decode(T.self, from: data)
    }

    private func buildRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }

        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 65
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func validate(_ response: URLResponse) throws {
        if let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) == false {
            throw URLError(.badServerResponse)
        }
    }

    nonisolated private static func parseDate(_ stringValue: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let withoutFractional = ISO8601DateFormatter()
        withoutFractional.formatOptions = [.withInternetDateTime]

        return withFractional.date(from: stringValue) ?? withoutFractional.date(from: stringValue)
    }
}
