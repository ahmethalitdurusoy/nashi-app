# PDF → Word

Converting a PDF to DOCX rebuilds an editable document and lays the page's own
picture behind it, so the result both edits like a Word file and looks like the
PDF.

## What becomes what

| In the PDF | In Word |
| --- | --- |
| Text | Editable paragraphs with the source font, size, weight, slant, colour and alignment. Justified paragraphs keep their source line breaks so line counts never change. |
| Headings, bullet and numbered lines | Separate paragraphs (never merged into the text around them). |
| Lines repeated at the top/bottom of most pages | The Word header and footer. Page numbers become `PAGE` / `NUMPAGES` fields; header/footer graphics (logo, rules) sit behind them in the header/footer. |
| Aligned rows of cells | Word tables. Ruled tables get real Word borders, column widths and row heights read from the rules, and cell shading. |
| Side-by-side blocks (letterhead vs. invoice box, two signature blocks, newspaper columns) | One borderless layout row per band, one cell per column (an XY-cut of the page). Stacked bands with the same columns (receipts, forms) become one table, one row per band; text that wraps inside a cell keeps its source line breaks. |
| Framed sections and shaded bands (receipts, forms, statements) | One Word table per box: the frame becomes the cell borders, every band its own row with the band colour as cell shading, separator lines become row borders, and the content shares columns across rows. Rows grow with their text, so text can never drift off its band in Word, Google Docs or Pages. |
| Placed photos and screenshots | Separate pictures at their exact position. |
| Everything else — page colour, rules, charts, logos, signatures, stamps, seals, watermarks | The page artwork: the page rendered with the editable text lifted out, anchored behind the text. |
| Text set at an angle (seal rings, stamps, diagonal watermarks) | Stays in the artwork instead of turning into stray letters. |
| Scanned pages and pictures of text | On-device OCR (Turkish and English); the recognised lines become editable text in their own ink colour, and the scan without that text becomes the artwork. |

Glyph positions come from PDFKit's per-character bounds, not from selection
boxes: PDFKit can join lines from neighbouring cells into one "line" (a
wrapped IBAN beside a vertically centred label) and report that line's box for
every glyph, which would interleave the two lines' characters.

Lifting text out of the artwork removes only pixels that match the glyph's ink
blended with its local background, then refills them from the clean pixels on
either side. A red seal or blue signature drawn over a line of text therefore
survives intact, and a watermark under the text stays continuous.

Boxes are read from the rendered page: one-colour runs stacked across pixel
rows give rules (thin) and fills (tall); a frame is a top and bottom rule
joined by vertical rules. Rounded shapes, boxes over pictures, boxes with
anything else drawn inside (a logo, a stamp), scans and pages under 300pt stay
in the artwork.

LibreOffice writes DOCX with the strict OOXML side names (`w:start`/`w:end`);
UForge rewrites them to `left`/`right`, which Google Docs and older Word
versions need to keep cell margins, indents and right-aligned amounts.

Pages export uses the same reconstruction without the artwork layer (Pages has
no page-anchored background); light text is then darkened to stay readable.

## Checking fidelity

`scripts/pdf-fidelity/run.sh` generates a corpus — report, contract, invoice,
bank receipt, scanned and mixed documents covering every case above, with
fictitious data — converts each to DOCX
with UForge's engine, re-exports the DOCX to PDF and writes, per page:

- a side-by-side image (original | Word) with a visual similarity score, and
- a drift report: how many points each line of text moved, and whether every
  run of digit-bearing tokens (IBANs, amounts, dates, reference numbers) of
  each source line appears, in order, in the output.

Output lands in `build/pdf-fidelity/compare/`. Unit tests for the individual
behaviours are in `Tests/NashiCoreTests/PDFLayoutReconstructionTests.swift`.
