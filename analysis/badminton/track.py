"""Turn per-frame candidates into shuttle flights, and pick the one that belongs to our court.

1. Gate: drop candidates outside the image region of the box above our court.
2. Multi-target tracking: each live track predicts its next position from its velocity and
   takes the nearest candidate inside a gate that widens with the frame gap. Unmatched
   candidates start new tracks, so a neighbour-court shuttle gets its own track instead of
   hijacking ours.
3. Drop tracks that are too short or barely move (ceiling lights, white shoes).
4. Per frame, keep the best track (long, mostly inside our court volume) and fill short
   gaps by linear interpolation.
"""
import numpy as np
import pandas as pd


def build_tracks(cands, volume_mask, max_gap=5, gate=30, gate_per_frame=18):
    h, w = volume_mask.shape
    c = cands.copy()
    xi, yi = c.x.clip(0, w - 1).astype(int), c.y.clip(0, h - 1).astype(int)
    c['in_volume'] = volume_mask[yi, xi] > 0
    c = c[c.in_volume]

    live, finished = [], []
    for f, grp in c.groupby('frame'):
        pts = grp[['x', 'y']].to_numpy()
        still = []
        for t in live:
            if f - t['f'][-1] > max_gap:
                finished.append(t)
            else:
                still.append(t)
        live = still
        # greedy assignment, closest (track, candidate) pairs first
        pairs = []
        for ti, t in enumerate(live):
            gap = f - t['f'][-1]
            pred = np.array(t['p'][-1]) + t['v'] * gap
            d = np.hypot(*(pts - pred).T)
            for ci in np.nonzero(d < gate + gate_per_frame * gap)[0]:
                pairs.append((d[ci], ti, ci))
        used_t, used_c = set(), set()
        for d, ti, ci in sorted(pairs):
            if ti in used_t or ci in used_c:
                continue
            t = live[ti]
            gap = f - t['f'][-1]
            v = (pts[ci] - np.array(t['p'][-1])) / gap
            t['v'] = 0.5 * t['v'] + 0.5 * v if len(t['f']) > 1 else v
            t['f'].append(f)
            t['p'].append(tuple(pts[ci]))
            used_t.add(ti)
            used_c.add(ci)
        for ci in range(len(pts)):
            if ci not in used_c:
                live.append({'f': [f], 'p': [tuple(pts[ci])], 'v': np.zeros(2)})
    finished += live
    return [(np.array(t['f']), np.array(t['p'])) for t in finished]


def select(tracks, min_len=8, min_travel=40):
    """Keep real flights, then for every frame the single best track. Returns a DataFrame."""
    good = []
    for f, p in tracks:
        travel = np.hypot(*(p.max(0) - p.min(0)))
        if len(f) >= min_len and travel >= min_travel:
            good.append((f, p, len(f) / (f[-1] - f[0] + 1) * len(f)))   # density * length
    owner = {}
    for k, (f, p, score) in enumerate(good):
        for fr in range(f[0], f[-1] + 1):
            if fr not in owner or good[owner[fr]][2] < score:
                owner[fr] = k
    rows = []
    for k, (f, p, _) in enumerate(good):
        frames = [fr for fr in range(f[0], f[-1] + 1) if owner.get(fr) == k]
        if not frames:
            continue
        xs = np.interp(frames, f, p[:, 0])
        ys = np.interp(frames, f, p[:, 1])
        detected = np.isin(frames, f)
        rows += [(fr, x, y, k, bool(d)) for fr, x, y, d in zip(frames, xs, ys, detected)]
    df = pd.DataFrame(rows, columns=['frame', 'x', 'y', 'track', 'detected']).sort_values('frame')
    return df.reset_index(drop=True)


def falling_ends(df, n=5):
    """Last point of each selected track if the shuttle was moving down the image before it."""
    out = []
    for _, t in df[df.detected].groupby('track'):
        tail = t.tail(n)
        if len(tail) == n and np.all(np.diff(tail.y) >= -1) and tail.y.iloc[-1] - tail.y.iloc[0] > 8:
            out.append(tail.iloc[-1][['frame', 'x', 'y']].to_numpy(float))
    return np.array(out).reshape(-1, 3)


def turn_points(seg, k=3, min_turn_deg=50, min_speedup=2.5, min_sep=0):
    """(frame, pixel) where an image trajectory turns sharply or suddenly speeds up: likely racket contacts."""
    f, p = seg.frame.to_numpy(), seg[['x', 'y']].to_numpy()
    out = []
    for i in range(k, len(f) - k):
        vb = (p[i] - p[i - k]) / (f[i] - f[i - k])
        va = (p[i + k] - p[i]) / (f[i + k] - f[i])
        nb, na = np.linalg.norm(vb), np.linalg.norm(va)
        if nb < 1e-6 or na < 1e-6:
            continue
        turn = np.degrees(np.arccos(np.clip(vb @ va / (nb * na), -1, 1)))
        if (turn > min_turn_deg or na / nb > min_speedup) and (not out or f[i] - out[-1][0] >= min_sep):
            out.append((int(f[i]), p[i]))
    return out
