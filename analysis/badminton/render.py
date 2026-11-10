"""Broadcast-style render: the real video with overlays + a side panel (static 3D court and live stats).

Left:  court lines, players as smoothed skeletons in their own colour with a name tag, the shuttle trail,
       the fitted 3D flight projected back, hit callouts (player, stroke, speed, contact height), landings.
Right: a fixed 3/4 view of the 3D scene (players, flight with height, contacts, landings) and cards:
       the last shot and each player's running distance / shot count.

Only identified players (P1..Pn) are drawn: people walking past or sitting by the court are not players.
Skeletons are interpolated through short detection gaps and smoothed over time, so they do not flicker.
Text is drawn with a real font (Segoe UI) through Pillow, so Vietnamese diacritics render.
"""
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

from .court import HALF, NET_BOTTOM, NET_POST, W, court_lines, net_top
from .flight import positions
from .players import BONES

HIT_SHOW = 28            # frames a hit callout stays up
TRAIL = 14               # shuttle trail length (frames)
LANDING_S = 2.0          # a landing is shown this long, then fades away (no permanent marks)


def _rgb(hexs):
    return tuple(int(hexs[i:i + 2], 16) for i in (1, 3, 5))


def _bgr(hexs):
    return _rgb(hexs)[::-1]


PLAYER_HEX = ['#4FC3F7', '#FFB74D', '#F06292', '#AED581', '#BA68C8', '#4DD0E1']
SHUTTLE_HEX, PATH_HEX, IN_HEX, OUT_HEX = '#FF5252', '#B3E5FC', '#69F0AE', '#FF5252'
BG_TOP, BG_BOTTOM = np.array(_bgr('#0D1117'), float), np.array(_bgr('#161B22'), float)
TEXT, MUTED, CARD = _rgb('#E6EDF3'), _rgb('#8B949E'), (22, 27, 34, 215)
TYPES_VI = {'serve': 'Giao cầu', 'smash': 'Đập', 'clear': 'Phông cao', 'drop': 'Bỏ nhỏ', 'lift': 'Lốp',
            'net': 'Cầu lưới', 'drive': 'Tạt', 'push': 'Đẩy / chặn'}


def pcol(p, bgr=True):
    h = PLAYER_HEX[p % len(PLAYER_HEX)]
    return _bgr(h) if bgr else _rgb(h)


# ---------------------------------------------------------------- fonts

class Fonts:
    def __init__(self, scale):
        win = Path('C:/Windows/Fonts')
        regular, bold = win / 'segoeui.ttf', win / 'segoeuib.ttf'
        sb = win / 'seguisb.ttf'
        def f(path, size):
            try:
                return ImageFont.truetype(str(path), max(8, int(size * scale)))
            except OSError:
                return ImageFont.load_default()
        self.small, self.body = f(regular, 13), f(regular, 15)
        self.label = f(sb if sb.exists() else bold, 14)
        self.title = f(bold, 17)
        self.big = f(bold, 34)
        self.tag = f(bold, 13)


# ---------------------------------------------------------------- smoothed skeletons

def _fill_short(a, max_gap):
    """Linear interpolation of NaN runs no longer than max_gap that have data on both sides."""
    ok = ~np.isnan(a)
    if ok.sum() < 2:
        return a
    idx = np.arange(len(a))
    filled = np.interp(idx, idx[ok], a[ok])
    out = a.copy()
    run_start = None
    for i in range(len(a) + 1):
        missing = i < len(a) and not ok[i]
        if missing and run_start is None:
            run_start = i
        elif not missing and run_start is not None:
            if run_start > 0 and i < len(a) and i - run_start <= max_gap:
                out[run_start:i] = filled[run_start:i]
            run_start = None
    return out


def _smooth(a, sigma):
    """NaN-aware Gaussian smoothing along time (axis 0, 1-D)."""
    r = int(3 * sigma)
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    v = (~np.isnan(a)).astype(float)
    num = np.convolve(np.nan_to_num(a), k, 'same')
    den = np.convolve(v, k, 'same')
    out = np.where(den > 0.35 * k.sum(), num / np.maximum(den, 1e-9), np.nan)
    return np.where(v > 0, out, np.nan)


def build_poses(players, kpts, scores, k3d, max_gap=12, sigma=1.2, thr=0.3):
    """player -> (first_frame, K2 (n,17,2), K3 (n,17,3)) with gaps filled and jitter smoothed.
    k3d rows are aligned with the players table rows."""
    out = {}
    pl = players.reset_index(drop=True)
    for p, g in pl[pl.player >= 0].groupby('player'):
        g = g.sort_values('frame').drop_duplicates('frame')
        f0, f1 = int(g.frame.min()), int(g.frame.max())
        n = f1 - f0 + 1
        K2 = np.full((n, 17, 2), np.nan)
        K3 = np.full((n, 17, 3), np.nan)
        for r, row in zip(g.index, g.itertuples()):
            i = int(row.frame) - f0
            det = int(row.det)
            ok = scores[det] > thr
            K2[i, ok] = kpts[det][ok]
            K3[i, ok] = k3d[r][ok]
        for arr in (K2, K3):
            flat = arr.reshape(n, -1)
            for c in range(flat.shape[1]):
                flat[:, c] = _smooth(_fill_short(flat[:, c], max_gap), sigma)
        out[int(p)] = (f0, K2, K3)
    return out


def poses_at(poses, f, min_joints=8):
    for p, (f0, K2, K3) in poses.items():
        i = f - f0
        if 0 <= i < len(K2):
            k2, k3 = K2[i], K3[i]
            if (~np.isnan(k2[:, 0])).sum() >= min_joints:
                yield p, k2, k3


def head_of(k):
    """Head position also when the face is not visible (players seen from behind: nose/eyes score low):
    nose; else mean of eyes/ears; else above the shoulders along hips -> shoulders. (p, neck, r) or None."""
    ok = lambda j: not np.isnan(k[j, 0])
    def mid(a, b):
        pts = [k[j] for j in (a, b) if ok(j)]
        return np.mean(pts, axis=0) if pts else None
    neck, hips = mid(5, 6), mid(11, 12)
    sw = float(np.linalg.norm(k[5] - k[6])) if ok(5) and ok(6) else 0.0
    p = k[0] if ok(0) else None
    if p is None:
        face = [k[j] for j in (1, 2, 3, 4) if ok(j)]
        if face:
            p = np.mean(face, axis=0)
    if p is None and neck is not None:
        if hips is not None:
            p = neck + 0.42 * (neck - hips)
        elif k.shape[1] == 3:
            p = neck + np.array([0, 0, 0.25])
        else:
            p = neck - np.array([0, max(sw, 10) * 0.8])
    if p is None:
        return None
    torso = float(np.linalg.norm(neck - hips)) if neck is not None and hips is not None else sw * 1.5
    return p, neck, max(4.0, min(0.2 * torso, 0.45 * sw if sw else 0.2 * torso))


def _draw_skeleton(img, k2, col, th):
    hd = head_of(k2)
    for a, b in BONES:
        if a == 0 or b == 0 or np.isnan(k2[a, 0]) or np.isnan(k2[b, 0]):
            continue
        pa, pb = tuple(np.int32(k2[a])), tuple(np.int32(k2[b]))
        cv2.line(img, pa, pb, (20, 20, 20), th + 3, cv2.LINE_AA)
        cv2.line(img, pa, pb, col, th, cv2.LINE_AA)
    if hd is not None:                                   # neck + head circle, also seen from the back
        p, neck, r = hd
        if neck is not None:
            cv2.line(img, tuple(np.int32(neck)), tuple(np.int32(p)), (20, 20, 20), th + 3, cv2.LINE_AA)
            cv2.line(img, tuple(np.int32(neck)), tuple(np.int32(p)), col, th, cv2.LINE_AA)
        cv2.circle(img, tuple(np.int32(p)), int(r), (20, 20, 20), th + 3, cv2.LINE_AA)
        cv2.circle(img, tuple(np.int32(p)), int(r), col, th, cv2.LINE_AA)
    for j in range(5, 17):
        if not np.isnan(k2[j, 0]):
            cv2.circle(img, tuple(np.int32(k2[j])), max(2, th - 1), (255, 255, 255), -1, cv2.LINE_AA)


# ---------------------------------------------------------------- left: video overlay

def _seg(a, b, n=40):
    a, b = np.float64(a), np.float64(b)
    return a + (b - a) * np.linspace(0, 1, n)[:, None]


def draw_court(img, cam, alpha=0.55):
    """Thin court lines, net and posts projected into the real camera."""
    ov = img.copy()
    def pl(pts, col, th):
        pts = np.float64(pts)
        pts = pts[(pts @ cam.R.T + cam.tvec.ravel())[:, 2] > 0.3]      # clip the part behind the lens
        if len(pts) > 1:
            cv2.polylines(ov, [cam.project(pts).astype(np.int32)], False, col, th, cv2.LINE_AA)
    for a, b in court_lines():
        pl(_seg([*a, 0], [*b, 0]), (250, 245, 235), 2)
    pl(net_top(), (255, 255, 255), 2)
    pl(_seg([0, 0, NET_BOTTOM], [W, 0, NET_BOTTOM]), (200, 200, 200), 1)
    for x in (0, W):
        pl(_seg([x, 0, 0], [x, 0, NET_POST], 2), _bgr('#FFB74D'), 3)
    return cv2.addWeighted(ov, alpha, img, 1 - alpha, 0)


def _glow_polyline(img, pts, col, core=2, glow=8, glow_alpha=0.35):
    if len(pts) < 2:
        return img
    ov = img.copy()
    cv2.polylines(ov, [np.int32(pts)], False, col, glow, cv2.LINE_AA)
    img = cv2.addWeighted(ov, glow_alpha, img, 1 - glow_alpha, 0)
    cv2.polylines(img, [np.int32(pts)], False, col, core, cv2.LINE_AA)
    return img


# ---------------------------------------------------------------- right: static 3D view

class Court3D:
    """Fixed 3/4 view from the real camera's side, rendered 2x and downsampled (smooth lines)."""

    def __init__(self, cam, size, ss=2, fps=30.0, zoom=1.0):
        self.cam, self.ss, self.fps = cam, ss, fps
        self.w, self.h = size[0] * ss, size[1] * ss
        f = 0.94 * zoom * self.w
        self.K = np.array([[f, 0, self.w * 0.5], [0, f, self.h * 0.42], [0, 0, 1]])
        c = np.array([W / 2, 0.0, 1.2])
        yaw = np.arctan2(cam.pos[1], cam.pos[0] - W / 2) + np.radians(22)
        eye = c + np.array([17.5 * np.cos(yaw), 17.5 * np.sin(yaw), 10.0])
        fw = c - eye
        fw /= np.linalg.norm(fw)
        r = np.cross(fw, [0, 0, 1])
        r /= np.linalg.norm(r)
        Rv = np.stack([r, np.cross(fw, r), fw])
        self.rv, self.tv = cv2.Rodrigues(Rv)[0], -Rv @ eye
        self.base = self._background()

    def p(self, pts):
        q, _ = cv2.projectPoints(np.float64(pts).reshape(-1, 3), self.rv, self.tv, self.K, None)
        return q.reshape(-1, 2)

    def line(self, img, pts, col, th=1, closed=False):
        cv2.polylines(img, [self.p(pts).astype(np.int32)], closed, col, th * self.ss, cv2.LINE_AA)

    def _background(self):
        y = np.linspace(0, 1, self.h)[:, None, None]
        img = (BG_TOP * (1 - y) + BG_BOTTOM * y).repeat(self.w, 1).astype(np.uint8)
        m = 2.2
        cv2.fillPoly(img, [self.p([[-m, -HALF - m, 0], [W + m, -HALF - m, 0], [W + m, HALF + m, 0],
                                   [-m, HALF + m, 0]]).astype(np.int32)], _bgr('#1B3A2A'), cv2.LINE_AA)
        cv2.fillPoly(img, [self.p([[0, -HALF, 0], [W, -HALF, 0], [W, HALF, 0], [0, HALF, 0]]).astype(np.int32)],
                     _bgr('#1F6B47'), cv2.LINE_AA)
        for a, b in court_lines():
            self.line(img, [[*a, 0], [*b, 0]], (235, 240, 240), 1)
        ov = img.copy()
        sheet = [[0, 0, NET_BOTTOM], [W, 0, NET_BOTTOM], [W, 0, NET_POST], [0, 0, NET_POST]]
        cv2.fillPoly(ov, [self.p(sheet).astype(np.int32)], (220, 220, 220), cv2.LINE_AA)
        img = cv2.addWeighted(ov, 0.22, img, 0.78, 0)
        self.line(img, net_top(), (255, 255, 255), 1)
        for x in (0, W):
            self.line(img, [[x, 0, 0], [x, 0, NET_POST]], _bgr('#FFB74D'), 2)
        # the real camera, small
        P = self.cam.pos
        self.line(img, [[P[0], P[1], 0], P], (110, 120, 130), 1)
        c = self.p([P])[0].astype(int)
        cv2.circle(img, tuple(c), 5 * self.ss, _bgr('#79C0FF'), -1, cv2.LINE_AA)
        return img

    def render(self, f, people, path, contacts, landings):
        img = self.base.copy()
        sh = img.copy()
        for p, k3 in people:                                  # floor shadows
            foot = np.nanmean(k3[[15, 16], :2], axis=0) if not np.isnan(k3[[15, 16], 0]).all() else None
            if foot is not None:
                q = self.p([[foot[0], foot[1], 0]])[0].astype(int)
                cv2.ellipse(sh, tuple(q), (14 * self.ss, 5 * self.ss), 0, 0, 360, (10, 20, 14), -1, cv2.LINE_AA)
        img = cv2.addWeighted(sh, 0.6, img, 0.4, 0)
        for p, k3 in people:
            col = pcol(p)
            for a, b in BONES:
                if a and b and not (np.isnan(k3[a, 0]) or np.isnan(k3[b, 0])):
                    self.line(img, [k3[a], k3[b]], col, 2)
            hd = head_of(k3)
            if hd is not None:
                if hd[1] is not None:
                    self.line(img, [hd[1], hd[0]], col, 2)
                cv2.circle(img, tuple(self.p([hd[0]])[0].astype(int)), 5 * self.ss, col, -1, cv2.LINE_AA)
        for C in contacts:
            q = self.p([C])[0].astype(int)
            self.line(img, [[C[0], C[1], 0], C], _bgr('#FFD54F'), 1)
            cv2.circle(img, tuple(q), 6 * self.ss, _bgr('#FFD54F'), -1, cv2.LINE_AA)
        ball = None
        if path is not None:
            fr, Pp, n_fit = path
            k = int(np.searchsorted(fr, f, side='right'))
            ghost = img.copy()
            self.line(ghost, Pp, _bgr(PATH_HEX), 1)
            img = cv2.addWeighted(ghost, 0.35, img, 0.65, 0)
            if k >= 2:
                glow = img.copy()
                self.line(glow, Pp[:k], _bgr(PATH_HEX), 6)
                img = cv2.addWeighted(glow, 0.3, img, 0.7, 0)
                self.line(img, Pp[:k], _bgr(PATH_HEX), 2)
            cur = Pp[max(k - 1, 0)]
            self.line(img, [[cur[0], cur[1], 0], cur], (130, 140, 150), 1)
            q0 = self.p([[cur[0], cur[1], 0]])[0].astype(int)
            cv2.ellipse(img, tuple(q0), (6 * self.ss, 2 * self.ss), 0, 0, 360, (40, 50, 50), -1, cv2.LINE_AA)
            q = self.p([cur])[0].astype(int)
            cv2.circle(img, tuple(q), 7 * self.ss, (255, 255, 255), -1, cv2.LINE_AA)
            cv2.circle(img, tuple(q), 9 * self.ss, _bgr(SHUTTLE_HEX), 2 * self.ss, cv2.LINE_AA)
            ball = (q / self.ss, float(cur[2]))
        marks = []
        for e in landings:                                    # only around the moment it lands, fading
            age = (f - e['frame']) / self.fps
            if not 0 <= age < LANDING_S:
                continue
            X, Y = e['court']
            col = _bgr(IN_HEX if e['in'] else OUT_HEX)
            ring = [[X + 0.22 * np.cos(a), Y + 0.22 * np.sin(a), 0.01] for a in np.linspace(0, 2 * np.pi, 32)]
            ov = img.copy()
            self.line(ov, ring, col, 2, closed=True)
            a_ = 1.0 - max(0.0, age - LANDING_S * 0.6) / (LANDING_S * 0.4)
            img = cv2.addWeighted(ov, a_, img, 1 - a_, 0)
            marks.append((self.p([[X, Y, 0]])[0] / self.ss, e['in'], a_))
        img = cv2.resize(img, (self.w // self.ss, self.h // self.ss), interpolation=cv2.INTER_AREA)
        return img, ball, marks


# ---------------------------------------------------------------- UI cards (Pillow)

def _pill(d, xy, text, font, fill, fg=(255, 255, 255), pad=(9, 4), r=None):
    x, y = xy
    bb = d.textbbox((0, 0), text, font=font)
    w, h = bb[2] - bb[0] + 2 * pad[0], bb[3] - bb[1] + 2 * pad[1]
    d.rounded_rectangle([x, y, x + w, y + h], radius=r if r is not None else h // 2, fill=fill)
    d.text((x + pad[0] - bb[0], y + pad[1] - bb[1]), text, font=font, fill=fg)
    return w, h


def _fade(age, total, rise=4, fall=8):
    if age < rise:
        return age / rise
    if age > total - fall:
        return max(0.0, (total - age) / fall)
    return 1.0


# ---------------------------------------------------------------- main

def render_video(video, out_path, cam, shuttle_df, landings, hits=(), players=None, k3d=None, kpts=None,
                 scores=None, shots=(), report=None, tracks=None, layout='horizontal', panel_position='below'):
    """players: players.csv (with 'player', 'det'); k3d aligned with players rows; tracks: analytics
    player_tracks (smoothed floor positions) for the running distance.

    layout='horizontal': video | panel side by side. layout='vertical': a 9:16 portrait frame for
    TikTok / Reels / Shorts: the video full width, the analysis (3D court + cards) above or below it.
    The video itself only gets skeletons, name tags, the shuttle and the flight line: all numbers are in
    the panel."""
    cap = cv2.VideoCapture(video)
    fps = cap.get(cv2.CAP_PROP_FPS)
    w, h = int(cap.get(3)), int(cap.get(4))
    sv = h / 576.0                                      # scale of what is drawn on the video
    if layout == 'vertical':
        OW = w // 2 * 2
        OH = int(round(OW * 16 / 9)) // 2 * 2
        PW, PH = OW, OH - h
        video_y = 0 if panel_position == 'below' else PH
        panel_x, panel_y = 0, (h if panel_position == 'below' else 0)
        h3d = int(PH * 0.6) // 2 * 2
        sp = PW / 560.0
    else:
        PW, PH = int(round(0.5 * w / 2)) * 2, h
        OW, OH = w + PW, h
        video_y, panel_x, panel_y = 0, w, 0
        h3d = int(h * 0.56) // 2 * 2
        sp = sv
    fonts_v, fonts = Fonts(sv), Fonts(sp)
    view = Court3D(cam, (PW, h3d), fps=fps, zoom=1.35 if layout == 'vertical' else 1.0)

    poses = build_poses(players, kpts, scores, k3d) if players is not None and scores is not None else {}
    paths = [positions(sh, fps) for sh in shots]
    fit_last = [sh['fit_last_frame'] for sh in shots]
    cover = {}
    for i, (fr, _) in enumerate(paths):
        for f_ in fr:
            cover[int(f_)] = i
    pos = {int(r.frame): (r.x, r.y) for r in shuttle_df.itertuples()}
    rshots = sorted((report or {}).get('shots', []), key=lambda c: c['frame'])
    shot_frames = np.array([c['frame'] for c in rshots]) if rshots else np.array([], int)
    rally_start = np.array([int(round(r['start_s'] * fps)) for r in (report or {}).get('rallies', [])])
    contacts = [(hh['frame'], np.array(hh['contact']), tuple(hh['px'])) for hh in hits]
    landings = sorted(landings, key=lambda e: e['frame'])
    dist = {}
    for p, t in (tracks or {}).items():
        step = np.where(t.speed < 8.0, t.speed * np.r_[0, np.diff(t.index)] / fps, 0)
        dist[p] = (t.index.to_numpy(), np.cumsum(step))
    n_players = len(poses) or len(dist)
    gy_bg = np.linspace(0, 1, PH)[:, None, None]
    panel_bg = (BG_TOP * (1 - gy_bg) + BG_BOTTOM * gy_bg).repeat(PW, 1).astype(np.uint8)

    out = cv2.VideoWriter(out_path, cv2.VideoWriter_fourcc(*'mp4v'), fps, (OW, OH))
    f = 0
    while True:
        ok, img = cap.read()
        if not ok:
            break
        left = draw_court(img, cam)
        people = list(poses_at(poses, f))

        path = None                                     # fitted flight projected back
        if f in cover:
            fr, Pp = paths[cover[f]]
            n_fit = int(np.searchsorted(fr, fit_last[cover[f]], side='right'))
            q = cam.project(Pp).astype(np.int32)
            ov = left.copy()
            cv2.polylines(ov, [q[:n_fit]], False, _bgr(PATH_HEX), 2, cv2.LINE_AA)
            left = cv2.addWeighted(ov, 0.5, left, 0.5, 0)
            for a in range(max(n_fit - 1, 0), len(q) - 1, 3):
                cv2.circle(left, tuple(q[a]), 2, _bgr(PATH_HEX), -1, cv2.LINE_AA)
            path = (fr, Pp, n_fit)

        for p, k2, _ in people:
            _draw_skeleton(left, k2, pcol(p), max(2, int(2.5 * sv)))

        trail = [pos[k] for k in range(f - TRAIL, f + 1) if k in pos]
        if len(trail) > 1:
            left = _glow_polyline(left, trail, _bgr(SHUTTLE_HEX), core=max(2, int(2 * sv)), glow=int(9 * sv))
        if f in pos:
            c = tuple(map(int, pos[f]))
            cv2.circle(left, c, int(9 * sv), _bgr(SHUTTLE_HEX), 2, cv2.LINE_AA)
            cv2.circle(left, c, int(4 * sv), (255, 255, 255), -1, cv2.LINE_AA)

        live_hits = [(fr_, C, px) for fr_, C, px in contacts if 0 <= f - fr_ < HIT_SHOW]
        for fr_, C, px in live_hits:                    # a short pulse at the contact, no text
            age = f - fr_
            rr = int((12 + 14 * min(age, 8) / 8) * sv)
            a = _fade(age, HIT_SHOW)
            ov = left.copy()
            cv2.circle(ov, tuple(map(int, px)), rr, _bgr('#FFD54F'), 2, cv2.LINE_AA)
            left = cv2.addWeighted(ov, a, left, 1 - a, 0)

        for e in landings:                              # landing ring only for LANDING_S, fading
            age = (f - e['frame']) / fps
            if not 0 <= age < LANDING_S:
                continue
            X, Y = e['court']
            ring = cam.project([[X + 0.25 * np.cos(t), Y + 0.25 * np.sin(t), 0] for t in np.linspace(0, 2 * np.pi, 24)])
            a = 1.0 - max(0.0, age - LANDING_S * 0.6) / (LANDING_S * 0.4)
            ov = left.copy()
            cv2.polylines(ov, [ring.astype(np.int32)], True, _bgr(IN_HEX if e['in'] else OUT_HEX), 2, cv2.LINE_AA)
            left = cv2.addWeighted(ov, a, left, 1 - a, 0)

        panel3d, ball, marks = view.render(f, [(p, k3) for p, _, k3 in people], path,
                                           [C for _, C, _ in live_hits], landings)
        panel = panel_bg.copy()
        panel[:h3d] = panel3d
        frame = np.zeros((OH, OW, 3), np.uint8)
        frame[video_y:video_y + h, :w] = left
        frame[panel_y:panel_y + PH, panel_x:panel_x + PW] = panel

        pil = Image.fromarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)).convert('RGBA')
        layer = Image.new('RGBA', pil.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)

        for p, k2, _ in people:                         # only small name tags on the video
            hd = head_of(k2)
            if hd is not None:
                hx, hy = hd[0][0], hd[0][1] - hd[2] + 8
                txt = f'P{p + 1}'
                bb = d.textbbox((0, 0), txt, font=fonts_v.tag)
                _pill(d, (int(hx - (bb[2] - bb[0]) / 2 - 8), int(video_y + hy - 34 * sv)), txt, fonts_v.tag,
                      pcol(p, False) + (230,), fg=(15, 17, 21))

        X0, Y0 = panel_x, panel_y
        u = lambda v: int(v * sp)
        # panel header: rally / shot count and time (moved off the video)
        ri = int(np.searchsorted(rally_start, f, side='right')) if len(rally_start) else 0
        n_shot = sum(1 for c in rshots if c['rally'] == ri and c['frame'] <= f) if ri else 0
        d.text((X0 + u(14), Y0 + u(12)), 'SÂN 3D', font=fonts.tag, fill=MUTED + (255,))
        status = f"PHA {ri}  ·  CÚ {n_shot}" if ri else 'KHỞI ĐỘNG'
        tt = f'{int(f / fps // 60):02d}:{f / fps % 60:04.1f}'
        bb = d.textbbox((0, 0), status, font=fonts.label)
        _pill(d, (X0 + PW - u(14) - (bb[2] - bb[0]) - u(18), Y0 + u(10)), status, fonts.label, (13, 17, 23, 210),
              fg=TEXT, r=u(8))
        bb2 = d.textbbox((0, 0), tt, font=fonts.small)
        _pill(d, (X0 + PW - u(14) - (bb2[2] - bb2[0]) - u(18), Y0 + u(42)), tt, fonts.small, (13, 17, 23, 170),
              fg=MUTED, r=u(6))
        if ball is not None:
            (bx_, by_), bz = ball
            _pill(d, (int(X0 + bx_ + u(12)), int(Y0 + by_ - u(12))), f'{bz:.1f} m', fonts.small,
                  (255, 255, 255, 225), fg=(15, 17, 21))
        for (mx, my), inn, a_ in marks:
            d.text((X0 + mx + u(8), Y0 + my - u(8)), 'IN' if inn else 'OUT', font=fonts.tag,
                   fill=_rgb(IN_HEX if inn else OUT_HEX) + (int(255 * a_),))

        # last shot card
        k = int(np.searchsorted(shot_frames, f, side='right')) - 1
        cx0, cy0, cw = X0 + u(12), Y0 + h3d + u(8), PW - u(24)
        ch = u(118)
        d.rounded_rectangle([cx0, cy0, cx0 + cw, cy0 + ch], radius=u(12), fill=CARD)
        d.text((cx0 + u(14), cy0 + u(10)), 'CÚ VỪA ĐÁNH', font=fonts.tag, fill=MUTED + (255,))
        if k >= 0:
            c = rshots[k]
            p = (c['player'] or 1) - 1
            fresh = f - c['frame'] < HIT_SHOW
            _pill(d, (cx0 + u(14), cy0 + u(34)), f"P{p + 1}", fonts.tag, pcol(p, False) + (255,), fg=(15, 17, 21))
            d.text((cx0 + u(54), cy0 + u(32)), TYPES_VI.get(c['type'], c['type']) +
                   (' · bật nhảy' if c.get('jump') else ''), font=fonts.title, fill=TEXT + (255,))
            unsure = not c.get('speed_reliable', True)
            big = ('~' if unsure else '') + f"{c['speed_kmh']:.0f}"
            d.text((cx0 + u(14), cy0 + u(58)), big, font=fonts.big,
                   fill=(MUTED if unsure else (_rgb('#FFD54F') if fresh else TEXT)) + (255,))
            bb = d.textbbox((0, 0), big, font=fonts.big)
            sd = c.get('speed_sd_kmh')
            d.text((cx0 + u(20) + bb[2], cy0 + u(76)), 'km/h' + (f'  ± {sd:.0f}' if sd is not None else ''),
                   font=fonts.small, fill=MUTED + (255,))
            facts = [f"chạm {c['contact_height_m']:.2f} m", f"đỉnh {c['apex_m']:.1f} m",
                     'chéo sân' if c['direction'] == 'cross' else 'thẳng']
            if c.get('net_clearance_m') is not None:
                facts.insert(2, f"qua lưới {c['net_clearance_m']:+.2f} m")
            fx = cx0 + int(max(u(150), cw * 0.45))
            for i, t in enumerate(facts[:4]):
                d.text((fx, cy0 + u(34 + 19 * i)), t, font=fonts.small, fill=TEXT + (255,))
        else:
            d.text((cx0 + u(14), cy0 + u(40)), 'Chưa có cú đánh', font=fonts.body, fill=MUTED + (255,))

        # player cards
        gy = cy0 + ch + u(10)
        cols = max(1, n_players)
        gw = (cw - u(8) * (cols - 1)) // cols
        gh = min(Y0 + PH - gy - u(12), u(120))
        for p in range(cols):
            x = cx0 + p * (gw + u(8))
            d.rounded_rectangle([x, gy, x + gw, gy + gh], radius=u(10), fill=CARD)
            d.rounded_rectangle([x, gy, x + gw, gy + u(4)], radius=u(2), fill=pcol(p, False) + (255,))
            d.text((x + u(10), gy + u(10)), f'P{p + 1}', font=fonts.title, fill=pcol(p, False) + (255,))
            dm = 0.0
            if p in dist:
                fr_, cum = dist[p]
                j = int(np.searchsorted(fr_, f, side='right')) - 1
                dm = float(cum[j]) if j >= 0 else 0.0
            nshots = sum(1 for c in rshots if c['frame'] <= f and (c['player'] or 0) - 1 == p)
            d.text((x + u(10), gy + u(36)), f'{dm:.0f} m', font=fonts.label, fill=TEXT + (255,))
            d.text((x + u(10), gy + u(56)), f'{nshots} cú', font=fonts.small, fill=MUTED + (255,))

        out_img = Image.alpha_composite(pil, layer).convert('RGB')
        out.write(cv2.cvtColor(np.asarray(out_img), cv2.COLOR_RGB2BGR))
        f += 1
    out.release()
    return f
