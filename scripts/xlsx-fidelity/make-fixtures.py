#!/usr/bin/env python3
"""Excel → PDF fidelity corpus (fictitious data, standard library only).

Writes workbooks that cover what real spreadsheets do: styled header bands,
merged titles, currency / date / percent formats, formulas with cached values,
zebra rows, borders, wrapped text, frozen panes, a hidden column and a hidden
sheet, a bar chart, a sheet far wider than a page, a list far longer than a
page, and sheets with and without their own page setup.

    make-fixtures.py OUTPUT_DIR
"""
import sys, zipfile, datetime, random
from pathlib import Path
from xml.sax.saxutils import escape

random.seed(7)
out = Path(sys.argv[1] if len(sys.argv) > 1 else "fixtures"); out.mkdir(parents=True, exist_ok=True)

HIDDEN, HIDDEN_SHEET = ' hidden="1"', ' state="hidden"'

def col(n):  # 1 → A
    s = ""
    while n: n, r = divmod(n - 1, 26); s = chr(65 + r) + s
    return s

# Styles: index → (numFmt, font, fill, border, align)
NUMFMTS = {164: '#,##0.00\\ "₺"', 165: 'dd.mm.yyyy', 166: '0%', 167: '#,##0'}
FONTS = ['<font><sz val="10"/><name val="Arial"/></font>',
         '<font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Arial"/></font>',
         '<font><b/><sz val="14"/><color rgb="FF1E3360"/><name val="Arial"/></font>',
         '<font><b/><sz val="10"/><name val="Arial"/></font>',
         '<font><i/><sz val="9"/><color rgb="FF666666"/><name val="Arial"/></font>']
FILLS = ['<fill><patternFill patternType="none"/></fill>', '<fill><patternFill patternType="gray125"/></fill>',
         '<fill><patternFill patternType="solid"><fgColor rgb="FF1E3360"/></patternFill></fill>',
         '<fill><patternFill patternType="solid"><fgColor rgb="FFF2F4F8"/></patternFill></fill>',
         '<fill><patternFill patternType="solid"><fgColor rgb="FFE3F2E1"/></patternFill></fill>',
         '<fill><patternFill patternType="solid"><fgColor rgb="FFFDE7E7"/></patternFill></fill>',
         '<fill><patternFill patternType="solid"><fgColor rgb="FFFFF4D6"/></patternFill></fill>']
BORDERS = ['<border/>', '<border><left style="thin"><color rgb="FFB0B7C3"/></left><right style="thin"><color rgb="FFB0B7C3"/></right><top style="thin"><color rgb="FFB0B7C3"/></top><bottom style="thin"><color rgb="FFB0B7C3"/></bottom></border>',
           '<border><top style="medium"><color rgb="FF1E3360"/></top><bottom style="double"><color rgb="FF1E3360"/></bottom></border>']
XF = []  # (numFmt, font, fill, border, align)
def style(num=0, font=0, fill=0, border=0, align=""):
    key = (num, font, fill, border, align)
    if key not in XF: XF.append(key)
    return XF.index(key)
style()  # 0 default

QUOTE = {'"': "&quot;"}

def styles_xml():
    nf = "".join(f'<numFmt numFmtId="{k}" formatCode="{escape(v, QUOTE)}"/>' for k, v in NUMFMTS.items())
    xfs = ""
    for num, font, fill, border, align in XF:
        a = f'<alignment {align}/>' if align else ""
        xfs += f'<xf numFmtId="{num}" fontId="{font}" fillId="{fill}" borderId="{border}" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">{a}</xf>'
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            f'<numFmts count="{len(NUMFMTS)}">{nf}</numFmts><fonts count="{len(FONTS)}">{"".join(FONTS)}</fonts><fills count="{len(FILLS)}">{"".join(FILLS)}</fills>'
            f'<borders count="{len(BORDERS)}">{"".join(BORDERS)}</borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
            f'<cellXfs count="{len(XF)}">{xfs}</cellXfs></styleSheet>')

class Sheet:
    def __init__(self, name, hidden=False):
        self.name, self.hidden = name, hidden
        self.rows = {}; self.merges = []; self.widths = {}; self.hidden_cols = set(); self.extra = ""; self.page = ""; self.freeze = None; self.chart = None; self.heights = {}
    def set(self, r, c, value, s=0, formula=None):
        self.rows.setdefault(r, {})[c] = (value, s, formula)
    def xml(self):
        cols = "".join(f'<col min="{c}" max="{c}" width="{w}" customWidth="1"{HIDDEN if c in self.hidden_cols else ""}/>' for c, w in sorted(self.widths.items()))
        rows = ""
        for r in sorted(self.rows):
            ht = f' ht="{self.heights[r]}" customHeight="1"' if r in self.heights else ""
            cells = ""
            for c in sorted(self.rows[r]):
                v, s, f = self.rows[r][c]; ref = f"{col(c)}{r}"
                fx = f"<f>{escape(f)}</f>" if f else ""
                if v is None: cells += f'<c r="{ref}" s="{s}"/>'
                elif isinstance(v, str): cells += f'<c r="{ref}" s="{s}" t="inlineStr">{fx}<is><t xml:space="preserve">{escape(v)}</t></is></c>'
                else: cells += f'<c r="{ref}" s="{s}">{fx}<v>{v}</v></c>'
            rows += f'<row r="{r}"{ht}>{cells}</row>'
        view = ""
        if self.freeze:
            r, c = self.freeze
            view = f'<sheetViews><sheetView workbookViewId="0"><pane xSplit="{c}" ySplit="{r}" topLeftCell="{col(c+1)}{r+1}" activePane="bottomRight" state="frozen"/></sheetView></sheetViews>'
        merges = f'<mergeCells count="{len(self.merges)}">' + "".join(f'<mergeCell ref="{m}"/>' for m in self.merges) + "</mergeCells>" if self.merges else ""
        drawing = '<drawing r:id="rId1"/>' if self.chart else ""
        return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
                f'{self.extra}{view}<sheetFormatPr defaultRowHeight="15"/>{"<cols>" + cols + "</cols>" if cols else ""}<sheetData>{rows}</sheetData>{merges}'
                f'<pageMargins left="0.5" right="0.5" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>{self.page}{drawing}</worksheet>')

def excel_date(d): return (d - datetime.date(1899, 12, 30)).days

def chart_xml(sheet, cats, vals, title):
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
            f'<c:chart><c:title><c:tx><c:rich><a:bodyPr/><a:p><a:r><a:t>{escape(title)}</a:t></a:r></a:p></c:rich></c:tx><c:overlay val="0"/></c:title><c:plotArea><c:barChart><c:barDir val="col"/><c:grouping val="clustered"/>'
            f'<c:ser><c:idx val="0"/><c:order val="0"/><c:tx><c:v>Ciro</c:v></c:tx><c:spPr><a:solidFill><a:srgbClr val="1E3360"/></a:solidFill></c:spPr>'
            f"<c:cat><c:strRef><c:f>'{sheet}'!{cats}</c:f></c:strRef></c:cat><c:val><c:numRef><c:f>'{sheet}'!{vals}</c:f></c:numRef></c:val></c:ser>"
            '<c:axId val="1"/><c:axId val="2"/></c:barChart><c:catAx><c:axId val="1"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="b"/><c:crossAx val="2"/></c:catAx>'
            '<c:valAx><c:axId val="2"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/><c:axPos val="l"/><c:majorGridlines/><c:numFmt formatCode="#,##0" sourceLinked="0"/><c:crossAx val="1"/></c:valAx></c:plotArea>'
            '<c:plotVisOnly val="1"/></c:chart></c:chartSpace>')

def drawing_xml(c0, r0, c1, r1):
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart">'
            f'<xdr:twoCellAnchor><xdr:from><xdr:col>{c0}</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>{r0}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from><xdr:to><xdr:col>{c1}</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>{r1}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>'
            '<xdr:graphicFrame macro=""><xdr:nvGraphicFramePr><xdr:cNvPr id="2" name="Grafik 1"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr><xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm>'
            '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart r:id="rId1"/></a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor></xdr:wsDr>')

def save(path, sheets, defined=""):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        ct = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
              '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>')
        rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        book = ""
        for i, s in enumerate(sheets, 1):
            ct += f'<Override PartName="/xl/worksheets/sheet{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
            rels += f'<Relationship Id="rId{i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet{i}.xml"/>'
            book += f'<sheet name="{escape(s.name)}" sheetId="{i}"{HIDDEN_SHEET if s.hidden else ""} r:id="rId{i}"/>'
            z.writestr(f"xl/worksheets/sheet{i}.xml", s.xml())
            if s.chart:
                ct += f'<Override PartName="/xl/drawings/drawing{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/><Override PartName="/xl/charts/chart{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>'
                z.writestr(f"xl/worksheets/_rels/sheet{i}.xml.rels", f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing{i}.xml"/></Relationships>')
                z.writestr(f"xl/drawings/drawing{i}.xml", drawing_xml(*s.chart["anchor"]))
                z.writestr(f"xl/drawings/_rels/drawing{i}.xml.rels", f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart{i}.xml"/></Relationships>')
                z.writestr(f"xl/charts/chart{i}.xml", chart_xml(s.name, *s.chart["data"]))
        rels += f'<Relationship Id="rId{len(sheets)+1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'
        z.writestr("[Content_Types].xml", ct + "</Types>")
        z.writestr("_rels/.rels", '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
        z.writestr("xl/workbook.xml", f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>{book}</sheets>{defined}<calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>')
        z.writestr("xl/_rels/workbook.xml.rels", rels)
        z.writestr("xl/styles.xml", styles_xml())

# ---- Shared styles
HEAD = style(font=1, fill=2, border=1, align='horizontal="center" vertical="center" wrapText="1"')
TITLE = style(font=2, align='horizontal="left" vertical="center"')
NOTE = style(font=4)
def body(num=0, zebra=False, fill=None, align=""):
    return style(num=num, fill=fill if fill is not None else (3 if zebra else 0), border=1, align=align)
TOTAL_LABEL = style(font=3, border=2); TOTAL_MONEY = style(num=164, font=3, border=2)

# ---- 1) Sales report: no page setup of its own (the common real-world case)
regions = ["Alanya", "Antalya", "İstanbul", "İzmir", "Ankara", "Bursa"]
products = ["Web sitesi", "Mobil uygulama", "SEO danışmanlığı", "Barındırma", "Bakım paketi", "E-ticaret altyapısı"]
people = ["Ayşe Yılmaz", "Mehmet Demir", "Zeynep Kaya", "Can Öztürk", "Elif Şahin"]
status = [("Ödendi", 4), ("Bekliyor", 6), ("Gecikti", 5)]
s1 = Sheet("Satışlar")
heads = ["Tarih", "Bölge", "Ürün", "Adet", "Birim Fiyat", "Tutar", "KDV %", "KDV", "Toplam", "Durum", "Temsilci", "Not", "Gizli Kod"]
for c, w in enumerate([11, 11, 20, 7, 14, 15, 8, 13, 15, 11, 15, 34, 10], 1): s1.widths[c] = w
s1.hidden_cols = {13}
s1.set(1, 1, "2026 3. Çeyrek Satış Raporu", TITLE); s1.merges.append("A1:L1"); s1.heights[1] = 26
s1.set(2, 1, "Kaynak: Muhasebe sistemi · Tutarlar Türk lirası, KDV dahil toplamlar", NOTE); s1.merges.append("A2:L2")
for c, h in enumerate(heads, 1): s1.set(4, c, h, HEAD)
s1.heights[4] = 30; s1.freeze = (4, 1)
r = 5; totals = [0.0, 0.0, 0.0]
for i in range(60):
    z = i % 2 == 1
    d = datetime.date(2026, 7, 1) + datetime.timedelta(days=i * 1.5)
    qty = random.randint(1, 12); price = random.choice([4200, 750, 2500, 45000, 1800, 12500]) * 1.0
    amount = qty * price; vat = 0.20 if i % 7 else 0.10; tax = round(amount * vat, 2); total = amount + tax
    st, fill = status[i % 3] if i % 5 else status[0]
    note = "Yıllık sözleşme; fatura ayın son iş günü kesilir ve banka havalesiyle ödenir." if i % 9 == 0 else ""
    s1.set(r, 1, excel_date(d), body(165, z, align='horizontal="center"'))
    s1.set(r, 2, regions[i % 6], body(0, z)); s1.set(r, 3, products[(i * 5) % 6], body(0, z))
    s1.set(r, 4, qty, body(167, z)); s1.set(r, 5, price, body(164, z))
    s1.set(r, 6, amount, body(164, z), f"D{r}*E{r}"); s1.set(r, 7, vat, body(166, z, align='horizontal="center"'))
    s1.set(r, 8, tax, body(164, z), f"ROUND(F{r}*G{r},2)"); s1.set(r, 9, total, body(164, z), f"F{r}+H{r}")
    s1.set(r, 10, st, body(0, fill=fill, align='horizontal="center"')); s1.set(r, 11, people[i % 5], body(0, z))
    s1.set(r, 12, note, body(0, z, align='wrapText="1" vertical="top"')); s1.set(r, 13, f"K-{1000+i}", body(0, z))
    totals[0] += amount; totals[1] += tax; totals[2] += total; r += 1
s1.set(r, 1, "GENEL TOPLAM", TOTAL_LABEL); s1.merges.append(f"A{r}:E{r}")
for c in range(2, 6): s1.set(r, c, None, TOTAL_LABEL)
s1.set(r, 6, round(totals[0], 2), TOTAL_MONEY, f"SUM(F5:F{r-1})"); s1.set(r, 7, None, TOTAL_LABEL)
s1.set(r, 8, round(totals[1], 2), TOTAL_MONEY, f"SUM(H5:H{r-1})"); s1.set(r, 9, round(totals[2], 2), TOTAL_MONEY, f"SUM(I5:I{r-1})")
for c in (10, 11, 12): s1.set(r, c, None, TOTAL_LABEL)

# ---- 2) Summary with a chart, landscape page setup of its own
s2 = Sheet("Özet")
for c, w in enumerate([18, 16, 12, 14], 1): s2.widths[c] = w
s2.set(1, 1, "Bölge Bazında Ciro", TITLE); s2.merges.append("A1:D1"); s2.heights[1] = 24
for c, h in enumerate(["Bölge", "Ciro", "Pay", "Müşteri"], 1): s2.set(3, c, h, HEAD)
values = [412500, 388200, 905300, 512900, 267400, 198750]; whole = sum(values)
for i, (reg, v) in enumerate(zip(regions, values)):
    z = i % 2 == 1; rr = 4 + i
    s2.set(rr, 1, reg, body(0, z)); s2.set(rr, 2, v, body(164, z)); s2.set(rr, 3, round(v / whole, 4), body(166, z, align='horizontal="center"'), f"B{rr}/B$10"); s2.set(rr, 4, 10 + i * 7, body(167, z))
s2.set(10, 1, "Toplam", TOTAL_LABEL); s2.set(10, 2, whole, TOTAL_MONEY, "SUM(B4:B9)"); s2.set(10, 3, 1, style(num=166, font=3, border=2, align='horizontal="center"'), "SUM(C4:C9)"); s2.set(10, 4, sum(10 + i * 7 for i in range(6)), style(num=167, font=3, border=2), "SUM(D4:D9)")
s2.chart = {"anchor": (5, 2, 13, 22), "data": ("$A$4:$A$9", "$B$4:$B$9", "Bölge Bazında Ciro (₺)")}
s2.page = '<pageSetup paperSize="9" orientation="landscape"/>'

# ---- 3) A sheet far wider than a page (30 columns), no page setup
s3 = Sheet("Aylık Dağılım")
s3.set(1, 1, "Ürün", HEAD); s3.widths[1] = 20
months = ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"]
for c in range(2, 31):
    s3.widths[c] = 10; s3.set(1, c, f"{months[(c-2) % 12]} {2025 + (c-2)//12}", HEAD)
for i, p in enumerate(products * 2):
    rr = 2 + i; z = i % 2 == 1
    s3.set(rr, 1, f"{p} {'B' if i >= 6 else 'A'}", body(0, z))
    for c in range(2, 31): s3.set(rr, c, random.randint(5, 900) * 100, body(167, z))

# ---- 4) A long list (300 rows): a page and a half of… many pages
s4 = Sheet("Müşteri Listesi")
for c, (h, w) in enumerate([("No", 6), ("Firma", 30), ("Şehir", 14), ("Telefon", 16), ("Bakiye", 15)], 1): s4.set(1, c, h, HEAD); s4.widths[c] = w
cities = ["Alanya", "Antalya", "İstanbul", "İzmir", "Ankara", "Muğla", "Konya"]
for i in range(300):
    rr = 2 + i; z = i % 2 == 1
    s4.set(rr, 1, i + 1, body(0, z, align='horizontal="center"')); s4.set(rr, 2, f"Örnek Ticaret {i+1:03d} Ltd. Şti.", body(0, z))
    s4.set(rr, 3, cities[i % 7], body(0, z)); s4.set(rr, 4, f"0242 555 {1000 + i:04d}", body(0, z)); s4.set(rr, 5, round(random.uniform(-5000, 90000), 2), body(164, z))

# ---- 5) A hidden sheet: must not print
s5 = Sheet("Hesap", hidden=True); s5.set(1, 1, "Bu sayfa gizlidir ve PDF'te görünmemelidir.")

save(out / "01-satis-raporu.xlsx", [s1, s2, s3, s4, s5])

# A single small sheet with Excel's own "fit to one page wide" and print titles.
s6 = Sheet("Liste")
for c, (h, w) in enumerate([("No", 6), ("Firma", 30), ("Şehir", 14), ("Bakiye", 15)], 1): s6.set(1, c, h, HEAD); s6.widths[c] = w
for i in range(120):
    rr = 2 + i; z = i % 2 == 1
    s6.set(rr, 1, i + 1, body(0, z, align='horizontal="center"')); s6.set(rr, 2, f"Deneme Yapı {i+1:03d} A.Ş.", body(0, z)); s6.set(rr, 3, cities[i % 7], body(0, z)); s6.set(rr, 4, round(random.uniform(0, 50000), 2), body(164, z))
s6.extra = '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>'
s6.page = '<pageSetup paperSize="9" orientation="portrait" fitToWidth="1" fitToHeight="0"/><headerFooter><oddFooter>&amp;C&amp;P / &amp;N</oddFooter></headerFooter>'
save(out / "02-ayarli-liste.xlsx", [s6], defined="<definedNames><definedName name=\"_xlnm.Print_Titles\" localSheetId=\"0\">'Liste'!$1:$1</definedName></definedNames>")
print("\n".join(str(p) for p in sorted(out.glob("*.xlsx"))))
