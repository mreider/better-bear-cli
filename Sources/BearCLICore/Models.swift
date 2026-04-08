import Foundation

// MARK: - CloudKit API Request/Response Types

public struct CKZoneListResponse: Decodable {
    public let zones: [CKZone]
}

public struct CKZone: Decodable {
    public let zoneID: CKZoneID
    public let syncToken: String?
}

public struct CKZoneID: Codable {
    public let zoneName: String
    public let ownerRecordName: String?

    public init(zoneName: String, ownerRecordName: String? = nil) {
        self.zoneName = zoneName
        self.ownerRecordName = ownerRecordName
    }
}

public struct CKRecordQueryRequest: Encodable {
    public let zoneID: CKZoneID
    public let query: CKQuery
    public let resultsLimit: Int?
    public let desiredKeys: [String]?

    public init(zoneID: CKZoneID, query: CKQuery, resultsLimit: Int? = nil, desiredKeys: [String]? = nil) {
        self.zoneID = zoneID
        self.query = query
        self.resultsLimit = resultsLimit
        self.desiredKeys = desiredKeys
    }
}

public struct CKQuery: Encodable {
    public let recordType: String
    public let filterBy: [CKFilter]?
    public let sortBy: [CKSort]?

    public init(recordType: String, filterBy: [CKFilter]? = nil, sortBy: [CKSort]? = nil) {
        self.recordType = recordType
        self.filterBy = filterBy
        self.sortBy = sortBy
    }
}

public struct CKFilter: Encodable {
    public let fieldName: String
    public let comparator: String
    public let fieldValue: CKFieldValue

    public init(fieldName: String, comparator: String, fieldValue: CKFieldValue) {
        self.fieldName = fieldName
        self.comparator = comparator
        self.fieldValue = fieldValue
    }
}

public struct CKSort: Encodable {
    public let fieldName: String
    public let ascending: Bool

    public init(fieldName: String, ascending: Bool) {
        self.fieldName = fieldName
        self.ascending = ascending
    }
}

public struct CKFieldValue: Codable {
    public let value: AnyCodableValue
    public let type: String?

    public init(value: AnyCodableValue, type: String? = nil) {
        self.value = value
        self.type = type
    }
}

public struct CKRecordLookupRequest: Encodable {
    public let records: [CKRecordRef]
    public let zoneID: CKZoneID
    public let desiredKeys: [String]?
}

public struct CKRecordRef: Encodable {
    public let recordName: String

    public init(recordName: String) {
        self.recordName = recordName
    }
}

public struct CKRecordQueryResponse: Decodable {
    public let records: [CKRecord]
    public let continuationMarker: String?
}

public struct CKRecordLookupResponse: Decodable {
    public let records: [CKRecord]
}

/// Response from CloudKit /records/modify endpoint.
/// Each record entry may be a success (with fields) or a per-record error
/// (with serverErrorCode and reason). We parse both.
public struct CKModifyResponse: Decodable {
    public let records: [CKModifyRecordResult]
}

public struct CKModifyRecordResult: Decodable {
    public let recordName: String
    public let recordType: String?
    public let fields: [String: CKRecordField]?
    public let recordChangeTag: String?
    public let created: CKTimestamp?
    public let modified: CKTimestamp?
    public let deleted: Bool?
    // Per-record error fields returned by CloudKit on conflict/failure
    public let serverErrorCode: String?
    public let reason: String?

    public var isError: Bool {
        serverErrorCode != nil
    }

    /// Convert a successful result into a CKRecord.
    public func toRecord() -> CKRecord? {
        guard !isError else { return nil }
        return CKRecord(
            recordName: recordName,
            recordType: recordType,
            fields: fields ?? [:],
            recordChangeTag: recordChangeTag,
            created: created,
            modified: modified,
            deleted: deleted
        )
    }
}

public struct CKRecord: Decodable {
    public let recordName: String
    public let recordType: String?
    public let fields: [String: CKRecordField]
    public let recordChangeTag: String?
    public let created: CKTimestamp?
    public let modified: CKTimestamp?
    public let deleted: Bool?

    public init(
        recordName: String,
        recordType: String? = nil,
        fields: [String: CKRecordField] = [:],
        recordChangeTag: String? = nil,
        created: CKTimestamp? = nil,
        modified: CKTimestamp? = nil,
        deleted: Bool? = nil
    ) {
        self.recordName = recordName
        self.recordType = recordType
        self.fields = fields
        self.recordChangeTag = recordChangeTag
        self.created = created
        self.modified = modified
        self.deleted = deleted
    }
}

// MARK: - CloudKit Zone Changes (for incremental sync)

public struct CKZoneChangesResponse: Decodable {
    public let zones: [CKZoneChangeResult]
}

public struct CKZoneChangeResult: Decodable {
    public let zoneID: CKZoneID
    public let moreComing: Bool
    public let syncToken: String
    public let records: [CKRecord]
}

public struct CKTimestamp: Decodable {
    public let timestamp: Int64?
    public let userRecordName: String?

    public init(timestamp: Int64? = nil, userRecordName: String? = nil) {
        self.timestamp = timestamp
        self.userRecordName = userRecordName
    }
}

public struct CKRecordField: Decodable {
    public let value: AnyCodableValue
    public let type: String?

    public init(value: AnyCodableValue, type: String? = nil) {
        self.value = value
        self.type = type
    }
}

// MARK: - Flexible JSON Value Type

public enum AnyCodableValue: Codable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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

    public var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    public var intValue: Int64? {
        if case .int(let v) = self { return v }
        return nil
    }

    public var doubleValue: Double? {
        if case .double(let v) = self { return v }
        if case .int(let v) = self { return Double(v) }
        return nil
    }

    public var arrayValue: [AnyCodableValue]? {
        if case .array(let v) = self { return v }
        return nil
    }

    public var dictValue: [String: AnyCodableValue]? {
        if case .dictionary(let v) = self { return v }
        return nil
    }
}

// MARK: - Bear Domain Models

public struct BearNote {
    public let id: String
    public let uniqueIdentifier: String
    public let title: String
    public let tags: [String]
    public let pinned: Bool
    public let archived: Bool
    public let trashed: Bool
    public let locked: Bool
    public let todoCompleted: Int
    public let todoIncompleted: Int
    public let creationDate: Date?
    public let modificationDate: Date?
    public let textAssetURL: String?
    public let hasFiles: Bool

    public init(from record: CKRecord) {
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

        if let textDict = record.fields["text"]?.value.dictValue,
           let url = textDict["downloadURL"]?.stringValue {
            self.textAssetURL = url
        } else {
            self.textAssetURL = nil
        }

        self.hasFiles = record.fields["hasFiles"]?.value.intValue == 1
    }
}

public struct BearTag {
    public let id: String
    public let title: String
    public let notesCount: Int
    public let pinned: Bool
    public let isRoot: Bool

    public init(from record: CKRecord) {
        self.id = record.recordName
        self.title = record.fields["title"]?.value.stringValue ?? "(unknown)"
        self.notesCount = Int(record.fields["notesCount"]?.value.intValue ?? 0)
        self.pinned = record.fields["pinned"]?.value.intValue == 1
        self.isRoot = record.fields["isRoot"]?.value.intValue == 1
    }
}

// MARK: - Auth Config

public struct AuthConfig: Codable {
    public var ckWebAuthToken: String
    public let ckAPIToken: String
    public var savedAt: Date

    public static let apiToken = "ce59f955ec47e744f720aa1d2816a4e985e472d8b859b6c7a47b81fd36646307"

    public static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("bear-cli")
    }

    public static var configFile: URL {
        configDir.appendingPathComponent("auth.json")
    }

    public init(ckWebAuthToken: String, ckAPIToken: String, savedAt: Date) {
        self.ckWebAuthToken = ckWebAuthToken
        self.ckAPIToken = ckAPIToken
        self.savedAt = savedAt
    }

    public static func load() throws -> AuthConfig {
        let data = try Data(contentsOf: configFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AuthConfig.self, from: data)
    }

    public func save() throws {
        let dir = AuthConfig.configDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: AuthConfig.configFile)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: AuthConfig.configFile.path
        )
    }
}
