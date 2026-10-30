import AppKit
import PDFKit

// Side-by-side visual comparison of an original PDF and the PDF re-exported
// from its Word conversion, with a per-page similarity score.
//   compare ORIGINAL.pdf ROUNDTRIP.pdf OUTPUT_DIR
// Score: share of 8×8-pixel tiles (at 600 px width, on a 4-bit grey scale)
// whose mean ink differs by less than 12%. 100 = visually identical layout.
func render(_ page:PDFPage,width:Int)->CGImage {
    let box=page.bounds(for:.mediaBox),scale=CGFloat(width)/box.width,height=Int(box.height*scale)
    let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(gray:1,alpha:1);context.fill(CGRect(x:0,y:0,width:width,height:height))
    context.scaleBy(x:scale,y:scale);context.translateBy(x:-box.minX,y:-box.minY);context.drawPDFPage(page.pageRef!)
    return context.makeImage()!
}
func grey(_ image:CGImage,width:Int,height:Int)->[UInt8] {
    var pixels=[UInt8](repeating:255,count:width*height)
    let context=CGContext(data:&pixels,width:width,height:height,bitsPerComponent:8,bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue)!
    context.interpolationQuality = .high;context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
    return pixels
}
func score(_ a:CGImage,_ b:CGImage)->Double {
    let w=600,h=Int(Double(w)*Double(a.height)/Double(a.width)),pa=grey(a,width:w,height:h),pb=grey(b,width:w,height:h)
    var same=0,total=0
    for ty in stride(from:0,to:h-8,by:8) { for tx in stride(from:0,to:w-8,by:8) {
        var sa=0,sb=0
        for y in ty..<ty+8 { for x in tx..<tx+8 { sa+=255-Int(pa[y*w+x]);sb+=255-Int(pb[y*w+x]) } }
        if sa<64*6 && sb<64*6 { continue } // blank in both
        total+=1;if abs(sa-sb)<64*255*12/100 { same+=1 }
    } }
    return total==0 ? 100:Double(same)/Double(total)*100
}
@main struct Compare {
    static func main() throws {
        let args=CommandLine.arguments
        guard args.count==4,let original=PDFDocument(url:URL(fileURLWithPath:args[1])),let roundtrip=PDFDocument(url:URL(fileURLWithPath:args[2])) else { print("Usage: compare ORIGINAL.pdf ROUNDTRIP.pdf OUTPUT_DIR");exit(64) }
        let out=URL(fileURLWithPath:args[3],isDirectory:true);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let name=URL(fileURLWithPath:args[1]).deletingPathExtension().lastPathComponent
        var scores:[String]=[]
        for index in 0..<max(original.pageCount,roundtrip.pageCount) {
            let width=700
            let left=original.page(at:index).map{render($0,width:width)},right=roundtrip.page(at:index).map{render($0,width:width)}
            let height=max(left?.height ?? 0,right?.height ?? 0)
            let canvas=CGContext(data:nil,width:width*2+30,height:height+40,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
            canvas.setFillColor(gray:0.82,alpha:1);canvas.fill(CGRect(x:0,y:0,width:width*2+30,height:height+40))
            if let left { canvas.draw(left,in:CGRect(x:10,y:10+height-left.height,width:left.width,height:left.height)) }
            if let right { canvas.draw(right,in:CGRect(x:width+20,y:10+height-right.height,width:right.width,height:right.height)) }
            let value=left != nil && right != nil ? score(left!,right!):0
            scores.append(String(format:"p%d=%.0f",index+1,value))
            NSGraphicsContext.current=NSGraphicsContext(cgContext:canvas,flipped:false)
            NSAttributedString(string:"ORİJİNAL PDF",attributes:[.font:NSFont.boldSystemFont(ofSize:14)]).draw(at:CGPoint(x:14,y:height+16))
            NSAttributedString(string:String(format:"WORD (DOCX) → PDF · benzerlik %.0f",value),attributes:[.font:NSFont.boldSystemFont(ofSize:14)]).draw(at:CGPoint(x:width+24,y:height+16))
            NSGraphicsContext.current=nil
            try NSBitmapImageRep(cgImage:canvas.makeImage()!).representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent("\(name)-p\(index+1).png"))
        }
        print(name,"pages \(original.pageCount)→\(roundtrip.pageCount)",scores.joined(separator:" "))
    }
}
