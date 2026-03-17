#!/usr/bin/env bash

set -euo pipefail

NAME="${1:-Whisper Dictation}"
COMMAND="${2:-$HOME/tech/dictation-on-ubuntu-mac/run-dictate-ptt.sh}"
BINDING="${3:-<Ctrl><Alt>space}"
BASE="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"
ENTRY="$BASE/whisper-dictation/"

existing="$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)"

if [[ "$existing" == "@as []" ]]; then
    updated="['$ENTRY']"
elif [[ "$existing" == *"$ENTRY"* ]]; then
    updated="$existing"
else
    updated="${existing%]}"
    updated="$updated, '$ENTRY']"
fi

gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$updated"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$ENTRY" name "$NAME"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$ENTRY" command "$COMMAND"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"$ENTRY" binding "$BINDING"

printf 'Bound %s to %s -> %s\n' "$NAME" "$BINDING" "$COMMAND"
