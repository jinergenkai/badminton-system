"""Match analytics from the reconstructed 3D scene: what each shot was, and how each player moved.

Everything here is derived from metric 3D (physics-fitted flights, players on the floor plane), which is
what a single-camera 2D tracker cannot give: real speeds in km/h, heights in metres, court zones.

Shots (one per good flight):
  type      serve / smash / clear / drop / lift / net / drive / push, from contact height, launch angle,
            speed, apex and where the shuttle went (rules below, in metres and km/h)
  speed     launch speed (km/h) — the shuttle loses ~half of it in the first 0.2 s, so also mean speed
  apex, net clearance, flight time, straight / cross-court, landing or receiving zone
  stroke    overhead / side / underarm (contact height vs. the hitter's own height),
            forehand / backhand (contact side vs. the player's dominant hand)
Players:
  distance covered, mean / top movement speed, time in front / mid / back of their half, heatmap,
  ready stance at the opponent's contact ("split step": feet apart + knees bent), reaction time
  (first push-off after the opponent's contact), recovery time (back to base after own shot)
Rallies: duration, shots, who won the point when the last shot's landing is known.
"""
import numpy as np
import pandas as pd

from .court import HALF, NET_CENTRE, SHORT, W
from .flight import shot_time, simulate
from .players import L_ANK, L_HIP, R_ANK, R_HIP

L_KNEE, R_KNEE = 13, 14
RALLY_GAP_S = 3.0
TYPES_VI = {'serve': 'giao cầu', 'smash': 'đập', 'clear': 'phông cao', 'drop': 'bỏ nhỏ (trên cao)',
            'lift': 'lốp', 'net': 'cầu lưới', 'drive': 'tạt', 'push': 'đẩy / chặn'}


def zone(y_abs):
    return 'front' if y_abs < SHORT + 0.3 else ('mid' if y_abs < HALF - 2.0 else 'back')


# ---------------------------------------------------------------- players: movement

def player_tracks(players, fps):
    """Per player: frame-indexed smoothed floor positions and speeds (gaps not bridged)."""
    out = {}
    for p, g in players[players.player >= 0].groupby('player'):
        g = g.sort_values('frame').drop_duplicates('frame')
        f = g.frame.to_numpy()
        xy = g[['X', 'Y']].to_numpy(float)
        # median then mean filter: foot keypoints jitter a few cm, occasionally jump
        med = pd.DataFrame(xy).rolling(5, center=True, min_periods=1).median()
        sm = med.rolling(7, center=True, min_periods=1).mean().to_numpy()
        dt = np.diff(f) / fps
        step = np.hypot(*np.diff(sm, axis=0).T)
        v = np.r_[0, np.where((dt > 0) & (dt < 0.2), step / np.maximum(dt, 1e-6), 0)]
        out[p] = pd.DataFrame({'frame': f, 'X': sm[:, 0], 'Y': sm[:, 1], 'speed': v,
                               'side': g.side.to_numpy(), 'row': g.index.to_numpy()}).set_index('frame')
    return out


def movement_stats(t, fps):
    ok = t.speed < 8.0                                   # faster than any human: a foot-keypoint glitch
    dt_ok = np.r_[0, np.diff(t.index) == 1]
    dist = float((t.speed[ok & (dt_ok > 0)] / fps).sum())
    moving = t.speed[ok]
    yabs = t.Y.abs()
    z = yabs.map(zone)
    return {'distance_m': round(dist, 1),
            'seen_s': round(len(t) / fps, 1),
            'mean_speed_ms': round(float(moving[moving > 0.3].mean()), 2) if (moving > 0.3).any() else 0.0,
            'top_speed_ms': round(float(np.percentile(moving, 99)), 2) if len(moving) else 0.0,
            'zones_pct': {k: round(100 * float((z == k).mean()), 1) for k in ('front', 'mid', 'back')},
            'base_position': [round(float(t.X.median()), 2), round(float(t.Y.median()), 2)]}


def heatmap(t, cell=0.5):
    nx, ny = int(np.ceil((W + 2) / cell)), int(np.ceil((2 * HALF + 4) / cell))
    H, _, _ = np.histogram2d(t.X, t.Y, bins=[nx, ny], range=[[-1, W + 1], [-HALF - 2, HALF + 2]])
    return (H / max(H.sum(), 1)).round(4).tolist()


# ---------------------------------------------------------------- players: posture

def _angle(a, b, c):
    u, v = a - b, c - b
    return float(np.degrees(np.arccos(np.clip(u @ v / (np.linalg.norm(u) * np.linalg.norm(v) + 1e-9), -1, 1))))


def posture(row, players, k3d, kpts2d, scores):
    """Stance width (m), knee angle (deg, 180 = straight), hip height (m) of one detection."""
    k = k3d[row]
    det = int(players.det[row])
    k2, s2 = kpts2d[det], scores[det]
    width = float(np.hypot(*(k[L_ANK, :2] - k[R_ANK, :2])))
    knees = [_angle(k2[h], k2[kn], k2[a]) for h, kn, a in ((L_HIP, L_KNEE, L_ANK), (R_HIP, R_KNEE, R_ANK))
             if min(s2[h], s2[kn], s2[a]) > 0.3]
    return width, (float(np.mean(knees)) if knees else np.nan), float((k[L_HIP, 2] + k[R_HIP, 2]) / 2)


# ---------------------------------------------------------------- shots

def jumped(t, f, players, kpts2d, scores, fps):
    """Was the player off the floor at frame f? Both ankles AND the hips higher on the image than in the
    stance just before (0.6-0.25 s earlier), by > 7% of the body's pixel height. Moving towards or away
    from the camera shifts the ankles too, but then the floor position changes with them; a jump leaves
    the hips and ankles rising together while the player stays in place."""
    def pts(fr):
        if fr not in t.index:
            return None
        det = int(players.det[int(t.row[fr])])
        k, sc = kpts2d[det], scores[det]
        if min(sc[L_ANK], sc[R_ANK], sc[L_HIP], sc[R_HIP], sc[0]) < 0.3:
            return None
        return (k[L_ANK, 1] + k[R_ANK, 1]) / 2, (k[L_HIP, 1] + k[R_HIP, 1]) / 2, abs((k[L_ANK, 1] + k[R_ANK, 1]) / 2 - k[0, 1])
    now = pts(f)
    before = [pts(fr) for fr in range(f - int(0.6 * fps), f - int(0.25 * fps))]
    before = [b for b in before if b is not None]
    if now is None or len(before) < 3:
        return False
    ank0, hip0, body = np.median(np.array(before), axis=0)
    return bool(ank0 - now[0] > 0.07 * body and hip0 - now[1] > 0.07 * body)


def classify(s, first_of_rally, fps):
    p0, v0 = np.array(s['p0']), np.array(s['v0'])
    speed = float(np.linalg.norm(v0) * 3.6)
    elev = float(np.degrees(np.arcsin(v0[2] / max(np.linalg.norm(v0), 1e-6))))
    T = max(shot_time(s, np.array([s['end_frame']]), fps)[0], 1 / fps)
    t = np.linspace(0, T, 60)
    P = simulate(p0, v0, t)
    if s.get('landing'):
        end = np.array([*s['landing']['court'], 0.0])
    else:
        end = P[-1]
    apex = float(P[:, 2].max())
    net = None
    cross = np.nonzero(np.sign(P[1:, 1]) != np.sign(P[:-1, 1]))[0]
    if len(cross):
        j = cross[0]
        a = P[j, 1] / (P[j, 1] - P[j + 1, 1])
        net = float(P[j, 2] + a * (P[j + 1, 2] - P[j, 2]) - NET_CENTRE)
    hz = float(np.hypot(v0[0], v0[1]))
    toward = np.sign(-p0[1]) if abs(p0[1]) > 0.05 else 1.0
    angle = float(np.degrees(np.arctan2(abs(v0[0]), max(abs(v0[1]), 1e-6)))) if hz > 0.5 else 0.0
    mean_speed = float(np.mean(np.linalg.norm(np.diff(P, axis=0), axis=1)) / (t[1] - t[0]) * 3.6)
    z0, y0, yend = p0[2], abs(p0[1]), abs(end[1])
    rise = apex - z0                                     # how much the shuttle climbs after the contact
    to = zone(yend)
    if first_of_rally:
        kind = 'serve'
    elif z0 >= 1.9 and speed >= 110 and elev < 5:       # hit down (or flat and fast) from above the head
        kind = 'smash'
    elif apex >= 3.0 and to == 'back':                   # high and deep
        kind = 'clear' if z0 >= 1.6 else 'lift'
    elif z0 < 1.3 and elev > 15 and rise > 0.6 and (to != 'front' or apex >= 2.8):
        kind = 'lift'                                    # from below, up and deep
    elif to == 'front' and z0 < 1.8 and speed < 60 and apex < 2.6:
        kind = 'net' if y0 < SHORT + 1.0 else 'push'     # short: tumbling over the net, or a block
    elif z0 >= 1.6 and rise < 0.6 and to in ('front', 'mid') and speed < 110:
        kind = 'drop'                                    # from above, falling short
    elif rise < 0.7 and speed >= 50 and 0.6 <= z0 <= 2.2:
        kind = 'drive'                                   # flat and fast
    else:
        kind = 'push'                                    # mid-speed placement, block, soft return
    return {'type': kind, 'type_vi': TYPES_VI[kind], 'speed_kmh': round(speed, 1),
            'mean_speed_kmh': round(mean_speed, 1), 'launch_angle_deg': round(elev, 1),
            'contact_height_m': round(float(z0), 2), 'apex_m': round(apex, 2),
            'net_clearance_m': None if net is None else round(net, 2),
            'flight_s': round(float(T), 2), 'direction': 'cross' if angle > 15 else 'straight',
            'to_zone': zone(yend), 'end_point': [round(float(end[0]), 2), round(float(end[1]), 2)]}


def stroke_side(k2, s2, hand):
    """forehand / backhand / centre from the 2D skeleton at the contact.

    The hitting wrist is projected on the hitter's own left-shoulder -> right-shoulder axis: on the
    side of its own shoulder (or beyond) = forehand, crossed over the body = backhand. Done in the
    image, where the skeleton is reliable; in 3D the contact's depth error (tens of cm along the view
    ray, i.e. across the court for a corner camera) would decide the answer."""
    if hand not in ('L', 'R') or min(s2[5], s2[6]) < 0.3:
        return None
    wr = 9 if hand == 'L' else 10
    if s2[wr] < 0.3:
        return None
    a, b = k2[5], k2[6]                                  # left, right shoulder
    ab = b - a
    if ab @ ab < 4:                                      # shoulders overlap: side-on to the camera
        return None
    u = (k2[wr] - a) @ ab / (ab @ ab)                    # 0 = left shoulder, 1 = right shoulder
    own = u if hand == 'R' else 1 - u
    return 'forehand' if own > 0.65 else ('backhand' if own < 0.25 else 'centre')


# ---------------------------------------------------------------- main

def analyse(shots, hits, players, k3d, kpts2d, scores, landings, fps):
    # < 10 km/h is not a stroke (a shuttle tossed to the server, a degenerate fit)
    good = sorted([s for s in shots if s['good'] and s['speed_kmh'] >= 10], key=lambda s: s['hit_frame'])
    floor_frames = sorted(e['frame'] for e in landings)
    tracks = player_tracks(players, fps)
    n_players = len(tracks)
    height = {p: float(players.nose_z[players.player == p].quantile(0.9) + 0.12) for p in tracks}

    def who(frame, side, near_point=None):
        """Player of `side` at `frame`; the one closest to near_point when two."""
        best, bd = None, 1e9
        for p, t in tracks.items():
            if frame not in t.index or t.side[frame] != side:
                continue
            d = 0 if near_point is None else np.hypot(t.X[frame] - near_point[0], t.Y[frame] - near_point[1])
            if d < bd:
                best, bd = p, d
        return best

    def same_track(s):
        """Identity of the hitter's own floor track around the hit, when the hit frame itself is not
        identified (e.g. during a jump the feet leave the floor and the position is off)."""
        if s.get('pid', -1) is None or s.get('pid', -1) < 0:
            return None
        near = players[(players.pid == s['pid']) & (players.player >= 0)
                       & ((players.frame - s['hit_frame']).abs() <= 15)]
        return int(near.player.mode()[0]) if len(near) else None

    # racket hand: at overhead contacts the racket arm is the raised one (higher wrist on the image).
    # Per-hit "closest wrist to the view ray" is not usable: both wrists are often near the ray.
    hand = {}
    for s in shots:
        p = s.get('player', -1)
        if not s['good'] or p is None or p < 0 or s['p0'][2] < 1.8 or p not in tracks:
            continue
        if s['hit_frame'] not in tracks[p].index:
            continue
        det = int(players.det[int(tracks[p].row[s['hit_frame']])])
        k2, s2 = kpts2d[det], scores[det]
        if min(s2[9], s2[10]) > 0.3 and abs(k2[9, 1] - k2[10, 1]) > 15:
            hand.setdefault(p, []).append('L' if k2[9, 1] < k2[10, 1] else 'R')
    dominant = {p: max(set(v), key=v.count) for p, v in hand.items()}

    # rallies from the good shots
    # a rally ends when the shuttle lands (landing step) or play pauses for RALLY_GAP_S
    rallies, cur = [], []
    for s in good:
        landed = cur and any(cur[-1]['hit_frame'] < f <= s['hit_frame'] for f in floor_frames)
        if cur and (landed or (s['hit_frame'] - cur[-1]['hit_frame']) / fps > RALLY_GAP_S):
            rallies.append(cur)
            cur = []
        cur.append(s)
    if cur:
        rallies.append(cur)

    shot_rows = []
    for ri, r in enumerate(rallies):
        for i, s in enumerate(r):
            p = s.get('player', -1)
            if p is None or p < 0:
                p = same_track(s) or who(s['hit_frame'], s['side'], s['p0'])
            c = classify(s, i == 0, fps)
            side_2d = None
            if p is not None and s['hit_frame'] in tracks[p].index:
                det = int(players.det[int(tracks[p].row[s['hit_frame']])])
                side_2d = stroke_side(kpts2d[det], scores[det], dominant.get(p, s.get('hand')))
            hgt = height.get(p, 1.7)
            z0 = s['p0'][2]
            sd = s.get('speed_sd_kmh')
            c.update({'speed_sd_kmh': sd,
                      # launch speed is well determined (< 10 %) except for shots along the line of sight
                      'speed_reliable': bool(sd is not None and sd < 0.10 * max(c['speed_kmh'], 1)),
                      'rally': ri + 1, 'shot_in_rally': i + 1, 'frame': s['hit_frame'],
                      'time_s': round(s['hit_frame'] / fps, 2), 'player': None if p is None else int(p) + 1,
                      'side': s['side'], 'confidence': s.get('confidence', 'high'),
                      'stroke_height': 'overhead' if z0 > 0.85 * hgt else ('side' if z0 > 0.5 * hgt else 'underarm'),
                      'stroke_side': side_2d,
                      'jump': bool(p is not None and s['p0'][2] > 1.7 and jumped(tracks[p], s['hit_frame'], players,
                                                                                  kpts2d, scores, fps)),
                      'landing_in': s['landing']['in'] if s.get('landing') else None})
            shot_rows.append(c)

    rally_rows = []
    for ri, r in enumerate(rallies):
        last = r[-1]
        winner = None
        if last.get('landing'):
            hitter_side = last['side']
            winner = hitter_side if last['landing']['in'] else ('far' if hitter_side == 'near' else 'near')
        rally_rows.append({'rally': ri + 1, 'start_s': round(r[0]['hit_frame'] / fps, 1),
                           'duration_s': round((last['end_frame'] - r[0]['hit_frame']) / fps, 1),
                           'shots': len(r), 'winner_side': winner})

    # per player
    hit_frames = [(s['hit_frame'], s['side']) for s in good]
    per_player = {}
    for p, t in tracks.items():
        side = t.side.mode()[0]
        st = movement_stats(t, fps)
        st.update({'player': int(p) + 1, 'side': side, 'height_m': round(height[p], 2),
                   'dominant_hand': dominant.get(p)})
        # readiness, reaction at the opponent's contacts
        widths, knees, ready, reacts = [], [], 0, []
        for f, s_side in hit_frames:
            if s_side == side or f not in t.index:
                continue
            w, kn, _ = posture(int(t.row[f]), players, k3d, kpts2d, scores)
            if np.isnan(kn):
                continue
            widths.append(w)
            knees.append(kn)
            ready += (w >= 0.22 * height[p]) and (kn <= 165)
            # reaction: only when (nearly) standing at the contact, else the push-off already happened
            if t.speed.get(f, 9) < 0.8:
                after = t.loc[f:f + int(fps)]
                go = after.index[after.speed > 1.5]
                if len(go):
                    reacts.append((go[0] - f) / fps)
        n = len(widths)
        st['at_opponent_contact'] = {
            'samples': n,
            'stance_width_m': round(float(np.median(widths)), 2) if n else None,
            'knee_angle_deg': round(float(np.median(knees)), 1) if n else None,
            'ready_stance_pct': round(100 * ready / n, 1) if n else None,
            'reaction_s': round(float(np.median(reacts)), 2) if reacts else None}
        # recovery after own shot: time to come back within 1 m of the base position
        base = np.array(st['base_position'])
        recs = []
        for s in good:
            if s.get('player', -1) != p or s['hit_frame'] not in t.index:
                continue
            seg = t.loc[s['hit_frame']:s['hit_frame'] + int(2 * fps)]
            back = seg.index[np.hypot(seg.X - base[0], seg.Y - base[1]) < 1.0]
            far = np.hypot(t.X[s['hit_frame']] - base[0], t.Y[s['hit_frame']] - base[1]) >= 1.0
            if far and len(back):
                recs.append((back[0] - s['hit_frame']) / fps)
        st['recovery_s'] = round(float(np.median(recs)), 2) if recs else None
        mine = [c for c in shot_rows if c['player'] == int(p) + 1]
        st['shots'] = len(mine)
        st['shot_types'] = pd.Series([c['type'] for c in mine]).value_counts().to_dict() if mine else {}
        allsm = [c for c in mine if c['type'] == 'smash']
        smash = [c['speed_kmh'] for c in allsm if c['speed_reliable']]
        st['smash_kmh'] = {'count': len(allsm), 'measured': len(smash),
                           'mean': round(float(np.mean(smash)), 1) if smash else None,
                           'max': round(float(np.max(smash)), 1) if smash else None}
        st['jump_shots'] = sum(c['jump'] for c in mine)
        st['contact_height_m'] = round(float(np.median([c['contact_height_m'] for c in mine])), 2) if mine else None
        st['strokes'] = pd.Series([c['stroke_side'] for c in mine if c['stroke_side']]).value_counts().to_dict() if mine else {}
        st['heatmap_0.5m'] = heatmap(t)
        per_player[f'P{int(p) + 1}'] = st

    return {'players': per_player, 'shots': shot_rows, 'rallies': rally_rows,
            'summary': {'players': n_players, 'rallies': len(rallies), 'shots': len(shot_rows),
                        'shot_types': pd.Series([c['type'] for c in shot_rows]).value_counts().to_dict(),
                        'landings': len(landings)}}


# ---------------------------------------------------------------- report

ZONE_VI = {'front': 'trước', 'mid': 'giữa', 'back': 'sau'}
SIDE_VI = {'near': 'phía camera', 'far': 'phía xa'}
STROKE_VI = {'forehand': 'thuận tay', 'backhand': 'trái tay', 'centre': 'giữa người'}


def _fmt(v, f='{:.0f}', unit=''):
    return '—' if v is None else f.format(v) + unit


def to_markdown(rep, name):
    L = [f'# Báo cáo trận — {name}', '']
    s = rep['summary']
    L += [f"{s['players']} người chơi · {s['rallies']} pha cầu · {s['shots']} cú đánh có đường bay 3D · "
          f"{s['landings']} điểm rơi", '']
    if s['shot_types']:
        L += ['**Các loại cú:** ' + ', '.join(f"{TYPES_VI[k]} {v}" for k, v in s['shot_types'].items()), '']
    L += ['## Người chơi', '',
          '| | Bên | Cao | Quãng đường | Tốc độ TB / tối đa | Trước / giữa / sau | Cú | Đập TB / max | '
          'Tư thế chờ | Phản ứng | Về vị trí |',
          '|---|---|---|---|---|---|---|---|---|---|---|']
    for k, p in sorted(rep['players'].items()):
        z, a, sm = p['zones_pct'], p['at_opponent_contact'], p['smash_kmh']
        smash = '—' if sm['mean'] is None else f"{sm['mean']:.0f} / {sm['max']:.0f} km/h"
        L.append(f"| **{k}** | {SIDE_VI[p['side']]} | {p['height_m']:.2f} m | {p['distance_m']:.0f} m "
                 f"| {p['mean_speed_ms']:.1f} / {p['top_speed_ms']:.1f} m/s "
                 f"| {z['front']:.0f} / {z['mid']:.0f} / {z['back']:.0f} % | {p['shots']} | {smash} "
                 f"| {_fmt(a['ready_stance_pct'], unit='%')} | {_fmt(a['reaction_s'], '{:.2f}', ' s')} "
                 f"| {_fmt(p['recovery_s'], '{:.2f}', ' s')} |")
    L += ['', '*Đập TB / max chỉ tính các cú đo được tốc độ với sai số < 10% (cú bay dọc hướng nhìn của camera,'
          ' từ cuối sân xa về phía camera, chỉ đo được độ cao/hướng; tốc độ của chúng có dấu ~ ở bảng dưới).*', '',
          '*Tư thế chờ: % số lần đối thủ chạm cầu mà người này đang dang chân ≥ 22% chiều cao và chùng gối '
          '(góc gối ≤ 160°). Phản ứng: từ lúc đối thủ chạm cầu đến lúc bắt đầu di chuyển > 1.5 m/s. Về vị trí: '
          'từ cú đánh của mình đến lúc về trong 1 m quanh vị trí trung tâm.*', '']
    for k, p in sorted(rep['players'].items()):
        if p['shot_types']:
            types = ', '.join(f"{TYPES_VI[t]} {n}" for t, n in p['shot_types'].items())
            strokes = ', '.join(f"{STROKE_VI.get(t, t)} {n}" for t, n in p['strokes'].items())
            hand = {'R': 'tay phải', 'L': 'tay trái'}.get(p['dominant_hand'], 'tay ?')
            jump = f" {p['jump_shots']} cú bật nhảy." if p.get('jump_shots') else ''
            L.append(f"- **{k}** ({hand}): {types}. {strokes}.{jump} Điểm chạm cầu cao trung vị {p['contact_height_m']} m.")
    L += ['', '## Pha cầu', '', '| Pha | Bắt đầu | Thời lượng | Số cú | Bên thắng |', '|---|---|---|---|---|']
    for r in rep['rallies']:
        L.append(f"| {r['rally']} | {r['start_s']} s | {r['duration_s']} s | {r['shots']} "
                 f"| {SIDE_VI.get(r['winner_side'], '—')} |")
    L += ['', '## Từng cú', '', '| t | Pha | Người | Loại | Tốc độ rời vợt | TB | Góc | Điểm chạm | Đỉnh | Qua lưới | '
          'Hướng | Tới | Độ tin |', '|---|---|---|---|---|---|---|---|---|---|---|---|---|']
    for c in rep['shots']:
        net = _fmt(c['net_clearance_m'], '{:+.2f}', ' m')
        kind = c['type_vi'] + (' (nhảy)' if c.get('jump') else '')
        sd = c.get('speed_sd_kmh')
        speed = f"{c['speed_kmh']:.0f} ± {sd:.0f} km/h" if sd is not None else f"{c['speed_kmh']:.0f} km/h"
        if not c.get('speed_reliable', True):
            speed = '~' + speed
        L.append(f"| {c['time_s']} s | {c['rally']}.{c['shot_in_rally']} | P{c['player'] or '?'} | {kind} "
                 f"| {speed} | {c['mean_speed_kmh']:.0f} | {c['launch_angle_deg']:.0f}° "
                 f"| {c['contact_height_m']} m ({c['stroke_height']}) | {c['apex_m']} m | {net} "
                 f"| {'chéo' if c['direction'] == 'cross' else 'thẳng'} | {ZONE_VI[c['to_zone']]} | {c['confidence']} |")
    return '\n'.join(L) + '\n'
