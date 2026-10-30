import Foundation

/// Most workbooks are never set up for printing: their PDF then splits wide
/// tables down the middle (rows on one set of pages, the remaining columns on
/// another), prints the header row only on page one and has no page numbers.
/// Before a spreadsheet becomes a PDF, every visible sheet without its own
/// print setup gets what a person would choose in Excel's Page Setup:
///
/// - all columns on one page width (landscape when that prints larger);
/// - the header row repeated on every page — the frozen top row, or else the
///   first row styled as a header (bold or shaded labels);
/// - a footer with the sheet name and the page number.
///
/// Anything the workbook sets itself — scaling, orientation, print titles,
/// headers and footers — is left exactly as it is.
enum SpreadsheetPrintSetup {
    static let mainNamespace = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    static let relationshipNamespace = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    /// An .xlsx copy of `source` (converted first when it is not one) with the
    /// print setup applied, in `folder`, keeping the source's base name.
    static func prepare(_ source: URL, in folder: URL, token: CancellationToken) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = source.pathExtension.lowercased()
        let workbook: URL
        if ext == "xlsx" || ext == "xlsm" {
            workbook = folder.appendingPathComponent(source.deletingPathExtension().lastPathComponent).appendingPathExtension("xlsx")
            try fm.copyItem(at: source, to: workbook)
        } else {
            workbook = try DocumentEngine.office(source, to: "xlsx", in: folder, token: token)
        }
        let package = folder.appendingPathComponent(".package-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: package) }
        try ArchiveCodec.extract(workbook, into: package, token: token)
        // CSV and TSV have no styling to recognise a header by: their first
        // row is the header.
        guard try apply(package, firstRowIsHeader: ["csv", "tsv"].contains(ext), token: token) else { return workbook }
        let rebuilt = folder.appendingPathComponent(".\(UUID().uuidString).xlsx")
        try ArchiveCodec.create(from: package, at: rebuilt, format: "zip", token: token)
        _ = try fm.replaceItemAt(workbook, withItemAt: rebuilt)
        return workbook
    }

    /// Applies the setup to an extracted workbook package; true when anything changed.
    static func apply(_ package: URL, firstRowIsHeader: Bool = false, token: CancellationToken) throws -> Bool {
        let bookURL = package.appendingPathComponent("xl/workbook.xml")
        guard let book = try? XMLDocument(contentsOf: bookURL, options: [.nodePreserveWhitespace]), let bookRoot = book.rootElement() else { return false }
        let targets = relationships(package.appendingPathComponent("xl/_rels/workbook.xml.rels"))
        let sheets = children(bookRoot, "sheets").first.map { children($0, "sheet") } ?? []
        let names = children(bookRoot, "definedNames").first.map { children($0, "definedName") } ?? []
        var changed = false, titles: [(index: Int, name: String, row: Int?, column: Bool)] = []
        for (index, sheet) in sheets.enumerated() {
            try token.check()
            guard sheet.attribute(forName: "state")?.stringValue.map({ $0 == "hidden" || $0 == "veryHidden" }) != true,
                  let id = sheet.attributes?.first(where: { $0.localName == "id" })?.stringValue, let target = targets[id] else { continue }
            let url = package.appendingPathComponent("xl").appendingPathComponent(target.hasPrefix("/xl/") ? String(target.dropFirst(4)) : target)
            guard let document = try? XMLDocument(contentsOf: url, options: [.nodePreserveWhitespace]), let root = document.rootElement() else { continue }
            let hasTitles = names.contains { $0.attribute(forName: "name")?.stringValue == "_xlnm.Print_Titles" && $0.attribute(forName: "localSheetId")?.stringValue == "\(index)" }
            let styles = try? stylesInfo(package)
            let result = setUp(root, styles: styles, needsTitles: !hasTitles, firstRowIsHeader: firstRowIsHeader)
            if result.changed {
                try document.xmlData(options: [.nodeCompactEmptyElement]).write(to: url, options: .atomic)
                changed = true
            }
            if result.titleRow != nil || result.titleColumn, let name = sheet.attribute(forName: "name")?.stringValue { titles.append((index, name, result.titleRow, result.titleColumn)) }
        }
        if !titles.isEmpty {
            let definedNames: XMLElement
            if let existing = children(bookRoot, "definedNames").first { definedNames = existing } else {
                definedNames = XMLElement(name: "definedNames")
                insert(definedNames, into: bookRoot, order: ["fileVersion", "fileSharing", "workbookPr", "workbookProtection", "bookViews", "sheets", "functionGroups", "externalReferences", "definedNames"])
            }
            for title in titles {
                let sheet = "'\(title.name.replacingOccurrences(of: "'", with: "''"))'!"
                let parts = (title.column ? [sheet + "$A:$A"] : []) + (title.row.map { [sheet + "$\($0):$\($0)"] } ?? [])
                let element = XMLElement(name: "definedName", stringValue: parts.joined(separator: ","))
                element.addAttribute(XMLNode.attribute(withName: "name", stringValue: "_xlnm.Print_Titles") as! XMLNode)
                element.addAttribute(XMLNode.attribute(withName: "localSheetId", stringValue: "\(title.index)") as! XMLNode)
                definedNames.addChild(element)
            }
            try book.xmlData(options: [.nodeCompactEmptyElement]).write(to: bookURL, options: .atomic)
            changed = true
        }
        return changed
    }

    /// The order SpreadsheetML requires for the worksheet's own elements.
    static let worksheetOrder = ["sheetPr", "dimension", "sheetViews", "sheetFormatPr", "cols", "sheetData", "sheetCalcPr", "sheetProtection", "protectedRanges", "scenarios", "autoFilter", "sortState", "dataConsolidate", "customSheetViews", "mergeCells", "phoneticPr", "conditionalFormatting", "dataValidations", "hyperlinks", "printOptions", "pageMargins", "pageSetup", "headerFooter"]

    /// Sets up one worksheet. Returns whether it changed and the row to
    /// repeat at the top of each page (nil when none or already defined).
    static func setUp(_ root: XMLElement, styles: StylesInfo?, needsTitles: Bool, firstRowIsHeader: Bool = false) -> (changed: Bool, titleRow: Int?, titleColumn: Bool) {
        var changed = false
        let sheetPr = children(root, "sheetPr").first
        let fitFlag = sheetPr.flatMap { children($0, "pageSetUpPr").first }?.attribute(forName: "fitToPage")?.stringValue
        let pageSetup = children(root, "pageSetup").first
        let explicitScale = pageSetup?.attribute(forName: "scale")?.stringValue.flatMap(Int.init).map { $0 != 100 } ?? false
        let userScaling = fitFlag == "1" || fitFlag == "true" || explicitScale
        // Portrait is the default (LibreOffice and older Excel files always
        // write it), so only landscape counts as a choice.
        let userOrientation = pageSetup?.attribute(forName: "orientation")?.stringValue == "landscape" ? "landscape" : nil

        // Page and printable width.
        let paper = pageSetup?.attribute(forName: "paperSize")?.stringValue.flatMap(Int.init) ?? 9
        let size: (CGFloat, CGFloat) = paper == 1 ? (612, 792) : paper == 5 ? (612, 1008) : paper == 8 ? (842, 1191) : (595, 842)
        let margins = children(root, "pageMargins").first
        func inches(_ name: String, _ fallback: CGFloat) -> CGFloat { margins?.attribute(forName: name)?.stringValue.flatMap(Double.init).map { CGFloat($0) } ?? fallback }
        let sideMargins = (inches("left", 0.7) + inches("right", 0.7)) * 72
        let portrait = size.0 - sideMargins, landscape = size.1 - sideMargins
        var titleColumn = false
        let width = contentWidth(root)

        if !userScaling, width > portrait + 1 {
            let orientation = userOrientation ?? (width > portrait ? "landscape" : "portrait")
            let setup = pageSetup ?? {
                let element = XMLElement(name: "pageSetup"); insert(element, into: root, order: worksheetOrder); return element
            }()
            setAttribute(setup, "orientation", orientation)
            // One page width, unless that shrinks the text below ~55%: a very
            // wide sheet then spans a few page widths, each repeating its
            // first (label) column.
            let printable = orientation == "landscape" ? landscape : portrait
            var across = 1
            if width * 0.55 > printable { across = Int((width * 0.65 / printable).rounded(.up)); titleColumn = needsTitles && labelColumn(root) }
            setAttribute(setup, "fitToWidth", "\(across)")
            setAttribute(setup, "fitToHeight", "0")
            if setup.attribute(forName: "paperSize") == nil { setAttribute(setup, "paperSize", "\(paper)") }
            let properties = sheetPr ?? {
                let element = XMLElement(name: "sheetPr"); insert(element, into: root, order: worksheetOrder); return element
            }()
            let fit = children(properties, "pageSetUpPr").first ?? {
                let element = XMLElement(name: "pageSetUpPr")
                // pageSetUpPr follows tabColor and outlinePr inside sheetPr.
                insert(element, into: properties, order: ["tabColor", "outlinePr", "pageSetUpPr"]); return element
            }()
            setAttribute(fit, "fitToPage", "1")
            changed = true
        }

        // A header or footer with any text is the workbook's own; empty ones
        // (LibreOffice writes them for every sheet) count as none.
        let existing = children(root, "headerFooter").first
        let hasText = (existing?.children ?? []).contains { !($0.stringValue ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        if !hasText {
            let footer = existing ?? { let element = XMLElement(name: "headerFooter"); insert(element, into: root, order: worksheetOrder); return element }()
            for child in children(footer, "oddFooter") { child.detach() }
            insert(XMLElement(name: "oddFooter", stringValue: "&L&8&A&R&8&P / &N"), into: footer, order: ["oddHeader", "oddFooter"])
            changed = true
        }

        var titleRow: Int?
        if needsTitles, let row = headerRow(root, styles: styles) ?? (firstRowIsHeader && (children(root, "sheetData").first.map { children($0, "row") }?.count ?? 0) > 3 ? 1 : nil) { titleRow = row }
        return (changed || titleRow != nil || titleColumn, titleRow, titleColumn)
    }

    // MARK: Measuring

    /// Printed width of the used columns, in points.
    static func contentWidth(_ root: XMLElement) -> CGFloat {
        let format = children(root, "sheetFormatPr").first
        let base = format?.attribute(forName: "defaultColWidth")?.stringValue.flatMap(Double.init)
            ?? (format?.attribute(forName: "baseColWidth")?.stringValue.flatMap(Double.init).map { $0 + 0.43 }) ?? 8.43
        var widths: [Int: (width: Double, hidden: Bool)] = [:]
        for col in children(root, "cols").first.map({ children($0, "col") }) ?? [] {
            guard let min = col.attribute(forName: "min")?.stringValue.flatMap(Int.init), let max = col.attribute(forName: "max")?.stringValue.flatMap(Int.init), min <= max, max - min < 20_000 else { continue }
            let width = col.attribute(forName: "width")?.stringValue.flatMap(Double.init) ?? base
            let hidden = col.attribute(forName: "hidden")?.stringValue.map { $0 == "1" || $0 == "true" } ?? false
            for index in min...max { widths[index] = (width, hidden) }
        }
        let last = usedColumns(root)
        guard last > 0 else { return 0 }
        var points: CGFloat = 0
        for index in 1...last {
            let column = widths[index] ?? (base, false)
            if column.hidden { continue }
            // Excel's column width is in characters of the default font
            // (7 px each at 100%, plus 5 px of padding); 1 px = 0.75 pt.
            points += CGFloat(column.width * 7 + 5) * 0.75
        }
        return points
    }

    /// The last column with a value or a style in the sheet's data.
    static func usedColumns(_ root: XMLElement) -> Int {
        var last = 0
        for row in children(root, "sheetData").first.map({ children($0, "row") }) ?? [] {
            for cell in children(row, "c") {
                guard let reference = cell.attribute(forName: "r")?.stringValue else { continue }
                let hasValue = !(cell.children ?? []).isEmpty
                guard hasValue || cell.attribute(forName: "s") != nil else { continue }
                last = max(last, column(reference))
            }
        }
        // Charts and pictures anchored to the right of the data count too.
        return last
    }

    static func column(_ reference: String) -> Int {
        var value = 0
        for character in reference.uppercased() {
            guard let ascii = character.asciiValue, (65...90).contains(ascii) else { break }
            value = value * 26 + Int(ascii - 64)
        }
        return value
    }

    /// Whether the first column holds text labels (product names, regions…).
    static func labelColumn(_ root: XMLElement) -> Bool {
        let rows = children(root, "sheetData").first.map { children($0, "row") } ?? []
        let first = rows.compactMap { row in children(row, "c").first { column($0.attribute(forName: "r")?.stringValue ?? "") == 1 } }.filter { !($0.children ?? []).isEmpty }
        let text = first.filter { $0.attribute(forName: "t")?.stringValue.map { ["s", "inlineStr", "str"].contains($0) } ?? false }
        return first.count >= 3 && text.count * 10 >= first.count * 8
    }

    static func letters(_ column: Int) -> String {
        var value = column, text = ""
        while value > 0 { let remainder = (value - 1) % 26; text = String(UnicodeScalar(UInt8(65 + remainder))) + text; value = (value - 1) / 26 }
        return text
    }

    // MARK: Header row

    /// The row to repeat on every page: the last frozen row, or else the first
    /// row of two or more labels that are all bold or shaded, with data below.
    static func headerRow(_ root: XMLElement, styles: StylesInfo?) -> Int? {
        if let pane = children(root, "sheetViews").first.flatMap({ children($0, "sheetView").first }).flatMap({ children($0, "pane").first }),
           ["frozen", "frozenSplit"].contains(pane.attribute(forName: "state")?.stringValue ?? ""),
           let split = pane.attribute(forName: "ySplit")?.stringValue.flatMap(Double.init), split >= 1 {
            return Int(split)
        }
        guard let styles else { return nil }
        let rows = children(root, "sheetData").first.map { children($0, "row") } ?? []
        for (position, row) in rows.prefix(12).enumerated() {
            let cells = children(row, "c").filter { !($0.children ?? []).isEmpty }
            guard cells.count >= 2,
                  cells.allSatisfy({ $0.attribute(forName: "t")?.stringValue.map { ["s", "inlineStr", "str"].contains($0) } ?? false }),
                  cells.allSatisfy({ styles.emphasised($0.attribute(forName: "s")?.stringValue.flatMap(Int.init) ?? 0) }),
                  rows.count - position > 3,
                  let number = row.attribute(forName: "r")?.stringValue.flatMap(Int.init) else { continue }
            return number
        }
        return nil
    }

    struct StylesInfo {
        var boldFonts: Set<Int>
        var solidFills: Set<Int>
        var formats: [(font: Int, fill: Int)]
        func emphasised(_ index: Int) -> Bool {
            guard formats.indices.contains(index) else { return false }
            return boldFonts.contains(formats[index].font) || solidFills.contains(formats[index].fill)
        }
    }

    static func stylesInfo(_ package: URL) throws -> StylesInfo? {
        guard let document = try? XMLDocument(contentsOf: package.appendingPathComponent("xl/styles.xml"), options: []), let root = document.rootElement() else { return nil }
        let fonts = children(root, "fonts").first.map { children($0, "font") } ?? []
        let fills = children(root, "fills").first.map { children($0, "fill") } ?? []
        let bold = Set(fonts.enumerated().compactMap { index, font in
            children(font, "b").first.map { $0.attribute(forName: "val")?.stringValue.map { $0 != "0" && $0 != "false" } ?? true } == true ? index : nil })
        let solid = Set(fills.enumerated().compactMap { index, fill in
            children(fill, "patternFill").first?.attribute(forName: "patternType")?.stringValue == "solid" ? index : nil })
        let formats = (children(root, "cellXfs").first.map { children($0, "xf") } ?? []).map {
            (font: $0.attribute(forName: "fontId")?.stringValue.flatMap(Int.init) ?? 0, fill: $0.attribute(forName: "fillId")?.stringValue.flatMap(Int.init) ?? 0)
        }
        return StylesInfo(boldFonts: bold, solidFills: solid, formats: formats)
    }

    // MARK: XML helpers

    static func children(_ element: XMLElement, _ name: String) -> [XMLElement] {
        (element.children ?? []).compactMap { $0 as? XMLElement }.filter { ($0.localName ?? $0.name) == name }
    }

    static func setAttribute(_ element: XMLElement, _ name: String, _ value: String) {
        element.removeAttribute(forName: name)
        element.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
    }

    /// Inserts `element` after the last sibling that comes before it in `order`.
    static func insert(_ element: XMLElement, into parent: XMLElement, order: [String]) {
        guard let rank = order.firstIndex(of: element.name ?? "") else { parent.addChild(element); return }
        let siblings = (parent.children ?? [])
        var index = 0
        for (position, node) in siblings.enumerated() {
            guard let sibling = node as? XMLElement, let siblingRank = order.firstIndex(of: sibling.localName ?? sibling.name ?? "") else { continue }
            if siblingRank < rank { index = position + 1 }
        }
        parent.insertChild(element, at: index)
    }

    static func relationships(_ url: URL) -> [String: String] {
        guard let document = try? XMLDocument(contentsOf: url, options: []), let root = document.rootElement() else { return [:] }
        var result: [String: String] = [:]
        for relationship in children(root, "Relationship") {
            if let id = relationship.attribute(forName: "Id")?.stringValue, let target = relationship.attribute(forName: "Target")?.stringValue { result[id] = target }
        }
        return result
    }
}
