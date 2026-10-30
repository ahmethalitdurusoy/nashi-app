# Excel → PDF

Workbooks (`.xlsx`, `.xlsm`, `.xls`) and CSV/TSV files are printed to PDF by
LibreOffice. Most workbooks are never set up for printing, and printed as they
are, their PDF splits wide tables down the middle (the rows on some pages, the
remaining columns on others), shows the header row only on page one and has no
page numbers. Before printing, UForge gives every visible sheet that has no
print setup of its own what a person would pick in Excel's Page Setup.

| Sheet | Printed as |
| --- | --- |
| Wider than a portrait page | Landscape, all columns scaled onto one page width. |
| So wide that one page width would shrink the text below ~55% | A few page widths at a readable size, each repeating the first (label) column. |
| Taller than a page | The header row repeats on every page: the frozen top row, or else the first row of bold or shaded labels (for CSV/TSV, the first row). |
| Any | A small footer with the sheet name and "page / pages". |

Whatever the workbook sets itself is kept: fit-to-page or a scale, landscape,
print titles, and headers or footers with text. Hidden sheets and hidden
columns stay out of the PDF; formulas print their values; charts, merged cells,
fills, borders and number formats (currency, dates, percentages) print as in
Excel. `.xls` and CSV files are first read into a workbook so they get the same
treatment.

## Checking

`scripts/xlsx-fidelity/run.sh` builds a corpus of workbooks with fictitious
data — a sales report (merged title, formulas, ₺ currency, dates, percentages,
status colours, wrapped notes, a hidden column, frozen header), a summary with a
chart, a 30-column sheet, a 300-row list, a hidden sheet, and a workbook with its
own page setup — also as `.xls` and `.csv`, converts each to PDF and writes a
page summary and a contact sheet of every page to `build/xlsx-fidelity/`. Unit
tests are in `Tests/NashiCoreTests/SpreadsheetPrintSetupTests.swift`.
