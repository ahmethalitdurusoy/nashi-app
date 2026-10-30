import AppKit
import PDFKit

// Measures how far each line moved: for every text line of the original page,
// finds the same text on the round-tripped page and reports the vertical and
// horizontal offset in points. Large offsets point at the block that drifted.
//   drift ORIGINAL.pdf ROUNDTRIP.pdf [PAGE]
@main struct Drift {
    static func main() {
        let args=CommandLine.arguments
        guard args.count>=3,let original=PDFDocument(url:URL(fileURLWithPath:args[1])),let roundtrip=PDFDocument(url:URL(fileURLWithPath:args[2])) else { print("Usage: drift ORIGINAL.pdf ROUNDTRIP.pdf [PAGE]");exit(64) }
        let pages=args.count>3 ? [Int(args[3])!-1]:Array(0..<original.pageCount)
        var worst:Double=0,missing=0,total=0
        for index in pages {
            guard let source=original.page(at:index),let target=roundtrip.page(at:index) else { continue }
            let lines=(source.selection(for:source.bounds(for:.mediaBox))?.selectionsByLine() ?? [])
            for line in lines {
                guard let text=line.string?.trimmingCharacters(in:.whitespacesAndNewlines),text.count>=4 else { continue }
                let probe=String(text.prefix(18)),from=line.bounds(for:source)
                total+=1
                let hits=roundtrip.findString(probe,withOptions:[]).filter{ $0.pages.contains(target) }.map{ $0.bounds(for:target) }
                guard let best=hits.min(by:{ abs($0.midY-from.midY)<abs($1.midY-from.midY) }) else { missing+=1;print(String(format:"p%d  MISSING          %@",index+1,probe));continue }
                let dy=Double(from.midY-best.midY),dx=Double(best.minX-from.minX)
                worst=max(worst,abs(dy))
                if abs(dy)>2 || abs(dx)>3 { print(String(format:"p%d  dy=%+6.1f dx=%+6.1f  %@",index+1,dy,dx,probe)) }
            }
        }
        print(String(format:"lines=%d missing=%d worst|dy|=%.1fpt",total,missing,worst))
    }
}
