import XCTest
@testable import NashiCore

/// Print setup for spreadsheets without their own, checked on worksheet XML.
final class SpreadsheetPrintSetupTests: XCTestCase {
    private func sheet(columns: Int, width: Double = 12, extra: String = "", tail: String = "", rows: Int = 60, pane: String = "") -> XMLElement {
        var data = "<row r=\"1\">" + (1...columns).map { "<c r=\"\(SpreadsheetPrintSetup.letters($0))1\" t=\"inlineStr\" s=\"1\"><is><t>H\($0)</t></is></c>" }.joined() + "</row>"
        for row in 2...rows { data += "<row r=\"\(row)\">" + (1...columns).map { "<c r=\"\(SpreadsheetPrintSetup.letters($0))\(row)\"><v>\($0)</v></c>" }.joined() + "</row>" }
        let views = pane.isEmpty ? "" : "<sheetViews><sheetView workbookViewId=\"0\">\(pane)</sheetView></sheetViews>"
        let xml = "<worksheet xmlns=\"\(SpreadsheetPrintSetup.mainNamespace)\">\(extra)\(views)<cols><col min=\"1\" max=\"\(columns)\" width=\"\(width)\"/></cols><sheetData>\(data)</sheetData><pageMargins left=\"0.7\" right=\"0.7\" top=\"0.75\" bottom=\"0.75\" header=\"0.3\" footer=\"0.3\"/>\(tail)</worksheet>"
        return try! XMLDocument(xmlString: xml, options: []).rootElement()!
    }
    private func element(_ root: XMLElement, _ name: String) -> XMLElement? { SpreadsheetPrintSetup.children(root, name).first }
    private let styles = SpreadsheetPrintSetup.StylesInfo(boldFonts: [1], solidFills: [], formats: [(0, 0), (1, 0)])

    func testWideSheetFitsOnePageWidthInLandscape() {
        let root = sheet(columns: 12)
        let result = SpreadsheetPrintSetup.setUp(root, styles: styles, needsTitles: true)
        XCTAssertTrue(result.changed)
        let setup = element(root, "pageSetup")
        XCTAssertEqual(setup?.attribute(forName: "orientation")?.stringValue, "landscape")
        XCTAssertEqual(setup?.attribute(forName: "fitToWidth")?.stringValue, "1")
        XCTAssertEqual(setup?.attribute(forName: "fitToHeight")?.stringValue, "0")
        XCTAssertEqual(element(element(root, "sheetPr")!, "pageSetUpPr")?.attribute(forName: "fitToPage")?.stringValue, "1")
        XCTAssertEqual(result.titleRow, 1, "A row of bold labels is repeated on every page")
        // SpreadsheetML order: sheetPr first, pageSetup right after pageMargins.
        let names = (root.children ?? []).compactMap(\.name)
        XCTAssertEqual(names.first, "sheetPr")
        XCTAssertEqual(names[names.firstIndex(of: "pageMargins")! + 1], "pageSetup")
    }

    func testNarrowSheetKeepsItsScaleButGetsPageNumbers() {
        let root = sheet(columns: 4)
        _ = SpreadsheetPrintSetup.setUp(root, styles: styles, needsTitles: true)
        XCTAssertNil(element(root, "pageSetup"), "A sheet that fits keeps 100%")
        XCTAssertEqual(element(element(root, "headerFooter")!, "oddFooter")?.stringValue, "&L&8&A&R&8&P / &N")
    }

    func testVeryWideSheetSpansPagesAndRepeatsItsLabelColumn() {
        var root = sheet(columns: 40, width: 10)
        // Label column: text in column A.
        for row in SpreadsheetPrintSetup.children(element(root, "sheetData")!, "row") {
            let first = SpreadsheetPrintSetup.children(row, "c")[0]; first.setChildren([XMLElement(name: "is", stringValue: nil)]); first.addAttribute(XMLNode.attribute(withName: "t", stringValue: "inlineStr") as! XMLNode)
        }
        let result = SpreadsheetPrintSetup.setUp(root, styles: styles, needsTitles: true)
        XCTAssertGreaterThan(Int(element(root, "pageSetup")?.attribute(forName: "fitToWidth")?.stringValue ?? "1") ?? 1, 1, "Text is not shrunk below ~55%")
        XCTAssertTrue(result.titleColumn)
        root = sheet(columns: 2)
        XCTAssertFalse(SpreadsheetPrintSetup.setUp(root, styles: styles, needsTitles: true).titleColumn)
    }

    func testWorkbookSettingsAreKept() {
        let root = sheet(columns: 12, extra: "<sheetPr><pageSetUpPr fitToPage=\"1\"/></sheetPr>",
                         tail: "<pageSetup orientation=\"portrait\" fitToWidth=\"2\" fitToHeight=\"3\"/><headerFooter><oddFooter>&amp;CGizli</oddFooter></headerFooter>")
        _ = SpreadsheetPrintSetup.setUp(root, styles: styles, needsTitles: false)
        XCTAssertEqual(element(root, "pageSetup")?.attribute(forName: "fitToWidth")?.stringValue, "2")
        XCTAssertEqual(element(element(root, "headerFooter")!, "oddFooter")?.stringValue, "&CGizli")
    }

    func testFrozenRowsChooseTheHeaderAndEmptyFootersAreFilled() {
        let root = sheet(columns: 3, tail: "<headerFooter><oddHeader/><oddFooter/></headerFooter>", pane: "<pane ySplit=\"4\" topLeftCell=\"A5\" state=\"frozen\"/>")
        let result = SpreadsheetPrintSetup.setUp(root, styles: nil, needsTitles: true)
        XCTAssertEqual(result.titleRow, 4)
        XCTAssertEqual(element(element(root, "headerFooter")!, "oddFooter")?.stringValue, "&L&8&A&R&8&P / &N")
    }

    func testCSVFirstRowIsTheHeader() {
        let root = sheet(columns: 3)
        XCTAssertNil(SpreadsheetPrintSetup.setUp(root, styles: nil, needsTitles: true).titleRow)
        XCTAssertEqual(SpreadsheetPrintSetup.setUp(sheet(columns: 3), styles: nil, needsTitles: true, firstRowIsHeader: true).titleRow, 1)
    }

    func testColumnLetters() {
        XCTAssertEqual(SpreadsheetPrintSetup.column("A1"), 1)
        XCTAssertEqual(SpreadsheetPrintSetup.column("AB12"), 28)
        XCTAssertEqual(SpreadsheetPrintSetup.letters(28), "AB")
    }
}
