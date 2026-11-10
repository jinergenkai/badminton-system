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
VINF = 6.7          # terminal velocity (m/s): feather shuttles ~6.5-6.9; overridable per video (config "vinf")


def simulate(p0, v0, t, vinf=None, sub=4):
    """Positions at times t (seconds from the hit, ascending, t[0] >= 0). RK4 with `sub` steps per gap."""
    # plain-float RK4: called tens of thousands of times by the optimiser, numpy overhead dominates
    k = 9.81 / (vinf or VINF) ** 2

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


def net_clearance(p0, v0, T, n=80):
    """Height above the tape where the path crosses the net between the posts (None if it does not)."""
    P = simulate(p0, v0, np.linspace(0, max(T, 1e-3), n))
    Y = P[:, 1]
    i = np.nonzero(np.sign(Y[1:]) != np.sign(Y[:-1]))[0]
    if not len(i):
        return None
    j = i[0]
    s = Y[j] / (Y[j] - Y[j + 1])
    x = P[j, 0] + s * (P[j + 1, 0] - P[j, 0])
    if not -0.3 <= x <= W + 0.3:
        return None
    return float(P[j, 2] + s * (P[j + 1, 2] - P[j, 2]) - NET_CENTRE)


def shot_time(shot, frames, fps):
    """Seconds since the fitted contact for video frames (the contact is t0 off the hit frame)."""
    return np.maximum((np.asarray(frames) - shot['hit_frame']) / fps + shot.get('t0', 0.0), 0.0)


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
    p0, v0, t0 = x[:3], x[3:6], x[6]
    tt = t if end is None else np.append(t, end[0])
    P = simulate(p0, v0, np.maximum(tt + t0, 0))       # t0: the contact is between frames
    obs = P[:len(t)]
    r = [(cam.project(obs) - px).ravel()]                                   # pixels
    r.append((p0 - p_anchor) / w['anchor'])                                 # start at the racket
    if end is not None:
        r.append((P[-1] - end[1]) / w['end'])                               # reach the next racket
    r.append(np.minimum(obs[:, 2], 0) / 0.05)                                # never below the floor
    # whenever the path crosses the net plane between the posts it must pass over the tape
    # (not only when the next hit is on the other side: final shots and missed hits too)
    Y = P[:, 1]
    i = np.nonzero(np.sign(Y[1:]) != np.sign(Y[:-1]))[0]
    if len(i):
        j = i[0]
        s = Y[j] / (Y[j] - Y[j + 1])
        x = P[j, 0] + s * (P[j + 1, 0] - P[j, 0])
        z = P[j, 2] + s * (P[j + 1, 2] - P[j, 2])
        r.append([max(0.0, NET_CENTRE - z) / 0.05 if -0.3 <= x <= W + 0.3 else 0.0])
    else:
        r.append([10.0 if crosses else 0.0])                                 # must reach the other side
    return np.concatenate([np.ravel(a) for a in r])


def _init_velocities(p0, towards_far):
    sign = 1 if towards_far else -1
    target = np.array([W / 2, sign * HALF * 0.6, 0])
    base = np.arctan2(target[1] - p0[1], target[0] - p0[0])
    for az in base + np.radians([-30, 0, 30]):
        for el in np.radians([-35, -10, 10, 35, 60]):
            for speed in (6, 12, 22, 40):
                yield speed * np.array([np.cos(el) * np.cos(az), np.cos(el) * np.sin(az), np.sin(el)])


def _uncertainty(sol, n_obs, v0):
    """1-sigma of the launch speed and contact position from the Gauss-Newton covariance at the solution.

    Why it matters: a shot travelling along the camera's line of sight (far court -> camera) barely moves on
    the image in depth, and with the strong drag the distance covered grows only with log(launch speed):
    180 vs 280 km/h is ~1.7 m of extra depth in 0.4 s. The pixels then pin the speed poorly, and the
    covariance says so. Residuals are in px (pixel noise ~1 px) and anchor units (0.25 m ~ 1 unit), so the
    covariance is scaled by the robust spread of the pixel residuals."""
    J = sol.jac
    pix = sol.fun[:2 * n_obs]
    s = 1.4826 * np.median(np.abs(pix)) if len(pix) else 1.0
    cov = np.linalg.pinv(J.T @ J) * max(s, 1.0) ** 2
    speed = np.linalg.norm(v0)
    g = v0 / max(speed, 1e-6)
    sd_v = float(np.sqrt(max(g @ cov[3:6, 3:6] @ g, 0.0)))
    sd_p = float(np.sqrt(max(np.trace(cov[:3, :3]), 0.0)))
    return {'speed_sd_kmh': round(sd_v * 3.6, 1), 'p0_sd_m': round(sd_p, 2)}


def fit_shot(cam, frames, px, fps, hit, next_hit=None, w=None, allow_landing=True, _retry=True, pin_m=1.2):
    """Fit one shot. frames/px: TrackNet observations after the hit. Returns a dict or None.
    If only the first part of the observations fits (a missed hit merged two shots), refit on that part."""
    w = w or {'anchor': np.array([0.25, 0.25, 0.25]), 'end': 0.4}
    p_anchor = np.array(hit['contact'])
    t = (np.asarray(frames) - hit['frame']) / fps
    keep = t >= 0
    t, px = t[keep], np.asarray(px, float)[keep]
    # fast flat exchanges (drives, blocks) last only 5-10 frames; with the receiver's racket as an end
    # anchor they are still well constrained
    min_obs = 5 if next_hit is not None else 8
    if len(t) < min(min_obs, 6):
        return None
    towards_far = hit['side'] == 'near'
    end = None
    crosses = False
    if next_hit is not None:
        end = ((next_hit['frame'] - hit['frame']) / fps, np.array(next_hit['contact']))
        crosses = next_hit['side'] != hit['side']
    args = (cam, t, px, p_anchor, end, crosses, w)

    # physical bounds: contact between 0.3 and 3.5 m high, launch speed below ~430 km/h, and the
    # contact itself within 1.5 frames of the detected hit frame (7th unknown t0: a fast smash moves
    # 1.3 m in half a frame, so pinning the contact to a frame boundary biases speed and depth)
    lo = np.r_[-2, -HALF - 2.5, 0.3, -120, -120, -120, -1.5 / fps]
    hi = np.r_[W + 2, HALF + 2.5, 3.2, 120, 120, 120, 1.5 / fps]     # 3.2 m: a tall player's jump smash
    # pin the start near the racket contact. The soft-L1 loss also down-weights the anchor term once it
    # is large, so on its own the anchor cannot stop the fit sliding along the view rays (one camera has
    # no depth): pixel-perfect paths starting metres away from any player.
    # the height is pinned tighter than the floor position: the racket head is ~0.6 m from the wrist and
    # mostly above it, while depth along the view ray is what one camera cannot see
    pin = np.array([pin_m, pin_m, 0.6])
    lo[:3] = np.maximum(lo[:3], p_anchor - pin)
    hi[:3] = np.minimum(hi[:3], p_anchor + pin)
    if np.any(lo[:3] >= hi[:3]):
        return None
    p_start = np.clip(p_anchor, lo[:3] + 1e-3, hi[:3] - 1e-3)
    starts = [np.r_[p_start, v, 0.0] for v in _init_velocities(p_start, towards_far)]
    costs = [np.sum(_residuals(x, *args) ** 2) for x in starts]
    best = None
    for i in np.argsort(costs)[:4]:
        sol = least_squares(_residuals, starts[i], args=args, bounds=(lo, hi), loss='soft_l1', f_scale=6.0,
                            max_nfev=300)
        if best is None or sol.cost < best.cost:
            best = sol
    p0, v0, t0 = best.x[:3], best.x[3:6], float(best.x[6])
    obs = simulate(p0, v0, np.maximum(t + t0, 0))
    err = np.hypot(*(cam.project(obs) - px).T)
    res = {'hit_frame': int(hit['frame']), 'pid': hit['pid'], 'side': hit['side'], 'player': hit.get('player', -1),
           'hand': hit.get('hand'),
           'p0': p0.round(3).tolist(), 'v0': v0.round(3).tolist(), 't0': round(t0, 4),
           'speed_kmh': round(float(np.linalg.norm(v0) * 3.6), 1),
           'n_obs': int(len(t)), 'median_px': round(float(np.median(err)), 2),
           'inliers': round(float(np.mean(err < 8)), 2),
           'anchor_shift_m': round(float(np.linalg.norm(p0 - p_anchor)), 2)}
    res['confidence'] = 'high' if len(t) >= 8 else 'medium'
    res.update(_uncertainty(best, len(t), v0))
    # through the net is impossible: such a fit slid along the view rays
    T_end = (end[0] if end is not None else t[-1]) + t0
    clear = net_clearance(p0, v0, max(T_end, t[-1] + t0))
    res['net_clearance_m'] = None if clear is None else round(clear, 2)
    res['good'] = bool(res['median_px'] < 6 and res['inliers'] > 0.7 and len(t) >= min_obs
                       and res['anchor_shift_m'] < 1.5 and res['speed_kmh'] < 360    # club players
                       and (clear is None or clear > -0.1))
    if not res['good'] and _retry:
        bad = np.convolve(err > 8, np.ones(3), 'valid') == 3          # 3 misses in a row
        cut = int(np.argmax(bad)) if bad.any() else len(err)
        if 8 <= cut < len(err):
            f_kept = np.asarray(frames)[keep][:cut]
            return fit_shot(cam, f_kept, px[:cut], fps, hit, None, w, allow_landing=False, _retry=False)
        # the whole fit is garbage (several shots or a shuttle lying on the floor mixed in), so it cannot
        # say where to cut: grow a window from the hit instead and keep the longest one that still fits
        if len(t) > 12:
            fr = np.asarray(frames)[keep]
            best_w = None
            for k in (10, 14, 20, 28, 40):
                if k >= len(t):
                    break
                r = fit_shot(cam, fr[:k], px[:k], fps, hit, None, w, allow_landing=False, _retry=False)
                if r is None or not r['good']:
                    break
                best_w = r
            if best_w is not None:
                best_w['cut'] = 'longest window that fits (mixed observations after it)'
                return best_w
    last = int(np.asarray(frames)[keep][-1] if next_hit is None else next_hit['frame'])
    res['end_frame'] = last
    res['fit_last_frame'] = int(np.asarray(frames)[keep][-1])      # beyond this the path is extrapolated
    if next_hit is None and allow_landing:
        lp = land(p0, v0)
        if lp is not None:
            res['landing'] = {'frame': int(hit['frame'] + round((lp[0] - t0) * fps)),
                              'court': [round(float(lp[1][0]), 2), round(float(lp[1][1]), 2)],
                              'in': bool(is_in(lp[1][0], lp[1][1]))}
            res['end_frame'] = res['landing']['frame']
    return res


def fit_rally(cam, shuttle, hits, fps, max_shot_s=3.0, top_px=30):
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
            f, y = seg.frame.to_numpy(), seg.y.to_numpy()
            # a high clear leaves through the top of the frame and falls back in: same flight, and the
            # falling half is what pins the physics down, so such a gap does not end the shot
            through_top = (y[:-1] < top_px) & (y[1:] < top_px)
            gaps = np.nonzero((np.diff(f) > 6) & ~through_top)[0]
            if len(gaps):
                seg = seg.iloc[:gaps[0] + 1]
                if nxt is not None and nxt['frame'] - seg.frame.iloc[-1] > 8:
                    nxt = None                           # lost before the next hit: no end anchor
        # who hit it? the closest wrist to the view ray is ambiguous (near and far players overlap
        # on the image): fit the flight from every candidate contact and keep the one physics agrees with
        prev_side = hits[i - 1]['side'] if i and (h['frame'] - hits[i - 1]['frame']) / fps <= max_shot_s else None
        best, best_key, best_h = None, None, h
        for cand in [h] + h.get('alts', []):
            r = fit_shot(cam, seg.frame.to_numpy(), seg[['x', 'y']].to_numpy(), fps, cand, nxt,
                         allow_landing=landing_ok)
            if not r:
                continue
            key = (not r['good'], r['median_px'] + (1.5 if cand['side'] == prev_side else 0) + 2 * r['anchor_shift_m'])
            if best is None or key < best_key:
                best, best_key, best_h = r, key, cand
        if best_h is not h:                              # physics picked the other player: swap
            swapped = {k: v for k, v in best_h.items() if k != 'alts'}
            swapped['alts'] = [{k: v for k, v in h.items() if k != 'alts'}]
            swapped['side_by'] = 'flight fit'
            hits[i] = swapped
        if best:
            out.append(validate(cam, best, obs, fps))
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
        y = free.y.to_numpy()
        through_top = (y[:-1] < 30) & (y[1:] < 30)          # out through the top and back: same flight
        runs = np.split(np.arange(len(f)), np.nonzero((np.diff(f) > 6) & ~through_top)[0] + 1)
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
                p = simulate(s['p0'], s['v0'], shot_time(s, np.array([fh]), fps))[0]
                p[2] = max(p[2], 0.3)
                hit = {'frame': fh, 'pid': -1, 'side': 'far' if p[1] > 0 else 'near',  # receiver: whoever is where it is
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
    P = simulate(shot['p0'], shot['v0'], shot_time(shot, f, fps))
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
    P = simulate(shot['p0'], shot['v0'], shot_time(shot, f, fps))
    if shot.get('landing'):
        P[:, 2] = np.maximum(P[:, 2], 0)
    return f, P
