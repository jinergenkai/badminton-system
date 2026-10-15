import subprocess
import re
from pathlib import Path

# ===== CONFIG =====
INPUT_FILE = "en_full.mp3"           # đổi sang en_full.mp3 cho tiếng Anh
OUTPUT_DIR = "assets/audio/score/en"  # đổi sang .../en cho tiếng Anh
NAMES = [
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    "10", "11", "12", "13", "14", "15", "16", "17", "18", "19",
    "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "30",
    "all", "game_point", "match_point", "win"
]
SILENCE_THRESHOLD = "-35dB"
MIN_SILENCE_DURATION = "0.3"
PADDING = 0.05
# ==================

def detect_silences(input_file):
    cmd = [
        "ffmpeg", "-i", input_file,
        "-af", f"silencedetect=n={SILENCE_THRESHOLD}:d={MIN_SILENCE_DURATION}",
        "-f", "null", "-"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    output = result.stderr
    starts = [float(m) for m in re.findall(r"silence_start: ([\d.]+)", output)]
    ends = [float(m) for m in re.findall(r"silence_end: ([\d.]+)", output)]
    return starts, ends

def get_duration(input_file):
    cmd = ["ffprobe", "-v", "error", "-show_entries", "format=duration",
           "-of", "default=noprint_wrappers=1:nokey=1", input_file]
    return float(subprocess.run(cmd, capture_output=True, text=True).stdout.strip())

def main():
    Path(OUTPUT_DIR).mkdir(parents=True, exist_ok=True)
    starts, ends = detect_silences(INPUT_FILE)
    duration = get_duration(INPUT_FILE)

    segments = []
    if starts and starts[0] < 0.1:
        prev_end = ends[0]
        starts, ends = starts[1:], ends[1:]
    else:
        prev_end = 0.0
    for s, e in zip(starts, ends):
        segments.append((prev_end, s))
        prev_end = e
    if prev_end < duration - 0.1:
        segments.append((prev_end, duration))

    print(f"Detected {len(segments)} segments, expecting {len(NAMES)}")
    if len(segments) != len(NAMES):
        print("⚠️ Mismatch! Segments detected:")
        for i, (s, e) in enumerate(segments):
            print(f"  [{i}] {s:.2f}s - {e:.2f}s (dur {e-s:.2f}s)")
        print("\n→ Tune SILENCE_THRESHOLD hoặc MIN_SILENCE_DURATION rồi chạy lại")
        return

    for name, (start, end) in zip(NAMES, segments):
        start = max(0, start - PADDING)
        end = min(duration, end + PADDING)
        out = f"{OUTPUT_DIR}/{name}.mp3"
        subprocess.run([
            "ffmpeg", "-y", "-i", INPUT_FILE,
            "-ss", str(start), "-to", str(end),
            "-c:a", "libmp3lame", "-b:a", "96k",
            out
        ], capture_output=True)
        print(f"✓ {name}.mp3  ({end-start:.2f}s)")

if __name__ == "__main__":
    main()