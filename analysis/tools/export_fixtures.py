"""Export one video's pipeline intermediates as JSON fixtures for the browser port's tests.

    python tools/export_fixtures.py danh-cau-02 [--frames 1800]

Writes analysis/web/test/fixtures/<name>/*.json (git-ignored: derived from personal videos).
"""
import argparse
import json
import sys
from pathlib import Path

import cv2
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from badminton import identity                     # noqa: E402
from badminton.calibrate import Camera            # noqa: E402


def dump(obj, path):
    path.write_text(json.dumps(obj, separators=(',', ':')), encoding='utf8')
    print(f'{path.name:22s} {path.stat().st_size / 1e6:6.2f} MB')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('name')
    a = ap.parse_args()
    o = ROOT / 'outputs' / a.name
    cfg = json.load(open(ROOT / 'configs' / f'{a.name}.json', encoding='utf8'))
    out = ROOT / 'web' / 'test' / 'fixtures' / a.name
    out.mkdir(parents=True, exist_ok=True)
    calib = json.load(open(o / 'calib.json'))
    cam = Camera(calib)
    cap = cv2.VideoCapture(str(ROOT / cfg['video']))
    fps = cap.get(cv2.CAP_PROP_FPS)
    calib.update({'pos': cam.pos.tolist(), 'R': cam.R.tolist(), 'fps': fps})
    # a few reference projections / rays so the JS camera can be checked numerically
    pts = [[0, 0, 0], [6.1, 0, 1.55], [3.05, 6.7, 0], [1.0, -4.0, 2.5], [5.0, 3.0, 4.0]]
    calib['check'] = {'points': pts, 'pixels': cam.project(pts).tolist(),
                      'ray_px': [[512, 288], [100, 400]], 'rays': [cam.ray([512, 288]).tolist(), cam.ray([100, 400]).tolist()]}
    dump(calib, out / 'calib.json')
    dump(pd.read_csv(o / 'candidates.csv').to_dict('list'), out / 'candidates.json')
    dump(pd.read_csv(o / 'shuttle.csv').to_dict('list'), out / 'shuttle.json')
    z = np.load(o / 'pose.npz')
    dump({'frame': z['frame'].tolist(), 'kpts': np.round(z['kpts'], 2).tolist(),
          'scores': np.round(z['scores'], 3).tolist()}, out / 'pose.json')
    pl = pd.read_csv(o / 'players.csv')
    dump(pl.to_dict('list'), out / 'players.json')
    dump(np.round(np.load(o / 'players_k3d.npy'), 4).tolist(), out / 'players_k3d.json')
    feats = identity.appearance(str(ROOT / cfg['video']), pl, z['kpts'], z['scores'])
    dump(np.where(np.isnan(feats), None, np.round(feats, 5)).tolist(), out / 'appearance.json')
    for f in ('hits.json', 'flights.json', 'landings.json', 'report.json'):
        dump(json.load(open(o / f, encoding='utf8')), out / f)


if __name__ == '__main__':
    main()
