"""Ground-truth benchmark for the 3D flight fit (badminton/flight.py).

Simulates realistic shots with the shuttle physics, seen by a REAL calibrated camera from outputs/,
projects them to pixels with TrackNet-like errors (noise, missed frames, a gap at the contact,
outliers, leaving the frame), perturbs the racket-contact anchors like the pose would, then runs
fit_shot and compares with the truth.

    python tools/synth_eval.py outputs/danh-cau-02/calib.json [--n 40] [--seed 0]
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from badminton.calibrate import Camera            # noqa: E402
from badminton.court import HALF, W, is_in        # noqa: E402
from badminton.flight import fit_shot, land, net_clearance, simulate  # noqa: E402

FPS = 30
# type: (|Y| of contact, contact height, speed km/h, elevation deg, receiver height)
TYPES = {
    'clear': ((4.8, 6.9), (2.2, 2.8), (140, 230), (20, 40), (2.0, 2.7)),
    'smash': ((3.0, 6.0), (2.3, 3.0), (170, 300), (-15, -4), (0.6, 1.4)),
    'drop':  ((4.5, 6.5), (2.2, 2.7), (50, 95), (-5, 12), (0.4, 1.0)),
    'lift':  ((0.8, 2.6), (0.3, 1.0), (80, 150), (35, 60), (2.0, 2.7)),
    'drive': ((1.5, 4.0), (1.0, 1.7), (90, 170), (-2, 8), (0.9, 1.6)),
    'net':   ((0.4, 1.6), (0.7, 1.4), (12, 30), (15, 45), (0.6, 1.3)),
}


def make_shot(rng, kind):
    yr, zr, sr, er, recv = TYPES[kind]
    side = rng.choice([-1, 1])                     # -1 = hitter on the camera half
    p0 = np.array([rng.uniform(0.5, W - 0.5), side * rng.uniform(*yr), rng.uniform(*zr)])
    target = np.array([rng.uniform(0.5, W - 0.5), -side * rng.uniform(1.0, HALF - 0.3)])
    az = np.arctan2(target[1] - p0[1], target[0] - p0[0])
    el = np.radians(rng.uniform(*er))
    v0 = rng.uniform(*sr) / 3.6 * np.array([np.cos(el) * np.cos(az), np.cos(el) * np.sin(az), np.sin(el)])
    # the contact happens between frames: frame 0 of the video is u seconds after it
    u = rng.uniform(0, 1 / FPS)
    t = np.arange(0, int(4 * FPS)) / FPS + u
    P = simulate(p0, v0, t)
    clear = net_clearance(p0, v0, t[-1])
    if clear is None or clear < 0.02:              # into the net: not a rally shot, draw again
        return make_shot(rng, kind)
    crossed = np.sign(P[:, 1]) == -side
    zr_ = rng.uniform(*recv)
    end = np.nonzero(crossed & (P[:, 2] <= zr_) & (np.r_[0, np.diff(P[:, 2])] < 0))[0]
    floor = np.nonzero(P[:, 2] <= 0)[0]
    final = rng.random() < 0.3 or not len(end)     # rally ends: fly to the floor
    if final:
        n = floor[0] if len(floor) else len(t)
        return p0, v0, side, t[:n], P[:n], None
    n = end[0]
    return p0, v0, side, t[:n + 1], P[:n + 1], P[n]


def observe(rng, cam, P, noise=2.0, miss=0.12, gap=3, outliers=0.03):
    px = cam.project(P) + rng.normal(0, noise, (len(P), 2))
    w, h = cam.size
    keep = (px[:, 0] > 0) & (px[:, 0] < w) & (px[:, 1] > 0) & (px[:, 1] < h)
    keep &= rng.random(len(P)) > miss
    keep[:gap] = False                              # blur / racket occlusion right after the contact
    out = rng.random(len(P)) < outliers
    px[out] += rng.normal(0, 30, (out.sum(), 2))
    return keep, px


def run(calib, n_per_type, seed, anchor_noise=0.2):
    cam = Camera(json.load(open(calib)))
    rng = np.random.default_rng(seed)
    rows = []
    for kind in TYPES:
        for _ in range(n_per_type):
            p0, v0, side, t, P, end = make_shot(rng, kind)
            if len(t) < 8:
                continue
            keep, px = observe(rng, cam, P)
            frames = np.arange(len(t))
            # the hit detector is off by up to a frame either way
            hit = {'frame': int(rng.integers(-1, 2)), 'pid': 0, 'side': 'near' if side < 0 else 'far',
                   'contact': (p0 + rng.normal(0, anchor_noise, 3)).tolist()}
            keep &= frames > hit['frame']
            nxt = None
            if end is not None:
                nxt = {'frame': int(frames[-1]), 'side': 'far' if side < 0 else 'near',
                       'contact': (end + rng.normal(0, anchor_noise, 3)).tolist()}
            if keep.sum() < 5:
                continue
            r = fit_shot(cam, frames[keep], px[keep], FPS, hit, nxt, allow_landing=end is None)
            if r is None:
                rows.append((kind, False, np.nan, np.nan, np.nan, np.nan, np.nan))
                continue
            tf = (frames - hit['frame']) / FPS + r.get('t0', 0.0)   # fitted time since the fitted contact
            Pf = simulate(r['p0'], r['v0'], np.maximum(tf, 0))
            err3d = np.linalg.norm(Pf - P, axis=1)
            sp_true = np.linalg.norm(v0) * 3.6
            land_err = np.nan
            if end is None and r.get('landing'):
                lt = land(p0, v0)
                if lt is not None:
                    land_err = float(np.hypot(*(np.array(r['landing']['court']) - lt[1][:2])))
            rows.append((kind, r['good'], float(np.median(err3d)), float(err3d.max()),
                         (r['speed_kmh'] - sp_true) / sp_true * 100, land_err,
                         (r['speed_kmh'] - sp_true) / max(r.get('speed_sd_kmh', np.nan), 0.5)))
    return rows


def report(rows):
    print(f"{'type':6s} {'n':>3s} {'good%':>6s} {'3D med':>7s} {'3D p90':>7s} {'max p90':>8s} "
          f"{'speed err med/p90 %':>20s} {'landing med m':>14s} {'|err|<1sd  <2sd':>16s}")
    for kind in list(TYPES) + ['ALL']:
        R = [r for r in rows if kind == 'ALL' or r[0] == kind]
        g = [r for r in R if r[1]]
        if not R:
            continue
        a = np.array([r[2:] for r in g], float) if g else np.full((1, 5), np.nan)
        zz = np.abs(a[:, 4])
        se = np.abs(a[:, 2])
        print(f"{kind:6s} {len(R):3d} {100 * len(g) / len(R):5.0f}% {np.nanmedian(a[:, 0]):6.2f}m "
              f"{np.nanpercentile(a[:, 0], 90):6.2f}m {np.nanpercentile(a[:, 1], 90):7.2f}m "
              f"{np.nanmedian(se):9.1f} / {np.nanpercentile(se, 90):5.1f}"
              f"{np.nanmedian(a[:, 3]):14.2f} {100 * np.mean(zz < 1):9.0f}% {100 * np.mean(zz < 2):5.0f}%")


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('calib')
    ap.add_argument('--n', type=int, default=40)
    ap.add_argument('--seed', type=int, default=0)
    a = ap.parse_args()
    report(run(a.calib, a.n, a.seed))
