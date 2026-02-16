import Foundation

/// Client for CloudKit Web Services REST API targeting Bear's iCloud container.
struct CloudKitAPI {
    let auth: AuthConfig

    private let baseURL = "https://api.apple-cloudkit.com/database/1/iCloud.net.shinyfrog.bear/production/private"
    private let bearZone = CKZoneID(zoneName: "Notes", ownerRecordName: nil)

    // MARK: - Low-level API

    private func buildURL(path: String) -> URL {
        // Manually percent-encode query values because URLQueryItem does NOT
        // encode '+' as '%2B'. Apple's servers decode '+' as space, corrupting tokens.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove("+")
        let tokenEncoded = auth.ckWebAuthToken.addingPercentEncoding(withAllowedCharacters: allowed) ?? auth.ckWebAuthToken
        let apiKeyEncoded = auth.ckAPIToken.addingPercentEncoding(withAllowedCharacters: allowed) ?? auth.ckAPIToken
        let urlString = "\(baseURL)/\(path)?ckWebAuthToken=\(tokenEncoded)&ckAPIToken=\(apiKeyEncoded)"
        return URL(string: urlString)!
    }

    private func post<T: Decodable>(path: String, body: some Encodable) async throws -> T {
        let url = buildURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BearCLIError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 421 {
            throw BearCLIError.authExpired
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw BearCLIError.apiError(httpResponse.statusCode, body)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Zones

    func listZones() async throws -> [CKZone] {
        struct Empty: Encodable {}
        let response: CKZoneListResponse = try await post(path: "zones/list", body: Empty())
        return response.zones
    }

    // MARK: - Query Notes

    func queryNotes(
        trashed: Bool = false,
        archived: Bool = false,
        limit: Int = 50,
        desiredKeys: [String]? = nil
    ) async throws -> [CKRecord] {
        let filters: [CKFilter] = [
            CKFilter(
                fieldName: "trashed",
                comparator: "EQUALS",
                fieldValue: CKFieldValue(value: .int(trashed ? 1 : 0), type: "INT64")
            ),
            CKFilter(
                fieldName: "archived",
                comparator: "EQUALS",
                fieldValue: CKFieldValue(value: .int(archived ? 1 : 0), type: "INT64")
            ),
        ]

        let query = CKQuery(
            recordType: "SFNote",
            filterBy: filters,
            sortBy: [
                CKSort(fieldName: "pinned", ascending: false),
                CKSort(fieldName: "sf_modificationDate", ascending: false),
            ]
        )

        let request = CKRecordQueryRequest(
            zoneID: bearZone,
            query: query,
            resultsLimit: limit,
            desiredKeys: desiredKeys
        )

        let response: CKRecordQueryResponse = try await post(path: "records/query", body: request)
        return response.records
    }

    /// Query notes with pagination support, fetching all results
    func queryAllNotes(
        trashed: Bool = false,
        archived: Bool = false,
        desiredKeys: [String]? = nil
    ) async throws -> [CKRecord] {
        var allRecords: [CKRecord] = []
        var continuationMarker: String? = nil

        repeat {
            var body: [String: AnyCodableValue] = [
                "zoneID": .dictionary([
                    "zoneName": .string("Notes"),
                ]),
                "query": .dictionary([
                    "recordType": .string("SFNote"),
                    "filterBy": .array([
                        .dictionary([
                            "fieldName": .string("trashed"),
                            "comparator": .string("EQUALS"),
                            "fieldValue": .dictionary(["value": .int(trashed ? 1 : 0), "type": .string("INT64")]),
                        ]),
                        .dictionary([
                            "fieldName": .string("archived"),
                            "comparator": .string("EQUALS"),
                            "fieldValue": .dictionary(["value": .int(archived ? 1 : 0), "type": .string("INT64")]),
                        ]),
                    ]),
                    "sortBy": .array([
                        .dictionary(["fieldName": .string("pinned"), "ascending": .bool(false)]),
                        .dictionary(["fieldName": .string("sf_modificationDate"), "ascending": .bool(false)]),
                    ]),
                ]),
                "resultsLimit": .int(200),
            ]

            if let keys = desiredKeys {
                body["desiredKeys"] = .array(keys.map { .string($0) })
            }

            if let marker = continuationMarker {
                body["continuationMarker"] = .string(marker)
            }

            let response: CKRecordQueryResponse = try await post(path: "records/query", body: body)
            allRecords.append(contentsOf: response.records)
            continuationMarker = response.continuationMarker
        } while continuationMarker != nil

        return allRecords
    }

    // MARK: - Query Tags

    func queryTags(limit: Int = 200) async throws -> [CKRecord] {
        let query = CKQuery(
            recordType: "SFNoteTag",
            filterBy: [],
            sortBy: [CKSort(fieldName: "title", ascending: true)]
        )

        let request = CKRecordQueryRequest(
            zoneID: bearZone,
            query: query,
            resultsLimit: limit
        )

        let response: CKRecordQueryResponse = try await post(path: "records/query", body: request)
        return response.records
    }

    // MARK: - Lookup by ID

    func lookupRecords(ids: [String], desiredKeys: [String]? = nil) async throws -> [CKRecord] {
        let request = CKRecordLookupRequest(
            records: ids.map { CKRecordRef(recordName: $0) },
            zoneID: bearZone,
            desiredKeys: desiredKeys
        )

        let response: CKRecordLookupResponse = try await post(path: "records/lookup", body: request)
        return response.records
    }

    // MARK: - Download Asset (note text)

    func downloadAsset(url: String) async throws -> String {
        guard let assetURL = URL(string: url) else {
            throw BearCLIError.invalidURL(url)
        }

        let (data, response) = try await URLSession.shared.data(from: assetURL)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BearCLIError.networkError("Failed to download note content")
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw BearCLIError.networkError("Note content is not valid UTF-8")
        }

        return text
    }

    // MARK: - Modify Records (create/update)

    func modifyRecords(operations: [[String: AnyCodableValue]]) async throws -> [CKRecord] {
        let body: [String: AnyCodableValue] = [
            "operations": .array(operations.map { .dictionary($0) }),
            "zoneID": .dictionary(["zoneName": .string("Notes")]),
        ]

        let response: CKRecordQueryResponse = try await post(path: "records/modify", body: body)
        return response.records
    }

    /// Create a new note. Returns the created CKRecord.
    func createNote(title: String, text: String, tags: [String] = []) async throws -> CKRecord {
        let noteID = UUID().uuidString
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        // Build the full markdown: title as H1, then tags, then body
        var markdown = "# \(title)"
        if !tags.isEmpty {
            markdown += "\n" + tags.map { "#\($0)" }.joined(separator: " ")
        }
        if !text.isEmpty {
            markdown += "\n\n\(text)"
        }

        // Build subtitle from first line of body text
        let subtitle = text.components(separatedBy: "\n").first ?? ""

        // Look up or create tag records
        var tagUUIDs: [AnyCodableValue] = []
        var tagStrings: [AnyCodableValue] = []
        var operations: [[String: AnyCodableValue]] = []

        if !tags.isEmpty {
            // Fetch existing tags to find matches
            let existingTags = try await queryTags()
            var tagMap: [String: String] = [:] // title -> recordName
            for record in existingTags {
                if let t = record.fields["title"]?.value.stringValue {
                    tagMap[t] = record.recordName
                }
            }

            for tag in tags {
                tagStrings.append(.string(tag))
                if let existingID = tagMap[tag] {
                    tagUUIDs.append(.string(existingID))
                } else {
                    // Create new tag
                    let tagID = UUID().uuidString
                    tagUUIDs.append(.string(tagID))
                    operations.append(buildCreateTagOperation(
                        tagID: tagID, title: tag, now: now
                    ))
                }
            }
        }

        // Build the note create operation
        let noteOp = buildCreateNoteOperation(
            noteID: noteID,
            title: title,
            markdown: markdown,
            subtitle: subtitle,
            tagUUIDs: tagUUIDs,
            tagStrings: tagStrings,
            now: now
        )
        operations.insert(noteOp, at: 0)

        let records = try await modifyRecords(operations: operations)
        guard let noteRecord = records.first(where: { $0.recordName == noteID }) else {
            throw BearCLIError.networkError("Create succeeded but note not found in response")
        }
        return noteRecord
    }

    /// Update an existing note's text content.
    func updateNote(record: CKRecord, newText: String) async throws -> CKRecord {
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        // Extract title from the first H1 line of the new text, or keep existing
        let lines = newText.components(separatedBy: "\n")
        let title: String
        if let firstLine = lines.first, firstLine.hasPrefix("# ") {
            title = String(firstLine.dropFirst(2))
        } else {
            title = record.fields["title"]?.value.stringValue ?? ""
        }

        // Build subtitle from first non-title, non-tag, non-empty line
        let subtitle = lines.dropFirst().first(where: {
            !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) ?? ""

        // Increment vector clock
        let existingClock = record.fields["vectorClock"]?.value.stringValue ?? ""
        let newClock = incrementVectorClock(existingClock)

        let fields: [String: AnyCodableValue] = [
            "textADP": .dictionary([
                "value": .string(newText),
                "type": .string("STRING"),
                "isEncrypted": .bool(true),
            ]),
            "title": .dictionary([
                "value": .string(title),
                "type": .string("STRING"),
            ]),
            "subtitleADP": .dictionary([
                "value": .string(subtitle),
                "type": .string("STRING"),
                "isEncrypted": .bool(true),
            ]),
            "vectorClock": .dictionary([
                "value": .string(newClock),
                "type": .string("BYTES"),
            ]),
            "sf_modificationDate": .dictionary([
                "value": .int(now),
                "type": .string("TIMESTAMP"),
            ]),
            "lastEditingDevice": .dictionary([
                "value": .string("Bear CLI"),
                "type": .string("STRING"),
            ]),
        ]

        var recordDict: [String: AnyCodableValue] = [
            "recordName": .string(record.recordName),
            "recordType": .string("SFNote"),
            "fields": .dictionary(fields),
            "pluginFields": .dictionary([:]),
            "recordChangeTag": .string(record.recordChangeTag ?? ""),
            "deleted": .bool(false),
        ]

        // Include created/modified metadata for updates
        if let created = record.created {
            var createdDict: [String: AnyCodableValue] = [:]
            if let ts = created.timestamp { createdDict["timestamp"] = .int(ts) }
            if let user = created.userRecordName { createdDict["userRecordName"] = .string(user) }
            recordDict["created"] = .dictionary(createdDict)
        }
        if let modified = record.modified {
            var modifiedDict: [String: AnyCodableValue] = [:]
            if let ts = modified.timestamp { modifiedDict["timestamp"] = .int(ts) }
            if let user = modified.userRecordName { modifiedDict["userRecordName"] = .string(user) }
            recordDict["modified"] = .dictionary(modifiedDict)
        }

        let operation: [String: AnyCodableValue] = [
            "operationType": .string("update"),
            "record": .dictionary(recordDict),
            "recordType": .string("SFNote"),
        ]

        let records = try await modifyRecords(operations: [operation])
        guard let updated = records.first else {
            throw BearCLIError.networkError("Update succeeded but no record returned")
        }
        return updated
    }

    /// Trash a note (soft delete).
    func trashNote(record: CKRecord) async throws -> CKRecord {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let newClock = incrementVectorClock(
            record.fields["vectorClock"]?.value.stringValue ?? ""
        )

        let fields: [String: AnyCodableValue] = [
            "trashed": .dictionary(["value": .int(1), "type": .string("INT64")]),
            "trashedDate": .dictionary(["value": .int(now), "type": .string("TIMESTAMP")]),
            "vectorClock": .dictionary(["value": .string(newClock), "type": .string("BYTES")]),
            "sf_modificationDate": .dictionary(["value": .int(now), "type": .string("TIMESTAMP")]),
        ]

        var recordDict: [String: AnyCodableValue] = [
            "recordName": .string(record.recordName),
            "recordType": .string("SFNote"),
            "fields": .dictionary(fields),
            "pluginFields": .dictionary([:]),
            "recordChangeTag": .string(record.recordChangeTag ?? ""),
            "deleted": .bool(false),
        ]

        if let created = record.created {
            var createdDict: [String: AnyCodableValue] = [:]
            if let ts = created.timestamp { createdDict["timestamp"] = .int(ts) }
            if let user = created.userRecordName { createdDict["userRecordName"] = .string(user) }
            recordDict["created"] = .dictionary(createdDict)
        }
        if let modified = record.modified {
            var modifiedDict: [String: AnyCodableValue] = [:]
            if let ts = modified.timestamp { modifiedDict["timestamp"] = .int(ts) }
            if let user = modified.userRecordName { modifiedDict["userRecordName"] = .string(user) }
            recordDict["modified"] = .dictionary(modifiedDict)
        }

        let operation: [String: AnyCodableValue] = [
            "operationType": .string("update"),
            "record": .dictionary(recordDict),
            "recordType": .string("SFNote"),
        ]

        let records = try await modifyRecords(operations: [operation])
        guard let trashed = records.first else {
            throw BearCLIError.networkError("Trash succeeded but no record returned")
        }
        return trashed
    }

    // MARK: - Helper: Build Create Operations

    private func buildCreateNoteOperation(
        noteID: String, title: String, markdown: String, subtitle: String,
        tagUUIDs: [AnyCodableValue], tagStrings: [AnyCodableValue], now: Int64
    ) -> [String: AnyCodableValue] {
        let vectorClock = makeVectorClock(device: "Bear CLI", counter: 1)

        let fields: [String: AnyCodableValue] = [
            "archived": .dictionary(["type": .string("INT64"), "value": .int(0)]),
            "tags": .dictionary(["type": .string("STRING_LIST"), "value": .array(tagUUIDs)]),
            "trashedDate": .dictionary(["type": .string("TIMESTAMP"), "value": .null]),
            "subtitleADP": .dictionary(["type": .string("STRING"), "value": .string(subtitle), "isEncrypted": .bool(true)]),
            "pinnedDate": .dictionary(["type": .string("TIMESTAMP"), "value": .null]),
            "pinnedInTagsStrings": .dictionary(["type": .string("STRING_LIST"), "value": .null]),
            "archivedDate": .dictionary(["type": .string("TIMESTAMP"), "value": .null]),
            "pinned": .dictionary(["type": .string("INT64"), "value": .int(0)]),
            "textADP": .dictionary(["type": .string("STRING"), "value": .string(markdown), "isEncrypted": .bool(true)]),
            "sf_creationDate": .dictionary(["type": .string("TIMESTAMP"), "value": .int(now)]),
            "linkedBy": .dictionary(["type": .string("STRING_LIST"), "value": .array([])]),
            "title": .dictionary(["type": .string("STRING"), "value": .string(title)]),
            "hasImages": .dictionary(["type": .string("INT64"), "value": .int(0)]),
            "linkingTo": .dictionary(["type": .string("STRING_LIST"), "value": .array([])]),
            "hasFiles": .dictionary(["type": .string("INT64"), "value": .int(0)]),
            "locked": .dictionary(["type": .string("INT64"), "value": .int(0)]),
            "trashed": .dictionary(["type": .string("INT64"), "value": .int(0)]),
            "todoCompleted": .dictionary(["type": .string("INT64"), "value": .int(0)]),
            "subtitle": .dictionary(["type": .string("STRING"), "value": .null]),
            "files": .dictionary(["type": .string("STRING_LIST"), "value": .array([])]),
            "vectorClock": .dictionary(["type": .string("BYTES"), "value": .string(vectorClock)]),
            "hasSourceCode": .dictionary(["type": .string("INT64"), "value": .int(0)]),
            "conflictUniqueIdentifier": .dictionary(["type": .string("STRING"), "value": .null]),
            "tagsStrings": .dictionary(["type": .string("STRING_LIST"), "value": .array(tagStrings)]),
            "lastEditingDevice": .dictionary(["type": .string("STRING"), "value": .string("Bear CLI")]),
            "version": .dictionary(["type": .string("INT64"), "value": .int(3)]),
            "encrypted": .dictionary(["type": .string("INT64"), "value": .int(0)]),
            "conflictUniqueIdentifierDate": .dictionary(["type": .string("TIMESTAMP"), "value": .null]),
            "todoIncompleted": .dictionary(["type": .string("INT64"), "value": .int(0)]),
            "encryptedData": .dictionary(["type": .string("STRING"), "value": .null]),
            "sf_modificationDate": .dictionary(["type": .string("TIMESTAMP"), "value": .int(now + 1)]),
            "lockedDate": .dictionary(["type": .string("TIMESTAMP"), "value": .null]),
            "text": .dictionary(["type": .string("STRING"), "value": .null]),
            "uniqueIdentifier": .dictionary(["type": .string("STRING"), "value": .string(noteID)]),
        ]

        return [
            "operationType": .string("create"),
            "record": .dictionary([
                "recordName": .string(noteID),
                "recordType": .string("SFNote"),
                "fields": .dictionary(fields),
                "pluginFields": .dictionary([:]),
                "recordChangeTag": .null,
                "created": .null,
                "modified": .null,
                "deleted": .bool(false),
            ]),
            "recordType": .string("SFNote"),
        ]
    }

    private func buildCreateTagOperation(tagID: String, title: String, now: Int64) -> [String: AnyCodableValue] {
        let fields: [String: AnyCodableValue] = [
            "tagcon": .dictionary(["type": .string("STRING"), "value": .null]),
            "pinnedDate": .dictionary(["type": .string("TIMESTAMP"), "value": .null]),
            "pinned": .dictionary(["type": .string("INT64"), "value": .int(0)]),
            "pinnedNotes": .dictionary(["type": .string("STRING_LIST"), "value": .null]),
            "title": .dictionary(["type": .string("STRING"), "value": .string(title)]),
            "notesCount": .dictionary(["type": .string("INT64"), "value": .int(1)]),
            "tagconDate": .dictionary(["type": .string("TIMESTAMP"), "value": .null]),
            "pinnedNotesDate": .dictionary(["type": .string("TIMESTAMP"), "value": .null]),
            "isRoot": .dictionary(["type": .string("INT64"), "value": .int(title.contains("/") ? 0 : 1)]),
            "sortingDate": .dictionary(["type": .string("TIMESTAMP"), "value": .null]),
            "sorting": .dictionary(["type": .string("INT64"), "value": .int(0)]),
            "version": .dictionary(["type": .string("INT64"), "value": .int(3)]),
            "sf_modificationDate": .dictionary(["type": .string("TIMESTAMP"), "value": .int(now)]),
            "uniqueIdentifier": .dictionary(["type": .string("STRING"), "value": .string(tagID)]),
        ]

        return [
            "operationType": .string("create"),
            "record": .dictionary([
                "recordName": .string(tagID),
                "recordType": .string("SFNoteTag"),
                "fields": .dictionary(fields),
                "pluginFields": .dictionary([:]),
                "recordChangeTag": .null,
                "created": .null,
                "modified": .null,
                "deleted": .bool(false),
            ]),
            "recordType": .string("SFNoteTag"),
        ]
    }

    // MARK: - Vector Clock Helpers

    /// Create a fresh vector clock for a new record.
    private func makeVectorClock(device: String, counter: Int) -> String {
        // Minimal binary plist: { "Bear CLI": counter }
        // The format Bear uses is a bplist00 with the device name and an int counter.
        // We replicate the exact pattern from Bear Web's output.
        var data = Data()
        // bplist00 header
        data.append(contentsOf: [0x62, 0x70, 0x6C, 0x69, 0x73, 0x74, 0x30, 0x30])
        // ASCII string object (type 0x50 + length)
        let deviceBytes = Array(device.utf8)
        data.append(UInt8(0x50 | (deviceBytes.count & 0x0F)))
        data.append(contentsOf: deviceBytes)
        // Int object (type 0x10 + value)
        data.append(0x10)
        data.append(UInt8(counter & 0xFF))
        // Offset table and trailer (simplified)
        let obj0Offset: UInt8 = 8
        let obj1Offset = obj0Offset + 1 + UInt8(deviceBytes.count)
        // Dict with 1 entry: key=obj0, value=obj1
        data.append(0xD1) // dict with 1 entry
        data.append(0x00) // key index
        data.append(0x01) // value index
        // Offset table
        let offsetTableOffset = data.count
        data.append(obj0Offset)
        data.append(obj1Offset)
        data.append(obj1Offset + 2) // dict offset
        // Trailer (32 bytes)
        data.append(contentsOf: [UInt8](repeating: 0, count: 18))
        data.append(0x01) // offsetIntSize
        data.append(0x01) // objectRefSize
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03]) // numObjects
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02]) // topObject index
        let otBytes = withUnsafeBytes(of: UInt64(offsetTableOffset).bigEndian) { Array($0) }
        data.append(contentsOf: otBytes)
        return data.base64EncodedString()
    }

    /// Increment the counter in an existing vector clock, or create a fresh one.
    private func incrementVectorClock(_ base64: String) -> String {
        // For simplicity, if we can't parse the existing clock, create a fresh one.
        // The clock is a bplist with {"Device Name": counter}.
        // We create a new clock with "Bear CLI" and counter = extracted + 1.
        guard let data = Data(base64Encoded: base64), data.count > 20 else {
            return makeVectorClock(device: "Bear CLI", counter: 1)
        }

        // Try to find the counter byte (it follows 0x10 pattern)
        // The counter is typically near the device name, encoded as 0x10 + byte
        for i in 9..<(data.count - 20) {
            if data[i] == 0x10 {
                let currentCounter = Int(data[i + 1])
                return makeVectorClock(device: "Bear CLI", counter: currentCounter + 1)
            }
        }

        return makeVectorClock(device: "Bear CLI", counter: 1)
    }

    // MARK: - Search (client-side title match)

    func searchNotes(query searchTerm: String, limit: Int = 50) async throws -> [CKRecord] {
        // CloudKit doesn't support full-text search natively.
        // Fetch the lightweight index and filter client-side by title.
        let allRecords = try await queryAllNotes(
            desiredKeys: ["uniqueIdentifier", "title", "sf_creationDate", "sf_modificationDate", "tagsStrings", "pinned"]
        )

        let term = searchTerm.lowercased()
        return allRecords.filter { record in
            if let title = record.fields["title"]?.value.stringValue,
               title.lowercased().contains(term) {
                return true
            }
            if let tags = record.fields["tagsStrings"]?.value.arrayValue {
                for tag in tags {
                    if let t = tag.stringValue, t.lowercased().contains(term) {
                        return true
                    }
                }
            }
            return false
        }
    }
}

// MARK: - Errors

enum BearCLIError: Error, CustomStringConvertible {
    case authExpired
    case authNotConfigured
    case apiError(Int, String)
    case networkError(String)
    case invalidURL(String)
    case noteNotFound(String)

    var description: String {
        switch self {
        case .authExpired:
            return "Auth token expired. Run `bcli auth` to re-authenticate."
        case .authNotConfigured:
            return "Not authenticated. Run `bcli auth` first."
        case .apiError(let code, let body):
            return "CloudKit API error (\(code)): \(body.prefix(200))"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .noteNotFound(let id):
            return "Note not found: \(id)"
        }
    }
}
