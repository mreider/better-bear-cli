import Foundation

/// Bear's vector clock is a binary plist dictionary mapping device names to integer counters.
/// When updating a note, the clock must preserve all existing device entries and add/update
/// the editing device's counter to be greater than all existing values. Failing to preserve
/// entries causes Bear desktop to treat the update as a conflict and silently reject it.
public enum VectorClock {

    /// Decode a base64-encoded binary plist vector clock into a dictionary.
    public static func decode(_ base64: String) -> [String: Int]? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) else { return nil }

        // Bear stores the clock as {String: Int} but PropertyListSerialization
        // may decode values as various NSNumber types.
        guard let raw = plist as? [String: Any] else { return nil }
        var result: [String: Int] = [:]
        for (key, value) in raw {
            if let n = value as? Int {
                result[key] = n
            } else if let n = value as? NSNumber {
                result[key] = n.intValue
            }
        }
        return result
    }

    /// Encode a vector clock dictionary to a base64-encoded binary plist.
    public static func encode(_ clock: [String: Int]) -> String {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: clock, format: .binary, options: 0
        ) else {
            // Fallback: empty clock should never happen, but don't crash
            return ""
        }
        return data.base64EncodedString()
    }

    /// Increment a base64-encoded vector clock for the given device.
    /// Preserves all existing device entries. Sets the device's counter
    /// to max(all existing counters) + 1.
    public static func increment(_ base64: String, device: String) -> String {
        guard let clock = decode(base64) else {
            // Can't parse — create a fresh clock rather than silently corrupting
            return encode([device: 1])
        }

        var updated = clock
        let maxCounter = clock.values.max() ?? 0
        updated[device] = maxCounter + 1
        return encode(updated)
    }
}
