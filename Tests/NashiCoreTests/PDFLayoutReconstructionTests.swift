import XCTest
import AppKit
import PDFKit
@testable import NashiCore

/// PDF → Word layout reconstruction, checked on the intermediate OpenDocument
/// text (no LibreOffice needed): page furniture, rotated stamp text, the
/// artwork layer, columns, lists and font mapping.
final class PDFLayoutReconstructionTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws { root = try OutputFiles.temporaryDirectory() }
    override func tearDownWithError() throws { if let root { try? FileManager.default.removeItem(at: root) } }

    private let size = CGSize(width: 595, height: 842)

    /// Draws pages with a top-left origin, like a document.
    private func pdf(_ name: String, pages: Int, draw: (Int) -> Void) throws -> PDFDocument {
        let url = root.appendingPathComponent(name).appendingPathExtension("pdf")
        var box = CGRect(origin: .zero, size: size)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for page in 0..<pages {
            context.beginPDFPage(nil)
            context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            draw(page)
            NSGraphicsContext.current = nil
            context.endPDFPage()
        }
        context.closePDF()
        return try XCTUnwrap(PDFDocument(url: url))
    }

    private func text(_ string: String, at point: CGPoint, size: CGFloat = 11, color: NSColor = .black, bold: Bool = false) {
        let font = NSFontManager.shared.font(withFamily: "Arial", traits: bold ? .boldFontMask : [], weight: 5, size: size) ?? .systemFont(ofSize: size)
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color]).draw(at: point)
    }

    private func rotated(_ string: String, at point: CGPoint, degrees: CGFloat, size: CGFloat = 14, color: NSColor = .red) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform(); transform.translateX(by: point.x, yBy: point.y); transform.rotate(byDegrees: degrees); transform.concat()
        text(string, at: .zero, size: size, color: color, bold: true)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func reconstruct(_ document: PDFDocument, artwork: Bool = true) throws -> String {
        let output = root.appendingPathComponent(UUID().uuidString).appendingPathExtension("fodt")
        _ = try PDFDocumentReconstruction.document(document, at: output, options: OperationOptions(), token: .init(), artwork: artwork)
        return try String(contentsOf: output, encoding: .utf8)
    }

    private func body(_ xml: String) -> String {
        guard let start = xml.range(of: "<office:text>"), let end = xml.range(of: "</office:text>") else { return "" }
        return String(xml[start.upperBound..<end.lowerBound])
    }

    func testRepeatedHeaderAndFooterBecomeWordFurnitureWithPageFields() throws {
        let document = try pdf("Furniture", pages: 3) { page in
            self.text("ACME Muhasebe Ltd.", at: CGPoint(x: 50, y: 30), bold: true)
            self.text("Yıllık rapor", at: CGPoint(x: 460, y: 30), size: 9)
            self.text("Body paragraph number \(page + 1) of the report.", at: CGPoint(x: 50, y: 120))
            self.text("Sayfa \(page + 1) / 3", at: CGPoint(x: 480, y: 800), size: 8)
        }
        let xml = try reconstruct(document)
        let headerStart = try XCTUnwrap(xml.range(of: "<style:header>")), headerEnd = try XCTUnwrap(xml.range(of: "</style:header>"))
        let header = String(xml[headerStart.upperBound..<headerEnd.lowerBound])
        XCTAssertTrue(header.contains("ACME Muhasebe Ltd."))
        XCTAssertTrue(xml.contains("<text:page-number text:select-page=\"current\">"), "The varying page number becomes a field")
        XCTAssertTrue(xml.contains("<text:page-count>"), "The constant page total becomes a page-count field")
        XCTAssertFalse(body(xml).contains("ACME Muhasebe Ltd."), "Header text is not repeated in the body")
        for page in 1...3 { XCTAssertTrue(body(xml).contains("Body paragraph number \(page) of the report.")) }
        XCTAssertEqual(xml.components(separatedBy: "<style:master-page ").count - 1, 1, "Same-size pages share one page style (one Word section)")
    }

    func testRotatedStampTextStaysInTheArtwork() throws {
        let document = try pdf("Stamp", pages: 1) { _ in
            self.text("Sözleşme metni burada yer alır.", at: CGPoint(x: 50, y: 100))
            self.rotated("ONAYLANDI", at: CGPoint(x: 300, y: 300), degrees: -18)
            self.rotated("TASLAK", at: CGPoint(x: 150, y: 600), degrees: -35, size: 80, color: NSColor(white: 0.5, alpha: 0.2))
            // Seal: characters set one by one around a circle.
            let ring = Array("ALANYA ★ UNQSOFT ★ ")
            for (index, character) in ring.enumerated() {
                let angle = CGFloat(index) / CGFloat(ring.count) * 360
                let x = 420 + cos(angle * .pi / 180) * 50, y = 450 + sin(angle * .pi / 180) * 50
                self.rotated(String(character), at: CGPoint(x: x, y: y), degrees: angle + 90, size: 10)
            }
        }
        let text = body(try reconstruct(document))
        XCTAssertTrue(text.contains("Sözleşme metni burada yer alır."))
        for stray in ["ONAYLANDI", "TASLAK", "UNQSOFT", "ALANYA"] { XCTAssertFalse(text.contains(stray), "\(stray) is stamp/watermark artwork, not body text") }
        XCTAssertTrue(text.contains("Original page artwork"))
    }

    func testArtworkLiftsTextButKeepsAStampDrawnOverIt() throws {
        let document = try pdf("Erase", pages: 1) { _ in
            self.text("ERASED BODY TEXT", at: CGPoint(x: 100, y: 200), size: 24)
            let ring = NSBezierPath(ovalIn: CGRect(x: 150, y: 180, width: 80, height: 80)); ring.lineWidth = 4
            NSColor.red.setStroke(); ring.stroke()
        }
        let xml = try reconstruct(document)
        let start = try XCTUnwrap(xml.range(of: "draw:name=\"Page 1 artwork\""))
        let data = try XCTUnwrap(xml[start.upperBound...].range(of: "<office:binary-data>")).upperBound
        let end = try XCTUnwrap(xml[data...].range(of: "</office:binary-data>")).lowerBound
        let image = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(Data(base64Encoded: String(xml[data..<end])))))
        let scale = CGFloat(image.pixelsWide) / size.width
        var black = 0, red = 0
        for y in stride(from: Int(178 * scale), to: Int(262 * scale), by: 1) {
            for x in stride(from: Int(98 * scale), to: Int(330 * scale), by: 1) {
                guard let c = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if c.redComponent < 0.3 && c.greenComponent < 0.3 && c.blueComponent < 0.3 { black += 1 }
                if c.redComponent > 0.8 && c.greenComponent < 0.3 && c.blueComponent < 0.3 { red += 1 }
            }
        }
        XCTAssertLessThan(black, 40, "Editable text is lifted out of the artwork")
        XCTAssertGreaterThan(red, Int(200 * scale), "The red ring crossing the text survives, including where it overlaps letters")
        XCTAssertTrue(body(xml).contains("ERASED BODY TEXT"))
    }

    func testInterleavedSideBySideBlocksBecomeColumns() throws {
        let document = try pdf("Columns", pages: 1) { _ in
            self.text("Satıcı Firma A.Ş.", at: CGPoint(x: 50, y: 60), size: 14, bold: true)
            self.text("Atatürk Cad. No:12", at: CGPoint(x: 50, y: 82), size: 9)
            self.text("VKN: 1234567890", at: CGPoint(x: 50, y: 97), size: 9)
            self.text("FATURA", at: CGPoint(x: 400, y: 66), size: 18, bold: true)
            self.text("No: A-2026-17", at: CGPoint(x: 400, y: 91), size: 9)
            self.text("Tarih: 30.10.2026", at: CGPoint(x: 400, y: 104), size: 9)
            self.text("Açıklamalar tam genişlikte bir paragraf olarak devam eder.", at: CGPoint(x: 50, y: 160))
        }
        let text = body(try reconstruct(document))
        let layout = try XCTUnwrap(text.range(of: "table:name=\"Layout"), "Side-by-side blocks become one borderless layout row")
        let table = String(text[layout.lowerBound..<(try XCTUnwrap(text[layout.lowerBound...].range(of: "</table:table>")).lowerBound)])
        XCTAssertEqual(table.components(separatedBy: "<table:table-column ").count - 1, 2, "Two columns: seller details and the invoice box")
        for line in ["Satıcı Firma A.Ş.", "Atatürk Cad. No:12", "FATURA", "No: A-2026-17", "Tarih: 30.10.2026"] { XCTAssertTrue(text.contains(line), line) }
        // Each column keeps its own lines together (no interleaving).
        let left = try XCTUnwrap(text.range(of: "Atatürk Cad. No:12")).lowerBound, right = try XCTUnwrap(text.range(of: "No: A-2026-17")).lowerBound
        let vkn = try XCTUnwrap(text.range(of: "VKN: 1234567890")).lowerBound
        XCTAssertTrue(left < vkn && vkn < right, "The left column's lines come before the right column's")
    }

    func testListItemsAndHeadingsStaySeparateParagraphs() throws {
        let document = try pdf("Lists", pages: 1) { _ in
            self.text("Öne çıkan başlıklar:", at: CGPoint(x: 50, y: 80), bold: true)
            self.text("Yeni müşteri sayısı arttı ve hedeflerin üzerine çıktı.", at: CGPoint(x: 50, y: 95))
            self.text("•  Birinci madde", at: CGPoint(x: 62, y: 120))
            self.text("•  İkinci madde", at: CGPoint(x: 62, y: 135))
            self.text("1. Numaralı madde", at: CGPoint(x: 62, y: 160))
            self.text("2. İkinci numaralı madde", at: CGPoint(x: 62, y: 175))
        }
        let paragraphs = body(try reconstruct(document)).components(separatedBy: "<text:p ").filter { $0.contains("<text:span") }
        func paragraph(containing value: String) -> Int? { paragraphs.firstIndex { $0.contains(value) } }
        let heading = try XCTUnwrap(paragraph(containing: "Öne çıkan başlıklar:")), sentence = try XCTUnwrap(paragraph(containing: "Yeni müşteri"))
        XCTAssertNotEqual(heading, sentence, "A bold heading line does not run into the paragraph below it")
        let first = try XCTUnwrap(paragraph(containing: "Birinci madde")), second = try XCTUnwrap(paragraph(containing: "İkinci madde"))
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(try XCTUnwrap(paragraph(containing: "Numaralı madde")), try XCTUnwrap(paragraph(containing: "İkinci numaralı madde")))
    }

    /// Receipt rows: a value wrapping inside its cell beside a vertically
    /// centred label. PDFKit can report both as one line; the digits must
    /// still come out whole, in order, and in one cell.
    func testWrappedCellValuesKeepTheirDigitsInOrder() throws {
        let document = try pdf("Receipt", pages: 1) { _ in
            let shade = NSColor(white: 0.95, alpha: 1)
            for (index, top) in [CGFloat(200), 230, 290].enumerated() where index % 2 == 1 { shade.setFill(); CGRect(x: 58, y: top, width: 476, height: 60).fill() }
            self.text("İŞLEM", at: CGPoint(x: 64, y: 210), size: 8, bold: true)
            self.text("Hesaptan Havale", at: CGPoint(x: 184, y: 210), size: 8)
            self.text("İŞLEM TARİHİ", at: CGPoint(x: 302, y: 210), size: 8, bold: true)
            self.text("30.10.2026 14:12:09", at: CGPoint(x: 422, y: 210), size: 8)
            self.text("ALICI HESAP NO", at: CGPoint(x: 64, y: 255), size: 8, bold: true)
            self.text("TR12 0006 4000 0011 2345", at: CGPoint(x: 184, y: 250), size: 8)
            self.text("6789 01", at: CGPoint(x: 184, y: 260.4), size: 8)
            self.text("ALICI AD SOYAD/UNVAN", at: CGPoint(x: 302, y: 255), size: 8, bold: true)
            for (n, line) in ["ÖRNEK ÜNİVERSİTESİ", "SPOR BİLİMLERİ", "FAKÜLTESİ DÖNER", "SERMAYE", "İŞLETMESİ"].enumerated() {
                self.text(line, at: CGPoint(x: 422, y: 234 + CGFloat(n) * 10.4), size: 8)
            }
            self.text("İŞLEM TUTARI", at: CGPoint(x: 64, y: 300), size: 8, bold: true)
            self.text("150,00 TL", at: CGPoint(x: 184, y: 300), size: 8)
        }
        let body = self.body(try reconstruct(document))
        let text = body.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for value in ["TR12 0006 4000 0011 2345 6789 01", "30.10.2026 14:12:09", "150,00 TL", "ÖRNEK ÜNİVERSİTESİ SPOR BİLİMLERİ FAKÜLTESİ DÖNER SERMAYE İŞLETMESİ"] {
            XCTAssertTrue(text.contains(value), "\(value) must survive whole and in order")
        }
        // The IBAN's two lines share one table cell, broken where the source broke them.
        let cells = body.components(separatedBy: "<table:table-cell").dropFirst()
        let iban = try XCTUnwrap(cells.first { $0.contains("TR12 0006 4000 0011 2345") })
        XCTAssertTrue(iban.contains("6789 01"))
        XCTAssertTrue(iban.contains("<text:line-break/>"))
    }

    func testPrivateSystemFontsMapToAWordFont() {
        XCTAssertEqual(PDFDocumentReconstruction.wordFamily(".SFNS-Regular_wdth_opsz110000"), "Arial")
        XCTAssertEqual(PDFDocumentReconstruction.wordFamily("SF Pro Text"), "Arial")
        XCTAssertEqual(PDFDocumentReconstruction.wordFamily("Calibri"), "Calibri")
        XCTAssertEqual(PDFDocumentReconstruction.wordFamily("Times New Roman"), "Times New Roman")
    }

    func testPagesRouteKeepsAPlainPageWithoutArtwork() throws {
        let document = try pdf("Plain", pages: 1) { _ in
            NSColor(srgbRed: 0.1, green: 0.2, blue: 0.5, alpha: 1).setFill(); CGRect(x: 0, y: 0, width: 595, height: 200).fill()
            self.text("Light heading on a dark band", at: CGPoint(x: 50, y: 80), size: 18, color: .white)
        }
        let xml = try reconstruct(document, artwork: false)
        XCTAssertFalse(xml.contains("Original page artwork"))
        XCTAssertTrue(xml.contains("#202020"), "Without the dark band behind it, white text is darkened to stay readable")
    }

    func testFramedBoxWithShadedBandsBecomesATableWithCellShading() throws {
        let document = try pdf("Receipt", pages: 1) { _ in
            NSColor(white: 0.85, alpha: 1).setStroke()
            let frame = NSBezierPath(rect: CGRect(x: 50, y: 100, width: 495, height: 120)); frame.lineWidth = 1; frame.stroke()
            NSColor(srgbRed: 0.99, green: 0.69, blue: 0, alpha: 1).setFill(); CGRect(x: 54, y: 104, width: 487, height: 22).fill()
            NSColor(white: 0.96, alpha: 1).setFill(); CGRect(x: 54, y: 160, width: 487, height: 26).fill()
            self.text("BANKA", at: CGPoint(x: 270, y: 108), bold: true)
            self.text("İŞLEM", at: CGPoint(x: 60, y: 135), bold: true); self.text("Havale", at: CGPoint(x: 200, y: 135))
            self.text("TUTAR", at: CGPoint(x: 60, y: 166), bold: true); self.text("150,00 TL", at: CGPoint(x: 200, y: 166))
            self.text("NO", at: CGPoint(x: 60, y: 196), bold: true); self.text("2026000012345678", at: CGPoint(x: 200, y: 196))
        }
        let xml = try reconstruct(document)
        let start = try XCTUnwrap(xml.range(of: "<table:table table:name=\"Box")), end = try XCTUnwrap(xml.range(of: "</table:table>", range: start.upperBound..<xml.endIndex))
        let table = String(xml[start.lowerBound..<end.upperBound])
        for value in ["BANKA", "Havale", "150,00 TL", "2026000012345678"] { XCTAssertTrue(table.contains(value), "\(value) sits inside the box table") }
        XCTAssertTrue(xml.contains("fo:background-color=\"#FCB000\"") || xml.contains("fo:background-color=\"#FDB000\""), "The orange band is a cell fill")
        XCTAssertTrue(xml.contains("fo:background-color=\"#F5F5F5\""), "The gray band is a cell fill")
        XCTAssertTrue(xml.contains("fo:border-left=\"") , "The frame is drawn as cell borders")
    }

    func testWordOutputUsesTransitionalSideNames() {
        let strict = "<w:tcMar><w:start w:w=\"0\" w:type=\"dxa\"/><w:end w:w=\"0\" w:type=\"dxa\"/></w:tcMar><w:ind w:hanging=\"0\" w:start=\"200\" w:end=\"0\"/><w:jc w:val=\"end\"/><w:jc w:val=\"start\"/>"
        let fixed = WordCompatibility.transitional(strict)
        XCTAssertEqual(fixed, "<w:tcMar><w:left w:w=\"0\" w:type=\"dxa\"/><w:right w:w=\"0\" w:type=\"dxa\"/></w:tcMar><w:ind w:hanging=\"0\" w:left=\"200\" w:right=\"0\"/><w:jc w:val=\"right\"/><w:jc w:val=\"left\"/>")
    }
}
