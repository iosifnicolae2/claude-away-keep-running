#!/bin/sh
# Mutes the Mac while away and puts its sound back after, even after a crash or reboot.
# Used by bin/away.sh (mute, restore) and hooks/register.ts at session start (recover).
# The volume and mute state from before away wait in $AWAY_STATE_DIR/sound-before-away
# (default ~/.cache/away-keep-running) until restored.
# Usage: sound.sh mute|restore|recover
#   mute     notes the volume and mute state (unless already noted: an away in progress or a crashed one), then mutes
#   restore  puts the noted volume and mute state back and forgets them
#   recover  restore, unless an away is in progress
osascript="${AWAY_OSASCRIPT:-osascript}"
state_dir="${AWAY_STATE_DIR:-$HOME/.cache/away-keep-running}"
saved="$state_dir/sound-before-away"

# "output volume:56, input volume:94, alert volume:100, output muted:false" -> "56 false"
current_sound() {
  settings="$("$osascript" -e 'get volume settings')" || return 1
  volume="$(printf '%s' "$settings" | sed -n 's/.*output volume:\([^,]*\).*/\1/p')"
  muted="$(printf '%s' "$settings" | sed -n 's/.*output muted:\([^,]*\).*/\1/p')"
  printf '%s %s\n' "${volume:-?}" "${muted:-?}"
}

mute() {
  if [ ! -s "$saved" ]; then
    sound="$(current_sound)" || exit 1
    mkdir -p "$state_dir" && printf '%s\n' "$sound" > "$saved.new" && mv "$saved.new" "$saved" || exit 1
  fi
  "$osascript" -e 'set volume with output muted'
}

restore() {
  [ -s "$saved" ] || exit 0
  read -r volume muted < "$saved"
  case "$volume" in ''|*[!0-9]*) ;; *) "$osascript" -e "set volume output volume $volume" ;; esac
  case "$muted" in
    true) "$osascript" -e 'set volume with output muted' ;;
    false) "$osascript" -e 'set volume without output muted' ;;
  esac
  rm -f "$saved"
}

# A running blackout (bin/blackout.js with a status file, not --restore or --plan) means away is on.
away_in_progress() {
  pgrep -f 'blackout\.js /' >/dev/null 2>&1
}

case "${1:-}" in
  mute) mute ;;
  restore) restore ;;
  recover) away_in_progress || restore ;;
  -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) echo "sound.sh: mute, restore or recover, got \"${1:-}\" (see --help)" >&2; exit 2 ;;
esac
