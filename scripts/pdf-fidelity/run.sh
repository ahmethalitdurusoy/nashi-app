#!/bin/zsh
# PDF → Word fidelity check: build the corpus, convert each PDF to DOCX with
# UForge's own engine, re-export the DOCX to PDF with LibreOffice and write
# side-by-side comparisons plus a similarity score per page.
#   scripts/pdf-fidelity/run.sh [WORK_DIR]
set -euo pipefail
cd "${0:A:h:h:h}"
work=${1:-"$PWD/build/pdf-fidelity"}
tools="$work/tools" fixtures="$work/fixtures" docx="$work/docx" roundtrip="$work/roundtrip" report="$work/compare"
mkdir -p "$tools" "$docx" "$roundtrip" "$report"
for tool in make-fixtures render-pages compare drift; do
  swiftc -parse-as-library -O -o "$tools/$tool" "scripts/pdf-fidelity/$tool.swift"
done
"$tools/make-fixtures" "$fixtures" >/dev/null
swift build --product nashi-cli >/dev/null
cli="$(swift build --show-bin-path)/nashi-cli"
soffice=$("$cli" dependencies | python3 -c 'import json,sys;print(json.load(sys.stdin)["soffice"])')
# Same font folders the app gives LibreOffice, so the round trip renders with
# the document's real fonts instead of bundled look-alikes.
fontconf="$work/fonts.conf"
print -r -- "<?xml version=\"1.0\"?><fontconfig><dir>/System/Library/Fonts</dir><dir>/System/Library/Fonts/Supplemental</dir><dir>/Library/Fonts</dir><dir>$HOME/Library/Fonts</dir><dir>${soffice:h:h}/Resources/fonts</dir><cachedir>$HOME/Library/Caches/com.unqsoft.uforge/fontconfig</cachedir></fontconfig>" > "$fontconf"
for pdf in "$fixtures"/*.pdf; do
  name=${pdf:t:r}
  # Each run converts into its own folder so the newest DOCX is unambiguous.
  run_dir="$docx/$(date +%s)-$name";mkdir -p "$run_dir"
  "$cli" convert docx "$pdf" --options "{\"outputDirectory\":\"$run_dir\"}" >/dev/null
  cp "$(ls -t "$run_dir"/*.docx | /usr/bin/head -n 1)" "$docx/$name.docx"
  FONTCONFIG_FILE="$fontconf" "$soffice" --headless --norestore --convert-to pdf --outdir "$roundtrip" "$docx/$name.docx" >/dev/null 2>&1
  "$tools/compare" "$pdf" "$roundtrip/$name.pdf" "$report"
  "$tools/drift" "$pdf" "$roundtrip/$name.pdf" > "$report/$name-drift.txt" || true
done
print "Comparisons: $report"
