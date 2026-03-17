# Whisper Dictation Plan for This x86 Ubuntu Machine

## Goal

Set up fully local push-to-talk dictation on this Ubuntu x86_64 computer using Whisper, with:

- one hotkey to start dictation
- no language-switch key
- automatic detection of English, French, or Italian per utterance
- typed output into the currently focused X11 window

This plan is for the current machine, not a generic CUDA system.

## Current Implementation Status

Implemented locally:

- `/home/g/whisper.cpp` cloned
- CPU-only `whisper.cpp` build completed
- multilingual `base` and `tiny` models downloaded
- `/home/g/dictate-ptt.sh` created
- `/home/g/.config/whisper-ptt.conf.example` created
- `/home/g/bind-dictation-hotkey.sh` created

Still required:

- install `xdotool`
- install `xclip`
- install `portaudio19-dev` and `libsdl2-dev` if you want the remaining system dependencies from the original build plan

## Current Machine State

- OS: Ubuntu 22.04.4 LTS
- Architecture: x86_64
- Session type: X11
- CPU: Intel Core i7-5557U, 2 cores / 4 threads
- RAM: 16 GB
- Free disk space: about 17 GB on `/`
- GPU: Intel Iris 6100
- NVIDIA/CUDA: not present

### Important Consequence

The earlier CUDA-oriented Whisper plan does not match this computer.

This machine should use:

- CPU-only `whisper.cpp`
- push-to-talk, not continuous realtime streaming
- a multilingual model with automatic language detection

## Recommended Approach

Use `whisper.cpp` locally on CPU, with:

- `xclip` plus `xdotool` for clipboard-based paste into the focused X11 window
- `ffmpeg`, `arecord`, or `pw-record` to capture one utterance at a time
- a multilingual Whisper model so the speaker can begin in English, French, or Italian without manually selecting a language
- explicit audio normalization to 16 kHz mono WAV
- silence detection before transcription
- captured target-window handling so the transcript returns to the intended app
- visible status feedback during record and transcription

## Why Push-to-Talk

Push-to-talk is the right fit for this machine because:

- it is much lighter than continuous streaming
- it avoids realtime CPU pressure on an older dual-core mobile CPU
- it usually improves transcription quality because each utterance is processed as a complete chunk
- it simplifies language auto-detection

## Language Requirement

The dictation setup should support:

- English
- French
- Italian

The user should not need to press a separate key or choose a language in advance.

That means:

- do not use English-only models such as `tiny.en` or `base.en`
- use a multilingual model such as `tiny`, `base`, or `small`
- do not force a `--language` setting during transcription
- let Whisper auto-detect the language from each utterance

## Model Recommendation

### First Choice

Start with multilingual `base`.

Reason:

- better multilingual accuracy than `tiny`
- still realistic for short push-to-talk utterances on this machine

### Fallback

Keep multilingual `tiny` available.

Use it if:

- `base` feels too slow
- turnaround time becomes annoying in normal use

### Not Recommended Initially

Do not start with multilingual `small`.

Reason:

- likely too slow on this CPU for a comfortable dictation loop

## Dependencies

Already present:

- `cmake`
- `git`
- `ffmpeg`
- `arecord`
- `pw-record`

Still needed:

- `xdotool`
- `xclip`
- `portaudio19-dev`
- `libsdl2-dev`

Optional but useful:

- `sox`

## High-Level Workflow

The desired dictation flow is:

1. Press one hotkey.
2. Record one spoken utterance.
3. Stop recording automatically or on a second keypress.
4. Run Whisper locally on the recorded clip.
5. Let Whisper auto-detect whether the utterance is English, French, or Italian.
6. Paste the transcript back into the captured target window.

## Hotkey Design Options

### Option A: Fixed Recording Window

- Press hotkey once.
- Record for a fixed duration, such as 8 to 12 seconds.
- Stop automatically.
- Transcribe and type the result.

This is the recommended first implementation.

Reason:

- simplest to build
- easiest to bind from Ubuntu keyboard shortcuts
- less background state management

### Option B: Toggle Start/Stop with the Same Hotkey

- First press starts recording.
- Second press stops recording.
- The clip is transcribed and typed.

This is a better long-term interaction model, but it is more complex to implement cleanly.

Reason:

- needs a background state mechanism
- needs reliable process coordination
- is more work than a fixed-window first version

## Implementation Plan

### Step 1: Install Missing Packages

Install the missing system packages:

```bash
sudo apt install xdotool xclip portaudio19-dev libsdl2-dev
```

Optional:

```bash
sudo apt install xclip sox
```

### Step 2: Clone `whisper.cpp`

Place the repo at:

```bash
/home/g/whisper.cpp
```

### Step 3: Build `whisper.cpp` for CPU Only

Do not use CUDA flags.

Expected build pattern:

```bash
cd ~/whisper.cpp
cmake -B build -DWHISPER_SDL2=ON
cmake --build build -j$(nproc)
```

### Step 4: Download Multilingual Models

Download:

- `base`
- optionally `tiny` as a fallback

Expected pattern:

```bash
cd ~/whisper.cpp
bash models/download-ggml-model.sh base
bash models/download-ggml-model.sh tiny
```

### Step 5: Verify Basic Transcription

Before any hotkey integration, verify that transcription works with a sample file or a short microphone recording.

Success criteria:

- English phrase transcribes correctly
- French phrase transcribes correctly
- Italian phrase transcribes correctly

### Step 6: Create a Push-to-Talk Script

Create a script such as:

```bash
~/dictate-ptt.sh
```

Responsibilities of the script:

- create a temporary WAV file
- capture the currently active X11 window ID before recording
- record one utterance
- normalize audio to 16 kHz mono WAV
- detect silence or near-silence and skip transcription if the clip is empty
- run `whisper-cli` on the WAV file
- allow automatic language detection
- clean the transcript text
- copy the transcript to the clipboard
- paste into the captured X11 window using `xdotool`
- show user feedback while recording and while transcribing
- remove temporary files
- avoid overlapping runs with `flock`

### Step 7: Start with a Fixed-Duration Version

The first version should use:

- one hotkey
- a recording limit such as 10 seconds
- automatic transcription after recording ends

This is the fastest path to a usable prototype.

### Step 8: Bind the Script to a GNOME Shortcut

Use Ubuntu custom keyboard shortcuts to launch the script.

Candidate keys:

- `Ctrl+Alt+Space`
- `Pause`
- another unused function-key combination

### Step 9: Test Real Usage

Test dictation into:

- a text editor
- a browser text box
- a notes app
- a terminal, if desired

Validate:

- transcript quality
- transcription delay
- language auto-detection
- typing behavior in different applications

### Step 10: Tune for Practical Use

If `base` is too slow:

- switch to `tiny`

If fixed recording is awkward:

- move to a toggle start/stop implementation

If apps reject synthetic typing:

- add an alternate paste path or direct typing fallback

## Audio Device Selection

The script should not blindly trust the default recording device.

Requirements:

- allow a configured capture device
- prefer a USB microphone when the user chooses one
- make the recording device easy to change without editing core logic

Implementation preference:

- read an optional environment variable or small config file for the preferred device
- fall back to the system default if no explicit device is configured

## Audio Format Requirement

Whisper works best with 16 kHz mono WAV input.

The script should enforce that explicitly rather than rely on recorder defaults.

Practical rule:

- record directly as `S16_LE`, 16 kHz, mono when possible
- otherwise convert with `ffmpeg` before transcription

## Script Design Notes

The first script should be simple and robust rather than clever.

Recommended properties:

- no CUDA assumptions
- no hardcoded language
- no continuous microphone streaming
- clipboard paste as the default output path for accented characters
- capture the target window before recording starts
- skip empty or near-silent audio
- clear user-facing errors for missing model or missing binaries
- user feedback with notifications while recording and transcribing
- `flock` so repeated hotkey presses do not spawn overlapping jobs
- a temp directory under `/tmp`

## Auto Language Detection Notes

Whisper can auto-detect language per utterance, but detection quality depends on clip length.

Implications:

- short one-word clips are more error-prone
- full phrases work better
- French and Italian should be handled well with a multilingual model
- proper names may still be imperfect

Practical advice:

- expect better results from sentence-length speech than from isolated words

## Safety Risks to Handle in the First Version

### Silence Hallucination

Whisper can fabricate text from silent or extremely weak audio.

Mitigation:

- perform a silence or audio-level check before transcription
- skip pasting if the clip is effectively empty

### Wrong-Window Pasting

The user may change focus while recording or while the CPU is still transcribing.

Mitigation:

- capture the active window ID at record start
- paste back to that exact window instead of whichever window is active later

### Stale Lockfiles

A manual lockfile can get stuck after a crash.

Mitigation:

- use `flock` on a lock file descriptor instead of touch/rm lockfile logic

## What Not to Do on This Machine

Do not:

- install NVIDIA drivers for this task
- install CUDA for this task
- follow the CUDA-specific sections of the earlier Whisper note
- start with continuous realtime dictation
- start with English-only Whisper models
- rely on `xdotool type` as the default for multilingual text

## First Milestone

The first milestone should be:

- CPU-only `whisper.cpp`
- multilingual `base`
- one hotkey
- fixed 10-second push-to-talk recording window
- automatic language detection
- clipboard-based paste into the captured X11 window
- silence protection
- visible record/transcribe feedback

That version is enough to prove the full workflow.

## Second Milestone

Once the first milestone works, improve usability by choosing one of these:

- switch to `tiny` if speed matters more than accuracy
- build a toggle start/stop hotkey flow
- add silence-based early stopping
- add clipboard fallback for apps that misbehave with `xdotool`

## Main Risk

The main risk is not compatibility. The machine should support local dictation.

The main risk is turnaround time on multilingual models because this is an older CPU.

That is why the build order should be:

1. try multilingual `base`
2. measure responsiveness
3. drop to multilingual `tiny` if needed

## Concrete Next Actions

1. Install `xdotool`, `portaudio19-dev`, and `libsdl2-dev`.
2. Clone `whisper.cpp`.
3. Build it in CPU-only mode.
4. Download multilingual `base`.
5. Verify transcription manually.
6. Create a first fixed-window push-to-talk script.
7. Bind it to a GNOME keyboard shortcut.
8. Tune model choice and utterance length based on real use.
