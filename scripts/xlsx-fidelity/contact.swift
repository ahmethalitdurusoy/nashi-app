// Contact sheet of every page of a PDF, with page numbers:
//   contact OUT.png COLUMNS FILE.pdf
import AppKit
import PDFKit
let a = CommandLine.arguments, cols = Int(a[2])!, doc = PDFDocument(url: URL(fileURLWithPath: a[3]))!
let cell = CGSize(width: 300, height: 300), n = doc.pageCount, rows = (n + cols - 1) / cols
let W = Int(cell.width) * cols, H = (Int(cell.height) + 20) * rows
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(gray: 0.8, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
for i in 0..<n {
  let page = doc.page(at: i)!, b = page.bounds(for: .cropBox), s = min((cell.width - 10) / b.width, (cell.height - 10) / b.height)
  let x = CGFloat(i % cols) * cell.width + 5, y = CGFloat(H) - CGFloat(i / cols + 1) * (cell.height + 20) + 5
  ctx.saveGState(); ctx.translateBy(x: x, y: y); ctx.scaleBy(x: s, y: s)
  ctx.setFillColor(.white); ctx.fill(CGRect(origin: .zero, size: b.size)); ctx.translateBy(x: -b.minX, y: -b.minY); ctx.drawPDFPage(page.pageRef!); ctx.restoreGState()
  NSString(string: "\(i + 1)").draw(at: CGPoint(x: x, y: y + cell.height - 2), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
}
try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[1]))
