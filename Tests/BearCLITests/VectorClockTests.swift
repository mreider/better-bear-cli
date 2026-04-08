import XCTest
@testable import BearCLICore

final class VectorClockTests: XCTestCase {

    // MARK: - Round-trip encode/decode

    func testEncodeDecodeRoundTrip() {
        let clock: [String: Int] = ["Kevin's MacBook Pro": 42, "Bear CLI": 3]
        let encoded = VectorClock.encode(clock)
        let decoded = VectorClock.decode(encoded)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?["Kevin's MacBook Pro"], 42)
        XCTAssertEqual(decoded?["Bear CLI"], 3)
    }

    func testSingleDeviceRoundTrip() {
        let clock: [String: Int] = ["Bear CLI": 1]
        let encoded = VectorClock.encode(clock)
        let decoded = VectorClock.decode(encoded)

        XCTAssertEqual(decoded, ["Bear CLI": 1])
    }

    // MARK: - Increment preserves all devices

    func testIncrementPreservesExistingDevices() {
        let original: [String: Int] = ["Kevin's MacBook Pro": 10, "Kevin's iPhone": 5]
        let base64 = VectorClock.encode(original)

        let incremented = VectorClock.increment(base64, device: "Bear CLI")
        let result = VectorClock.decode(incremented)

        XCTAssertNotNil(result)
        // Original devices preserved
        XCTAssertEqual(result?["Kevin's MacBook Pro"], 10)
        XCTAssertEqual(result?["Kevin's iPhone"], 5)
        // New device gets max + 1
        XCTAssertEqual(result?["Bear CLI"], 11)
    }

    func testIncrementExistingDevice() {
        let original: [String: Int] = ["Bear CLI": 3, "Kevin's MacBook Pro": 7]
        let base64 = VectorClock.encode(original)

        let incremented = VectorClock.increment(base64, device: "Bear CLI")
        let result = VectorClock.decode(incremented)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?["Kevin's MacBook Pro"], 7)
        // Bear CLI updated to max(3,7) + 1 = 8
        XCTAssertEqual(result?["Bear CLI"], 8)
    }

    // MARK: - Counter values > 255

    func testLargeCounterValues() {
        let original: [String: Int] = ["Kevin's MacBook Pro": 500]
        let base64 = VectorClock.encode(original)

        let incremented = VectorClock.increment(base64, device: "Bear CLI")
        let result = VectorClock.decode(incremented)

        XCTAssertEqual(result?["Kevin's MacBook Pro"], 500)
        XCTAssertEqual(result?["Bear CLI"], 501)
    }

    // MARK: - Invalid input handling

    func testIncrementInvalidBase64() {
        let result = VectorClock.increment("not-valid-base64!!!", device: "Bear CLI")
        let decoded = VectorClock.decode(result)

        // Should create a fresh clock
        XCTAssertEqual(decoded?["Bear CLI"], 1)
    }

    func testIncrementEmptyString() {
        let result = VectorClock.increment("", device: "Bear CLI")
        let decoded = VectorClock.decode(result)

        XCTAssertEqual(decoded?["Bear CLI"], 1)
    }

    func testDecodeInvalidBase64ReturnsNil() {
        XCTAssertNil(VectorClock.decode("not-valid"))
    }

    func testDecodeNonPlistReturnsNil() {
        // Valid base64 but not a plist
        let base64 = Data("hello world".utf8).base64EncodedString()
        XCTAssertNil(VectorClock.decode(base64))
    }

    // MARK: - Many devices

    func testManyDevices() {
        let original: [String: Int] = [
            "Kevin's MacBook Pro": 50,
            "Kevin's iPhone": 30,
            "Kevin's iPad": 20,
            "Bear Web": 5,
        ]
        let base64 = VectorClock.encode(original)

        let incremented = VectorClock.increment(base64, device: "Bear CLI")
        let result = VectorClock.decode(incremented)

        XCTAssertEqual(result?.count, 5)
        XCTAssertEqual(result?["Kevin's MacBook Pro"], 50)
        XCTAssertEqual(result?["Kevin's iPhone"], 30)
        XCTAssertEqual(result?["Kevin's iPad"], 20)
        XCTAssertEqual(result?["Bear Web"], 5)
        XCTAssertEqual(result?["Bear CLI"], 51)
    }
}
