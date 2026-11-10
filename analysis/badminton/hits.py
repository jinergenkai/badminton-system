"""Racket-shuttle contacts ("hits") from the shuttle track + player poses.

Candidate moments: a flight starts, or the shuttle turns sharply / suddenly speeds up.
A candidate is a hit when, in 3D, the shuttle's view ray passes close to a player's wrist
(racket head is ~0.6 m beyond the wrist). The point on the ray nearest that wrist is the
contact estimate, which gives the contact height from a single camera.
Rule of the game: the same side cannot hit twice in a row, so near-duplicates are resolved.
"""
import numpy as np

from .keypoints import L_ANK, L_WR, NOSE, R_ANK, R_WR
from .track import turn_points


def _candidates(shuttle):
    """(frame, pixel, kind) moments where a hit may be: track starts, track ends, sharp turns."""
    out = []
    for _, t in shuttle[shuttle.detected].groupby('track'):
        out.append((int(t.frame.iloc[0]), t[['x', 'y']].to_numpy()[0], 'start'))
        # the contact itself is often in a short detection gap (blur / racket occlusion) that splits the
        # track: the new track starts already far from the racket, the old one ends right at it
        out.append((int(t.frame.iloc[-1]), t[['x', 'y']].to_numpy()[-1], 'end'))
        out += [(f, p, 'turn') for f, p in turn_points(t)]
    return out


def best_contact(cam, f, px, rows, by_frame, k3d, window=3, max_dist=1.0, min_z=0.25, side=None):
    """Player wrist closest (in 3D) to the shuttle's view ray around frame f -> hit dict or None.
    side='near'/'far' restricts the search to one half of the court."""
    d = cam.ray(px)
    best, best_score = None, np.inf
    for ff in range(f - window, f + window + 1):
        for r in by_frame.get(ff, []):
            if side is not None and rows.side[r] != side:
                continue
            # body height in pixels, to judge "near the racket" on the image at any depth
            head, la, ra = cam.project(k3d[r, [NOSE, L_ANK, R_ANK]])
            body_px = max(np.linalg.norm(head - (la + ra) / 2), 20.0)
            for name, j in (('L', L_WR), ('R', R_WR)):
                Wp = k3d[r, j] - cam.pos
                along = Wp @ d
                if along <= 0:
                    continue
                dist = np.linalg.norm(Wp - along * d)
                contact = cam.pos + along * d
                if contact[2] < min_z:          # at floor level: picking the shuttle up, not a stroke
                    continue
                # teammates stand at different depths on the same view ray, so the 3D distance alone can
                # pick the wrong one; the shuttle must also be within a racket length on the image
                img = np.linalg.norm(cam.project(k3d[r, j][None])[0] - px) / body_px
                score = dist + 0.8 * img
                if dist < max_dist and score < best_score:
                    best_score = score
                    best = {'frame': int(f), 'pid': int(rows.pid[r]), 'side': rows.side[r], 'hand': name,
                            'player': int(rows.player[r]) if 'player' in rows else -1,
                            'px': [round(float(px[0]), 1), round(float(px[1]), 1)],
                            'wrist_dist': round(float(dist), 2),
                            'wrist_z': round(float(k3d[r, j, 2]), 2),
                            'contact': [round(float(v), 2) for v in contact]}
    return best


def index_players(players):
    """(players with a 0..n-1 index, frame -> row indices of the detections allowed to hit)."""
    rows = players.reset_index(drop=True)
    keep = rows.index.to_numpy()
    if 'player' in rows:
        # bystanders (people walking past, sitting by the court) never match any player's look: drop
        # floor tracks that are almost never identified, so their wrists cannot "hit" the shuttle
        share = rows.groupby('pid').player.apply(lambda s: float((s >= 0).mean()))
        ok_pid = set(share.index[share >= 0.2])
        keep = rows.index[rows.pid.isin(ok_pid) | (rows.player >= 0)].to_numpy()
    sub = rows.loc[keep]
    return rows, {f: g.index.to_numpy() for f, g in sub.groupby('frame')}


def _choose_sides(moments, fps, switch_cost, rally_gap_s):
    """Pick the hitting side of every moment (Viterbi over each rally).

    One camera cannot tell which wrist the view ray passes: near and far players overlap on the image,
    so the closest wrist is often the wrong player. Sides alternate in a rally, so a path that keeps
    the same side twice pays switch_cost (it is possible only when a hit in between was missed)."""
    out = []
    i = 0
    while i < len(moments):
        j = i + 1
        while j < len(moments) and moments[j]['frame'] - moments[j - 1]['frame'] <= rally_gap_s * fps:
            j += 1
        rally = moments[i:j]
        sides = ('near', 'far')
        cost = [{s: (m['opts'][s]['wrist_dist'] if s in m['opts'] else np.inf) for s in sides} for m in rally]
        acc, back = [dict(cost[0])], [{}]
        for k in range(1, len(rally)):
            a, b = {}, {}
            for s in sides:
                prev = {p: acc[-1][p] + (switch_cost if p == s else 0) for p in sides}
                p = min(prev, key=prev.get)
                a[s], b[s] = prev[p] + cost[k][s], p
            acc.append(a)
            back.append(b)
        s = min(acc[-1], key=acc[-1].get)
        path = [s]
        for k in range(len(rally) - 1, 0, -1):
            s = back[k][s]
            path.append(s)
        for m, s in zip(rally, reversed(path)):
            h = dict(m['opts'][s])
            other = 'far' if s == 'near' else 'near'
            if other in m['opts']:
                h['alts'] = [m['opts'][other]]          # the flight fit may still prefer the other player
            out.append(h)
        i = j
    return out


def find_hits(cam, shuttle, players, k3d, window=3, max_dist=1.0, merge=8, min_gap_same_side=20, min_z=0.25,
              fps=30.0, switch_cost=0.8, rally_gap_s=3.0):
    """Hits in frame order: dicts with frame, pid, side, hand, player, px, wrist_dist, wrist_z, contact,
    kind, and 'alts' (the best candidate of the other side, for the flight fit to arbitrate)."""
    rows, by_frame = index_players(players)
    found = []
    for f, px, kind in _candidates(shuttle):
        opts = {}
        for side in ('near', 'far'):              # best wrist on EACH side: the closest overall is often wrong
            b = best_contact(cam, f, px, rows, by_frame, k3d, window, max_dist, min_z, side=side)
            if b:
                b['kind'] = kind
                opts[side] = b
        if opts:
            found.append({'frame': int(f), 'opts': opts})

    # one hit per moment: merge candidates close in time, keep the best supported one per side
    found.sort(key=lambda m: m['frame'])
    moments = []
    for m in found:
        if moments and m['frame'] - moments[-1]['frame'] <= merge:
            for s, b in m['opts'].items():
                cur = moments[-1]['opts'].get(s)
                if cur is None or b['wrist_dist'] < cur['wrist_dist']:
                    moments[-1]['opts'][s] = b
        else:
            moments.append(m)
    merged = _choose_sides(moments, fps, switch_cost, rally_gap_s)
    # the same side never hits twice in a row (a quick double means one of them is wrong)
    final = []
    for h in merged:
        if final and h['side'] == final[-1]['side'] and h['frame'] - final[-1]['frame'] < min_gap_same_side:
            if h['wrist_dist'] < final[-1]['wrist_dist']:
                final[-1] = h
        else:
            final.append(h)
    return final
