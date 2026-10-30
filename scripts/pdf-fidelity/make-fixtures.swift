import AppKit
import PDFKit

// Generates the PDF → Word fidelity corpus: native-text reports, contracts and
// invoices with headers/footers, page numbers, page backgrounds, bordered
// tables, vector charts, photos, two-column text, watermarks, signatures,
// company stamps and initials — plus scanned (image-only) and mixed pages.
//   swiftc -parse-as-library -o make-fixtures scripts/pdf-fidelity/make-fixtures.swift && ./make-fixtures OUTPUT_DIR

let pageSize=CGSize(width:595,height:842)
let ink=NSColor(srgbRed:0.12,green:0.13,blue:0.16,alpha:1)
let muted=NSColor(srgbRed:0.42,green:0.44,blue:0.48,alpha:1)
let gold=NSColor(srgbRed:0.78,green:0.60,blue:0.24,alpha:1)
let navy=NSColor(srgbRed:0.12,green:0.20,blue:0.38,alpha:1)
let stampRed=NSColor(srgbRed:0.80,green:0.10,blue:0.16,alpha:0.82)
let stampBlue=NSColor(srgbRed:0.10,green:0.25,blue:0.70,alpha:0.80)
let penBlue=NSColor(srgbRed:0.08,green:0.16,blue:0.48,alpha:1)
/// Business documents use installed, embeddable fonts. The body face can be
/// switched per document (Arial for reports and invoices, Times for contracts).
@MainActor var bodyFamily="Arial"
@MainActor func bodyFont(bold:Bool=false,size:CGFloat)->NSFont {
    NSFontManager.shared.font(withFamily:bodyFamily,traits:bold ? .boldFontMask:[],weight:bold ? 9:5,size:size) ?? .systemFont(ofSize:size)
}
let lorem=["Bu rapor, 2026 yılının üçüncü çeyreğine ait operasyonel sonuçları ve önümüzdeki dönem için öngörülen yatırım planını özetlemektedir. Müşteri memnuniyeti, teslimat süreleri ve maliyet kalemleri ayrıntılı biçimde incelenmiştir.",
           "Şirketimizin Alanya ve İstanbul ofislerinde yürütülen çalışmalar sonucunda yazılım geliştirme kapasitesi %18 oranında artmıştır. Çağrı merkezi yanıt süresi ortalama 42 saniyeye düşürülmüştür.",
           "Öneriler bölümünde yer alan maddeler yönetim kurulunun onayına sunulmuştur. Ekli tablolar ve grafikler, yalnızca şirket içi değerlendirme amacıyla hazırlanmış olup üçüncü kişilerle paylaşılmamalıdır."]

@MainActor final class PDFWriter {
    let context:CGContext
    var page=0
    let total:Int
    init(url:URL,pages:Int) {
        var box=CGRect(origin:.zero,size:pageSize)
        context=CGContext(url as CFURL,mediaBox:&box,[kCGPDFContextTitle as String:url.deletingPathExtension().lastPathComponent,kCGPDFContextCreator as String:"UForge fidelity corpus"] as CFDictionary)!
        total=pages
    }
    /// Top-left origin drawing, like a document.
    func beginPage(background:NSColor?=nil) {
        page+=1
        context.beginPDFPage(nil)
        context.translateBy(x:0,y:pageSize.height);context.scaleBy(x:1,y:-1)
        NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:true)
        if let background { background.setFill();CGRect(origin:.zero,size:pageSize).fill() }
    }
    func endPage() { NSGraphicsContext.current=nil;context.endPDFPage() }
    func close() { context.closePDF() }

    @discardableResult func text(_ string:String,at point:CGPoint,width:CGFloat=495,font:NSFont?=nil,color:NSColor=ink,align:NSTextAlignment = .left,lineSpacing:CGFloat=3)->CGFloat {
        let style=NSMutableParagraphStyle();style.alignment=align;style.lineSpacing=lineSpacing
        let attributed=NSAttributedString(string:string,attributes:[.font:font ?? bodyFont(size:11),.foregroundColor:color,.paragraphStyle:style])
        let bounds=attributed.boundingRect(with:CGSize(width:width,height:2000),options:[.usesLineFragmentOrigin,.usesFontLeading])
        attributed.draw(with:CGRect(x:point.x,y:point.y,width:width,height:ceil(bounds.height)+2),options:[.usesLineFragmentOrigin,.usesFontLeading])
        return ceil(bounds.height)
    }
    func line(_ a:CGPoint,_ b:CGPoint,color:NSColor=ink,width:CGFloat=0.8,dash:[CGFloat]=[]) {
        let path=NSBezierPath();path.move(to:a);path.line(to:b);path.lineWidth=width
        if !dash.isEmpty { path.setLineDash(dash,count:dash.count,phase:0) }
        color.setStroke();path.stroke()
    }
    func rect(_ r:CGRect,fill:NSColor?=nil,stroke:NSColor?=nil,width:CGFloat=0.8,radius:CGFloat=0) {
        let path=NSBezierPath(roundedRect:r,xRadius:radius,yRadius:radius);path.lineWidth=width
        if let fill { fill.setFill();path.fill() }
        if let stroke { stroke.setStroke();path.stroke() }
    }
    func logo(at origin:CGPoint,size:CGFloat) {
        let path=NSBezierPath();path.lineWidth=size*0.2;path.lineCapStyle = .round
        path.move(to:CGPoint(x:origin.x+size*0.22,y:origin.y+size*0.15));path.line(to:CGPoint(x:origin.x+size*0.22,y:origin.y+size*0.55))
        path.appendArc(withCenter:CGPoint(x:origin.x+size*0.5,y:origin.y+size*0.55),radius:size*0.28,startAngle:180,endAngle:0,clockwise:true)
        path.line(to:CGPoint(x:origin.x+size*0.78,y:origin.y+size*0.15));gold.setStroke();path.stroke()
    }
    func header(company:String="UNQSOFT Yazılım A.Ş.",title:String) {
        logo(at:CGPoint(x:50,y:28),size:26)
        text(company,at:CGPoint(x:84,y:30),width:250,font:bodyFont(bold:true,size:11))
        text(title,at:CGPoint(x:300,y:32),width:245,font:bodyFont(size:9),color:muted,align:.right)
        line(CGPoint(x:50,y:62),CGPoint(x:545,y:62),color:gold,width:1.2)
    }
    func footer(left:String="Gizli – Yalnızca şirket içi kullanım") {
        line(CGPoint(x:50,y:796),CGPoint(x:545,y:796),color:muted,width:0.5)
        text(left,at:CGPoint(x:50,y:802),width:300,font:bodyFont(size:8),color:muted)
        text("Sayfa \(page) / \(total)",at:CGPoint(x:395,y:802),width:150,font:bodyFont(size:8),color:muted,align:.right)
    }
    func table(_ rows:[[String]],at origin:CGPoint,widths:[CGFloat],rowHeight:CGFloat=22,headerFill:NSColor=navy,zebra:NSColor?=NSColor(white:0.95,alpha:1),rightAligned:Set<Int>=[]) -> CGFloat {
        let total=widths.reduce(0,+)
        for (r,row) in rows.enumerated() {
            let y=origin.y+CGFloat(r)*rowHeight
            if r==0 { rect(CGRect(x:origin.x,y:y,width:total,height:rowHeight),fill:headerFill) }
            else if let zebra,r%2==0 { rect(CGRect(x:origin.x,y:y,width:total,height:rowHeight),fill:zebra) }
            var x=origin.x
            for (c,cell) in row.enumerated() {
                text(cell,at:CGPoint(x:x+6,y:y+5),width:widths[c]-12,font:r==0 ? bodyFont(bold:true,size:9.5):bodyFont(size:9.5),color:r==0 ? .white:ink,align:rightAligned.contains(c) && r>0 ? .right:.left)
                x+=widths[c]
            }
        }
        let height=CGFloat(rows.count)*rowHeight
        rect(CGRect(x:origin.x,y:origin.y,width:total,height:height),stroke:NSColor(white:0.55,alpha:1),width:0.8)
        for r in 1..<rows.count { line(CGPoint(x:origin.x,y:origin.y+CGFloat(r)*rowHeight),CGPoint(x:origin.x+total,y:origin.y+CGFloat(r)*rowHeight),color:NSColor(white:0.70,alpha:1),width:0.5) }
        var x=origin.x
        for w in widths.dropLast() { x+=w;line(CGPoint(x:x,y:origin.y),CGPoint(x:x,y:origin.y+height),color:NSColor(white:0.70,alpha:1),width:0.5) }
        return height
    }
    func barChart(in r:CGRect,values:[(String,Double)]) {
        line(CGPoint(x:r.minX,y:r.maxY),CGPoint(x:r.maxX,y:r.maxY),color:muted,width:1);line(CGPoint(x:r.minX,y:r.minY),CGPoint(x:r.minX,y:r.maxY),color:muted,width:1)
        let maxValue=values.map(\.1).max() ?? 1
        for step in 1...4 { let y=r.maxY-r.height*CGFloat(step)/4;line(CGPoint(x:r.minX,y:y),CGPoint(x:r.maxX,y:y),color:NSColor(white:0.85,alpha:1),width:0.4,dash:[3,2]);text("\(Int(maxValue*Double(step)/4))",at:CGPoint(x:r.minX-34,y:y-6),width:30,font:bodyFont(size:7),color:muted,align:.right) }
        let slot=r.width/CGFloat(values.count)
        for (i,(label,value)) in values.enumerated() {
            let h=r.height*CGFloat(value/maxValue)
            rect(CGRect(x:r.minX+slot*CGFloat(i)+slot*0.2,y:r.maxY-h,width:slot*0.6,height:h),fill:[navy,gold,NSColor.systemTeal,NSColor.systemPink][i%4])
            text(label,at:CGPoint(x:r.minX+slot*CGFloat(i),y:r.maxY+4),width:slot,font:bodyFont(size:8),color:muted,align:.center)
        }
    }
    func pieChart(center:CGPoint,radius:CGFloat,values:[(String,Double)]) {
        let total=values.map(\.1).reduce(0,+);var angle:CGFloat=0
        for (i,(label,value)) in values.enumerated() {
            let sweep=CGFloat(value/total)*360,path=NSBezierPath();path.move(to:center)
            path.appendArc(withCenter:center,radius:radius,startAngle:angle,endAngle:angle+sweep);path.close()
            let color=[navy,gold,NSColor.systemTeal,NSColor.systemPink][i%4];color.setFill();path.fill();NSColor.white.setStroke();path.lineWidth=1.5;path.stroke()
            rect(CGRect(x:center.x+radius+24,y:center.y-radius+CGFloat(i)*18,width:10,height:10),fill:color)
            text("\(label) – %\(Int(value/total*100))",at:CGPoint(x:center.x+radius+40,y:center.y-radius+CGFloat(i)*18-2),width:140,font:bodyFont(size:9))
            angle+=sweep
        }
    }
    func photo(in r:CGRect) {
        NSGraphicsContext.saveGraphicsState()
        let image=NSImage(size:CGSize(width:480,height:300),flipped:true) { box in
            NSGradient(colors:[NSColor(srgbRed:0.98,green:0.70,blue:0.40,alpha:1),NSColor(srgbRed:0.30,green:0.55,blue:0.85,alpha:1)])!.draw(in:box,angle:90)
            NSColor(srgbRed:1,green:0.93,blue:0.6,alpha:1).setFill();NSBezierPath(ovalIn:CGRect(x:330,y:50,width:70,height:70)).fill()
            let hills=NSBezierPath();hills.move(to:CGPoint(x:0,y:300));hills.curve(to:CGPoint(x:480,y:220),controlPoint1:CGPoint(x:120,y:150),controlPoint2:CGPoint(x:300,y:300));hills.line(to:CGPoint(x:480,y:300));hills.close()
            NSColor(srgbRed:0.15,green:0.40,blue:0.30,alpha:1).setFill();hills.fill();return true
        }
        let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
        NSImage(data:rep.representation(using:.jpeg,properties:[.compressionFactor:0.85])!)!.draw(in:r,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        NSGraphicsContext.restoreGraphicsState()
    }
    /// A handwritten-looking signature: one continuous pen stroke.
    func signature(at o:CGPoint,scale:CGFloat=1,seed:Int=0) {
        let p=NSBezierPath();p.lineWidth=1.6*scale;p.lineCapStyle = .round;p.lineJoinStyle = .round
        let s=scale,j=CGFloat(seed)*3
        p.move(to:CGPoint(x:o.x,y:o.y+22*s))
        p.curve(to:CGPoint(x:o.x+18*s,y:o.y+2*s),controlPoint1:CGPoint(x:o.x+4*s,y:o.y+6*s),controlPoint2:CGPoint(x:o.x+12*s,y:o.y-4*s))
        p.curve(to:CGPoint(x:o.x+24*s,y:o.y+30*s),controlPoint1:CGPoint(x:o.x+26*s,y:o.y+10*s),controlPoint2:CGPoint(x:o.x+30*s,y:o.y+26*s))
        p.curve(to:CGPoint(x:o.x+46*s,y:o.y+12*s),controlPoint1:CGPoint(x:o.x+18*s,y:o.y+36*s),controlPoint2:CGPoint(x:o.x+36*s+j,y:o.y+4*s))
        p.curve(to:CGPoint(x:o.x+70*s,y:o.y+24*s),controlPoint1:CGPoint(x:o.x+52*s,y:o.y+20*s),controlPoint2:CGPoint(x:o.x+60*s,y:o.y+30*s))
        p.curve(to:CGPoint(x:o.x+96*s,y:o.y+8*s),controlPoint1:CGPoint(x:o.x+78*s,y:o.y+18*s),controlPoint2:CGPoint(x:o.x+86*s-j,y:o.y))
        p.curve(to:CGPoint(x:o.x+120*s,y:o.y+20*s),controlPoint1:CGPoint(x:o.x+104*s,y:o.y+16*s),controlPoint2:CGPoint(x:o.x+112*s,y:o.y+26*s))
        p.move(to:CGPoint(x:o.x+8*s,y:o.y+30*s));p.curve(to:CGPoint(x:o.x+128*s,y:o.y+26*s),controlPoint1:CGPoint(x:o.x+50*s,y:o.y+40*s),controlPoint2:CGPoint(x:o.x+90*s,y:o.y+20*s))
        penBlue.setStroke();p.stroke()
    }
    /// Round company stamp (kaşe): double ring, text around the ring, star and centre text, rotated.
    func roundStamp(center c:CGPoint,radius r:CGFloat,ring:String,middle:[String],color:NSColor=stampRed,angle:CGFloat = -14) {
        NSGraphicsContext.saveGraphicsState()
        let t=NSAffineTransform();t.translateX(by:c.x,yBy:c.y);t.rotate(byDegrees:angle);t.concat()
        color.setStroke()
        for (radius,width) in [(r,2.2),(r-5,0.9),(r*0.56,1.0)] as [(CGFloat,CGFloat)] { let o=NSBezierPath(ovalIn:CGRect(x:-radius,y:-radius,width:radius*2,height:radius*2));o.lineWidth=width;o.stroke() }
        let chars=Array(ring),font=bodyFont(bold:true,size:r*0.16)
        for (i,ch) in chars.enumerated() {
            let a=CGFloat(i)/CGFloat(chars.count)*2 * .pi - .pi/2
            NSGraphicsContext.saveGraphicsState()
            let g=NSAffineTransform();g.translateX(by:cos(a)*(r-13),yBy:sin(a)*(r-13));g.rotate(byRadians:a + .pi/2);g.concat()
            let s=NSAttributedString(string:String(ch),attributes:[.font:font,.foregroundColor:color]);s.draw(at:CGPoint(x:-s.size().width/2,y:-s.size().height/2))
            NSGraphicsContext.restoreGraphicsState()
        }
        for (i,line) in middle.enumerated() {
            let s=NSAttributedString(string:line,attributes:[.font:bodyFont(bold:true,size:i==0 ? r*0.2:r*0.15),.foregroundColor:color])
            s.draw(at:CGPoint(x:-s.size().width/2,y:-r*0.25+CGFloat(i)*r*0.26))
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    func boxStamp(center c:CGPoint,lines:[String],color:NSColor=stampBlue,angle:CGFloat=8) {
        NSGraphicsContext.saveGraphicsState()
        let t=NSAffineTransform();t.translateX(by:c.x,yBy:c.y);t.rotate(byDegrees:angle);t.concat()
        let box=CGRect(x:-78,y:-26,width:156,height:52);rect(box,stroke:color,width:2.2,radius:4);rect(box.insetBy(dx:4,dy:4),stroke:color,width:0.8,radius:2)
        for (i,line) in lines.enumerated() {
            let s=NSAttributedString(string:line,attributes:[.font:bodyFont(bold:true,size:i==0 ? 13:8),.foregroundColor:color])
            s.draw(at:CGPoint(x:-s.size().width/2,y:-19+CGFloat(i)*20))
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    func watermark(_ string:String) {
        NSGraphicsContext.saveGraphicsState()
        let t=NSAffineTransform();t.translateX(by:pageSize.width/2,yBy:pageSize.height/2);t.rotate(byDegrees:-35);t.concat()
        let s=NSAttributedString(string:string,attributes:[.font:bodyFont(bold:true,size:110),.foregroundColor:NSColor(white:0.5,alpha:0.12)])
        s.draw(at:CGPoint(x:-s.size().width/2,y:-s.size().height/2))
        NSGraphicsContext.restoreGraphicsState()
    }
    func qr(at o:CGPoint,size:CGFloat) {
        let n=21,cell=size/CGFloat(n);var seed:UInt64=0x5EED
        rect(CGRect(x:o.x-4,y:o.y-4,width:size+8,height:size+8),fill:.white)
        for y in 0..<n { for x in 0..<n {
            seed=seed &* 6364136223846793005 &+ 1442695040888963407
            let finder=(x<7&&y<7)||(x>=n-7&&y<7)||(x<7&&y>=n-7)
            let on=finder ? (x%6==0||y%6==0||(x%6>=2&&x%6<=4&&y%6>=2&&y%6<=4)||(x>=n-7&&((x-(n-7))%6==0||((x-(n-7))>=2&&(x-(n-7))<=4&&y%6>=2&&y%6<=4)))||(y>=n-7&&((y-(n-7))%6==0||(x%6>=2&&x%6<=4&&(y-(n-7))>=2&&(y-(n-7))<=4)))):(seed>>33)%2==0
            if on { rect(CGRect(x:o.x+CGFloat(x)*cell,y:o.y+CGFloat(y)*cell,width:cell,height:cell),fill:.black) }
        } }
    }
}

@MainActor func report(_ url:URL) {
    let w=PDFWriter(url:url,pages:3),bg=NSColor(srgbRed:0.985,green:0.975,blue:0.950,alpha:1)
    // Page 1: title, paragraphs, lists, bordered table
    w.beginPage(background:bg);w.header(title:"2026 Q3 Faaliyet Raporu")
    var y:CGFloat=90
    y+=w.text("2026 Üçüncü Çeyrek Faaliyet Raporu",at:CGPoint(x:50,y:y),font:bodyFont(bold:true,size:22),color:navy)+4
    y+=w.text("Hazırlayan: Strateji ve Planlama Birimi · 30 Ekim 2026",at:CGPoint(x:50,y:y),font:NSFontManager.shared.convert(bodyFont(size:10),toHaveTrait:.italicFontMask),color:muted)+14
    y+=w.text("1. Yönetici Özeti",at:CGPoint(x:50,y:y),font:bodyFont(bold:true,size:14))+6
    for p in lorem { y+=w.text(p,at:CGPoint(x:50,y:y),align:.justified)+8 }
    y+=w.text("Öne çıkan başlıklar:",at:CGPoint(x:50,y:y),font:bodyFont(bold:true,size:11))+4
    for item in ["Yeni müşteri sayısı 214'e ulaştı.","Ortalama proje teslim süresi 6 haftaya indi.","Bulut altyapı maliyetleri %11 azaldı."] { y+=w.text("•  "+item,at:CGPoint(x:62,y:y))+3 }
    y+=6
    for (i,item) in ["Satış ekibinin genişletilmesi","Mobil uygulama yol haritasının onaylanması","Veri merkezi göçünün tamamlanması"].enumerated() { y+=w.text("\(i+1). "+item,at:CGPoint(x:62,y:y))+3 }
    y+=14
    y+=w.text("Tablo 1 – Bölge bazında gelirler (₺)",at:CGPoint(x:50,y:y),font:bodyFont(bold:true,size:10),color:muted)+6
    _=w.table([["Bölge","Q1","Q2","Q3"],["Antalya","1.240.000","1.410.500","1.682.300"],["İstanbul","2.905.750","3.120.000","3.388.900"],["İzmir","845.200","912.430","1.004.000"],["Toplam","4.990.950","5.442.930","6.075.200"]],at:CGPoint(x:50,y:y),widths:[165,110,110,110],rightAligned:[1,2,3])
    w.footer();w.endPage()
    // Page 2: vector charts, photo with caption, callout box
    w.beginPage(background:bg);w.header(title:"2026 Q3 Faaliyet Raporu")
    y=90;y+=w.text("2. Grafikler",at:CGPoint(x:50,y:y),font:bodyFont(bold:true,size:14))+10
    w.barChart(in:CGRect(x:90,y:y+10,width:420,height:170),values:[("Ocak",42),("Şubat",58),("Mart",51),("Nisan",77),("Mayıs",69),("Haziran",88)])
    y+=215;w.text("Şekil 1 – Aylık yeni müşteri sayısı",at:CGPoint(x:50,y:y),width:495,font:bodyFont(size:9),color:muted,align:.center);y+=26
    w.pieChart(center:CGPoint(x:170,y:y+80),radius:75,values:[("Yazılım",46),("Danışmanlık",27),("Destek",18),("Diğer",9)]);y+=180
    w.photo(in:CGRect(x:50,y:y,width:240,height:150))
    w.rect(CGRect(x:310,y:y,width:235,height:150),fill:NSColor(srgbRed:0.93,green:0.95,blue:1,alpha:1),stroke:navy,width:1,radius:8)
    w.text("Not",at:CGPoint(x:324,y:y+12),width:200,font:bodyFont(bold:true,size:11),color:navy)
    w.text("Alanya ofisinin yeni çalışma alanı Eylül ayında hizmete açılmıştır. Fotoğraf, açılış gününde çekilmiştir.",at:CGPoint(x:324,y:y+32),width:205,font:bodyFont(size:10))
    w.text("Fotoğraf 1 – Alanya ofisi",at:CGPoint(x:50,y:y+156),width:240,font:bodyFont(size:9),color:muted)
    w.footer();w.endPage()
    // Page 3: two columns, rule, approval with signature and stamp
    w.beginPage(background:bg);w.header(title:"2026 Q3 Faaliyet Raporu")
    y=90;y+=w.text("3. Değerlendirme",at:CGPoint(x:50,y:y),font:bodyFont(bold:true,size:14))+10
    let column=lorem.joined(separator:"\n\n")
    w.text(column,at:CGPoint(x:50,y:y),width:235,font:bodyFont(size:10),align:.justified)
    w.text(column,at:CGPoint(x:310,y:y),width:235,font:bodyFont(size:10),align:.justified)
    y+=300;w.line(CGPoint(x:50,y:y),CGPoint(x:545,y:y),color:gold,width:2);y+=20
    w.text("Onaylayan",at:CGPoint(x:50,y:y),font:bodyFont(bold:true,size:11))
    w.text("Ahmet Halit Durusoy\nGenel Müdür",at:CGPoint(x:50,y:y+18),width:200,font:bodyFont(size:10))
    w.signature(at:CGPoint(x:60,y:y+56),scale:1)
    w.line(CGPoint(x:50,y:y+100),CGPoint(x:230,y:y+100),color:muted,width:0.6,dash:[2,2])
    w.text("İmza",at:CGPoint(x:50,y:y+104),width:180,font:bodyFont(size:8),color:muted)
    w.roundStamp(center:CGPoint(x:330,y:y+60),radius:52,ring:"UNQSOFT YAZILIM A.Ş. ★ ALANYA ★ ",middle:["ONAYLANDI","30.10.2026"])
    w.footer();w.endPage();w.close()
}

@MainActor func contract(_ url:URL) {
    bodyFamily="Times New Roman";defer{bodyFamily="Arial"}
    let w=PDFWriter(url:url,pages:2)
    for pageIndex in 0..<2 {
        w.beginPage();w.watermark("TASLAK");w.header(title:"Hizmet Sözleşmesi No: 2026/118")
        var y:CGFloat=92
        if pageIndex==0 {
            y+=w.text("HİZMET SÖZLEŞMESİ",at:CGPoint(x:50,y:y),width:495,font:bodyFont(bold:true,size:18),align:.center)+16
            for (i,title) in ["Taraflar","Sözleşmenin Konusu","Ücret ve Ödeme","Gizlilik"].enumerated() {
                y+=w.text("Madde \(i+1) – \(title)",at:CGPoint(x:50,y:y),font:bodyFont(bold:true,size:11))+4
                y+=w.text(lorem[i%3]+" İşbu madde kapsamında tarafların hak ve yükümlülükleri aşağıda belirtilmiştir.",at:CGPoint(x:50,y:y),align:.justified)+12
            }
            // Initials (paraf) in the margin of every page.
            w.text("Paraf:",at:CGPoint(x:470,y:760),width:40,font:bodyFont(size:7),color:muted)
            w.signature(at:CGPoint(x:500,y:750),scale:0.3,seed:1)
        } else {
            y+=w.text("Madde 5 – Yürürlük",at:CGPoint(x:50,y:y),font:bodyFont(bold:true,size:11))+4
            y+=w.text(lorem[1]+" Sözleşme imza tarihinde yürürlüğe girer.",at:CGPoint(x:50,y:y),align:.justified)+40
            for (i,(party,name)) in [("HİZMET VEREN","UNQSOFT Yazılım A.Ş."),("HİZMET ALAN","Alanya Turizm Ltd. Şti.")].enumerated() {
                let x:CGFloat=i==0 ? 50:320
                w.text(party,at:CGPoint(x:x,y:y),width:220,font:bodyFont(bold:true,size:10))
                w.text(name+"\nYetkili: "+(i==0 ? "Ahmet Halit Durusoy":"Ayşe Yılmaz"),at:CGPoint(x:x,y:y+16),width:220,font:bodyFont(size:10))
                w.signature(at:CGPoint(x:x+10,y:y+60),scale:1,seed:i)
                w.line(CGPoint(x:x,y:y+104),CGPoint(x:x+200,y:y+104),width:0.6)
                w.text("İmza / Kaşe",at:CGPoint(x:x,y:y+108),width:200,font:bodyFont(size:8),color:muted)
            }
            w.roundStamp(center:CGPoint(x:200,y:y+66),radius:46,ring:"UNQSOFT YAZILIM A.Ş. ★ ANTALYA ★ ",middle:["KAŞE","V.D. 1234567890"])
            w.boxStamp(center:CGPoint(x:440,y:y+190),lines:["ASLI GİBİDİR","Noter onaylı suret · 30.10.2026"])
            w.text("Paraf:",at:CGPoint(x:470,y:760),width:40,font:bodyFont(size:7),color:muted)
            w.signature(at:CGPoint(x:500,y:750),scale:0.3,seed:1)
        }
        w.footer(left:"Sözleşme No: 2026/118");w.endPage()
    }
    w.close()
}

@MainActor func invoice(_ url:URL) {
    let w=PDFWriter(url:url,pages:1)
    w.beginPage();w.logo(at:CGPoint(x:50,y:40),size:40)
    w.text("UNQSOFT Yazılım A.Ş.",at:CGPoint(x:98,y:44),width:240,font:bodyFont(bold:true,size:14))
    w.text("Saray Mah. Atatürk Cad. No:12, 07400 Alanya / Antalya\nV.D.: Alanya · VKN: 1234567890",at:CGPoint(x:98,y:64),width:260,font:bodyFont(size:8.5),color:muted)
    w.rect(CGRect(x:380,y:40,width:165,height:60),fill:navy,radius:6)
    w.text("FATURA",at:CGPoint(x:392,y:48),width:140,font:bodyFont(bold:true,size:18),color:.white)
    w.text("No: UNQ2026000418\nTarih: 30.10.2026",at:CGPoint(x:392,y:72),width:140,font:bodyFont(size:8.5),color:.white)
    w.rect(CGRect(x:50,y:120,width:240,height:80),fill:NSColor(white:0.96,alpha:1),radius:6)
    w.text("SAYIN",at:CGPoint(x:62,y:128),width:200,font:bodyFont(bold:true,size:8),color:muted)
    w.text("Alanya Turizm Ltd. Şti.\nKestel Mah. 42. Sok. No:7\n07450 Alanya / Antalya",at:CGPoint(x:62,y:142),width:220,font:bodyFont(size:10))
    w.qr(at:CGPoint(x:465,y:122),size:76)
    var y:CGFloat=220
    y+=w.table([["Açıklama","Miktar","Birim Fiyat","KDV","Tutar"],["Web sitesi tasarımı","1","45.000,00","%20","45.000,00"],["Yıllık barındırma","12","750,00","%20","9.000,00"],["SEO danışmanlığı","6","2.500,00","%20","15.000,00"],["Mobil uygulama bakımı","3","4.200,00","%20","12.600,00"]],at:CGPoint(x:50,y:y),widths:[200,60,85,50,100],rowHeight:24,rightAligned:[1,2,3,4])+16
    w.rect(CGRect(x:345,y:y,width:200,height:76),fill:NSColor(srgbRed:0.97,green:0.93,blue:0.82,alpha:1),stroke:gold,width:1,radius:4)
    for (i,(label,value)) in [("Ara Toplam","81.600,00 ₺"),("KDV (%20)","16.320,00 ₺"),("GENEL TOPLAM","97.920,00 ₺")].enumerated() {
        w.text(label,at:CGPoint(x:355,y:y+8+CGFloat(i)*22),width:90,font:i==2 ? bodyFont(bold:true,size:10):bodyFont(size:10))
        w.text(value,at:CGPoint(x:440,y:y+8+CGFloat(i)*22),width:95,font:i==2 ? bodyFont(bold:true,size:10):bodyFont(size:10),align:.right)
    }
    w.text("Yalnız: Doksan yedi bin dokuz yüz yirmi Türk Lirası",at:CGPoint(x:50,y:y+8),width:280,font:NSFontManager.shared.convert(bodyFont(size:9),toHaveTrait:.italicFontMask))
    w.signature(at:CGPoint(x:380,y:y+96),scale:0.9)
    w.roundStamp(center:CGPoint(x:470,y:y+120),radius:44,ring:"UNQSOFT YAZILIM A.Ş. ★ ALANYA ★ ",middle:["KAŞE","1234567890"],angle:10)
    w.line(CGPoint(x:50,y:770),CGPoint(x:545,y:770),color:muted,width:0.5)
    w.text("Banka: Ziraat Bankası · IBAN: TR12 0001 0012 3456 7890 1234 56 · Ödeme vadesi: 15 gün",at:CGPoint(x:50,y:776),width:495,font:bodyFont(size:8),color:muted,align:.center)
    w.endPage();w.close()
}

/// Bank transfer receipt: boxed sections, an orange title band, label/value
/// rows on alternating shading, values wrapping inside their cell (IBAN,
/// payee name) next to vertically centred labels, and justified, centred
/// and bold-label text. Data is fictitious.
@MainActor func receipt(_ url:URL) {
    let w=PDFWriter(url:url,pages:1)
    w.beginPage()
    w.logo(at:CGPoint(x:62,y:46),size:24)
    w.text("ÖrnekBank",at:CGPoint(x:92,y:48),width:200,font:bodyFont(bold:true,size:17))
    w.rect(CGRect(x:410,y:46,width:126,height:22),fill:NSColor(white:0.15,alpha:1),radius:3)
    w.text("Şubesiz Bankacılık",at:CGPoint(x:410,y:51),width:126,font:bodyFont(bold:true,size:9),color:gold,align:.center)
    let grey=NSColor(white:0.955,alpha:1),line=NSColor(white:0.85,alpha:1),orange=NSColor(srgbRed:0.98,green:0.70,blue:0.10,alpha:1)
    let left:CGFloat=58,width:CGFloat=476
    // Section 1: details table
    w.rect(CGRect(x:left-4,y:96,width:width+8,height:236),stroke:line,width:0.8)
    w.rect(CGRect(x:left,y:100,width:width,height:16),fill:orange)
    w.text("ÖRNEKBANK",at:CGPoint(x:left,y:103),width:width,font:bodyFont(bold:true,size:8.5),align:.center)
    var y:CGFloat=116
    let columns:[CGFloat]=[left+6,left+126,left+244,left+364]
    let rows:[(String,[String],String,[String],CGFloat)]=[
        ("İŞLEM",["Hesaptan Havale"],"İŞLEM TARİHİ",["30.10.2026 14:12:09"],22),
        ("ALICI HESAP NO",["TR12 0006 4000 0011 2345","6789 01"],"ALICI AD SOYAD/UNVAN",["ÖRNEK ÜNİVERSİTESİ","SPOR BİLİMLERİ","FAKÜLTESİ DÖNER","SERMAYE","İŞLETMESİ"],62),
        ("GONDEREN HESAP NO",["TR98 0006 4000 0019 8765","4321 55"],"GONDEREN AD\nSOYAD/UNVAN",["AYŞE YILMAZ"],34),
        ("İŞLEM TUTARI",["300,00 TL"],"MASRAF TUTARI",[],22),
        ("İŞLEM NO",["2026001234567890"],"FİŞ NO",[],22)]
    w.rect(CGRect(x:left,y:y,width:width,height:20),fill:grey)
    w.text("İŞLEM BİLGİLERİ",at:CGPoint(x:left+6,y:y+6),width:200,font:bodyFont(bold:true,size:8))
    y+=20
    for (index,row) in rows.enumerated() {
        if index%2==1 { w.rect(CGRect(x:left,y:y,width:width,height:row.4),fill:grey) }
        func cell(_ lines:[String],x:CGFloat,bold:Bool) {
            let height=CGFloat(lines.count)*10.4
            for (n,text) in lines.enumerated() { w.text(text,at:CGPoint(x:x,y:y+(row.4-height)/2+CGFloat(n)*10.4),width:118,font:bodyFont(bold:bold,size:8),lineSpacing:0) }
        }
        cell([row.0],x:columns[0],bold:true);cell(row.1,x:columns[1],bold:false)
        cell(row.2.components(separatedBy:"\n"),x:columns[2],bold:true);cell(row.3,x:columns[3],bold:false)
        y+=row.4
    }
    // Section 2: description
    y+=14;w.rect(CGRect(x:left-4,y:y,width:width+8,height:78),stroke:line,width:0.8)
    w.rect(CGRect(x:left,y:y+4,width:width,height:20),fill:grey)
    w.text("İŞLEM AÇIKLAMASI",at:CGPoint(x:left+6,y:y+10),width:200,font:bodyFont(bold:true,size:8))
    w.text("Yukarıda Detay Bilgileri Verilen Havale İşlemi Gerçekleştirilmiştir./ Örnek Kişi Koordinasyon Parkuru Tanıtım, Bilgilendirme ve Uygulama",at:CGPoint(x:left+6,y:y+44),width:width-12,font:bodyFont(size:8),lineSpacing:1)
    // Section 3: bold labels on one shaded band
    y+=92;w.rect(CGRect(x:left-4,y:y,width:width+8,height:64),stroke:line,width:0.8)
    w.rect(CGRect(x:left,y:y+4,width:width,height:56),fill:grey)
    for (n,(label,value)) in [("Sicil Numarası:","776444"),("Ticaret Ünvanı:","Örnek Bankası T.A.O"),("Ticaret Merkezi Adresi:","Saray Mahallesi Örnek Caddesi No:7/A-B Ümraniye/İSTANBUL"),("İnternet Sitesi Adresi:","www.ornekbank.com.tr")].enumerated() {
        let attributed=NSMutableAttributedString(string:label+" ",attributes:[.font:bodyFont(bold:true,size:8),.foregroundColor:ink])
        attributed.append(NSAttributedString(string:value,attributes:[.font:bodyFont(size:8),.foregroundColor:ink]))
        attributed.draw(at:CGPoint(x:left+6,y:y+10+CGFloat(n)*10.6))
    }
    // Section 4: centred disclaimer
    y+=78;w.rect(CGRect(x:left-4,y:y,width:width+8,height:44),stroke:line,width:0.8)
    w.rect(CGRect(x:left,y:y+4,width:width,height:36),fill:grey)
    w.text("Bu dekont bilgilendirme amaçlı hazırlanmıştır. Dekont üzerinde herhangi bir değişiklik yapılması ve/veya bu dekont üzerindeki bilgiler ile banka kayıtlarının uyuşmaması halinde banka kayıtları esas alınacaktır.",at:CGPoint(x:left+20,y:y+12),width:width-40,font:bodyFont(size:8),align:.center,lineSpacing:1)
    w.endPage();w.close()
}

/// Image-only pages that look like a flatbed scan: slight skew, paper tint and speckle noise.
@MainActor func scanned(from sources:[URL],pages:[(Int,Int)],to url:URL) {
    var box=CGRect(origin:.zero,size:pageSize)
    let context=CGContext(url as CFURL,mediaBox:&box,nil)!
    var seed:UInt64=42
    for (sourceIndex,pageIndex) in pages {
        guard let document=PDFDocument(url:sources[sourceIndex]),let page=document.page(at:pageIndex) else { continue }
        let scale:CGFloat=200/72,width=Int(pageSize.width*scale),height=Int(pageSize.height*scale)
        let bitmap=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
        bitmap.setFillColor(CGColor(srgbRed:0.965,green:0.955,blue:0.93,alpha:1));bitmap.fill(CGRect(x:0,y:0,width:width,height:height))
        bitmap.translateBy(x:CGFloat(width)/2,y:CGFloat(height)/2);bitmap.rotate(by:0.6 * .pi/180);bitmap.translateBy(x:-CGFloat(width)/2,y:-CGFloat(height)/2)
        bitmap.scaleBy(x:scale,y:scale);bitmap.setBlendMode(.multiply);bitmap.drawPDFPage(page.pageRef!)
        bitmap.setBlendMode(.normal);bitmap.rotate(by:0);bitmap.resetClip()
        let image=bitmap.makeImage()!
        let noisy=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
        noisy.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        for _ in 0..<2500 { seed=seed &* 6364136223846793005 &+ 1442695040888963407;let x=CGFloat((seed>>20)%UInt64(width)),y=CGFloat((seed>>40)%UInt64(height));noisy.setFillColor(gray:0.35,alpha:0.5);noisy.fill(CGRect(x:x,y:y,width:2,height:2)) }
        let jpeg=NSBitmapImageRep(cgImage:noisy.makeImage()!).representation(using:.jpeg,properties:[.compressionFactor:0.7])!
        let scan=NSBitmapImageRep(data:jpeg)!.cgImage!
        context.beginPDFPage(nil);context.draw(scan,in:box);context.endPDFPage()
    }
    context.closePDF()
}

/// Native text with an embedded screenshot of text and a vector logo.
@MainActor func mixed(_ url:URL,scanSource:URL) {
    let w=PDFWriter(url:url,pages:1)
    w.beginPage();w.header(title:"Karma içerik testi")
    var y:CGFloat=90
    y+=w.text("Karma Belge",at:CGPoint(x:50,y:y),font:bodyFont(bold:true,size:18))+8
    y+=w.text(lorem[0],at:CGPoint(x:50,y:y),align:.justified)+12
    if let document=PDFDocument(url:scanSource),let page=document.page(at:0) {
        let thumb=page.thumbnail(of:CGSize(width:900,height:1270),for:.mediaBox)
        let crop=NSImage(size:CGSize(width:495,height:200),flipped:false) { _ in thumb.draw(in:CGRect(x:-50,y:-405,width:595,height:842),from:.zero,operation:.copy,fraction:1);return true }
        crop.draw(in:CGRect(x:50,y:y,width:495,height:200),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        w.rect(CGRect(x:50,y:y,width:495,height:200),stroke:muted,width:0.5)
    }
    y+=212;w.text("Yukarıdaki alan bir ekran görüntüsüdür; içindeki metin yalnızca OCR ile okunabilir.",at:CGPoint(x:50,y:y),font:NSFontManager.shared.convert(bodyFont(size:9),toHaveTrait:.italicFontMask),color:muted)
    y+=30;y+=w.text(lorem[2],at:CGPoint(x:50,y:y),align:.justified)
    w.footer();w.endPage();w.close()
}

/// Typography: one font family per page (serif, sans, monospace), bold,
/// italic, bold italic and coloured runs, five sizes, growing line spacing,
/// left / justified / centred text and one letter-spaced paragraph.
@MainActor func typography(_ url:URL) {
    let families=["Times New Roman","Georgia","Courier New","Verdana","Trebuchet MS","Arial","Helvetica Neue","Palatino"]
    let words="Bu belge yazı tipi, kalınlık, eğiklik ve boşluk doğruluğunu ölçmek için hazırlanmış genel bir deneme metnidir; çeşitli satır aralıkları, paragraf boşlukları ve hizalamalar içerir. Sözleşme 2026/118 sayılı karar uyarınca 15.04.2026 tarihinde yürürlüğe girmiştir."
    func font(_ family:String,_ size:CGFloat,bold:Bool=false,italic:Bool=false)->NSFont {
        var traits:NSFontTraitMask=[]; if bold { traits.insert(.boldFontMask) }; if italic { traits.insert(.italicFontMask) }
        return NSFontManager.shared.font(withFamily:family,traits:traits,weight:5,size:size) ?? bodyFont(bold:bold,size:size)
    }
    let doc=PDFWriter(url:url,pages:families.count)
    for (index,family) in families.enumerated() {
        doc.beginPage()
        let alternate=families[(index+3)%families.count]
        var y:CGFloat=60
        NSAttributedString(string:"Bölüm \(index+1): \(family)",attributes:[.font:font(family,20,bold:true)]).draw(at:CGPoint(x:60,y:y)); y+=40
        for (step,size) in [9.5,10,11,12,13.5].enumerated() {
            let style=NSMutableParagraphStyle(); style.lineSpacing=CGFloat(step)*1.5; style.alignment = step==2 ? .justified : (step==4 ? .center : .left)
            let text=NSMutableAttributedString(string:words,attributes:[.font:font(step%2==0 ? family:alternate,CGFloat(size)),.paragraphStyle:style,.foregroundColor:ink])
            text.addAttributes([.font:font(family,CGFloat(size),bold:true)],range:NSRange(location:0,length:8))
            text.addAttributes([.font:font(family,CGFloat(size),italic:true)],range:NSRange(location:40,length:18))
            text.addAttributes([.font:font(family,CGFloat(size),bold:true,italic:true),.foregroundColor:stampRed],range:NSRange(location:120,length:22))
            if step==3 { text.addAttribute(.kern,value:1.2,range:NSRange(location:0,length:text.length)) }
            let origin=CGPoint(x:60+CGFloat(step%2)*20,y:y), width=455-CGFloat(step%2)*20
            let height=text.boundingRect(with:CGSize(width:width,height:400),options:[.usesLineFragmentOrigin]).height
            text.draw(with:CGRect(origin:origin,size:CGSize(width:width,height:height+2)),options:[.usesLineFragmentOrigin])
            y+=height+10+CGFloat(step)*4
        }
        NSAttributedString(string:"Sayfa \(index+1) / \(families.count)",attributes:[.font:font("Arial",8)]).draw(at:CGPoint(x:500,y:800))
        doc.endPage()
    }
    doc.close()
}

@main struct MakeFixtures {
    @MainActor static func main() {
        let out=URL(fileURLWithPath:CommandLine.arguments.count>1 ? CommandLine.arguments[1]:"fixtures",isDirectory:true)
        try? FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let names=["01-rapor.pdf","02-sozlesme.pdf","03-fatura.pdf","04-taranmis.pdf","05-karma.pdf","06-dekont.pdf","07-yazi-tipleri.pdf"].map{out.appendingPathComponent($0)}
        report(names[0]);contract(names[1]);invoice(names[2]);receipt(names[5]);typography(names[6])
        scanned(from:[names[1],names[2]],pages:[(0,1),(1,0)],to:names[3])
        mixed(names[4],scanSource:names[0])
        for url in names { print(url.path,PDFDocument(url:url)?.pageCount ?? 0) }
    }
}
