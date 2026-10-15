"""Racket-shuttle contacts ("hits") from the shuttle track + player poses.

Candidate moments: a flight starts, or the shuttle turns sharply / suddenly speeds up.
A candidate is a hit when, in 3D, the shuttle's view ray passes close to a player's wrist
(racket head is ~0.6 m beyond the wrist). The point on the ray nearest that wrist is the
contact estimate, which gives the contact height from a single camera.
Rule of the game: the same side cannot hit twice in a row, so near-duplicates are resolved.
"""
import numpy as np

from .players import L_WR, R_WR
from .track import turn_points


def _candidates(shuttle):
    out = []
    for _, t in shuttle[shuttle.detected].groupby('track'):
        out.append((int(t.frame.iloc[0]), t[['x', 'y']].to_numpy()[0], 'start'))
        out += [(f, p, 'turn') for f, p in turn_points(t)]
    return out


def best_contact(cam, f, px, rows, by_frame, k3d, window=3, max_dist=1.0, min_z=0.25):
    """Player wrist closest (in 3D) to the shuttle's view ray around frame f -> hit dict or None."""
    d = cam.ray(px)
    best = None
    for ff in range(f - window, f + window + 1):
        for r in by_frame.get(ff, []):
            for name, j in (('L', L_WR), ('R', R_WR)):
                Wp = k3d[r, j] - cam.pos
                along = Wp @ d
                if along <= 0:
                    continue
                dist = np.linalg.norm(Wp - along * d)
                contact = cam.pos + along * d
                if contact[2] < min_z:          # at floor level: picking the shuttle up, not a stroke
                    continue
                if dist < max_dist and (best is None or dist < best['wrist_dist']):
                    best = {'frame': int(f), 'pid': int(rows.pid[r]), 'side': rows.side[r], 'hand': name,
                            'px': [round(float(px[0]), 1), round(float(px[1]), 1)],
                            'wrist_dist': round(float(dist), 2),
                            'wrist_z': round(float(k3d[r, j, 2]), 2),
                            'contact': [round(float(v), 2) for v in contact]}
    return best


def index_players(players):
    rows = players.reset_index(drop=True)
    return rows, {f: g.index.to_numpy() for f, g in rows.groupby('frame')}


def find_hits(cam, shuttle, players, k3d, window=3, max_dist=1.0, merge=8, min_gap_same_side=20, min_z=0.25):
    rows, by_frame = index_players(players)
    found = []
    for f, px, kind in _candidates(shuttle):
        best = best_contact(cam, f, px, rows, by_frame, k3d, window, max_dist, min_z)
        if best:
            best['kind'] = kind
            found.append(best)

    # one hit per moment: merge candidates close in time, keep the best supported one
    found.sort(key=lambda h: h['frame'])
    merged = []
    for h in found:
        if merged and h['frame'] - merged[-1]['frame'] <= merge:
            if h['wrist_dist'] < merged[-1]['wrist_dist']:
                merged[-1] = h
        else:
            merged.append(h)
    # the same side never hits twice in a row (a quick double means one of them is wrong)
    final = []
    for h in merged:
        if final and h['side'] == final[-1]['side'] and h['frame'] - final[-1]['frame'] < min_gap_same_side:
            if h['wrist_dist'] < final[-1]['wrist_dist']:
                final[-1] = h
        else:
            final.append(h)
    return final
