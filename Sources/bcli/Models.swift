import Foundation

// MARK: - CloudKit API Request/Response Types

struct CKZoneListResponse: Decodable {
    let zones: [CKZone]
}

struct CKZone: Decodable {
    let zoneID: CKZoneID
    let syncToken: String?
}

struct CKZoneID: Codable {
    let zoneName: String
    let ownerRecordName: String?
}

struct CKRecordQueryRequest: Encodable {
    let zoneID: CKZoneID
    let query: CKQuery
    let resultsLimit: Int?
    let desiredKeys: [String]?

    init(zoneID: CKZoneID, query: CKQuery, resultsLimit: Int? = nil, desiredKeys: [String]? = nil) {
        self.zoneID = zoneID
        self.query = query
        self.resultsLimit = resultsLimit
        self.desiredKeys = desiredKeys
    }
}

struct CKQuery: Encodable {
    let recordType: String
    let filterBy: [CKFilter]?
    let sortBy: [CKSort]?
}

struct CKFilter: Encodable {
    let fieldName: String
    let comparator: String
    let fieldValue: CKFieldValue
}

struct CKSort: Encodable {
    let fieldName: String
    let ascending: Bool
}

struct CKFieldValue: Codable {
    let value: AnyCodableValue
    let type: String?

    init(value: AnyCodableValue, type: String? = nil) {
        self.value = value
        self.type = type
    }
}

struct CKRecordLookupRequest: Encodable {
    let records: [CKRecordRef]
    let zoneID: CKZoneID
    let desiredKeys: [String]?
}

struct CKRecordRef: Encodable {
    let recordName: String
}

struct CKRecordQueryResponse: Decodable {
    let records: [CKRecord]
    let continuationMarker: String?
}

struct CKRecordLookupResponse: Decodable {
    let records: [CKRecord]
}

struct CKRecord: Decodable {
    let recordName: String
    let recordType: String?
    let fields: [String: CKRecordField]
    let recordChangeTag: String?
    let created: CKTimestamp?
    let modified: CKTimestamp?
    let deleted: Bool?
}

// MARK: - CloudKit Zone Changes (for incremental sync)

struct CKZoneChangesResponse: Decodable {
    let zones: [CKZoneChangeResult]
}

struct CKZoneChangeResult: Decodable {
    let zoneID: CKZoneID
    let moreComing: Bool
    let syncToken: String
    let records: [CKRecord]
}

struct CKTimestamp: Decodable {
    let timestamp: Int64?
    let userRecordName: String?
}

struct CKRecordField: Decodable {
    let value: AnyCodableValue
    let type: String?
}

// MARK: - Flexible JSON Value Type

enum AnyCodableValue: Codable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Int64.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([AnyCodableValue].self) { self = .array(v); return }
        if let v = try? container.decode([String: AnyCodableValue].self) { self = .dictionary(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var intValue: Int64? {
        if case .int(let v) = self { return v }
        return nil
    }

    var doubleValue: Double? {
        if case .double(let v) = self { return v }
        if case .int(let v) = self { return Double(v) }
        return nil
    }

    var arrayValue: [AnyCodableValue]? {
        if case .array(let v) = self { return v }
        return nil
    }

    var dictValue: [String: AnyCodableValue]? {
        if case .dictionary(let v) = self { return v }
        return nil
    }
}

// MARK: - Bear Domain Models

struct BearNote {
    let id: String
    let uniqueIdentifier: String
    let title: String
    let tags: [String]
    let pinned: Bool
    let archived: Bool
    let trashed: Bool
    let locked: Bool
    let todoCompleted: Int
    let todoIncompleted: Int
    let creationDate: Date?
    let modificationDate: Date?
    let textAssetURL: String?
    let hasFiles: Bool

    init(from record: CKRecord) {
        self.id = record.recordName
        self.uniqueIdentifier = record.fields["uniqueIdentifier"]?.value.stringValue ?? record.recordName
        self.title = record.fields["title"]?.value.stringValue ?? "(untitled)"

        if let tagsArray = record.fields["tagsStrings"]?.value.arrayValue {
            self.tags = tagsArray.compactMap { $0.stringValue }
        } else {
            self.tags = []
        }

        self.pinned = record.fields["pinned"]?.value.intValue == 1
        self.archived = record.fields["archived"]?.value.intValue == 1
        self.trashed = record.fields["trashed"]?.value.intValue == 1
        self.locked = record.fields["locked"]?.value.intValue == 1
        self.todoCompleted = Int(record.fields["todoCompleted"]?.value.intValue ?? 0)
        self.todoIncompleted = Int(record.fields["todoIncompleted"]?.value.intValue ?? 0)

        if let ts = record.fields["sf_creationDate"]?.value.intValue {
            self.creationDate = Date(timeIntervalSince1970: Double(ts) / 1000.0)
        } else {
            self.creationDate = nil
        }

        if let ts = record.fields["sf_modificationDate"]?.value.intValue {
            self.modificationDate = Date(timeIntervalSince1970: Double(ts) / 1000.0)
        } else {
            self.modificationDate = nil
        }

        // Extract asset download URL from the text field
        if let textDict = record.fields["text"]?.value.dictValue,
           let url = textDict["downloadURL"]?.stringValue {
            self.textAssetURL = url
        } else {
            self.textAssetURL = nil
        }

        self.hasFiles = record.fields["hasFiles"]?.value.intValue == 1
    }
}

struct BearTag {
    let id: String
    let title: String
    let notesCount: Int
    let pinned: Bool
    let isRoot: Bool

    init(from record: CKRecord) {
        self.id = record.recordName
        self.title = record.fields["title"]?.value.stringValue ?? "(unknown)"
        self.notesCount = Int(record.fields["notesCount"]?.value.intValue ?? 0)
        self.pinned = record.fields["pinned"]?.value.intValue == 1
        self.isRoot = record.fields["isRoot"]?.value.intValue == 1
    }
}

// MARK: - Auth Config

struct AuthConfig: Codable {
    var ckWebAuthToken: String
    let ckAPIToken: String
    var savedAt: Date

    static let apiToken = "ce59f955ec47e744f720aa1d2816a4e985e472d8b859b6c7a47b81fd36646307"

    static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("bear-cli")
    }

    static var configFile: URL {
        configDir.appendingPathComponent("auth.json")
    }

    static func load() throws -> AuthConfig {
        let data = try Data(contentsOf: configFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AuthConfig.self, from: data)
    }

    func save() throws {
        let dir = AuthConfig.configDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: AuthConfig.configFile)
        // Restrict permissions to owner only
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: AuthConfig.configFile.path
        )
    }
}
