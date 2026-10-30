// Page count, first page size and the last line of text of each PDF:
//   pages FILE.pdf...
import PDFKit
for p in CommandLine.arguments.dropFirst() { let d = PDFDocument(url: URL(fileURLWithPath: p))!; let b = d.page(at: 0)!.bounds(for: .cropBox); print(URL(fileURLWithPath: p).lastPathComponent, d.pageCount, "pages", Int(b.width), "x", Int(b.height), "|", (d.page(at: d.pageCount-1)!.string ?? "").split(separator: "\n").suffix(1).joined()) }
