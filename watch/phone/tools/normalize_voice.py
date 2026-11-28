"""Make every bundled voice clip about equally loud — WITHOUT pushing them loud.

Reads the untouched originals in audio_src/ and writes processed copies into
assets/audio/. Always works from the originals, so it can be re-run with new
targets without compressing twice.

Per clip:
  1. trim leading/trailing silence (shorter, snappier score calls)
  2. gentle compression (2:1) — evens out a clip, does not squash it
  3. gain towards one loudness target (LUFS, EBU R128), but never more than
     MAX_BOOST_DB up: a quiet source stays a bit quiet instead of being
     dragged up into noise
  4. limit peaks to -1.5 dBFS (the MP3 re-encode overshoots ~1 dB)
  5. put LEAD_S of silence back in front: a speaker that has gone idle (the
     Bluetooth link, the phone's own amplifier) swallows the first 100-300 ms
     when it wakes, and with the trim the first syllable started at ~0 ms.

How loud it plays on court is the job of the volume sliders and the speaker,
not of this script. 2026-11: the old "loud" profile (-10 LUFS, 6:1 at -28 dB,
-0.5 dBFS ceiling) and the --louder flag were removed — the clips were so
dense that the Bluetooth speaker distorted ("rè") at any useful volume.

Every voice set has the same target: a score call, a hype line and a TTS line
(lib/services/wav_gain.dart, same numbers) are spliced one after another, so
any difference between them is heard as a jump.

Usage:  python tools/normalize_voice.py            (from watch/phone/)
        python tools/normalize_voice.py --dry-run  (report only)
        python tools/normalize_voice.py --changed  (only new/changed sources)

--changed is what the Android build runs before bundling assets
(android/app/build.gradle.kts): a source is redone when its bytes or the
settings below change, tracked in audio_src/.normalized.json.
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
TARGET_LUFS = -16.0

# Most a clip is ever turned UP, in dB. Turning down is unlimited.
# Kept in step with kMaxBoostDb in lib/services/wav_gain.dart.
MAX_BOOST_DB = 6.0

# (source dir under audio_src, output dir[, compress])
# compress=False: ElevenLabs renders come out already even (~-16 LUFS) and the
# 2:1 compressor only flattens their delivery — they get trim, gain, limiter.
SETS = [
    ('score/vi', 'assets/audio/score/vi', False),   # Mai Anh, ElevenLabs
    ('score/en', 'assets/audio/score/en'),
    ('hype', 'assets/audio/hype'),
    ('hype/female_pack', 'assets/audio/hype/female_pack'),
    ('hype/mai_anh', 'assets/audio/hype/mai_anh', False),
]

TRIM = ('silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.03,'
        'areverse,'
        'silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.06,'
        'areverse')
COMPRESS = 'acompressor=threshold=-18dB:ratio=2:attack=10:release=120'
LIMIT = 'alimiter=limit=0.841:level=false'  # 0.841 = -1.5 dBFS
LEAD_S = 0.15
LEAD = f'adelay=delays={int(LEAD_S * 1000)}:all=1'

# Part of every fingerprint: changing any of these redoes every clip.
SETTINGS_TAG = f'clean2|{TRIM}|{COMPRESS}|{LIMIT}|{LEAD}|{TARGET_LUFS}|{MAX_BOOST_DB}|128k'


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


def process(src, dst, target, compress=True):
    base = TRIM + (',' + COMPRESS if compress else '')
    m = lufs(src, base)
    if m is None:
        return None
    gain = min(target - m, MAX_BOOST_DB)

    def render(g, lead):
        chain = f'{base},volume={g:.2f}dB,{LIMIT}' + (f',{LEAD}' if lead else '')
        subprocess.run([FFMPEG, '-hide_banner', '-loglevel', 'error', '-y', '-i', src,
                        '-af', chain, '-c:a', 'libmp3lame', '-b:a', '128k', dst], check=True)

    # Levelled without the lead-in: lufs() loops the clip, and silence inside
    # every loop would read as quieter.
    render(gain, lead=False)
    # The limiter takes back a little on peaky clips: up to two correction
    # passes land them on the target — still never above MAX_BOOST_DB.
    for _ in range(2):
        got = lufs(dst)
        if got is None or abs(target - got) <= 0.3:
            break
        new_gain = min(gain + (target - got), MAX_BOOST_DB)
        if abs(new_gain - gain) < 0.05:
            break  # capped: cannot get closer
        gain = new_gain
        render(gain, lead=False)
    render(gain, lead=True)
    return gain


STAMP = os.path.join('audio_src', '.normalized.json')
LEVELS = os.path.join('audio_src', 'levels.json')


def warn_old_levels():
    """levels.json (--louder) is no longer read; say so if it asked for more."""
    if not os.path.exists(LEVELS):
        return
    try:
        v = float(json.load(open(LEVELS, encoding='utf-8')).get('louder_db', 0))
    except (ValueError, OSError):
        return
    if v:
        print(f'note: audio_src/levels.json louder_db={v:g} is ignored (feature removed)')


def fingerprint(src, compress=True):
    h = hashlib.sha1(open(src, 'rb').read())
    # Compressed sets keep the old tag, so this change redoes none of them.
    h.update((SETTINGS_TAG if compress else SETTINGS_TAG + '|nocomp').encode())
    return h.hexdigest()


def main():
    dry = '--dry-run' in sys.argv
    changed_only = '--changed' in sys.argv
    if '--louder' in sys.argv:
        print('--louder was removed: turn the volume up on the phone/speaker instead.')
        sys.exit(2)
    warn_old_levels()
    stamps = {}
    if os.path.exists(STAMP):
        stamps = json.load(open(STAMP, encoding='utf-8'))
    done = 0
    print(f'{"file":44} {"before":>14} {"gain":>7} {"after":>14}')
    for sub, out_dir, *opt in SETS:
        compress = opt[0] if opt else True
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
            fp = fingerprint(src, compress)
            if changed_only and os.path.exists(dst) and stamps.get(key) == fp:
                continue
            b = mean_max(src)
            if dry:
                print(f'{sub + "/" + name:44} {b[0]:6.1f}/{b[1]:6.1f}')
                continue
            os.makedirs(out_dir, exist_ok=True)
            gain = process(src, dst, TARGET_LUFS, compress)
            if gain is None:
                print(f'{sub + "/" + name:44} unreadable, skipped')
                continue
            stamps[key] = fp
            done += 1
            a = mean_max(dst)
            print(f'{sub + "/" + name:44} {b[0]:6.1f}/{b[1]:6.1f} {gain:+6.1f} {a[0]:6.1f}/{a[1]:6.1f}'
                  f'  {lufs(dst) or 0:6.1f} LUFS (incl. lead-in)')
    if not dry:
        with open(STAMP, 'w', encoding='utf-8', newline='\n') as f:
            json.dump(stamps, f, indent=1, sort_keys=True)
            f.write('\n')
    print(f'{done} file(s) normalized')


if __name__ == '__main__':
    main()
