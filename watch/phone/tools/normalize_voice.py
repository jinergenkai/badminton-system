"""Make every bundled voice clip equally loud, and loud enough to sit over music.

Reads the untouched originals in audio_src/ and writes processed copies into
assets/audio/. Always works from the originals, so it can be re-run with new
targets without compressing twice.

Per clip:
  1. trim leading/trailing silence (shorter, snappier score calls)
  2. compress (speech has gaps; music does not - density is what reads as loud)
  3. gain to a target mean level, measured on the compressed clip
  4. limit peaks to -1 dBFS so the gain never clips

Usage:  python tools/normalize_voice.py            (from bandcounter-flutter/)
        python tools/normalize_voice.py --dry-run  (report only)

Measured before this existed (mean / max dB): score vi -11.7..-13.7 / -1.4,
score en -17.2, hype -13.9..-19.5, bundled music -10.1..-13.5.
"""
import os
import re
import shutil
import subprocess
import sys

FFMPEG = os.environ.get('FFMPEG') or shutil.which('ffmpeg') or 'ffmpeg'

# (source dir under audio_src, output dir, target mean dB)
SETS = [
    ('score/vi', 'assets/audio/score/vi', -9.0),
    ('score/en', 'assets/audio/score/en', -9.0),
    ('hype', 'assets/audio/hype', -10.0),
    ('hype/female_pack', 'assets/audio/hype/female_pack', -10.0),
]

TRIM = ('silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.03,'
        'areverse,'
        'silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.06,'
        'areverse')
COMPRESS = 'acompressor=threshold=-20dB:ratio=3:attack=5:release=60'
LIMIT = 'alimiter=limit=0.841:level=false'  # 0.841 = -1.5 dBFS: MP3 re-encode overshoots ~1 dB


def mean_max(path, pre_filter=''):
    af = (pre_filter + ',' if pre_filter else '') + 'volumedetect'
    out = subprocess.run([FFMPEG, '-hide_banner', '-nostats', '-i', path, '-af', af,
                          '-f', 'null', '-'], capture_output=True, text=True).stderr
    mean = re.search(r'mean_volume: (-?[\d.]+) dB', out)
    peak = re.search(r'max_volume: (-?[\d.]+) dB', out)
    return (float(mean.group(1)) if mean else None, float(peak.group(1)) if peak else None)


def process(src, dst, target):
    base = TRIM + ',' + COMPRESS
    m, _ = mean_max(src, base)
    if m is None:
        return None
    gain = target - m
    chain = f'{base},volume={gain:.1f}dB,{LIMIT}'
    subprocess.run([FFMPEG, '-hide_banner', '-loglevel', 'error', '-y', '-i', src,
                    '-af', chain, '-c:a', 'libmp3lame', '-b:a', '128k', dst], check=True)
    return gain


def main():
    dry = '--dry-run' in sys.argv
    print(f'{"file":44} {"before":>14} {"gain":>7} {"after":>14}')
    for sub, out_dir, target in SETS:
        src_dir = os.path.join('audio_src', sub)
        if not os.path.isdir(src_dir):
            print(f'-- missing {src_dir}, skipped')
            continue
        for name in sorted(os.listdir(src_dir)):
            if not name.lower().endswith('.mp3'):
                continue
            src = os.path.join(src_dir, name)
            dst = os.path.join(out_dir, name)
            b = mean_max(src)
            if dry:
                print(f'{sub + "/" + name:44} {b[0]:6.1f}/{b[1]:6.1f}')
                continue
            gain = process(src, dst, target)
            a = mean_max(dst)
            print(f'{sub + "/" + name:44} {b[0]:6.1f}/{b[1]:6.1f} {gain:+6.1f} {a[0]:6.1f}/{a[1]:6.1f}')


if __name__ == '__main__':
    main()
