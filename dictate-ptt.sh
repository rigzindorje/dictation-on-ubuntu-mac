#!/usr/bin/env bash

set -euo pipefail

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/whisper-ptt.conf"
LOG_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/whisper-ptt.log"

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

WHISPER_DIR="${WHISPER_DIR:-$HOME/whisper.cpp}"
WHISPER_MODEL="${WHISPER_MODEL:-tiny}"
WHISPER_THREADS="${WHISPER_THREADS:-4}"
RECORD_SECONDS="${RECORD_SECONDS:-10}"
TARGET_DELAY_SECONDS="${TARGET_DELAY_SECONDS:-2}"
RECORDER="${RECORDER:-arecord}"
ARECORD_DEVICE="${ARECORD_DEVICE:-}"
SILENCE_MAX_DB="${SILENCE_MAX_DB:--45}"
NOTIFY="${NOTIFY:-1}"
OUTPUT_MODE="${OUTPUT_MODE:-clipboard}"

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
fi

export DISPLAY="${DISPLAY:-:0}"
if [[ -z "${XAUTHORITY:-}" && -f "$HOME/.Xauthority" ]]; then
    export XAUTHORITY="$HOME/.Xauthority"
fi

notify() {
    if [[ "$NOTIFY" == "1" ]] && command -v notify-send >/dev/null 2>&1; then
        notify-send "Whisper Dictation" "$1" >/dev/null 2>&1 || true
    fi
}

log() {
    mkdir -p "$(dirname "$LOG_FILE")"
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$LOG_FILE"
}

log "Startup DISPLAY=${DISPLAY:-unset} XAUTHORITY=${XAUTHORITY:-unset} PATH=$PATH"

fail() {
    log "ERROR: $1"
    notify "$1"
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

if [[ -x "$WHISPER_DIR/build/bin/whisper-cli" ]]; then
    WHISPER_BIN="$WHISPER_DIR/build/bin/whisper-cli"
elif command -v whisper-cli >/dev/null 2>&1; then
    WHISPER_BIN="$(command -v whisper-cli)"
else
    fail "whisper-cli not found. Build whisper.cpp first."
fi

MODEL_PATH="${MODEL_PATH:-$WHISPER_DIR/models/ggml-${WHISPER_MODEL}.bin}"
[[ -f "$MODEL_PATH" ]] || fail "Model file not found: $MODEL_PATH"

require_cmd ffmpeg
require_cmd flock
if [[ "$OUTPUT_MODE" == "paste" || "$OUTPUT_MODE" == "type_current" ]]; then
    require_cmd xdotool
fi

if [[ "$OUTPUT_MODE" == "clipboard" || "$OUTPUT_MODE" == "paste" ]]; then
    require_cmd xclip
fi

case "$RECORDER" in
    arecord)
        require_cmd arecord
        ;;
    pw-record)
        require_cmd pw-record
        require_cmd timeout
        ;;
    ffmpeg)
        ;;
    *)
        fail "Unsupported RECORDER value: $RECORDER"
        ;;
esac

lock_file="${XDG_RUNTIME_DIR:-/tmp}/whisper-ptt.lock"
exec 9>"$lock_file"
if ! flock -n 9; then
    log "Skipped because another dictation run is active"
    notify "Dictation is already running"
    exit 0
fi

workdir="$(mktemp -d "${TMPDIR:-/tmp}/whisper-ptt.XXXXXX")"
cleanup() {
    rm -rf "$workdir"
}
trap cleanup EXIT

input_wav="$workdir/input.wav"
transcript_base="$workdir/transcript"
transcript_file="${transcript_base}.txt"
clipboard_backup="$workdir/clipboard.txt"
last_transcript_file="${XDG_CACHE_HOME:-$HOME/.cache}/whisper-ptt-last.txt"

if [[ "$TARGET_DELAY_SECONDS" != "0" ]]; then
    notify "Focus the target window now"
    sleep "$TARGET_DELAY_SECONDS"
fi

detect_target_window() {
    local window_id=""
    local attempt

    for attempt in 1 2 3 4 5; do
        window_id="$(xdotool getactivewindow 2>/dev/null || true)"
        if [[ -n "$window_id" ]]; then
            printf '%s\n' "$window_id"
            return 0
        fi

        window_id="$(xdotool getwindowfocus 2>/dev/null || true)"
        if [[ -n "$window_id" && "$window_id" != "0" ]]; then
            printf '%s\n' "$window_id"
            return 0
        fi

        sleep 0.1
    done

    return 1
}

target_window=""
if [[ "$OUTPUT_MODE" == "paste" ]]; then
    target_window="$(detect_target_window || true)"
    [[ -n "$target_window" ]] || fail "No active X11 window found"
    log "Target window id=$target_window"
fi

if [[ "$OUTPUT_MODE" == "clipboard" || "$OUTPUT_MODE" == "paste" ]]; then
    if xclip -selection clipboard -o >"$clipboard_backup" 2>/dev/null; then
        clipboard_had_text=1
    else
        clipboard_had_text=0
    fi
fi

record_with_arecord() {
    local -a cmd=(arecord -q -f S16_LE -r 16000 -c 1 -d "$RECORD_SECONDS")
    if [[ -n "$ARECORD_DEVICE" ]]; then
        cmd+=(-D "$ARECORD_DEVICE")
    fi
    cmd+=("$input_wav")
    "${cmd[@]}"
}

record_with_ffmpeg() {
    local source="${FFMPEG_INPUT:-default}"
    ffmpeg -hide_banner -loglevel error -y \
        -f pulse -i "$source" \
        -ac 1 -ar 16000 -c:a pcm_s16le -t "$RECORD_SECONDS" \
        "$input_wav"
}

record_with_pw_record() {
    local -a cmd=(pw-record --rate 16000 --channels 1 --format s16)
    if [[ -n "${PW_RECORD_TARGET:-}" ]]; then
        cmd+=(--target "$PW_RECORD_TARGET")
    fi
    cmd+=("$input_wav")
    timeout --signal=INT "${RECORD_SECONDS}s" "${cmd[@]}"
}

check_audio_level() {
    local volume
    volume="$(
        ffmpeg -hide_banner -i "$input_wav" -af volumedetect -f null - 2>&1 \
            | awk -F': ' '/max_volume/ {print $2}' \
            | tail -n 1
    )"

    if [[ -z "$volume" || "$volume" == "-inf dB" ]]; then
        return 1
    fi

    local numeric
    numeric="$(printf '%s' "$volume" | awk '{print $1}')"
    awk -v observed="$numeric" -v limit="$SILENCE_MAX_DB" 'BEGIN { exit !(observed > limit) }'
}

restore_clipboard() {
    if [[ "${clipboard_had_text:-0}" == "1" ]]; then
        xclip -selection clipboard -in -loops 1 <"$clipboard_backup" 9>&- >/dev/null 2>&1 &
    fi
}

window_class() {
    xdotool getwindowclassname "$target_window" 2>/dev/null || true
}

paste_text() {
    local text="$1"
    local klass
    klass="$(window_class)"
    log "Target window class=${klass:-unknown}"

    printf '%s' "$text" | xclip -selection clipboard -in -loops 1 9>&- >/dev/null 2>&1 &
    local xclip_pid=$!

    xdotool windowactivate --sync "$target_window" || true
    sleep 0.1

    case "$klass" in
        gnome-terminal-server|Gnome-terminal|XTerm|xterm|Tilix|tilix|Konsole|konsole|Alacritty|alacritty|xfce4-terminal|mate-terminal)
            xdotool key --window "$target_window" --clearmodifiers ctrl+shift+v || \
                xdotool key --window "$target_window" --clearmodifiers Shift+Insert || true
            ;;
        *)
            xdotool key --window "$target_window" --clearmodifiers ctrl+v || \
                xdotool key --window "$target_window" --clearmodifiers Shift+Insert || true
            ;;
    esac

    wait "$xclip_pid" || true
}

copy_to_clipboard() {
    local text="$1"
    pkill -f '^xclip -selection clipboard' >/dev/null 2>&1 || true
    printf '%s' "$text" >"$last_transcript_file"
    xclip -selection clipboard -in <"$last_transcript_file" 9>&- >/dev/null 2>&1 &
}

type_into_current_window() {
    local text="$1"
    local current_window
    current_window="$(detect_target_window || true)"
    [[ -n "$current_window" ]] || fail "No active X11 window found for typing"
    log "Typing into current window id=$current_window"
    xdotool type --window "$current_window" --clearmodifiers --delay 1 -- "$text"
}

notify "Recording for up to ${RECORD_SECONDS}s"
log "Recording started with recorder=$RECORDER model=$WHISPER_MODEL seconds=$RECORD_SECONDS"
case "$RECORDER" in
    arecord)
        record_with_arecord
        ;;
    pw-record)
        record_with_pw_record
        ;;
    ffmpeg)
        record_with_ffmpeg
        ;;
esac

if ! check_audio_level; then
    log "Skipped near-silent audio"
    restore_clipboard
    notify "Skipped empty or near-silent audio"
    exit 0
fi

notify "Transcribing with ${WHISPER_MODEL}"
log "Transcription started"
"$WHISPER_BIN" \
    -m "$MODEL_PATH" \
    -l auto \
    -nt \
    -np \
    -ng \
    -otxt \
    -t "$WHISPER_THREADS" \
    -of "$transcript_base" \
    "$input_wav" >/dev/null

[[ -f "$transcript_file" ]] || fail "Whisper did not produce a transcript file"

transcript="$(
    sed -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//' "$transcript_file"
)"

if [[ -z "$transcript" ]]; then
    log "No speech recognized"
    restore_clipboard
    notify "No speech recognized"
    exit 0
fi

if [[ "$OUTPUT_MODE" == "paste" ]]; then
    paste_text "$transcript"
    restore_clipboard
    log "Transcript pasted: $transcript"
    notify "Pasted transcript"
elif [[ "$OUTPUT_MODE" == "type_current" ]]; then
    printf '%s' "$transcript" >"$last_transcript_file"
    type_into_current_window "$transcript"
    log "Transcript typed into current window: $transcript"
    notify "Typed transcript"
else
    copy_to_clipboard "$transcript"
    log "Transcript copied to clipboard: $transcript"
    notify "Transcript copied to clipboard"
fi
