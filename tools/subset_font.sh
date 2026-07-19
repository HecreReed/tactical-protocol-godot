#!/usr/bin/env bash
set -euo pipefail

source_url="https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf"
source_font="$(mktemp -t tactical-protocol-font.XXXXXX.otf)"
trap 'rm -f "${source_font}"' EXIT

curl --fail --location --silent --show-error "${source_url}" --output "${source_font}"
pyftsubset "${source_font}" \
  --output-file="assets/fonts/NotoSansSC-sub.otf" \
  --text="$(node tools/font_text.mjs)" \
  --layout-features='*' \
  --glyph-names \
  --symbol-cmap \
  --legacy-cmap \
  --notdef-glyph \
  --notdef-outline \
  --recommended-glyphs \
  --name-IDs='*' \
  --name-legacy \
  --name-languages='*'
