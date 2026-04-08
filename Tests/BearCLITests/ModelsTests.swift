import XCTest
@testable import BearCLICore

final class AnyCodableValueTests: XCTestCase {

    // MARK: - AnyCodableValue accessors

    func testStringValue() {
        let val = AnyCodableValue.string("hello")
        XCTAssertEqual(val.stringValue, "hello")
        XCTAssertNil(val.intValue)
    }

    func testIntValue() {
        let val = AnyCodableValue.int(42)
        XCTAssertEqual(val.intValue, 42)
        XCTAssertNil(val.stringValue)
    }

    func testDoubleFromInt() {
        let val = AnyCodableValue.int(10)
        XCTAssertEqual(val.doubleValue, 10.0)
    }

    func testDoubleValue() {
        let val = AnyCodableValue.double(3.14)
        XCTAssertEqual(val.doubleValue, 3.14)
    }

    func testArrayValue() {
        let val = AnyCodableValue.array([.string("a"), .string("b")])
        XCTAssertEqual(val.arrayValue?.count, 2)
        XCTAssertNil(val.stringValue)
    }

    func testDictValue() {
        let val = AnyCodableValue.dictionary(["key": .int(1)])
        XCTAssertEqual(val.dictValue?["key"]?.intValue, 1)
    }

    func testNullReturnsNil() {
        let val = AnyCodableValue.null
        XCTAssertNil(val.stringValue)
        XCTAssertNil(val.intValue)
        XCTAssertNil(val.doubleValue)
        XCTAssertNil(val.arrayValue)
        XCTAssertNil(val.dictValue)
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let original = AnyCodableValue.dictionary([
            "name": .string("test"),
            "count": .int(5),
            "active": .bool(true),
            "tags": .array([.string("a"), .string("b")]),
            "empty": .null,
        ])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)

        XCTAssertEqual(decoded.dictValue?["name"]?.stringValue, "test")
        XCTAssertEqual(decoded.dictValue?["count"]?.intValue, 5)
        XCTAssertEqual(decoded.dictValue?["tags"]?.arrayValue?.count, 2)
    }
}

final class CKRecordDecodingTests: XCTestCase {

    func testDecodesDeletedRecordWithoutFields() throws {
        let json = """
        {"recordName": "rec-deleted", "deleted": true}
        """.data(using: .utf8)!

        let record = try JSONDecoder().decode(CKRecord.self, from: json)

        XCTAssertEqual(record.recordName, "rec-deleted")
        XCTAssertEqual(record.deleted, true)
        XCTAssertTrue(record.fields.isEmpty)
    }
}

final class BearNoteTests: XCTestCase {

    func testNoteFromRecord() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let record = CKRecord(
            recordName: "rec-123",
            recordType: "SFNote",
            fields: [
                "uniqueIdentifier": CKRecordField(value: .string("uid-abc"), type: "STRING"),
                "title": CKRecordField(value: .string("My Note"), type: "STRING"),
                "tagsStrings": CKRecordField(value: .array([.string("tag1"), .string("tag2")]), type: "STRING_LIST"),
                "pinned": CKRecordField(value: .int(1), type: "INT64"),
                "archived": CKRecordField(value: .int(0), type: "INT64"),
                "trashed": CKRecordField(value: .int(0), type: "INT64"),
                "locked": CKRecordField(value: .int(0), type: "INT64"),
                "todoCompleted": CKRecordField(value: .int(3), type: "INT64"),
                "todoIncompleted": CKRecordField(value: .int(2), type: "INT64"),
                "sf_creationDate": CKRecordField(value: .int(now), type: "TIMESTAMP"),
                "sf_modificationDate": CKRecordField(value: .int(now), type: "TIMESTAMP"),
                "hasFiles": CKRecordField(value: .int(0), type: "INT64"),
            ]
        )

        let note = BearNote(from: record)

        XCTAssertEqual(note.id, "rec-123")
        XCTAssertEqual(note.uniqueIdentifier, "uid-abc")
        XCTAssertEqual(note.title, "My Note")
        XCTAssertEqual(note.tags, ["tag1", "tag2"])
        XCTAssertTrue(note.pinned)
        XCTAssertFalse(note.archived)
        XCTAssertFalse(note.trashed)
        XCTAssertEqual(note.todoCompleted, 3)
        XCTAssertEqual(note.todoIncompleted, 2)
        XCTAssertNotNil(note.creationDate)
        XCTAssertNotNil(note.modificationDate)
        XCTAssertFalse(note.hasFiles)
    }

    func testNoteFromEmptyRecord() {
        let record = CKRecord(recordName: "rec-empty")
        let note = BearNote(from: record)

        XCTAssertEqual(note.uniqueIdentifier, "rec-empty")
        XCTAssertEqual(note.title, "(untitled)")
        XCTAssertEqual(note.tags, [])
        XCTAssertFalse(note.pinned)
        XCTAssertNil(note.creationDate)
    }
}

final class BearTagTests: XCTestCase {

    func testTagFromRecord() {
        let record = CKRecord(
            recordName: "tag-1",
            recordType: "SFNoteTag",
            fields: [
                "title": CKRecordField(value: .string("recipes"), type: "STRING"),
                "notesCount": CKRecordField(value: .int(12), type: "INT64"),
                "pinned": CKRecordField(value: .int(0), type: "INT64"),
                "isRoot": CKRecordField(value: .int(1), type: "INT64"),
            ]
        )

        let tag = BearTag(from: record)

        XCTAssertEqual(tag.id, "tag-1")
        XCTAssertEqual(tag.title, "recipes")
        XCTAssertEqual(tag.notesCount, 12)
        XCTAssertFalse(tag.pinned)
        XCTAssertTrue(tag.isRoot)
    }
}

final class NoteCacheTests: XCTestCase {

    func testIsStaleWhenNoLastSync() {
        let cache = NoteCache()
        XCTAssertTrue(cache.isStale)
    }

    func testIsStaleWhenRecent() {
        let cache = NoteCache(lastSyncDate: Date())
        XCTAssertFalse(cache.isStale)
    }

    func testIsStaleWhenOld() {
        let old = Date().addingTimeInterval(-600) // 10 minutes ago
        let cache = NoteCache(lastSyncDate: old)
        XCTAssertTrue(cache.isStale)
    }

    func testUpsertAndRemove() {
        var cache = NoteCache()
        let record = CKRecord(
            recordName: "note-1",
            fields: [
                "uniqueIdentifier": CKRecordField(value: .string("uid-1"), type: nil),
                "title": CKRecordField(value: .string("Test"), type: nil),
            ]
        )
        let cached = CachedNote(from: record, text: "Hello world")
        cache.upsert(cached)

        XCTAssertEqual(cache.notes.count, 1)
        XCTAssertEqual(cache.notes["note-1"]?.title, "Test")
        XCTAssertEqual(cache.notes["note-1"]?.text, "Hello world")

        cache.remove(recordName: "note-1")
        XCTAssertEqual(cache.notes.count, 0)
    }

    func testMarkTrashed() {
        var cache = NoteCache()
        let record = CKRecord(
            recordName: "note-2",
            fields: [
                "uniqueIdentifier": CKRecordField(value: .string("uid-2"), type: nil),
                "title": CKRecordField(value: .string("To trash"), type: nil),
                "trashed": CKRecordField(value: .int(0), type: nil),
            ]
        )
        let cached = CachedNote(from: record, text: "content")
        cache.upsert(cached)

        XCTAssertFalse(cache.notes["note-2"]!.trashed)

        cache.markTrashed(recordName: "note-2")
        XCTAssertTrue(cache.notes["note-2"]!.trashed)
    }
}

final class SyncStatsTests: XCTestCase {

    func testSummaryEmpty() {
        let stats = SyncStats()
        XCTAssertEqual(stats.summary, "no changes")
        XCTAssertEqual(stats.total, 0)
    }

    func testSummaryWithChanges() {
        var stats = SyncStats()
        stats.added = 3
        stats.updated = 1
        stats.deleted = 2
        XCTAssertEqual(stats.total, 6)
        XCTAssertTrue(stats.summary.contains("3 new"))
        XCTAssertTrue(stats.summary.contains("1 updated"))
        XCTAssertTrue(stats.summary.contains("2 deleted"))
    }
}

final class CKModifyResponseTests: XCTestCase {

    func testSuccessfulResult() throws {
        let json = """
        {
            "records": [{
                "recordName": "note-1",
                "recordType": "SFNote",
                "fields": {
                    "title": {"value": "Test", "type": "STRING"}
                },
                "recordChangeTag": "abc123"
            }]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CKModifyResponse.self, from: json)
        XCTAssertEqual(response.records.count, 1)
        XCTAssertFalse(response.records[0].isError)
        XCTAssertNotNil(response.records[0].toRecord())
        XCTAssertEqual(response.records[0].toRecord()?.recordName, "note-1")
    }

    func testErrorResult() throws {
        let json = """
        {
            "records": [{
                "recordName": "note-1",
                "serverErrorCode": "CONFLICT",
                "reason": "record changed by another device"
            }]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CKModifyResponse.self, from: json)
        XCTAssertEqual(response.records.count, 1)
        XCTAssertTrue(response.records[0].isError)
        XCTAssertEqual(response.records[0].serverErrorCode, "CONFLICT")
        XCTAssertEqual(response.records[0].reason, "record changed by another device")
        XCTAssertNil(response.records[0].toRecord())
    }

    func testMixedResults() throws {
        let json = """
        {
            "records": [
                {
                    "recordName": "note-1",
                    "recordType": "SFNote",
                    "fields": {},
                    "recordChangeTag": "tag1"
                },
                {
                    "recordName": "note-2",
                    "serverErrorCode": "CONFLICT",
                    "reason": "stale change tag"
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CKModifyResponse.self, from: json)
        XCTAssertEqual(response.records.count, 2)

        let successes = response.records.compactMap { $0.toRecord() }
        let errors = response.records.filter { $0.isError }

        XCTAssertEqual(successes.count, 1)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].recordName, "note-2")
    }
}
