import AppKit

/// Shared vector artwork: the app, menu bar, installer icon and brand exports
/// all draw the same UForge mark — a gold crucible "U" holding a spark.
enum NashiArtwork {
    static let gold=NSColor(srgbRed:0.89,green:0.72,blue:0.35,alpha:1)
    static let ink=NSColor(srgbRed:0.20,green:0.25,blue:0.14,alpha:1)
    static func cruciblePath()->CGPath {
        let p=CGMutablePath();p.move(to:CGPoint(x:0.27,y:0.24));p.addLine(to:CGPoint(x:0.27,y:0.56))
        p.addArc(center:CGPoint(x:0.50,y:0.56),radius:0.23,startAngle:.pi,endAngle:0,clockwise:true)
        p.addLine(to:CGPoint(x:0.73,y:0.24))
        return p.copy(strokingWithWidth:0.17,lineCap:.round,lineJoin:.round,miterLimit:10)
    }
    static func sparkPath(center:CGPoint,radius r:CGFloat)->CGPath {
        let p=CGMutablePath(),k=r*0.16,x=center.x,y=center.y
        p.move(to:CGPoint(x:x,y:y-r))
        p.addQuadCurve(to:CGPoint(x:x+r,y:y),control:CGPoint(x:x+k,y:y-k))
        p.addQuadCurve(to:CGPoint(x:x,y:y+r),control:CGPoint(x:x+k,y:y+k))
        p.addQuadCurve(to:CGPoint(x:x-r,y:y),control:CGPoint(x:x-k,y:y+k))
        p.addQuadCurve(to:CGPoint(x:x,y:y-r),control:CGPoint(x:x-k,y:y-k))
        p.closeSubpath();return p
    }
    static func draw(in rect:NSRect,happy:Bool=false,monochrome:Bool=false) {
        guard let c=NSGraphicsContext.current?.cgContext else { return }
        c.saveGState();defer{c.restoreGState()}
        c.translateBy(x:rect.minX,y:rect.maxY);c.scaleBy(x:rect.width,y:-rect.height)
        let spark=sparkPath(center:CGPoint(x:0.50,y:0.45),radius:happy ? 0.115:0.10)
        let ember=sparkPath(center:CGPoint(x:0.585,y:0.25),radius:0.045)
        if monochrome {
            c.setFillColor(NSColor.black.cgColor);for path in [cruciblePath(),spark,ember] { c.addPath(path);c.fillPath() }
            return
        }
        let space=CGColorSpace(name:CGColorSpace.sRGB)
        c.saveGState();c.addPath(cruciblePath());c.clip()
        let metal=CGGradient(colorsSpace:space,colors:[NSColor(srgbRed:0.99,green:0.88,blue:0.60,alpha:1).cgColor,gold.cgColor,NSColor(srgbRed:0.71,green:0.50,blue:0.20,alpha:1).cgColor] as CFArray,locations:[0,0.55,1])!
        c.drawLinearGradient(metal,start:CGPoint(x:0.2,y:0.2),end:CGPoint(x:0.8,y:0.9),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation]);c.restoreGState()
        let fire=CGGradient(colorsSpace:space,colors:[NSColor(srgbRed:1,green:0.97,blue:0.86,alpha:1).cgColor,NSColor(srgbRed:1,green:0.62,blue:0.22,alpha:1).cgColor] as CFArray,locations:[0,1])!
        for (path,center,radius) in [(spark,CGPoint(x:0.50,y:0.45),CGFloat(0.115)),(ember,CGPoint(x:0.585,y:0.25),CGFloat(0.045))] {
            c.saveGState();c.addPath(path);c.clip()
            c.drawRadialGradient(fire,startCenter:center,startRadius:0,endCenter:center,endRadius:radius,options:[.drawsAfterEndLocation]);c.restoreGState()
        }
    }
    static func mark(size:CGFloat,happy:Bool=false)->NSImage {
        NSImage(size:NSSize(width:size,height:size),flipped:false) { rect in draw(in:rect,happy:happy);return true }
    }
    static func menuIcon(updateAvailable:Bool=false)->NSImage {
        let image=NSImage(size:NSSize(width:20,height:20),flipped:false) { rect in
            draw(in:rect.insetBy(dx:0.5,dy:0.5),monochrome:true)
            if updateAvailable { NSColor.black.setFill();NSBezierPath(ovalIn:NSRect(x:15,y:15,width:4,height:4)).fill() }
            return true
        }
        image.isTemplate=true;image.accessibilityDescription=updateAvailable ? "UForge update available":"UForge";return image
    }
}
