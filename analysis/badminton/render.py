"""Side-by-side render: real video (court overlay, shuttle trail, landings) + a separate 3D view
from an orbiting virtual camera showing the real camera, its view ray to the shuttle and the
landing spots. One camera cannot tell the shuttle's height: it lies somewhere on that ray."""
import cv2
import numpy as np

from .court import court_lines, net_top, W, HALF, NET_POST, NET_BOTTOM
from .players import BONES
from .flight import positions

YELLOW, MAGENTA, ORANGE = (0, 255, 255), (255, 80, 255), (0, 140, 255)
RAY, CAMCOL, IN_COL, OUT_COL = (80, 220, 255), (255, 200, 80), (90, 230, 90), (60, 60, 255)
NEAR_COL, FAR_COL, HIT_COL = (255, 160, 60), (200, 120, 255), (0, 255, 255)
PATH_COL = (255, 255, 120)
HIT_SHOW = 25   # frames a hit label stays up


def _seg(a, b, n=40):
    a, b = np.float64(a), np.float64(b)
    return a + (b - a) * np.linspace(0, 1, n)[:, None]


def draw_court(img, cam):
    """Court lines, net and posts projected into the real camera."""
    ov = img.copy()
    pl = lambda pts, col, th: cv2.polylines(ov, [cam.project(pts).astype(np.int32)], False, col, th, cv2.LINE_AA)
    front = lambda pts: np.all((np.float64(pts) @ cam.R.T + cam.tvec.ravel())[:, 2] > 0.3)
    for a, b in court_lines():
        pts = _seg([*a, 0], [*b, 0])
        pts = pts[(pts @ cam.R.T + cam.tvec.ravel())[:, 2] > 0.3]      # clip the part behind the lens
        if len(pts) > 1:
            pl(pts, YELLOW, 2)
    pl(net_top(), MAGENTA, 2)
    pl(_seg([0, 0, NET_BOTTOM], [W, 0, NET_BOTTOM]), MAGENTA, 2)
    for x in (0, W):
        if front([[x, 0, 0], [x, 0, NET_POST]]):
            pl(_seg([x, 0, 0], [x, 0, NET_POST], 2), ORANGE, 3)
    return cv2.addWeighted(ov, 0.75, img, 0.25, 0)


class Panel3D:
    def __init__(self, cam, landings, size, hits=()):
        self.cam, self.landings, self.hits = cam, landings, list(hits)
        self.w, self.h = size
        f = 0.95 * self.w
        self.K = np.array([[f, 0, self.w / 2], [0, f, self.h / 2], [0, 0, 1]])
        self.center = np.array([W / 2, 0, 0.0])
        # orbit around the side the real camera is on, so the panel matches the video's viewpoint
        self.yaw0 = np.arctan2(cam.pos[1] - self.center[1], cam.pos[0] - self.center[0])

    def _view(self, t):
        yaw = self.yaw0 + np.radians(35) * np.sin(t * 0.25)
        eye = self.center + np.array([14 * np.cos(yaw), 14 * np.sin(yaw), 9.0])
        f = self.center - eye
        f /= np.linalg.norm(f)
        r = np.cross(f, [0, 0, 1])
        r /= np.linalg.norm(r)
        Rv = np.stack([r, np.cross(f, r), f])
        return cv2.Rodrigues(Rv)[0], -Rv @ eye

    def _p(self, pts):
        q, _ = cv2.projectPoints(np.float64(pts).reshape(-1, 3), self.rv, self.tv, self.K, None)
        return q.reshape(-1, 2)

    def _line(self, img, pts, col, th=1, closed=False):
        cv2.polylines(img, [self._p(pts).astype(np.int32)], closed, col, th, cv2.LINE_AA)

    def render(self, frame_no, t, shuttle_px, people3d=(), path=None):
        """path: (frames, Nx3 positions) of the fitted shot covering this frame, if any."""
        cam = self.cam
        self.rv, self.tv = self._view(t)
        img = np.full((self.h, self.w, 3), (28, 22, 18), np.uint8)
        m = 2.0
        cv2.fillPoly(img, [self._p([[-m, -HALF - m, 0], [W + m, -HALF - m, 0], [W + m, HALF + m, 0],
                                    [-m, HALF + m, 0]]).astype(np.int32)], (60, 90, 40), cv2.LINE_AA)
        cv2.fillPoly(img, [self._p([[0, -HALF, 0], [W, -HALF, 0], [W, HALF, 0], [0, HALF, 0]]).astype(np.int32)],
                     (70, 130, 45), cv2.LINE_AA)
        for a, b in court_lines():
            self._line(img, [[*a, 0], [*b, 0]], (235, 235, 235), 2)

        ov = img.copy()
        sheet = [[0, 0, NET_BOTTOM], [W, 0, NET_BOTTOM], [W, 0, NET_POST], [0, 0, NET_POST]]
        cv2.fillPoly(ov, [self._p(sheet).astype(np.int32)], (210, 210, 210), cv2.LINE_AA)
        img = cv2.addWeighted(ov, 0.35, img, 0.65, 0)
        self._line(img, net_top(), (255, 255, 255), 2)
        for x in (0, W):
            self._line(img, [[x, 0, 0], [x, 0, NET_POST]], ORANGE, 3)

        # the real camera: tripod pole + frustum
        P = cam.pos
        self._line(img, [[P[0], P[1], 0], P], (160, 160, 160))
        fwd, rgt, dwn = cam.R.T @ [0, 0, 1.0], cam.R.T @ [1.0, 0, 0], cam.R.T @ [0, 1.0, 0]
        cs = [P + 0.8 * fwd + sx * 0.45 * rgt + sy * 0.25 * dwn for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        for k in cs:
            self._line(img, [P, k], CAMCOL)
        self._line(img, cs, CAMCOL, closed=True)

        for side, P3 in people3d:                      # players as 3D stick figures
            col = NEAR_COL if side == 'near' else FAR_COL
            for a, b in BONES:
                self._line(img, [P3[a], P3[b]], col, 2)
            head = self._p([P3[0]])[0].astype(int)
            cv2.circle(img, tuple(head), 4, col, -1, cv2.LINE_AA)

        for hh in self.hits:                           # contact points with height, shortly after the hit
            if 0 <= frame_no - hh['frame'] < HIT_SHOW:
                C = np.array(hh['contact'])
                self._line(img, [[C[0], C[1], 0], C], HIT_COL, 1)
                p = self._p([C])[0].astype(int)
                cv2.circle(img, tuple(p), 6, HIT_COL, -1, cv2.LINE_AA)
                cv2.putText(img, '%.2fm' % C[2], (p[0] + 8, p[1] - 6), cv2.FONT_HERSHEY_SIMPLEX, 0.5, HIT_COL, 1,
                            cv2.LINE_AA)

        if path is not None:                           # fitted 3D flight: whole path faint, flown part bright
            fr, Pp, n_fit = path
            self._line(img, Pp[:n_fit], (110, 110, 70), 1)
            for a in range(max(n_fit - 1, 0), len(Pp) - 1, 3):                         # extrapolated: dotted
                cv2.circle(img, tuple(self._p([Pp[a]])[0].astype(int)), 1, (110, 110, 70), -1)
            k = int(np.searchsorted(fr, frame_no, side='right'))
            if k >= 2:
                self._line(img, Pp[:min(k, n_fit)], PATH_COL, 2)
            cur = Pp[max(k - 1, 0)]
            self._line(img, [[cur[0], cur[1], 0], cur], (150, 150, 150), 1)          # drop line = shadow
            cv2.circle(img, tuple(self._p([[cur[0], cur[1], 0]])[0].astype(int)), 3, (90, 90, 90), -1)
            p = self._p([cur])[0].astype(int)
            cv2.circle(img, tuple(p), 6, (255, 255, 255), -1, cv2.LINE_AA)
            cv2.putText(img, '%.1fm' % cur[2], (p[0] + 8, p[1] + 4), cv2.FONT_HERSHEY_SIMPLEX, 0.45,
                        (255, 255, 255), 1, cv2.LINE_AA)
        elif shuttle_px is not None:
            d = cam.ray(shuttle_px)
            length = min(18.0, -P[2] / d[2]) if d[2] < 0 else 18.0
            end = P + d * length
            self._line(img, [P, end], RAY, 2)
            cv2.circle(img, tuple(self._p([end])[0].astype(int)), 4, RAY, -1, cv2.LINE_AA)

        shown = [e for e in self.landings if e['frame'] <= frame_no]
        for i, e in enumerate(shown):
            X, Y = e['court']
            col = IN_COL if e['in'] else OUT_COL
            age = (frame_no - e['frame']) / 30
            rr = 0.18 + (0.25 * abs(np.sin(age * 4)) if i == len(shown) - 1 and age < 4 else 0)
            ring = [[X + rr * np.cos(a), Y + rr * np.sin(a), 0.01] for a in np.linspace(0, 2 * np.pi, 32)]
            self._line(img, ring, col, 2, closed=True)
            self._line(img, [[X, Y, 0], [X, Y, 0.5]], col, 2)
            p = self._p([[X, Y, 0.55]])[0].astype(int)
            unsure = '?' if e.get('extrapolated_s', 0) > 0.5 else ''      # mostly predicted, not seen
            cv2.putText(img, '#%d %s%s' % (i + 1, 'IN' if e['in'] else 'OUT', unsure), (p[0] - 22, p[1] - 6),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, col, 1, cv2.LINE_AA)

        txt = lambda s, y, sc=0.5, col=(210, 210, 210), x=14: cv2.putText(
            img, s, (x, y), cv2.FONT_HERSHEY_SIMPLEX, sc, col, 1, cv2.LINE_AA)
        txt('3D court view', 28, 0.7, (255, 255, 255))
        txt('t = %5.1fs' % t, 52)
        if shown:
            X, Y = shown[-1]['court']
            txt('landing #%d: %.2fm from left line, %.2fm %s net' % (
                len(shown), X, abs(Y), 'beyond' if Y > 0 else 'before'), 76, 0.45)
        legend = [(CAMCOL, 'real camera'), (PATH_COL, '3D flight: solid fitted, dots extrapolated'), (RAY, 'view ray (no fit)'), (HIT_COL, 'racket contact (height)'),
                  (NEAR_COL, 'near-side player'), (FAR_COL, 'far-side player'), (IN_COL, 'landing IN'),
                  (OUT_COL, 'landing OUT')]
        for k, (col, name) in enumerate(legend):
            y = self.h - 18 - 20 * (len(legend) - 1 - k)
            cv2.line(img, (14, y - 5), (34, y - 5), col, 2)
            txt(name, y, 0.42, x=42)
        return img


def render_video(video, out_path, cam, shuttle_df, landings, trail_len=10, hits=(), players=None,
                 k3d=None, kpts=None, shots=()):
    """players: players.csv rows (with 'det' index into kpts), k3d aligned with players rows."""
    cap = cv2.VideoCapture(video)
    fps = cap.get(cv2.CAP_PROP_FPS)
    w, h = int(cap.get(3)), int(cap.get(4))
    pw = (w // 2) // 2 * 2
    panel = Panel3D(cam, landings, (pw, h), hits)
    paths = [positions(s, fps) for s in shots]
    fit_last = [s['fit_last_frame'] for s in shots]
    cover = {}
    for i, (fr, _) in enumerate(paths):
        for f_ in fr:
            cover[int(f_)] = i
    per_frame = {}
    if players is not None:
        for r, row in enumerate(players.itertuples()):
            per_frame.setdefault(int(row.frame), []).append((r, row))
    pos = {int(r.frame): (r.x, r.y) for r in shuttle_df.itertuples()}
    out = cv2.VideoWriter(out_path, cv2.VideoWriter_fourcc(*'mp4v'), fps, (w + pw, h))
    f = 0
    while True:
        ok, img = cap.read()
        if not ok:
            break
        left = draw_court(img, cam)
        trail = [pos[k] for k in range(f - trail_len, f + 1) if k in pos]
        for a, b in zip(trail, trail[1:]):
            cv2.line(left, tuple(map(int, a)), tuple(map(int, b)), (0, 0, 255), 2, cv2.LINE_AA)
        if f in pos:
            cv2.circle(left, tuple(map(int, pos[f])), 6, (0, 0, 255), -1, cv2.LINE_AA)
        people3d = []
        for r, row in per_frame.get(f, []):
            col = NEAR_COL if row.side == 'near' else FAR_COL
            k2 = kpts[int(row.det)]
            for a, b in BONES:
                cv2.line(left, tuple(map(int, k2[a])), tuple(map(int, k2[b])), col, 2, cv2.LINE_AA)
            cv2.putText(left, 'P%d' % row.pid, (int(k2[0][0]) - 10, int(k2[0][1]) - 14),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, col, 2, cv2.LINE_AA)
            people3d.append((row.side, k3d[r]))
        for hh in hits:
            if 0 <= f - hh['frame'] < HIT_SHOW:
                c = tuple(map(int, hh['px']))
                cv2.circle(left, c, 16, HIT_COL, 2, cv2.LINE_AA)
                cv2.putText(left, '%s P%d  %.2fm' % ('HIT*' if hh.get('recovered') else 'HIT', hh['pid'], hh['contact'][2]),
                            (c[0] + 18, c[1] - 10),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.6, HIT_COL, 2, cv2.LINE_AA)
        for e in landings:
            if e['frame'] <= f:
                cv2.drawMarker(left, tuple(map(int, e['px'])), IN_COL if e['in'] else OUT_COL,
                               cv2.MARKER_TILTED_CROSS, 18, 2)
        path = paths[cover[f]] if f in cover else None
        if path is not None:                           # fitted path projected back into the video
            fr, Pp = path
            q = cam.project(Pp).astype(np.int32)
            n_fit = int(np.searchsorted(fr, fit_last[cover[f]], side='right'))
            cv2.polylines(left, [q[:n_fit]], False, PATH_COL, 2, cv2.LINE_AA)        # measured: solid
            for a in range(max(n_fit - 1, 0), len(q) - 1, 3):                           # extrapolated: dotted
                cv2.circle(left, tuple(q[a]), 2, (170, 170, 120), -1, cv2.LINE_AA)
            path = (fr, Pp, n_fit)
        out.write(np.hstack([left, panel.render(f, f / fps, pos.get(f), people3d, path)]))
        f += 1
    out.release()
    return f
