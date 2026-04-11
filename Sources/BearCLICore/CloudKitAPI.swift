import Foundation
import ImageIO

/// Client for CloudKit Web Services REST API targeting Bear's iCloud container.
public struct CloudKitAPI {
    public let auth: AuthConfig

    public init(auth: AuthConfig) {
        self.auth = auth
    }

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

    public func listZones() async throws -> [CKZone] {
        struct Empty: Encodable {}
        let response: CKZoneListResponse = try await post(path: "zones/list", body: Empty())
        return response.zones
    }

    // MARK: - Query Notes

    public func queryNotes(
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
    public func queryAllNotes(
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

    public func queryTags(limit: Int = 200) async throws -> [CKRecord] {
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

    public func lookupRecords(ids: [String], desiredKeys: [String]? = nil) async throws -> [CKRecord] {
        let request = CKRecordLookupRequest(
            records: ids.map { CKRecordRef(recordName: $0) },
            zoneID: bearZone,
            desiredKeys: desiredKeys
        )

        let response: CKRecordLookupResponse = try await post(path: "records/lookup", body: request)
        return response.records
    }

    // MARK: - Download Asset (note text)

    public func downloadAsset(url: String) async throws -> String {
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

    // MARK: - Upload Asset

    /// Upload a file as a CloudKit asset. Returns the asset dictionary to use in a record's ASSETID field.
    /// Two-step flow: 1) POST to assets/upload to get an upload URL, 2) POST binary to that URL.
    public func uploadAsset(
        fileData: Data,
        fileName: String,
        contentType: String,
        recordType: String = "SFNoteImage",
        recordName: String,
        fieldName: String = "file"
    ) async throws -> [String: AnyCodableValue] {
        // Step 1: Request an upload URL from CloudKit
        let tokenRequest: [String: AnyCodableValue] = [
            "zoneID": .dictionary(["zoneName": .string("Notes")]),
            "tokens": .array([
                .dictionary([
                    "recordType": .string(recordType),
                    "recordName": .string(recordName),
                    "fieldName": .string(fieldName),
                ]),
            ]),
        ]

        let uploadResponse: CKAssetUploadResponse = try await post(
            path: "assets/upload", body: tokenRequest
        )

        guard let token = uploadResponse.tokens.first,
              let uploadURL = URL(string: token.url)
        else {
            throw BearCLIError.networkError("No upload URL returned from assets/upload")
        }

        // Step 2: POST the raw binary to the upload URL
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        uploadRequest.httpBody = fileData

        let (responseData, response) = try await URLSession.shared.data(for: uploadRequest)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: responseData, encoding: .utf8) ?? ""
            throw BearCLIError.apiError(status, "Asset upload failed: \(body)")
        }

        // Parse the receipt from the singleFileUpload response
        let receipt = try JSONDecoder().decode(CKAssetUploadReceipt.self, from: responseData)
        return receipt.singleFile.toFieldValue()
    }

    // MARK: - Modify Records (create/update)

    public func modifyRecords(operations: [[String: AnyCodableValue]]) async throws -> [CKRecord] {
        let body: [String: AnyCodableValue] = [
            "operations": .array(operations.map { .dictionary($0) }),
            "zoneID": .dictionary(["zoneName": .string("Notes")]),
        ]

        let response: CKModifyResponse = try await post(path: "records/modify", body: body)

        // Check for per-record errors (conflicts, etc.)
        let errors = response.records.filter { $0.isError }
        if let first = errors.first {
            throw BearCLIError.recordError(
                recordName: first.recordName,
                serverErrorCode: first.serverErrorCode ?? "UNKNOWN",
                reason: first.reason ?? "No reason provided"
            )
        }

        return response.records.compactMap { $0.toRecord() }
    }

    /// Create a new note. Returns the created CKRecord.
    public func createNote(title: String, text: String, tags: [String] = [], frontMatter: String? = nil) async throws -> CKRecord {
        let noteID = UUID().uuidString
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        // Build the full markdown: optional front matter, then title as H1, then tags, then body
        var markdown = ""
        if let fm = frontMatter, !fm.isEmpty {
            markdown += fm
        }
        markdown += "# \(title)"
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
    public func updateNote(record: CKRecord, newText: String) async throws -> CKRecord {
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        // Extract title from the first H1 line of the new text, or keep existing
        // Skip past front matter block if present
        let lines = newText.components(separatedBy: "\n")
        let contentLines: ArraySlice<String>
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let closeIdx = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            contentLines = lines[(closeIdx + 1)...]
        } else {
            contentLines = lines[lines.startIndex...]
        }

        let title: String
        if let firstLine = contentLines.first, firstLine.hasPrefix("# ") {
            title = String(firstLine.dropFirst(2))
        } else {
            title = record.fields["title"]?.value.stringValue ?? ""
        }

        // Build subtitle from first non-title, non-tag, non-empty content line
        let subtitle = contentLines.dropFirst().first(where: {
            !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) ?? ""

        // Increment vector clock
        let existingClock = record.fields["vectorClock"]?.value.stringValue ?? ""
        let newClock = incrementVectorClock(existingClock)

        // Count TODO items to keep CloudKit metadata accurate
        let todoCompletedCount = newText.components(separatedBy: "- [x]").count - 1
        let todoIncompletedCount = newText.components(separatedBy: "- [ ]").count - 1

        // Preserve existing field values from the record for fields Bear desktop
        // may require to properly process the sync update
        let existingVersion = record.fields["version"]?.value.intValue ?? 3
        let existingUniqueID = record.fields["uniqueIdentifier"]?.value.stringValue
            ?? record.recordName

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
            "todoCompleted": .dictionary([
                "value": .int(Int64(todoCompletedCount)),
                "type": .string("INT64"),
            ]),
            "todoIncompleted": .dictionary([
                "value": .int(Int64(todoIncompletedCount)),
                "type": .string("INT64"),
            ]),
            "version": .dictionary([
                "value": .int(existingVersion),
                "type": .string("INT64"),
            ]),
            "uniqueIdentifier": .dictionary([
                "value": .string(existingUniqueID),
                "type": .string("STRING"),
            ]),
            "text": .dictionary([
                "value": .null,
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
    public func trashNote(record: CKRecord) async throws -> CKRecord {
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

    /// Where to insert the attachment in the note's markdown.
    public enum AttachPosition {
        case append
        case prepend   // after the title line
        case at(Int)   // after line number (0-based)
    }

    /// Attach a file to an existing note. Uploads the asset, creates the image/file record,
    /// and updates the note's markdown and metadata.
    public func attachToNote(
        noteRecord: CKRecord,
        fileData: Data,
        fileName: String,
        contentType: String,
        position: AttachPosition = .append
    ) async throws -> (imageRecord: CKRecord, updatedNote: CKRecord) {
        let imageRecordID = UUID().uuidString
        let noteID = noteRecord.fields["uniqueIdentifier"]?.value.stringValue ?? noteRecord.recordName
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        let isImage = ["jpg", "jpeg", "png", "gif", "webp", "heic", "svg", "avif", "apng"].contains(ext)
        let recordType = isImage ? "SFNoteImage" : "SFNoteGenericFile"

        // Step 1: Upload the binary asset
        let assetValue = try await uploadAsset(
            fileData: fileData,
            fileName: fileName,
            contentType: contentType,
            recordType: recordType,
            recordName: imageRecordID,
            fieldName: "file"
        )

        // Step 2: Build the image/file record
        // Build the file/asset field value — must be {"type": "ASSETID", "value": {...receipt...}}
        let fileFieldValue: [String: AnyCodableValue] = [
            "type": .string("ASSETID"),
            "value": .dictionary(assetValue),
        ]

        var imageFields: [String: AnyCodableValue] = [
            "filenameADP": .dictionary([
                "type": .string("STRING"), "value": .string(fileName), "isEncrypted": .bool(true),
            ]),
            "normalizedFileExtension": .dictionary([
                "type": .string("STRING"), "value": .string(ext),
            ]),
            "fileSize": .dictionary([
                "type": .string("INT64"), "value": .int(Int64(fileData.count)),
            ]),
            "file": .dictionary(fileFieldValue),
            "noteUniqueIdentifier": .dictionary([
                "type": .string("STRING"), "value": .string(noteID),
            ]),
            "index": .dictionary([
                "type": .string("INT64"), "value": .int(0),
            ]),
            "unused": .dictionary([
                "type": .string("INT64"), "value": .int(0),
            ]),
            "uploaded": .dictionary([
                "type": .string("INT64"), "value": .int(1),
            ]),
            "uploadedDate": .dictionary([
                "type": .string("TIMESTAMP"), "value": .int(now),
            ]),
            "insertionDate": .dictionary([
                "type": .string("TIMESTAMP"), "value": .int(now),
            ]),
            "encrypted": .dictionary([
                "type": .string("INT64"), "value": .int(0),
            ]),
            "animated": .dictionary([
                "type": .string("INT64"), "value": .int(ext == "gif" ? 1 : 0),
            ]),
            "version": .dictionary([
                "type": .string("INT64"), "value": .int(3),
            ]),
            "sf_creationDate": .dictionary([
                "type": .string("TIMESTAMP"), "value": .int(now),
            ]),
            "sf_modificationDate": .dictionary([
                "type": .string("TIMESTAMP"), "value": .int(now),
            ]),
            "uniqueIdentifier": .dictionary([
                "type": .string("STRING"), "value": .string(imageRecordID),
            ]),
        ]

        // Add width/height for images if we can detect them
        if isImage, let imageSource = CGImageSourceCreateWithData(fileData as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
           let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
           let height = properties[kCGImagePropertyPixelHeight as String] as? Int {
            imageFields["width"] = .dictionary(["type": .string("INT64"), "value": .int(Int64(width))])
            imageFields["height"] = .dictionary(["type": .string("INT64"), "value": .int(Int64(height))])
        }

        let imageOp: [String: AnyCodableValue] = [
            "operationType": .string("create"),
            "record": .dictionary([
                "recordName": .string(imageRecordID),
                "recordType": .string(recordType),
                "fields": .dictionary(imageFields),
                "pluginFields": .dictionary([:]),
                "recordChangeTag": .null,
                "created": .null,
                "modified": .null,
                "deleted": .bool(false),
            ]),
            "recordType": .string(recordType),
        ]

        // Step 3: Update the note's markdown to embed the file
        var noteText = ""
        if let textADP = noteRecord.fields["textADP"]?.value.stringValue {
            noteText = textADP
        } else if let assetURL = BearNote(from: noteRecord).textAssetURL {
            noteText = try await downloadAsset(url: assetURL)
        }

        let encodedName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
        let embedMarkdown: String
        if isImage {
            embedMarkdown = "![\(fileName)](\(encodedName))<!-- {\"preview\":\"true\",\"embed\":\"true\"} -->"
        } else {
            embedMarkdown = "[\(encodedName)](\(encodedName))<!-- {\"preview\":\"true\",\"embed\":\"true\"} -->"
        }

        let newText: String
        switch position {
        case .append:
            newText = noteText.hasSuffix("\n")
                ? noteText + "\n" + embedMarkdown
                : noteText + "\n\n" + embedMarkdown
        case .prepend:
            // Insert after the first line (title)
            var lines = noteText.components(separatedBy: "\n")
            if lines.count > 1 {
                lines.insert("", at: 1)
                lines.insert(embedMarkdown, at: 2)
            } else {
                lines.append("")
                lines.append(embedMarkdown)
            }
            newText = lines.joined(separator: "\n")
        case .at(let lineNumber):
            var lines = noteText.components(separatedBy: "\n")
            let insertAt = min(lineNumber, lines.count)
            lines.insert(embedMarkdown, at: insertAt)
            lines.insert("", at: insertAt)
            newText = lines.joined(separator: "\n")
        }

        // Build existing files list and add the new one
        var existingFiles: [AnyCodableValue] = []
        if let filesArray = noteRecord.fields["files"]?.value.arrayValue {
            existingFiles = filesArray
        }
        existingFiles.append(.string(imageRecordID))

        let newClock = incrementVectorClock(
            noteRecord.fields["vectorClock"]?.value.stringValue ?? ""
        )

        let title: String
        let lines = newText.components(separatedBy: "\n")
        if let firstLine = lines.first, firstLine.hasPrefix("# ") {
            title = String(firstLine.dropFirst(2))
        } else {
            title = noteRecord.fields["title"]?.value.stringValue ?? ""
        }

        let noteFields: [String: AnyCodableValue] = [
            "textADP": .dictionary([
                "value": .string(newText), "type": .string("STRING"), "isEncrypted": .bool(true),
            ]),
            "title": .dictionary(["value": .string(title), "type": .string("STRING")]),
            "files": .dictionary(["value": .array(existingFiles), "type": .string("STRING_LIST")]),
            "hasImages": .dictionary([
                "value": .int(isImage ? 1 : (noteRecord.fields["hasImages"]?.value.intValue ?? 0)),
                "type": .string("INT64"),
            ]),
            "hasFiles": .dictionary([
                "value": .int(isImage ? (noteRecord.fields["hasFiles"]?.value.intValue ?? 0) : 1),
                "type": .string("INT64"),
            ]),
            "vectorClock": .dictionary(["value": .string(newClock), "type": .string("BYTES")]),
            "sf_modificationDate": .dictionary(["value": .int(now), "type": .string("TIMESTAMP")]),
            "lastEditingDevice": .dictionary(["value": .string("Bear CLI"), "type": .string("STRING")]),
            "text": .dictionary(["value": .null, "type": .string("STRING")]),
        ]

        var noteRecordDict: [String: AnyCodableValue] = [
            "recordName": .string(noteRecord.recordName),
            "recordType": .string("SFNote"),
            "fields": .dictionary(noteFields),
            "pluginFields": .dictionary([:]),
            "recordChangeTag": .string(noteRecord.recordChangeTag ?? ""),
            "deleted": .bool(false),
        ]

        if let created = noteRecord.created {
            var d: [String: AnyCodableValue] = [:]
            if let ts = created.timestamp { d["timestamp"] = .int(ts) }
            if let user = created.userRecordName { d["userRecordName"] = .string(user) }
            noteRecordDict["created"] = .dictionary(d)
        }
        if let modified = noteRecord.modified {
            var d: [String: AnyCodableValue] = [:]
            if let ts = modified.timestamp { d["timestamp"] = .int(ts) }
            if let user = modified.userRecordName { d["userRecordName"] = .string(user) }
            noteRecordDict["modified"] = .dictionary(d)
        }

        let noteOp: [String: AnyCodableValue] = [
            "operationType": .string("update"),
            "record": .dictionary(noteRecordDict),
            "recordType": .string("SFNote"),
        ]

        // Step 4: Send both operations in one records/modify call
        let records = try await modifyRecords(operations: [imageOp, noteOp])

        guard let imageResult = records.first(where: { $0.recordName == imageRecordID }) else {
            throw BearCLIError.networkError("Attach succeeded but image record not in response")
        }
        guard let noteResult = records.first(where: { $0.recordName == noteRecord.recordName }) else {
            throw BearCLIError.networkError("Attach succeeded but note record not in response")
        }

        return (imageResult, noteResult)
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

    /// Create a fresh vector clock for a new record (used only for note creation).
    private func makeVectorClock(device: String, counter: Int) -> String {
        let clock: [String: Int] = [device: counter]
        return VectorClock.encode(clock)
    }

    /// Increment the counter in an existing vector clock, or create a fresh one.
    private func incrementVectorClock(_ base64: String) -> String {
        return VectorClock.increment(base64, device: "Bear CLI")
    }

    // MARK: - Zone Changes (incremental sync)

    public func fetchZoneChanges(syncToken: String?, resultsLimit: Int = 200) async throws -> CKZoneChangeResult {
        var zone: [String: AnyCodableValue] = [
            "zoneID": .dictionary(["zoneName": .string("Notes")]),
            "resultsLimit": .int(Int64(resultsLimit)),
        ]
        if let token = syncToken {
            zone["syncToken"] = .string(token)
        }

        let body: [String: AnyCodableValue] = [
            "zones": .array([.dictionary(zone)]),
        ]

        let response: CKZoneChangesResponse = try await post(path: "changes/zone", body: body)
        guard let result = response.zones.first else {
            throw BearCLIError.networkError("No zone in changes response")
        }
        return result
    }

    // MARK: - Search (client-side title match)

    public func searchNotes(query searchTerm: String, limit: Int = 50) async throws -> [CKRecord] {
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

public enum BearCLIError: Error, CustomStringConvertible {
    case authExpired
    case authNotConfigured
    case apiError(Int, String)
    case networkError(String)
    case invalidURL(String)
    case noteNotFound(String)
    case recordError(recordName: String, serverErrorCode: String, reason: String)

    public var description: String {
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
        case .recordError(let recordName, let code, let reason):
            return "CloudKit record error on \(recordName): \(code) — \(reason)"
        }
    }
}
