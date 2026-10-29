import Foundation

/// Any way people (or autofill) write a number, turned into one E.164 form.
///   "(585) 210-6589", "585.210.6589", "5852106589"    -> "+15852106589"   (US default)
///   "1 585 210 6589", "+1 (585) 210 6589"             -> "+15852106589"
///   "+86 181 7141 5420", "0086 ...", "011 86 ..."     -> "+8618171415420"
/// Must match normalizePhone / isValidPhone in backend/convex/lib/phone.ts.
enum PhoneNumber {
    /// E.164, or nil when it isn't a full number yet.
    static func normalize(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let plus = trimmed.hasPrefix("+") || trimmed.hasPrefix("＋")
        var digits = String(trimmed.unicodeScalars.filter { ("0"..."9").contains($0) }.map(Character.init))
        if !plus {
            if digits.hasPrefix("011") { digits.removeFirst(3) }
            else if digits.hasPrefix("00") { digits.removeFirst(2) }
            else if digits.count == 10 { digits = "1" + digits }
            else if !(digits.count == 11 && digits.hasPrefix("1")) { return nil }
        }
        guard (8...15).contains(digits.count) else { return nil }
        if digits.hasPrefix("1"), digits.count != 11 { return nil }
        return "+" + digits
    }

    /// "+1 (585) 210-6589" for US numbers, "+86 181 7141 5420" style otherwise.
    static func display(_ e164: String) -> String {
        let d = Array(e164.dropFirst())
        if d.count == 11, d.first == "1" {
            return "+1 " + field(e164)
        }
        // Country code lengths vary (1 to 3 digits), so don't guess where it ends
        return e164
    }

    /// What the phone field shows after editing: "(585) 210-6589" for US
    /// numbers (the +1 is implied), the full international form otherwise.
    static func field(_ e164: String) -> String {
        let d = Array(e164.dropFirst())
        if d.count == 11, d.first == "1" {
            return "(\(String(d[1...3]))) \(String(d[4...6]))-\(String(d[7...10]))"
        }
        return display(e164)
    }
}
