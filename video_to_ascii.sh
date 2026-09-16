#!/usr/bin/env bash
# video_to_ascii.sh — TOUT-EN-UN : convertit une vidéo en animation ASCII
# Usage: ./video_to_ascii.sh <video.mp4> [largeur] [fps] [debut] [fin]
#   debut/fin au format ffmpeg : 95 (secondes), 1:35, ou 00:01:35
#   ex: ./video_to_ascii.sh video.mp4 100 10 1:35 1:45
set -euo pipefail

VIDEO="${1:?Usage: $0 <video.mp4> [largeur] [fps] [debut] [fin]}"
WIDTH="${2:-100}"
FPS="${3:-10}"
START="${4:-}"
END="${5:-}"

# Construit les options ffmpeg de découpage temporel
TIME_OPTS=()
if [[ -n "$START" ]]; then
    TIME_OPTS+=(-ss "$START")
fi
if [[ -n "$END" ]]; then
    TIME_OPTS+=(-to "$END")
fi

WORKDIR="$(mktemp -d)"
FRAMES_DIR="$WORKDIR/frames"
ASCII_DIR="$WORKDIR/ascii"
mkdir -p "$FRAMES_DIR" "$ASCII_DIR"

# --- Script Python embarqué (conversion image -> ASCII) ---
cat > "$WORKDIR/frame_to_ascii.py" <<'PYEOF'
import sys
from PIL import Image

CHARS = "@%#*+=-:. "

def frame_to_ascii(path, width=100):
    img = Image.open(path).convert("L")
    w, h = img.size
    new_h = int((h / w) * width * 0.5)
    img = img.resize((width, max(new_h, 1)))
    pixels = img.getdata()
    ramp_len = len(CHARS) - 1
    chars = [CHARS[int(p / 255 * ramp_len)] for p in pixels]
    lines = []
    for i in range(0, len(chars), width):
        lines.append("".join(chars[i:i + width]))
    return "\n".join(lines)

if __name__ == "__main__":
    print(frame_to_ascii(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 100))
PYEOF

echo "[1/3] Extraction des frames (${FPS} fps)${START:+, de $START à ${END:-la fin}}..."
ffmpeg -y -loglevel error "${TIME_OPTS[@]}" -i "$VIDEO" -vf "fps=${FPS}" "$FRAMES_DIR/frame_%05d.png"

FRAME_COUNT=$(ls "$FRAMES_DIR" | wc -l)
echo "[2/3] Conversion de ${FRAME_COUNT} frames en ASCII (largeur=${WIDTH})..."
i=0
for f in "$FRAMES_DIR"/frame_*.png; do
    i=$((i+1))
    printf "\r  frame %d/%d" "$i" "$FRAME_COUNT"
    python3 "$WORKDIR/frame_to_ascii.py" "$f" "$WIDTH" > "$ASCII_DIR/$(basename "${f%.png}").txt"
done
echo

echo "[3/3] Lecture (Ctrl+C pour quitter)..."
DELAY=$(python3 -c "print(1/${FPS})")
tput civis 2>/dev/null || true
trap 'tput cnorm 2>/dev/null || true' EXIT

for txt in "$ASCII_DIR"/frame_*.txt; do
    clear
    cat "$txt"
    sleep "$DELAY"
done

echo "Terminé. Frames ASCII conservées dans: $ASCII_DIR"
