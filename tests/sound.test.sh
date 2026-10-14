#!/bin/sh
# Tests bin/sound.sh against a fake osascript, so the real volume is never touched.
# Run: sh tests/sound.test.sh   (prints one line per test, exits 1 if any fails)
sound="$(cd "$(dirname "$0")/.." && pwd)/bin/sound.sh"
UNMUTED='output volume:56, input volume:94, alert volume:100, output muted:false'
MUTED='output volume:30, input volume:94, alert volume:100, output muted:true'
failures=0
root="$(mktemp -d -t away-sound)"
trap 'rm -rf "$root"' EXIT

# A fresh fake host reporting $1 as its volume settings; logs every AppleScript it is given.
host() {
  dir="$(mktemp -d "$root/host.XXXXXX")"
  saved="$dir/state/sound-before-away"
  log="$dir/osascript.log"
  : > "$log"
  cat > "$dir/osascript" <<FAKE
#!/bin/sh
printf '%s\n' "\$2" >> '$log'
[ "\$2" = 'get volume settings' ] && printf '%s\n' '$1'
exit 0
FAKE
  chmod +x "$dir/osascript"
}
sound() { AWAY_OSASCRIPT="$dir/osascript" AWAY_STATE_DIR="$dir/state" sh "$sound" "$@"; }
said() { paste -sd'|' "$log"; }
check() { # name, actual, expected
  if [ "$2" = "$3" ]; then echo "(pass) $1"; else echo "(fail) $1: got \"$2\", want \"$3\""; failures=$((failures + 1)); fi
}

host "$UNMUTED"; sound mute
check 'mute notes the volume on disk, then mutes' "$(cat "$saved")|$(said)" \
  '56 false|get volume settings|set volume with output muted'

host "$UNMUTED"; sound mute; : > "$log"; sound restore
check 'restore puts the volume back and unmutes, then forgets it' "$(said)|$([ -e "$saved" ] && echo kept)" \
  'set volume output volume 56|set volume without output muted|'

host "$MUTED"; sound mute; : > "$log"; sound restore
check 'a Mac muted before away stays muted after' "$(said)" \
  'set volume output volume 30|set volume with output muted'

host "$MUTED"; mkdir -p "$dir/state"; echo '56 false' > "$saved"; sound mute
check 'a second mute keeps the state noted first (an away in progress, or one that crashed)' "$(cat "$saved")|$(said)" \
  '56 false|set volume with output muted'

host "$MUTED"; mkdir -p "$dir/state"; echo '56 false' > "$saved"; sound recover
check 'recover restores what a crashed away left on disk' "$(said)|$([ -e "$saved" ] && echo kept)" \
  'set volume output volume 56|set volume without output muted|'

host "$MUTED"; mkdir -p "$dir/state"; echo '56 false' > "$saved"
sh -c 'sleep 2; :' 'blackout.js /status' & away=$!  # looks like a running blackout to pgrep
sleep 0.2; sound recover; kill "$away"; wait "$away" 2>/dev/null
check 'recover leaves the sound muted while an away is on' "$(said)|$(cat "$saved")" '|56 false'

host "$UNMUTED"; sound restore
check 'restore with nothing noted does nothing' "$(said)" ''

host 'output volume:missing value, input volume:94, alert volume:100, output muted:missing value'
sound mute; : > "$log"; sound restore
check 'an output that reports no volume is left alone' "$(said)" ''

host "$UNMUTED"; sound bogus 2>/dev/null
check 'an unknown command is refused' "$?" 2

exit $((failures > 0))
