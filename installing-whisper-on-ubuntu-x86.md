# Installing Whisper.cpp Dictation on x86_64 Ubuntu

## Target System

- **Architecture**: x86_64
- **OS**: Ubuntu 20.04 / 22.04 / 24.04 LTS
- **GPU**: NVIDIA discrete GPU (any with CUDA support)
- **Display server**: X11

## Goal

System-wide real-time speech-to-text dictation into any focused window, using:
- **whisper.cpp** with CUDA for GPU-accelerated transcription
- **xdotool** to inject typed text into the active X11 window
- A USB microphone for audio capture

## Prerequisites

- sudo access
- Internet access
- A USB microphone plugged in (for actual dictation use — not needed for install/build)

## Step-by-Step Install

### 1. Install NVIDIA driver (skip if already installed)

Check if a driver is already present:
```bash
nvidia-smi
```

If not installed:
```bash
sudo apt-get update
sudo apt-get install -y nvidia-driver-550
sudo reboot
```

After reboot, verify:
```bash
nvidia-smi
# Should show your GPU and driver version
```

### 2. Install CUDA toolkit

Option A — from NVIDIA's apt repo (recommended):
```bash
# Add NVIDIA's package repo (Ubuntu 22.04 example — adjust for your version)
DISTRO=ubuntu2204
ARCH=x86_64
wget https://developer.download.nvidia.com/compute/cuda/repos/${DISTRO}/${ARCH}/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt-get update
sudo apt-get install -y cuda-toolkit
```

For Ubuntu 20.04 use `DISTRO=ubuntu2004`, for 24.04 use `DISTRO=ubuntu2404`.

Option B — install just the toolkit if driver is already present:
```bash
sudo apt-get install -y cuda-toolkit-12-6
```

Add CUDA to your PATH:
```bash
echo 'export PATH=/usr/local/cuda/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}' >> ~/.bashrc
source ~/.bashrc
```

Verify:
```bash
nvcc --version
```

### 3. Install CMake (>= 3.18 required)

Check your version first:
```bash
cmake --version
```

If >= 3.18, skip this step (Ubuntu 22.04+ ships 3.22+).

If on Ubuntu 20.04 (ships 3.16.3), install from Kitware:
```bash
sudo apt-get install -y gpg wget
wget -qO - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null \
  | gpg --dearmor - \
  | sudo tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null

echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/kitware.list

sudo apt-get update
sudo apt-get install -y cmake
```

### 4. Install build dependencies

```bash
sudo apt-get install -y \
    build-essential git \
    xdotool \
    portaudio19-dev libsdl2-dev \
    ffmpeg
```

### 5. Clone and build whisper.cpp with CUDA

```bash
cd ~
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp

cmake -B build \
    -DGGML_CUDA=ON \
    -DCMAKE_CUDA_ARCHITECTURES=native \
    -DWHISPER_SDL2=ON

cmake --build build -j$(nproc)
```

Notes:
- `CMAKE_CUDA_ARCHITECTURES=native` auto-detects your GPU. If that fails, set it manually based on your GPU:
  - GTX 10xx (Pascal): `"61"`
  - RTX 20xx (Turing): `"75"`
  - RTX 30xx (Ampere): `"86"`
  - RTX 40xx (Ada Lovelace): `"89"`
  - RTX 50xx (Blackwell): `"100"`

Verify CUDA linkage:
```bash
ldd build/bin/whisper-stream | grep cuda
# Should show libcudart, libcublas, libggml-cuda
```

Test with sample audio:
```bash
./build/bin/whisper-cli -m models/ggml-base.bin -f samples/jfk.wav
# Should print: "And so my fellow Americans ask not what your country can do for you..."
# Look for your GPU name and "compute capability" in the output
```

### 6. Download Whisper models

```bash
cd ~/whisper.cpp
bash models/download-ggml-model.sh base    # 147 MB — fastest, decent English
bash models/download-ggml-model.sh small   # 465 MB — better accuracy, multilingual
```

### 7. Create the dictation script

Create `~/dictate.sh`:

```bash
#!/bin/bash
# dictate.sh — Real-time speech-to-text dictation for any focused window
# Uses whisper.cpp (CUDA) + xdotool on X11
#
# Usage:
#   ./dictate.sh              # uses 'base' model (fastest)
#   ./dictate.sh small        # uses 'small' model (more accurate)
#
# Controls:
#   Ctrl+C to stop dictation

set -euo pipefail

WHISPER_DIR="$HOME/whisper.cpp"
MODEL="${1:-base}"
MODEL_PATH="$WHISPER_DIR/models/ggml-${MODEL}.bin"
STREAM_BIN="$WHISPER_DIR/build/bin/whisper-stream"

export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}

if [ ! -f "$STREAM_BIN" ]; then
    echo "ERROR: whisper-stream not found at $STREAM_BIN"
    exit 1
fi

if [ ! -f "$MODEL_PATH" ]; then
    echo "ERROR: Model not found at $MODEL_PATH"
    echo "Download it: cd $WHISPER_DIR && bash models/download-ggml-model.sh $MODEL"
    exit 1
fi

if ! command -v xdotool &>/dev/null; then
    echo "ERROR: xdotool not found. Install with: sudo apt install xdotool"
    exit 1
fi

if ! arecord -l 2>/dev/null | grep -q 'card'; then
    echo "WARNING: No audio capture devices found. Plug in a USB microphone."
    exit 1
fi

echo "=== Whisper Dictation ==="
echo "Model:  $MODEL ($MODEL_PATH)"
echo "GPU:    CUDA"
echo ""
echo "Speak into your microphone. Text will be typed into the focused window."
echo "Press Ctrl+C to stop."
echo "========================="
echo ""
echo ">>> Click on the window you want to dictate into... (2 seconds)"
sleep 2
echo ">>> Listening..."

"$STREAM_BIN" \
    -m "$MODEL_PATH" \
    --step 500 \
    --length 5000 \
    --keep 200 \
    --threads 2 \
    2>/dev/null | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^\[.*--\> ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue

    text="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$text" ]] && continue

    xdotool type --clearmodifiers --delay 12 -- "$text "
done
```

Make it executable:
```bash
chmod +x ~/dictate.sh
```

## Usage

```bash
# Plug in a USB mic, then:
./dictate.sh          # base model (fast, ~1-2s latency)
./dictate.sh small    # small model (better accuracy)
```

Click on any window after launch — dictated text is typed wherever the cursor is.

## Notes

- **No USB mic driver needed** — Linux `snd-usb-audio` handles virtually all USB microphones automatically.
- **Audio stack**: ALSA + PulseAudio (or PipeWire on Ubuntu 24.04) are pre-installed on standard Ubuntu desktop.
- **The `whisper-stream` binary uses GPU by default** — no explicit GPU flag needed. Use `--no-gpu` to force CPU-only.
- **Display server must be X11** for xdotool to work. If running Wayland (default on Ubuntu 22.04+), either:
  - Switch to X11 at the login screen (gear icon), or
  - Use `ydotool` instead of `xdotool` (requires `sudo apt install ydotool` and running `ydotoold` as a service).
- **No NVIDIA GPU?** whisper.cpp works on CPU too — skip the CUDA/driver steps and build with just `cmake -B build -DWHISPER_SDL2=ON`. Latency will be higher.
- **Disk usage**: CUDA toolkit ~5-6 GB, whisper.cpp build ~200 MB, models ~600 MB.

## Differences from the Jetson (ARM64) Guide

| Aspect | Jetson guide | This guide |
|---|---|---|
| CUDA install | `nvidia-jetpack` (Jetson-only) | `cuda-toolkit` from NVIDIA repo |
| NVIDIA driver | Pre-installed in L4T | Must install separately |
| GPU arch flag | `"87"` (Orin hardcoded) | `native` (auto-detect) |
| CMake fix | Always needed (Ubuntu 20.04) | Only needed on Ubuntu 20.04 |
| Wayland note | N/A (Jetson uses X11) | Ubuntu 22.04+ defaults to Wayland |
