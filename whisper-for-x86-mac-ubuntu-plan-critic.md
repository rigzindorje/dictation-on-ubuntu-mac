# Whisper Dictation Plan Review

## Overall Verdict

The plan is solid and well-suited to this machine. The hardware facts are accurate (confirmed: Ubuntu 22.04, x86_64, 4 threads, 17GB free, no CUDA, X11). The dependency inventory is correct — `xdotool`, `portaudio19-dev`, and `libsdl2-dev` are indeed missing; the rest is present. `build-essential` and `g++` are installed, which the plan doesn't mention but does need. Nothing in the plan is wrong or outdated.

That said, there are gaps worth knowing about before implementation.

---

## Missing Practical Details

### 1. Audio device selection

The machine has two capture devices: a built-in mic (HDA Intel PCH / CS4208) and a USB microphone. The plan never mentions how the script should pick one. `arecord` will use a default that may or may not be the USB mic. The script should either let the user configure the device or auto-select the USB mic when present — the USB mic will almost certainly produce better transcription.

### 2. Sample rate and format conversion

Whisper expects 16 kHz mono WAV. Both `arecord` and `pw-record` default to 44.1 kHz stereo. The script must either record at 16 kHz directly (`arecord -f S16_LE -r 16000 -c 1`) or convert with `ffmpeg` before passing to whisper-cli. This is a common gotcha that the plan skips over.

### 3. Non-ASCII typing (French/Italian accents)

`xdotool type` is unreliable with accented characters (é, è, ù, ç, ô, etc.). For a setup that explicitly targets French and Italian, this is not a second-milestone problem — it is a day-one problem. The clipboard path (`xclip` + `xdotool key ctrl+v`) should probably be the default, not the fallback.

### 4. No user feedback during recording/transcription

There is no mention of how the user knows that recording started, that it stopped, or that transcription is running. On a slow CPU where transcription may take several seconds, a visual or audio cue (e.g., `notify-send`, a beep, or a tray indicator) is important for usability.

### 5. Binary name after build

The plan references `whisper-cli`, but the actual binary name in whisper.cpp has changed over time (it was `main`, then `whisper-cli`, and may vary by version). The plan should verify the binary name after building rather than assume it.

---

## Risks Not Mentioned

### 1. Whisper hallucination on silence

This is the most significant unmentioned risk. Whisper is well-known for generating plausible but entirely fabricated text when given silent or near-silent audio. If the user triggers the hotkey by accident or pauses too long, the script could type garbage into the focused window. The script should detect silence (e.g., with `sox` or by checking audio levels) and skip transcription if the clip is essentially empty.

### 2. Wrong-window typing

Between the moment recording starts and the moment `xdotool` types the result (potentially 10+ seconds later), the user may have switched focus. The transcript could land in the wrong window — including a terminal, where it might be interpreted as commands. The script should either capture the target window ID at record-start (`xdotool getactivewindow`) and type into that specific window, or use clipboard paste which is less dangerous.

### 3. Stale lockfile

The plan mentions a lockfile to prevent overlapping runs, but does not address what happens if the script crashes or is killed, leaving a stale lockfile. Subsequent invocations would silently do nothing. Use `flock` on a file descriptor rather than manual touch/rm.

### 4. CPU thermal throttling

This is a Broadwell chip in a Mac chassis (the CS4208 codec and Iris 6100 confirm Mac hardware). These machines throttle aggressively under sustained CPU load. A 10-second clip processed with the `base` model could take noticeably longer than benchmarks suggest if the CPU is already warm. This reinforces the plan's fallback to `tiny`, but the plan frames it purely as a speed concern rather than a thermal one.

### 5. French/Italian language confusion

Whisper's auto-detection can confuse French and Italian on short utterances, since they share many cognates and phonetic patterns. The plan acknowledges short clips are error-prone but does not call out the specific FR/IT confusion risk. In practice, sentence-length clips should be fine, but one- or two-word utterances may get the wrong language (and therefore wrong spelling).

---

## Minor Notes

- The filename says "mac-ubuntu" — accurate (this is Mac hardware running Ubuntu), but worth being explicit about Mac-specific Linux quirks if any arise (e.g., function key behavior for hotkey binding).
- Disk space (17GB free) is fine for the models (~142MB for base, ~75MB for tiny) and the build, but with 83% usage it is worth monitoring.
- The plan's step ordering is good. Nothing is out of sequence.

---

## Summary

The plan is correct and actionable. The three things to promote from "later" to "do immediately" are:

1. **Use clipboard paste instead of `xdotool type`** — essential for French/Italian accents
2. **Add silence detection** — to prevent hallucinated text from being typed
3. **Capture the target window ID at record-start** — to prevent typing into the wrong window
