#!/usr/bin/env bash
set -euo pipefail
export SERIAL=EC320125720
hex_file="${1:-build/market_pbl.hex}"
serial="${SERIAL:-}"
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tool_dir="$root_dir/siliconlabs-c8051-efm8-utils/c8051"
inspect_dir="$root_dir/siliconlabs-c8051-efm8-utils/inspect_c8051"

if [[ ! -f "$hex_file" ]]; then
    echo "hex file not found: $hex_file" >&2
    exit 1
fi

if [[ -z "$serial" ]]; then
    echo "Set SERIAL first. Detected adapters:" >&2
    LD_LIBRARY_PATH="$inspect_dir" "$inspect_dir/device8051" -slist >&2 || true
    echo "Example: SERIAL=EC3T0120100 make flash" >&2
    exit 2
fi

export LD_LIBRARY_PATH="$tool_dir:${LD_LIBRARY_PATH:-}"
exec "$tool_dir/flash8051" -sn "$serial" -tif c2 -erasemode full -upload "$hex_file"
