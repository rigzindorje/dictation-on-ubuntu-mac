# Dictation On Ubuntu Mac

Local Whisper-based dictation prototype for an Intel Mac running Ubuntu X11.

## Current Status

This repository contains the wrapper scripts and notes for a working local dictation prototype.

What currently works:

- local audio capture
- local Whisper transcription with `whisper.cpp`
- multilingual dictation testing
- direct typing into at least some normal GUI text fields on X11

What is still rough:

- global hotkey integration is not stable on this machine
- terminal targets are unreliable and should not be treated as supported
- some GUI widgets may reject synthetic keyboard events

## Main Pieces

- `dictate-ptt.sh`
  The main push-to-talk style dictation wrapper.
- `run-dictate-ptt.sh`
  Small launcher wrapper that logs execution.
- `bind-dictation-hotkey.sh`
  Helper for GNOME custom shortcuts.
- `whisper-ptt.conf.example`
  Example runtime config for the wrapper script.
- `whisper-for-x86-mac-ubuntu.md`
  Main plan and machine-specific notes.
- `whisper-for-x86-mac-ubuntu-plan-critic.md`
  Critique and risks review of the original plan.

## Dependencies

System packages used by the wrapper:

- `xdotool`
- `xclip`
- `ffmpeg`
- `arecord`
- `notify-send`

Whisper engine:

- local `whisper.cpp` checkout in `whisper.cpp/`
- local GGML model files inside `whisper.cpp/models/`

## Configuration

The live runtime config is not stored in the repo. It lives at:

```bash
~/.config/whisper-ptt.conf
```

The tracked template is:

```bash
./whisper-ptt.conf.example
```

Typical settings include:

- Whisper repo location
- model selection
- recording duration
- recorder backend
- output mode

## Running It

Current practical way to test:

```bash
/home/g/tech/dictation-on-ubuntu-mac/run-dictate-ptt.sh
```

Suggested test target:

- a normal GUI editable field such as Chrome address bar, Gedit, or a browser text area

Avoid using a terminal as the first test target.

## Notes About Output

The current best output mode for this machine is direct typing into the focused X11 window after transcription.

That is configured through:

```bash
OUTPUT_MODE="type_current"
```

in the local runtime config.

## Repository Scope

This repo intentionally tracks the scripts, notes, and configuration template.

It does not try to vendor the full `whisper.cpp` source or built models as part of the committed history for portability reasons, even though a local checkout may exist in the project directory during development.
