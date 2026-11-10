"""Golden-output regression check for the desktop pipeline (a refactor must not change any output).

    python tools/regression.py snapshot <golden_dir> [--videos danh-cau-02 danh-cau]
    python tools/regression.py compare  <golden_dir> [--videos ...] [--skip-pipeline]

For every video it
  1. reruns the cheap steps (track players hits flight landing analytics, forced; detect / pose /
     background / calibrate stay cached) through the normal CLI,
  2. copies the step outputs (CSV / JSON / NPY / report.md) to <golden_dir>/<video>/ (snapshot) or
     compares them with the copies there (compare: exact bytes, else values within 1e-9),
  3. renders frames 0..N-1 for both layouts ('horizontal', 'vertical') with badminton.render.render_video
     and keeps the raw BGR frames (before any video codec): a SHA-256 per frame plus a few PNGs.
     Compare demands pixel-identical frames (max abs diff 0).

The render is frame-limited by wrapping cv2.VideoCapture / cv2.VideoWriter for the duration of the call,
so render.py itself needs no test hook. The real outputs/<video>/*.mp4 are not touched.
Exit code 0 = identical, 1 = something differs.
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from contextlib import contextmanager
from pathlib import Path

import cv2
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from badminton import render                       # noqa: E402
from badminton.__main__ import render_inputs       # noqa: E402
from badminton.calibrate import Camera             # noqa: E402

VIDEOS = ['danh-cau-02', 'danh-cau']
STEPS = ['track', 'players', 'hits', 'flight', 'landing', 'analytics']
FILES = ['shuttle.csv', 'players.csv', 'players_k3d.npy', 'hits.json', 'flights.json', 'landings.json',
         'report.json', 'report.md']
LAYOUTS = ['horizontal', 'vertical']
N_FRAMES = 300
PNG_FRAMES = (50, 150, 280)


# ---------------------------------------------------------------- pipeline outputs

def run_pipeline(video):
    env = dict(os.environ, PYTHONIOENCODING='utf-8')
    cmd = [sys.executable, '-m', 'badminton', f'configs/{video}.json', '--only', *STEPS, '--force', *STEPS]
    print('$', ' '.join(cmd[1:]), flush=True)
    subprocess.run(cmd, cwd=ROOT, env=env, check=True)


def _close(a, b, tol=1e-9):
    """Structural equality of JSON values, floats within tol."""
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(_close(a[k], b[k], tol) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(_close(x, y, tol) for x, y in zip(a, b))
    if isinstance(a, float) or isinstance(b, float):
        return isinstance(a, (int, float)) and isinstance(b, (int, float)) and abs(a - b) <= tol
    return a == b


def compare_file(golden, current):
    """'identical', 'equal within 1e-9 (formatting)', or a description of the difference."""
    if golden.read_bytes() == current.read_bytes():
        return 'identical'
    if golden.suffix == '.json':
        ok = _close(json.loads(golden.read_text('utf8')), json.loads(current.read_text('utf8')))
    elif golden.suffix == '.csv':
        a, b = pd.read_csv(golden), pd.read_csv(current)
        ok = list(a.columns) == list(b.columns) and a.shape == b.shape and all(
            np.allclose(a[c], b[c], rtol=0, atol=1e-9, equal_nan=True) if a[c].dtype.kind in 'fiub'
            else a[c].equals(b[c]) for c in a)
    elif golden.suffix == '.npy':
        a, b = np.load(golden), np.load(current)
        ok = a.shape == b.shape and a.dtype == b.dtype and np.allclose(a, b, rtol=0, atol=1e-9, equal_nan=True)
    else:
        ok = False
    return 'equal within 1e-9 (formatting)' if ok else 'DIFFERENT'


# ---------------------------------------------------------------- frame-limited render

@contextmanager
def capture_render(n_frames, keep):
    """Inside the block, video readers stop after n_frames and writers store raw frames instead of encoding.
    Yields a dict: 'hashes' (list of SHA-256 per written frame) and 'frames' {index: BGR array} for `keep`."""
    real_cap, real_writer = cv2.VideoCapture, cv2.VideoWriter
    got = {'hashes': [], 'frames': {}}

    class LimitedCapture:
        def __init__(self, *a):
            self._cap, self._n = real_cap(*a), 0

        def read(self):
            if self._n >= n_frames:
                return False, None
            self._n += 1
            return self._cap.read()

        def __getattr__(self, name):
            return getattr(self._cap, name)

    class FrameSink:
        def __init__(self, *a, **k):
            pass

        def write(self, img):
            i = len(got['hashes'])
            got['hashes'].append(hashlib.sha256(np.ascontiguousarray(img).tobytes()).hexdigest())
            if i in keep:
                got['frames'][i] = img.copy()

        def release(self):
            pass

    cv2.VideoCapture, cv2.VideoWriter = LimitedCapture, FrameSink
    try:
        yield got
    finally:
        cv2.VideoCapture, cv2.VideoWriter = real_cap, real_writer


def render_frames(video, layout, n_frames=N_FRAMES, keep=PNG_FRAMES):
    out = ROOT / 'outputs' / video
    cfg = json.load(open(ROOT / 'configs' / f'{video}.json', encoding='utf8'))
    src = str(ROOT / cfg['video'])
    cam = Camera(json.load(open(out / 'calib.json')))
    df, events = pd.read_csv(out / 'shuttle.csv'), json.load(open(out / 'landings.json'))
    fps = cv2.VideoCapture(src).get(cv2.CAP_PROP_FPS)
    extra = render_inputs(out, cam, fps)
    with capture_render(n_frames, set(keep)) as got:
        render.render_video(src, 'unused.mp4', cam, df, events, layout=layout,
                            panel_position=cfg.get('panel', 'below'), **extra)
    return got


# ---------------------------------------------------------------- commands

def snapshot(golden, videos, skip_pipeline):
    for v in videos:
        if not skip_pipeline:
            run_pipeline(v)
        dst = golden / v
        dst.mkdir(parents=True, exist_ok=True)
        for name in FILES:
            shutil.copy2(ROOT / 'outputs' / v / name, dst / name)
        for layout in LAYOUTS:
            got = render_frames(v, layout)
            (dst / f'frames_{layout}.json').write_text(json.dumps(got['hashes'], indent=0))
            for i, img in got['frames'].items():
                cv2.imwrite(str(dst / f'{layout}_{i:04d}.png'), img)
            print(f'{v} {layout}: {len(got["hashes"])} frames hashed', flush=True)
    print('snapshot written to', golden)
    return 0


def compare(golden, videos, skip_pipeline):
    bad = 0
    for v in videos:
        if not skip_pipeline:
            run_pipeline(v)
        src = golden / v
        print(f'== {v}')
        for name in FILES:
            r = compare_file(src / name, ROOT / 'outputs' / v / name)
            bad += r == 'DIFFERENT'
            print(f'   {name:18s} {r}')
        for layout in LAYOUTS:
            got = render_frames(v, layout)
            ref = json.loads((src / f'frames_{layout}.json').read_text())
            diff = [i for i, (a, b) in enumerate(zip(ref, got['hashes'])) if a != b]
            if len(ref) != len(got['hashes']):
                diff.append(f'count {len(ref)} vs {len(got["hashes"])}')
            for i, img in sorted(got['frames'].items()):
                g = cv2.imread(str(src / f'{layout}_{i:04d}.png'))
                d = int(np.abs(g.astype(int) - img.astype(int)).max()) if g.shape == img.shape else -1
                print(f'   {layout:10s} frame {i:4d}: max abs diff {d}')
                bad += d != 0
            print(f'   {layout:10s} {len(got["hashes"])} frames: '
                  + ('all pixel-identical' if not diff else f'DIFFERENT at {diff[:10]}'))
            bad += bool(diff)
    print('RESULT:', 'IDENTICAL' if not bad else f'{bad} DIFFERENCES')
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('mode', choices=['snapshot', 'compare'])
    ap.add_argument('golden', type=Path)
    ap.add_argument('--videos', nargs='*', default=VIDEOS)
    ap.add_argument('--skip-pipeline', action='store_true', help='use the outputs already on disk')
    a = ap.parse_args()
    fn = snapshot if a.mode == 'snapshot' else compare
    sys.exit(fn(a.golden.resolve(), a.videos, a.skip_pipeline))


if __name__ == '__main__':
    main()
