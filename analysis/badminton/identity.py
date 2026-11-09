"""Stable player identities ("P1".."P4") over the whole video.

The floor-position tracker in players.py breaks an id at every occlusion (partners crossing,
someone walking behind another): ~100 ids for 4 people. Per-player statistics need one id per
person, so:

1. Appearance: HSV colour histogram of the shirt (shoulders-hips) and of the shorts (hips-knees),
   from the pose keypoints. Hellinger-normalised, so euclidean distance is meaningful.
2. Who plays: the number of players per side is the most common count of people standing on
   that half (1 = singles, 2 = doubles). k-means over confident detections, k = total players.
   Global clustering (not per side) still works when teams change ends between games.
3. Per frame, Hungarian assignment of detections to players: appearance distance + jump from the
   player's last floor position (a person moves < ~7 m/s). Each player at most once per frame;
   detections that resemble no player (spectators, the next court) stay unassigned.
"""
import cv2
import numpy as np
from scipy.cluster.vq import kmeans2
from scipy.optimize import linear_sum_assignment

from .court import HALF, W
from .players import L_HIP, L_SH, R_HIP, R_SH

L_KNEE, R_KNEE = 13, 14
H_BINS, S_BINS, V_BINS = 16, 4, 6


def _hist(hsv, box):
    x0, y0, x1, y1 = box
    roi = hsv[max(0, y0):max(0, y1), max(0, x0):max(0, x1)]
    if roi.size < 30:
        return None
    h = cv2.calcHist([roi], [0, 1], None, [H_BINS, S_BINS], [0, 180, 0, 256]).ravel()
    # dark / grey pixels have meaningless hue: count them in a separate "value" histogram
    v = cv2.calcHist([roi], [2], None, [V_BINS], [0, 256]).ravel()
    f = np.r_[h, 0.5 * v]
    f = np.sqrt(f / max(f.sum(), 1))             # Hellinger
    # texture: a patterned shirt and a plain one of the same colours differ in local contrast
    val = roi[..., 2].astype(np.float32)
    lap = np.abs(cv2.Laplacian(val, cv2.CV_32F)).mean() / 40.0
    return np.r_[f, min(lap, 1.5), val.std() / 80.0]


def _boxes(k, s, thr=0.3):
    out = []
    for top, bottom in (((L_SH, R_SH), (L_HIP, R_HIP)), ((L_HIP, R_HIP), (L_KNEE, R_KNEE))):
        idx = [j for j in top + bottom if s[j] > thr]
        if len(idx) < 3:
            out.append(None)
            continue
        p = k[idx]
        x0, y0 = p.min(0)
        x1, y1 = p.max(0)
        mx, my = 0.15 * (x1 - x0), 0.1 * (y1 - y0)
        out.append(tuple(int(v) for v in (x0 + mx, y0 + my, x1 - mx, y1 - my)))
    return out


def appearance(video, players, kpts, scores):
    """One feature per players.csv row (NaN where the body is not visible enough)."""
    rows_by_frame = {f: g.index.to_numpy() for f, g in players.groupby('frame')}
    D = 2 * (H_BINS * S_BINS + V_BINS + 2)
    feats = np.full((len(players), D), np.nan, np.float32)
    det = players.det.to_numpy()
    cap = cv2.VideoCapture(video)
    f = 0
    while True:
        ok, img = cap.read()
        if not ok:
            break
        if f in rows_by_frame:
            hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
            for r in rows_by_frame[f]:
                shirt, shorts = _boxes(kpts[det[r]], scores[det[r]])
                hs = _hist(hsv, shirt) if shirt else None
                hb = _hist(hsv, shorts) if shorts else None
                if hs is not None and hb is not None:
                    feats[r] = np.r_[hs, 0.6 * hb]
        f += 1
    return feats


def _vote(players, lab, feats, cent, scale, min_share=0.6):
    lab = lab.copy()
    for pid, g in players.groupby('pid'):
        idx = g.index.to_numpy()
        v = lab[idx]
        v = v[v >= 0]
        if len(v) < 3:
            continue
        top = np.bincount(v).argmax()
        if np.mean(v == top) >= min_share:
            lab[idx] = top
    # two detections of one frame may now share a player: keep the closer-looking one
    frame = players.frame.to_numpy()
    for p in range(len(cent)):
        rows = np.nonzero(lab == p)[0]
        f = frame[rows]
        dup = np.unique(f[np.r_[False, np.diff(f) == 0] | np.r_[np.diff(f) == 0, False]])
        for fr in dup:
            r = rows[f == fr]
            d = [np.linalg.norm(feats[i] - cent[p]) / scale if not np.isnan(feats[i]).any() else 9 for i in r]
            for i in np.delete(r, int(np.argmin(d))):
                lab[i] = -1
    return lab


def players_per_side(players):
    on = players[players.X.between(-0.5, W + 0.5) & (players.Y.abs() < HALF + 0.8)]
    c = on.groupby(['frame', 'side']).size().unstack(fill_value=0)
    return {side: int(max(1, min(2, c[side].mode()[0]))) if side in c else 1 for side in ('near', 'far')}


def assign(players, feats, fps, max_speed=7.0, w_pos=0.35, max_cost=1.2, seed=0, vote=False):
    """Adds column 'player' (0..k-1, -1 = not a player). Returns (players, centroids, per_side)."""
    per_side = players_per_side(players)
    k = per_side['near'] + per_side['far']
    on = players.X.between(0, W) & (players.Y.abs() < HALF) & ~np.isnan(feats).any(1)
    X = feats[on.to_numpy()]
    best = None
    for s in range(8):                              # k-means restarts, keep the tightest
        c, lab = kmeans2(X, k, minit='++', seed=seed + s)
        inertia = ((X - c[lab]) ** 2).sum()
        if best is None or inertia < best[0]:
            best = (inertia, c, lab)
    cent = best[1]
    # typical distance of a detection to its own centre: the scale of "looks like this player"
    scale = np.median(np.linalg.norm(X - cent[best[2]], axis=1)) + 1e-6

    out = np.full(len(players), -1)
    last = {}                                       # player -> (frame, X, Y)
    for f, g in players.groupby('frame'):
        idx = g.index.to_numpy()
        C = np.full((len(idx), k), 9.0)
        for a, r in enumerate(idx):
            ft = feats[r]
            app = np.linalg.norm(cent - ft, axis=1) / scale if not np.isnan(ft).any() else np.full(k, 1.5)
            for p in range(k):
                pos = 0.0
                if p in last:
                    lf, lx, ly = last[p]
                    jump = np.hypot(players.X[r] - lx, players.Y[r] - ly)
                    allowed = max_speed * (f - lf) / fps + 0.4
                    # small moves are free (and slightly preferred), impossible jumps forbidden
                    pos = 9.0 if jump > 3 * allowed else (jump / allowed if jump > allowed else 0.3 * jump / allowed)
                C[a, p] = 0.5 * app[p] + w_pos * pos
        rr, cc = linear_sum_assignment(C)
        for a, p in zip(rr, cc):
            if C[a, p] < max_cost:
                out[idx[a]] = p
                last[p] = (f, players.X[idx[a]], players.Y[idx[a]])
    # tracklet vote: a floor-position track (pid) from players.py is short but pure (it breaks at
    # occlusions instead of swapping), so all its frames belong to the same person
    if vote:
        out = _vote(players, out, feats, cent, scale)
    players = players.copy()
    players['player'] = out
    # order players: near side first, then by mean X, so labels are stable and readable
    order = sorted(range(k), key=lambda p: (players.Y[players.player == p].median() > 0,
                                            players.X[players.player == p].median()))
    remap = {p: i for i, p in enumerate(order)}
    players['player'] = players.player.map(lambda p: remap.get(p, -1))
    return players, cent[order], per_side
