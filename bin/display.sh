#!/bin/sh
# Runs the display helper (bin/display_helper.swift): the bundled universal binary while it matches the Swift
# source, else compiled once per version of the source when swiftc is there, else the bundled one anyway.
#   display.sh screens|virtuals|ddc
#   display.sh dim|undim <file> | off <file> <ids> <pid> | on <file>
# See the top of display_helper.swift for what each does.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"

binary() {
  bundled="$here/display_helper"
  sources() { cat "$here/display_helper.swift" "$here/display_helper.h"; }
  if [ -x "$bundled" ] && [ "$(sources | shasum -a 256 | cut -d' ' -f1)" = "$(cat "$here/display_helper.sha256" 2>/dev/null)" ]; then
    echo "$bundled"; return
  fi
  if ! command -v swiftc >/dev/null 2>&1; then
    [ -x "$bundled" ] || { echo "away-keep-running: no display helper; run scripts/build-display-helper.sh" >&2; return 1; }
    echo "$bundled"; return
  fi
  path="${XDG_CACHE_HOME:-$HOME/.cache}/away-keep-running/display_helper-$(sources | cksum | cut -d' ' -f1)"
  if [ ! -x "$path" ]; then
    mkdir -p "$(dirname "$path")"
    swiftc -O -import-objc-header "$here/display_helper.h" "$here/display_helper.swift" -o "$path.$$" >&2
    mv "$path.$$" "$path"
  fi
  echo "$path"
}

exe="$(binary)" || exit 1
case "${1:-}" in
  screens|virtuals|ddc|dim|undim|on) "$exe" "$@" ;;
  off) exec "$exe" "$@" ;;
  *) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
