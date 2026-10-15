"""3D shuttle flight from a single camera, by fitting the physics of a shuttlecock.

Model (quadratic drag, e.g. Cohen et al. 2015 "The physics of badminton"):
    dv/dt = g - (g / Vinf^2) * |v| * v,   Vinf ~ 6.7 m/s (terminal velocity)
So the path is not a parabola: it leaves almost straight, brakes hard, then drops steeply.

Each shot (one hit to the next hit, or to the end of the flight) has 6 unknowns: position
and velocity at the hit. Every TrackNet observation gives 2 equations (its pixel), so a
shot of 10+ frames is over-determined. Gravity gives the metric scale a single camera lacks.
Extra anchors: start near the racket contact found from the pose, end near the next contact,
clear the net (>= 1.524 m) when the shot crosses it, stay above the floor.
"""
from math import ceil, sqrt

import numpy as np
from scipy.optimize import least_squares

from .court import W, HALF, NET_CENTRE, is_in
from .track import turn_points

G = np.array([0, 0, -9.81])


def simulate(p0, v0, t, vinf=6.7, sub=4):
    """Positions at times t (seconds from the hit, ascending, t[0] >= 0). RK4 with `sub` steps per gap."""
    # plain-float RK4: called tens of thousands of times by the optimiser, numpy overhead dominates
    k = 9.81 / vinf ** 2

    def acc(vx, vy, vz):
        s = k * sqrt(vx * vx + vy * vy + vz * vz)
        return -s * vx, -s * vy, -9.81 - s * vz

    out = np.empty((len(t), 3))
    px, py, pz = map(float, p0)
    vx, vy, vz = map(float, v0)
    now = 0.0
    for i, ti in enumerate(t):
        n = max(1, int(ceil((ti - now) * 30 * sub)))
        h = (ti - now) / n
        for _ in range(n):
            a1 = acc(vx, vy, vz)
            b = (vx + 0.5 * h * a1[0], vy + 0.5 * h * a1[1], vz + 0.5 * h * a1[2])
            a2 = acc(*b)
            c = (vx + 0.5 * h * a2[0], vy + 0.5 * h * a2[1], vz + 0.5 * h * a2[2])
            a3 = acc(*c)
            d = (vx + h * a3[0], vy + h * a3[1], vz + h * a3[2])
            a4 = acc(*d)
            px += h / 6 * (vx + 2 * b[0] + 2 * c[0] + d[0])
            py += h / 6 * (vy + 2 * b[1] + 2 * c[1] + d[1])
            pz += h / 6 * (vz + 2 * b[2] + 2 * c[2] + d[2])
            vx += h / 6 * (a1[0] + 2 * a2[0] + 2 * a3[0] + a4[0])
            vy += h / 6 * (a1[1] + 2 * a2[1] + 2 * a3[1] + a4[1])
            vz += h / 6 * (a1[2] + 2 * a2[2] + 2 * a3[2] + a4[2])
        now = ti
        out[i] = px, py, pz
    return out


def land(p0, v0, t_max=4.0, dt=1 / 240):
    """Integrate until the shuttle reaches the floor. Returns (time, point) or None."""
    t = np.arange(dt, t_max, dt)
    P = simulate(p0, v0, t, sub=1)
    below = np.nonzero(P[:, 2] <= 0)[0]
    if not len(below):
        return None
    i = below[0]
    a, b = P[i - 1] if i else np.array(p0), P[i]
    s = a[2] / (a[2] - b[2])
    return float(t[i] - dt * (1 - s)), a + s * (b - a)


def _residuals(x, cam, t, px, p_anchor, end, crosses, w):
    p0, v0 = x[:3], x[3:]
    tt = t if end is None else np.append(t, end[0])
    P = simulate(p0, v0, tt)
    obs = P[:len(t)]
    r = [(cam.project(obs) - px).ravel()]                                   # pixels
    r.append((p0 - p_anchor) / w['anchor'])                                 # start at the racket
    if end is not None:
        r.append((P[-1] - end[1]) / w['end'])                               # reach the next racket
    r.append(np.minimum(obs[:, 2], 0) / 0.05)                                # never below the floor
    if crosses:
        Y = obs[:, 1]
        i = np.nonzero(np.sign(Y[1:]) != np.sign(Y[:-1]))[0]
        if len(i):
            j = i[0]
            s = Y[j] / (Y[j] - Y[j + 1])
            z = obs[j, 2] + s * (obs[j + 1, 2] - obs[j, 2])
            r.append([max(0.0, NET_CENTRE - z) / 0.05])                     # over the net
        else:
            r.append([10.0])
    return np.concatenate([np.ravel(a) for a in r])


def _init_velocities(p0, towards_far):
    sign = 1 if towards_far else -1
    target = np.array([W / 2, sign * HALF * 0.6, 0])
    base = np.arctan2(target[1] - p0[1], target[0] - p0[0])
    for az in base + np.radians([-30, 0, 30]):
        for el in np.radians([-35, -10, 10, 35, 60]):
            for speed in (6, 12, 22, 40):
                yield speed * np.array([np.cos(el) * np.cos(az), np.cos(el) * np.sin(az), np.sin(el)])


def fit_shot(cam, frames, px, fps, hit, next_hit=None, w=None, allow_landing=True, _retry=True):
    """Fit one shot. frames/px: TrackNet observations after the hit. Returns a dict or None.
    If only the first part of the observations fits (a missed hit merged two shots), refit on that part."""
    w = w or {'anchor': np.array([0.25, 0.25, 0.25]), 'end': 0.4}
    p_anchor = np.array(hit['contact'])
    t = (np.asarray(frames) - hit['frame']) / fps
    keep = t >= 0
    t, px = t[keep], np.asarray(px, float)[keep]
    if len(t) < 6:
        return None
    towards_far = hit['side'] == 'near'
    end = None
    crosses = False
    if next_hit is not None:
        end = ((next_hit['frame'] - hit['frame']) / fps, np.array(next_hit['contact']))
        crosses = next_hit['side'] != hit['side']
    args = (cam, t, px, p_anchor, end, crosses, w)

    # physical bounds: contact between 0.3 and 3.5 m high, launch speed below ~430 km/h
    lo = np.r_[-2, -HALF - 2.5, 0.3, -120, -120, -120]
    hi = np.r_[W + 2, HALF + 2.5, 3.5, 120, 120, 120]
    p_start = np.clip(p_anchor, lo[:3] + 1e-3, hi[:3] - 1e-3)
    starts = [np.r_[p_start, v] for v in _init_velocities(p_start, towards_far)]
    costs = [np.sum(_residuals(x, *args) ** 2) for x in starts]
    best = None
    for i in np.argsort(costs)[:4]:
        sol = least_squares(_residuals, starts[i], args=args, bounds=(lo, hi), loss='soft_l1', f_scale=6.0,
                            max_nfev=300)
        if best is None or sol.cost < best.cost:
            best = sol
    p0, v0 = best.x[:3], best.x[3:]
    obs = simulate(p0, v0, t)
    err = np.hypot(*(cam.project(obs) - px).T)
    res = {'hit_frame': int(hit['frame']), 'pid': hit['pid'], 'side': hit['side'],
           'p0': p0.round(3).tolist(), 'v0': v0.round(3).tolist(),
           'speed_kmh': round(float(np.linalg.norm(v0) * 3.6), 1),
           'n_obs': int(len(t)), 'median_px': round(float(np.median(err)), 2),
           'inliers': round(float(np.mean(err < 8)), 2),
           'anchor_shift_m': round(float(np.linalg.norm(p0 - p_anchor)), 2)}
    res['good'] = bool(res['median_px'] < 6 and res['inliers'] > 0.7 and len(t) >= 8
                       and res['anchor_shift_m'] < 1.5 and res['speed_kmh'] < 360)   # club players
    if not res['good'] and _retry:
        bad = np.convolve(err > 8, np.ones(3), 'valid') == 3          # 3 misses in a row
        cut = int(np.argmax(bad)) if bad.any() else len(err)
        if 8 <= cut < len(err):
            f_kept = np.asarray(frames)[keep][:cut]
            return fit_shot(cam, f_kept, px[:cut], fps, hit, None, w, allow_landing=False, _retry=False)
    last = int(np.asarray(frames)[keep][-1] if next_hit is None else next_hit['frame'])
    res['end_frame'] = last
    res['fit_last_frame'] = int(np.asarray(frames)[keep][-1])      # beyond this the path is extrapolated
    if next_hit is None and allow_landing:
        lp = land(p0, v0)
        if lp is not None:
            res['landing'] = {'frame': int(hit['frame'] + round(lp[0] * fps)),
                              'court': [round(float(lp[1][0]), 2), round(float(lp[1][1]), 2)],
                              'in': bool(is_in(lp[1][0], lp[1][1]))}
            res['end_frame'] = res['landing']['frame']
    return res


def fit_rally(cam, shuttle, hits, fps, max_shot_s=3.0):
    """Split into shots between consecutive hits and fit each."""
    obs = shuttle[shuttle.detected]
    out = []
    for i, h in enumerate(hits):
        nxt = hits[i + 1] if i + 1 < len(hits) else None
        if nxt is not None and (nxt['frame'] - h['frame']) / fps > max_shot_s:
            nxt = None                                   # rally ended in between
        stop = nxt['frame'] if nxt else h['frame'] + int(max_shot_s * fps)
        seg = obs[(obs.frame > h['frame']) & (obs.frame < stop)]
        landing_ok = nxt is None
        if len(seg):
            # follow only the flight that starts right after the hit, up to its first gap
            f = seg.frame.to_numpy()
            gaps = np.nonzero(np.diff(f) > 6)[0]
            if len(gaps):
                seg = seg.iloc[:gaps[0] + 1]
                if nxt is not None and nxt['frame'] - seg.frame.iloc[-1] > 8:
                    nxt = None                           # lost before the next hit: no end anchor
        r = fit_shot(cam, seg.frame.to_numpy(), seg[['x', 'y']].to_numpy(), fps, h, nxt,
                     allow_landing=landing_ok)
        if r:
            out.append(validate(cam, r, obs, fps))
    return out


def recover_missed(cam, shots, shuttle, hits, players, k3d, fps, min_obs=8, passes=3):
    """Fill flights that no fitted shot explains ("orphans"), i.e. a hit we did not detect.

    For each orphan stretch of TrackNet points, infer the hit that started it:
      - if a previous shot was cut just before (the shuttle left its path), the shuttle position
        predicted by that shot at the cut is where it was hit (a physics anchor);
      - otherwise the closest wrist to the view ray, with a looser gate than normal hits.
    Then fit the orphan as a new shot, and repeat (a recovered shot can be cut again).
    """
    from .hits import best_contact, index_players
    rows, by_frame = index_players(players)
    obs = shuttle[shuttle.detected]
    hit_frames = sorted(h['frame'] for h in hits)
    added = 0
    for _ in range(passes):
        covered = set()
        for s in shots:
            if s['good']:
                covered.update(range(s['hit_frame'], s['end_frame'] + 1))
        free = obs[~obs.frame.isin(covered)]
        f = free.frame.to_numpy()
        if not len(f):
            break
        runs = np.split(np.arange(len(f)), np.nonzero(np.diff(f) > 6)[0] + 1)
        pieces = []
        for r in runs:                          # an orphan run can hold several shots: split at sharp turns
            seg = free.iloc[r]
            turns = [fr for fr, _ in turn_points(seg, min_sep=6)]
            edges = [seg.frame.iloc[0]] + turns + [seg.frame.iloc[-1] + 1]
            for a, b in zip(edges, edges[1:]):
                pieces.append(seg[(seg.frame >= a) & (seg.frame < b)])
        new = 0
        for seg in pieces:
            if len(seg) < min_obs:
                continue
            fs, px0 = int(seg.frame.iloc[0]), seg[['x', 'y']].to_numpy()[0]
            hit = None
            prev = [s for s in shots if s['good'] and s.get('cut') and 0 <= fs - s['end_frame'] <= 10]
            if prev:
                s = prev[-1]
                fh = s['end_frame'] + 1
                p = simulate(s['p0'], s['v0'], np.array([(fh - s['hit_frame']) / fps]))[0]
                p[2] = max(p[2], 0.3)
                hit = {'frame': fh, 'pid': -1, 'side': 'near' if p[1] > 0 else 'far',  # receiver: other side
                       'contact': p.round(2).tolist(), 'how': 'end of the previous predicted path'}
                near = best_contact(cam, fh, cam.project([p])[0], rows, by_frame, k3d, max_dist=1.6)
                if near:
                    hit['pid'], hit['side'] = near['pid'], near['side']
            else:
                # no wrist within 1.6 m: no anchor. An unanchored fit slides along the view ray
                # (contact pinned to the height limit, very low speed) while still matching the pixels.
                near = best_contact(cam, fs - 1, px0, rows, by_frame, k3d, window=5, max_dist=1.6)
                if near:
                    hit = dict(near, frame=fs - 1, how='closest wrist (loose gate)')
            if hit is None:
                continue
            nxt = next((h for h in hits if h['frame'] > seg.frame.iloc[-1]), None)
            if nxt is not None and nxt['frame'] - seg.frame.iloc[-1] > 8:
                nxt = None
            res = fit_shot(cam, seg.frame.to_numpy(), seg[['x', 'y']].to_numpy(), fps, hit, nxt,
                           allow_landing=nxt is None)
            if res and res['good']:
                res['inferred_hit'] = hit['how']
                shots.append(validate(cam, res, obs, fps))
                new += 1
        added += new
        if not new:
            break
    shots.sort(key=lambda s: s['hit_frame'])
    return shots, added


def validate(cam, shot, obs, fps, max_px=25, run=2):
    """Check the extrapolated part against later TrackNet points. If the real shuttle leaves the
    predicted path (a hit we missed), the shot ends there and its predicted landing is dropped."""
    later = obs[(obs.frame > shot['fit_last_frame']) & (obs.frame <= shot['end_frame'])]
    if not len(later):
        return shot
    f = later.frame.to_numpy()
    P = simulate(shot['p0'], shot['v0'], (f - shot['hit_frame']) / fps)
    off = np.hypot(*(cam.project(P) - later[['x', 'y']].to_numpy()).T) > max_px
    bad = np.convolve(off, np.ones(run), 'valid') == run
    if bad.any():
        shot['end_frame'] = int(f[int(np.argmax(bad))] - 1)
        shot['cut'] = 'shuttle left the predicted path (missed hit?)'
        shot.pop('landing', None)
    return shot


def positions(shot, fps):
    """Per-frame 3D positions of a fitted shot, for rendering."""
    f = np.arange(shot['hit_frame'], shot['end_frame'] + 1)
    P = simulate(shot['p0'], shot['v0'], (f - shot['hit_frame']) / fps)
    if shot.get('landing'):
        P[:, 2] = np.maximum(P[:, 2], 0)
    return f, P
