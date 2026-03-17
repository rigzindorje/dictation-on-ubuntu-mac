#!/usr/bin/env bash

set -euo pipefail

LOG_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/whisper-ptt-launch.log"
mkdir -p "$(dirname "$LOG_FILE")"
printf '%s launcher start\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG_FILE"

exec /bin/bash /home/g/tech/dictation-on-ubuntu-mac/dictate-ptt.sh >>"$LOG_FILE" 2>&1
