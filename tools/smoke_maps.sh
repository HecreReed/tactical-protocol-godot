#!/usr/bin/env bash
set -euo pipefail

godot_bin="${1:-godot}"
frames="${TP_SMOKE_FRAMES:-1800}"
timeout_seconds="${TP_SMOKE_TIMEOUT:-180}"
error_pattern='SCRIPT ERROR|ERROR:|Failed to load script|Parse Error|Compile Error'
map_ids="$(node -e "const c=require('./data/agents.json'); console.log(c.maps.join(' '))")"
map_count=0

for map_id in ${map_ids}; do
  log_file="/tmp/tactical-protocol-${map_id}.log"
  echo "Smoke testing ${map_id}"
  if command -v timeout >/dev/null 2>&1; then
    if ! env TP_AUTOSTART="${map_id}" timeout "${timeout_seconds}" "${godot_bin}" \
      --headless --path . --quit-after "${frames}" >"${log_file}" 2>&1; then
      cat "${log_file}"
      exit 1
    fi
  elif ! env TP_AUTOSTART="${map_id}" "${godot_bin}" \
    --headless --path . --quit-after "${frames}" >"${log_file}" 2>&1; then
    cat "${log_file}"
    exit 1
  fi

  if grep -qE "${error_pattern}" "${log_file}"; then
    grep -B1 -A3 -E "${error_pattern}" "${log_file}" | head -80
    exit 1
  fi
  if ! grep -q '\[BOOT\] menu built' "${log_file}"; then
    cat "${log_file}"
    echo "Game did not boot on ${map_id}" >&2
    exit 1
  fi
  if ! grep -q '\[TP\] t=8' "${log_file}"; then
    cat "${log_file}"
    echo "Match loop did not reach t=8 on ${map_id}" >&2
    exit 1
  fi
  map_count=$((map_count + 1))
done

if [[ "${map_count}" -ne 16 ]]; then
  echo "Expected 16 maps, smoked ${map_count}" >&2
  exit 1
fi

echo "Smoke tested ${map_count} maps"
