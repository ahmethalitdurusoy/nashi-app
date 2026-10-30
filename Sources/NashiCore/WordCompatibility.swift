import Foundation

/// LibreOffice writes WordprocessingML with the ISO "strict" spellings for
/// sides and alignment (`w:start`/`w:end`, `<w:jc w:val="start"/>`). Word
/// reads both, but Google Docs and older Word builds only know the
/// transitional `left`/`right`: cell margins then fall back to their defaults
/// (narrowing every cell), indents vanish and right-aligned amounts drift
/// left. Rewriting to the transitional spellings keeps the layout identical
/// in Word and makes it hold elsewhere.
enum WordCompatibility {
    static func normalise(_ docx: URL, token: CancellationToken) throws {
        let fm = FileManager.default
        let package = fm.temporaryDirectory.appendingPathComponent("UForge-docx-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: package) }
        try ArchiveCodec.extract(docx, into: package, token: token)
        let word = package.appendingPathComponent("word", isDirectory: true)
        let parts = (try? fm.contentsOfDirectory(at: word, includingPropertiesForKeys: nil)) ?? []
        var changed = false
        for part in parts where part.pathExtension == "xml" {
            try token.check()
            let original = try String(contentsOf: part, encoding: .utf8)
            let rewritten = transitional(original)
            if rewritten != original { try rewritten.write(to: part, atomically: true, encoding: .utf8); changed = true }
        }
        guard changed else { return }
        let rebuilt = docx.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).docx")
        try ArchiveCodec.create(from: package, at: rebuilt, format: "zip", token: token)
        _ = try fm.replaceItemAt(docx, withItemAt: rebuilt)
    }

    static func transitional(_ xml: String) -> String {
        var text = xml
        // Side elements of margins and borders: <w:start …/> / <w:end …/>.
        text = text.replacingOccurrences(of: "<w:start ", with: "<w:left ").replacingOccurrences(of: "<w:end ", with: "<w:right ")
        text = text.replacingOccurrences(of: "<w:start/>", with: "<w:left/>").replacingOccurrences(of: "<w:end/>", with: "<w:right/>")
        // Indent attributes on <w:ind …>.
        text = text.replacingOccurrences(of: "(<w:ind\\b[^>]*?) w:start=", with: "$1 w:left=", options: .regularExpression)
        text = text.replacingOccurrences(of: "(<w:ind\\b[^>]*?) w:end=", with: "$1 w:right=", options: .regularExpression)
        // Paragraph and table alignment.
        text = text.replacingOccurrences(of: "<w:jc w:val=\"start\"/>", with: "<w:jc w:val=\"left\"/>").replacingOccurrences(of: "<w:jc w:val=\"end\"/>", with: "<w:jc w:val=\"right\"/>")
        return text
    }
}
