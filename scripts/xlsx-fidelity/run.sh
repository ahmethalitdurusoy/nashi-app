#!/bin/zsh
# Excel → PDF check: build the workbook corpus (also as .xls and .csv),
# convert each with UForge's engine and write a page summary plus a contact
# sheet (every page as a thumbnail) per PDF.
#   scripts/xlsx-fidelity/run.sh [WORK_DIR]
set -euo pipefail
cd "${0:A:h:h:h}"
work=${1:-"$PWD/build/xlsx-fidelity"}
tools="$work/tools" fixtures="$work/fixtures" pdf="$work/pdf" sheets="$work/contact"
mkdir -p "$tools" "$pdf" "$sheets"
for tool in pages contact; do swiftc -O -o "$tools/$tool" "scripts/xlsx-fidelity/$tool.swift"; done
python3 -I scripts/xlsx-fidelity/make-fixtures.py "$fixtures" >/dev/null
swift build --product nashi-cli >/dev/null
cli="$(swift build --show-bin-path)/nashi-cli"
for workbook in "$fixtures"/*.xlsx; do
  for format in xls csv; do "$cli" convert $format "$workbook" --options "{\"outputDirectory\":\"$fixtures/$format\"}" >/dev/null; done
done
for input in "$fixtures"/*.xlsx "$fixtures"/xls/*.xls "$fixtures"/csv/*.csv; do
  run_dir="$pdf/$(date +%s)-${input:t:r}-${input:e}"; mkdir -p "$run_dir"
  "$cli" convert pdf "$input" --options "{\"outputDirectory\":\"$run_dir\"}" >/dev/null
  result="$pdf/${input:t:r}-${input:e}.pdf"; cp "$(ls -t "$run_dir"/*.pdf | /usr/bin/head -n 1)" "$result"
  "$tools/pages" "$result"
  "$tools/contact" "$sheets/${input:t:r}-${input:e}.png" 6 "$result"
done
print "Contact sheets: $sheets"
