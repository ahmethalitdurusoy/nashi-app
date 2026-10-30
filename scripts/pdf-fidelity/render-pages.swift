import AppKit
import PDFKit

// Renders every page of each PDF to PNG at a fixed width:
//   render-pages OUTPUT_DIR WIDTH FILE.pdf...  →  OUTPUT_DIR/<name>-p<N>.png
@main struct RenderPages {
    static func main() throws {
        let args=CommandLine.arguments
        guard args.count>=4,let width=Double(args[2]) else { print("Usage: render-pages OUTPUT_DIR WIDTH FILE.pdf...");exit(64) }
        let out=URL(fileURLWithPath:args[1],isDirectory:true)
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        for path in args.dropFirst(3) {
            let url=URL(fileURLWithPath:path)
            guard let document=PDFDocument(url:url) else { print("unreadable",path);continue }
            for index in 0..<document.pageCount {
                guard let page=document.page(at:index),let ref=page.pageRef else { continue }
                let box=page.bounds(for:.cropBox),scale=CGFloat(width)/box.width
                let w=Int(box.width*scale),h=Int(box.height*scale)
                let context=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
                context.setFillColor(gray:1,alpha:1);context.fill(CGRect(x:0,y:0,width:w,height:h))
                context.scaleBy(x:scale,y:scale);context.translateBy(x:-box.minX,y:-box.minY);context.drawPDFPage(ref)
                let png=NSBitmapImageRep(cgImage:context.makeImage()!).representation(using:.png,properties:[:])!
                try png.write(to:out.appendingPathComponent(url.deletingPathExtension().lastPathComponent+"-p\(index+1).png"))
            }
        }
    }
}
