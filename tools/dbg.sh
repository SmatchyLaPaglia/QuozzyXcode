#!/bin/bash
# Run Lua inside the app on a connected device and print the result (see Quozzy.codea/DevRemote.lua).
#
#   tools/dbg.sh 'return state, #vsListEntries'
#   tools/dbg.sh -f snippet.lua
#   tools/dbg.sh --pull dbg_avatar1.png        # copy Documents/<file> to ./dbg_pull/
#   tools/dbg.sh --shot [name]                 # screenshot via pymobiledevice3 (needs tunneld)
#
# Env: DBG_DEVICE (default: Wes 16e's CoreDevice id), DBG_TIMEOUT seconds (default 10).
set -euo pipefail

DEVICE="${DBG_DEVICE:-5DD72C91-34E6-5481-923E-00A13C2BD042}"
BUNDLE="com.jessewonderclark.quozzyseasons"
TIMEOUT="${DBG_TIMEOUT:-10}"
WORK="${TMPDIR:-/tmp}/quozzy_dbg"
PMD3="${PMD3:-$HOME/Library/Python/3.9/bin/pymobiledevice3}"
mkdir -p "$WORK"

copy_from() {  # <Documents/relpath> <local dest>
  xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
    --domain-identifier "$BUNDLE" --source "$1" --destination "$2" >/dev/null 2>&1
}

case "${1:-}" in
  --pull)
    mkdir -p dbg_pull
    copy_from "Documents/$2" "dbg_pull/$2" && echo "dbg_pull/$2"
    exit ;;
  --shot)
    out="$WORK/${2:-shot}.png"
    "$PMD3" developer dvt screenshot --tunnel '' "$out" 2>&1 | grep -v -i warn || true
    echo "$out"
    exit ;;
  -f)
    code="$(cat "$2")" ;;
  "")
    echo "usage: $0 '<lua>' | -f file.lua | --pull name | --shot [name]" >&2; exit 2 ;;
  *)
    code="$1" ;;
esac

id="$(date +%s)$RANDOM"
printf -- '--id %s\n%s\n' "$id" "$code" > "$WORK/dbg_cmd.txt"
xcrun devicectl device copy to --device "$DEVICE" --domain-type appDataContainer \
  --domain-identifier "$BUNDLE" --source "$WORK/dbg_cmd.txt" --destination Documents/dbg_cmd.txt >/dev/null 2>&1

deadline=$((SECONDS + TIMEOUT))
while (( SECONDS < deadline )); do
  if copy_from Documents/dbg_out.txt "$WORK/dbg_out.txt" && head -1 "$WORK/dbg_out.txt" | grep -q -- "--id $id"; then
    tail -n +2 "$WORK/dbg_out.txt"
    exit 0
  fi
  sleep 0.5
done
echo "timed out after ${TIMEOUT}s (is the app in the foreground and the phone unlocked?)" >&2
exit 1
