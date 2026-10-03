"""Make every bundled voice clip equally loud, and loud enough to sit over music.

Reads the untouched originals in audio_src/ and writes processed copies into
assets/audio/. Always works from the originals, so it can be re-run with new
targets without compressing twice.

Per clip:
  1. trim leading/trailing silence (shorter, snappier score calls)
  2. compress (speech has gaps; music does not - density is what reads as loud)
  3. gain to one loudness target, in LUFS (EBU R128: what the ear hears,
     not the plain mean), measured on the compressed clip
  4. limit peaks to -0.5 dBFS so the gain never clips

Every voice set has the same target and profile: a score call, a hype line
and a TTS line (lib/services/wav_gain.dart, same numbers) are spliced one
after another, so any difference between them is heard as a jump.

Usage:  python tools/normalize_voice.py            (from bandcounter-flutter/)
        python tools/normalize_voice.py --dry-run  (report only)
        python tools/normalize_voice.py --changed  (only new/changed sources)
        python tools/normalize_voice.py --louder 2 (every clip 2 dB louder, kept)
        python tools/normalize_voice.py --louder 0 (back to the targets below)

--louder is saved in audio_src/levels.json, so later builds keep it; the
clips it changes are redone right away (their fingerprint includes it).

--changed is what the Android build runs before bundling assets
(android/app/build.gradle.kts): a source is redone when its bytes or the
settings below change, tracked in audio_src/.normalized.json.

Measured before this existed (mean / max dB): score vi -11.7..-13.7 / -1.4,
score en -17.2, hype -13.9..-19.5, bundled music -10.1..-13.5.
With the old mean-dB targets (2026-10-03, LUFS): score vi -9.8..-7.1,
score en -11.6..-8.7, hype -9.7..-6.8, female pack -9.9..-7.3.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

FFMPEG = os.environ.get('FFMPEG') or shutil.which('ffmpeg') or 'ffmpeg'

# One loudness for every voice (integrated LUFS). Kept in step with
# kTargetLufs in lib/services/wav_gain.dart.
# -9 was tried: the English score set tops out near -10.8 under the -0.5 dBFS
# ceiling (sharp consonants), so it stayed quieter than the rest.
TARGET_LUFS = -10.0

# (source dir under audio_src, output dir, target LUFS, profile)
SETS = [
    ('score/vi', 'assets/audio/score/vi', TARGET_LUFS, 'loud'),
    ('score/en', 'assets/audio/score/en', TARGET_LUFS, 'loud'),
    ('hype', 'assets/audio/hype', TARGET_LUFS, 'loud'),
    ('hype/female_pack', 'assets/audio/hype/female_pack', TARGET_LUFS, 'loud'),
]

TRIM = ('silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.03,'
        'areverse,'
        'silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.06,'
        'areverse')
COMPRESS = 'acompressor=threshold=-20dB:ratio=3:attack=5:release=60'
LIMIT = 'alimiter=limit=0.841:level=false'  # 0.841 = -1.5 dBFS: MP3 re-encode overshoots ~1 dB

# (compressor, limiter) per profile.
# loud: harder compression and a -0.5 dBFS ceiling. Measured on all 33 vi
# score clips: mean -9.9 -> -7.5 dB (+2.4), highest peak after the MP3
# re-encode -0.5 dBFS, no clipped samples. More compression than this only
# flattens the voice without making it louder.
PROFILES = {
    'normal': (COMPRESS, LIMIT),
    'loud': ('acompressor=threshold=-28dB:ratio=6:attack=3:release=60',
             'alimiter=limit=0.944:level=false'),  # 0.944 = -0.5 dBFS
}


def mean_max(path, pre_filter=''):
    af = (pre_filter + ',' if pre_filter else '') + 'volumedetect'
    out = subprocess.run([FFMPEG, '-hide_banner', '-nostats', '-i', path, '-af', af,
                          '-f', 'null', '-'], capture_output=True, text=True).stderr
    mean = re.search(r'mean_volume: (-?[\d.]+) dB', out)
    peak = re.search(r'max_volume: (-?[\d.]+) dB', out)
    return (float(mean.group(1)) if mean else None, float(peak.group(1)) if peak else None)


def lufs(path, pre_filter=''):
    """Integrated loudness (EBU R128), or None for silence / too short."""
    # Looped 4x: R128 measures in 400 ms blocks, so a 0.3 s number clip
    # would read as silence and a 0.6 s one from barely two blocks.
    af = (pre_filter + ',' if pre_filter else '') + 'ebur128'
    out = subprocess.run([FFMPEG, '-hide_banner', '-nostats', '-stream_loop', '3', '-i', path, '-af', af,
                          '-f', 'null', '-'], capture_output=True, text=True).stderr
    m = re.search(r'I:\s+(-?[\d.]+) LUFS', out[out.rfind('Summary:'):])
    v = float(m.group(1)) if m else None
    return v if v is not None and v > -70 else None


def process(src, dst, target, profile='normal'):
    compress, limit = PROFILES[profile]
    base = TRIM + ',' + compress
    m = lufs(src, base)
    if m is None:
        return None
    gain = target - m

    def render(g):
        chain = f'{base},volume={g:.2f}dB,{limit}'
        subprocess.run([FFMPEG, '-hide_banner', '-loglevel', 'error', '-y', '-i', src,
                        '-af', chain, '-c:a', 'libmp3lame', '-b:a', '128k', dst], check=True)

    render(gain)
    # The limiter takes back a little on the loudest clips: up to two
    # correction passes land them on the target too.
    for _ in range(2):
        got = lufs(dst)
        if got is None or abs(target - got) <= 0.3:
            break
        gain += target - got
        render(gain)
    return gain


STAMP = os.path.join('audio_src', '.normalized.json')
LEVELS = os.path.join('audio_src', 'levels.json')


def louder_db():
    """Saved --louder offset, updated when the flag is given."""
    levels = json.load(open(LEVELS, encoding='utf-8')) if os.path.exists(LEVELS) else {}
    if '--louder' in sys.argv and '--dry-run' not in sys.argv:
        levels['louder_db'] = float(sys.argv[sys.argv.index('--louder') + 1])
        with open(LEVELS, 'w', encoding='utf-8', newline='\n') as f:
            json.dump(levels, f, indent=1)
            f.write('\n')
    return float(levels.get('louder_db', 0))


def fingerprint(src, target, profile):
    h = hashlib.sha1(open(src, 'rb').read())
    h.update(f'{TRIM}|{PROFILES[profile]}|{target}|lufs3|128k'.encode())
    return h.hexdigest()


def main():
    dry = '--dry-run' in sys.argv
    # --louder redoes only what it changes, like --changed.
    changed_only = '--changed' in sys.argv or '--louder' in sys.argv
    louder = louder_db()
    if louder:
        print(f'louder: +{louder:g} dB on every target (audio_src/levels.json)')
    stamps = {}
    if os.path.exists(STAMP):
        stamps = json.load(open(STAMP, encoding='utf-8'))
    done = 0
    print(f'{"file":44} {"before":>14} {"gain":>7} {"after":>14}')
    for sub, out_dir, target, profile in SETS:
        target += louder
        src_dir = os.path.join('audio_src', sub)
        if not os.path.isdir(src_dir):
            print(f'-- missing {src_dir}, skipped')
            continue
        for name in sorted(os.listdir(src_dir)):
            if not name.lower().endswith('.mp3'):
                continue
            src = os.path.join(src_dir, name)
            dst = os.path.join(out_dir, name)
            key = dst.replace(os.sep, '/')
            fp = fingerprint(src, target, profile)
            if changed_only and os.path.exists(dst) and stamps.get(key) == fp:
                continue
            b = mean_max(src)
            if dry:
                print(f'{sub + "/" + name:44} {b[0]:6.1f}/{b[1]:6.1f}')
                continue
            os.makedirs(out_dir, exist_ok=True)
            gain = process(src, dst, target, profile)
            if gain is None:
                print(f'{sub + "/" + name:44} unreadable, skipped')
                continue
            stamps[key] = fp
            done += 1
            a = mean_max(dst)
            print(f'{sub + "/" + name:44} {b[0]:6.1f}/{b[1]:6.1f} {gain:+6.1f} {a[0]:6.1f}/{a[1]:6.1f}'
                  f'  {lufs(dst) or 0:6.1f} LUFS')
    if not dry:
        with open(STAMP, 'w', encoding='utf-8', newline='\n') as f:
            json.dump(stamps, f, indent=1, sort_keys=True)
            f.write('\n')
    print(f'{done} file(s) normalized')


if __name__ == '__main__':
    main()
