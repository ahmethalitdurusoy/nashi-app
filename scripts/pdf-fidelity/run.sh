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
for pdf in "$fixtures"/*.pdf; do
  name=${pdf:t:r}
  # Each run converts into its own folder so the newest DOCX is unambiguous.
  run_dir="$docx/$(date +%s)-$name";mkdir -p "$run_dir"
  "$cli" convert docx "$pdf" --options "{\"outputDirectory\":\"$run_dir\"}" >/dev/null
  cp "$(ls -t "$run_dir"/*.docx | /usr/bin/head -n 1)" "$docx/$name.docx"
  "$soffice" --headless --norestore --convert-to pdf --outdir "$roundtrip" "$docx/$name.docx" >/dev/null 2>&1
  "$tools/compare" "$pdf" "$roundtrip/$name.pdf" "$report"
  "$tools/drift" "$pdf" "$roundtrip/$name.pdf" > "$report/$name-drift.txt" || true
done
print "Comparisons: $report"
