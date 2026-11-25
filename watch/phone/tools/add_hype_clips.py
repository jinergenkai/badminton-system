"""Cut hype clips out of the Gemini (Lyria) packs and add them to the app.

Input is the list that audio_src/hype/lyria/cat_clip.html copies ("Copy danh sách"),
one clip per line:

    goi12 | 40.20-43.43 | Còn đúng cái nịt! | shutdown
    goi13 | 3.10-5.00   | Ai sợ thì đi về!  | first_point_of_match,streak_high

Column 3 is the line as it should show on screen (with diacritics); a bare slug
such as con_dung_cai_nit also works. Column 4 is one or more trigger ids from
assets/config/sound_library.json, comma separated.

For every row this:
  1. cuts audio_src/hype/lyria/goiN.mp3 [a, b] with a short fade into
     audio_src/hype/g<N>_<slug>.mp3 — the pack prefix keeps equal lines from
     different packs apart, so nothing already in the app is overwritten;
  2. adds the sound (id, display, text, glow) and puts it in the trigger pools.
Then run:  python tools/normalize_voice.py --changed

    python tools/add_hype_clips.py list.txt            (add)
    python tools/add_hype_clips.py list.txt --dry-run  (show what would happen)
"""
import json
import re
import subprocess
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKS = ROOT / 'audio_src/hype/lyria'
OUT = ROOT / 'audio_src/hype'
LIB = ROOT / 'assets/config/sound_library.json'
GLOW = {'streak_high': 'fire', 'streak_5_plus': 'fire', 'comeback': 'legendary', 'match_end': 'legendary'}


def slugify(text):
    t = unicodedata.normalize('NFD', text.replace('đ', 'd').replace('Đ', 'D'))
    t = ''.join(c for c in t if unicodedata.category(c) != 'Mn').lower()
    return re.sub(r'[^a-z0-9]+', '_', t).strip('_')[:48]


def display(text):
    t = re.sub(r'[!?.…,]+$', '', text).strip().upper()
    if len(t) <= 12:
        return t
    w = t.split()
    best = min(((max(len(' '.join(w[:i])), len(' '.join(w[i:]))), i) for i in range(1, len(w))), default=None)
    return t if best is None else ' '.join(w[:best[1]]).rstrip(',') + '\n' + ' '.join(w[best[1]:])


def cut(src, a, b, out):
    d = round(b - a, 3)
    fo = max(0.0, round(d - 0.12, 3))
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', str(a), '-t', str(d), '-i', str(src),
                    '-af', f'afade=t=in:d=0.03,afade=t=out:st={fo}:d=0.12', '-b:a', '160k', str(out)], check=True)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    dry = '--dry-run' in sys.argv
    if not args:
        sys.exit(__doc__)
    lib = json.loads(LIB.read_text(encoding='utf-8'))
    ids = {s['id'] for s in lib['sounds']}
    trig = {t['id']: t for t in lib['triggers']}
    for n, line in enumerate(Path(args[0]).read_text(encoding='utf-8').splitlines(), 1):
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        pk, rng, text, groups = [c.strip() for c in line.split('|')]
        pk = pk.removeprefix('goi')
        a, b = map(float, rng.split('-'))
        is_slug = re.fullmatch(r'[a-z0-9_]+', text) is not None
        sid = f'g{pk}_{text if is_slug else slugify(text)}'
        spoken = text.replace('_', ' ') if is_slug else text
        groups = [g.strip() for g in groups.split(',') if g.strip()]
        bad = [g for g in groups if g not in trig]
        if bad:
            sys.exit(f'line {n}: unknown trigger {bad} (known: {", ".join(trig)})')
        if sid in ids:
            print(f'line {n}: {sid} already in the library, skipped')
            continue
        print(f'{sid:48s} {a:6.2f}-{b:6.2f}  {",".join(groups)}')
        if dry:
            continue
        cut(PACKS / f'goi{pk}.mp3', a, b, OUT / f'{sid}.mp3')
        s = {'id': sid, 'display': display(spoken), 'text': spoken}
        glow = next((GLOW[g] for g in groups if g in GLOW), None)
        if glow:
            s['glow'] = glow
        lib['sounds'].append(s)
        ids.add(sid)
        for g in groups:
            trig[g]['pool'].append(sid)
    if not dry:
        lib['sounds'].sort(key=lambda s: s['id'])
        LIB.write_text(json.dumps(lib, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print('done — now: python tools/normalize_voice.py --changed')


if __name__ == '__main__':
    main()
