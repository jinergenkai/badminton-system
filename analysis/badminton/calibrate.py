"""Fit the court model to the background, then recover the camera (intrinsics + pose).

Needs >= 4 rough seed correspondences (court metres -> pixel; points outside the frame are fine,
e.g. intersections extrapolated from visible lines). The homography is then refined so all court
lines sit on the painted white lines (chamfer distance), while staying near the seeds so it cannot
collapse onto a single line. The focal length is derived from the floor homography.
"""
import cv2
import numpy as np
from scipy.optimize import minimize

from .background import white_mask
from .court import court_lines, W, HALF


def line_distance_map(bg, floor_top, ignore):
    white = white_mask(bg)
    white[:floor_top] = 0
    for x0, y0, x1, y1 in ignore:
        white[y0:y1, x0:x1] = 0
    # keep thin strokes only: drops the wide light reflections on a glossy floor
    thin = cv2.subtract(white, cv2.morphologyEx(white, cv2.MORPH_OPEN, np.ones((11, 11), np.uint8)))
    return cv2.distanceTransform(255 - thin, cv2.DIST_L2, 3)


def fit(bg, seeds, floor_top=0, ignore=()):
    h, w = bg.shape[:2]
    dist = line_distance_map(bg, floor_top, ignore)
    court_pts = np.float32([s[0] for s in seeds])
    img_pts = np.float32([s[1] for s in seeds])
    H0, _ = cv2.findHomography(court_pts, img_pts, 0)
    seed_h = np.c_[court_pts, np.ones(len(court_pts))]

    samples = np.float64([(a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1]), 1)
                          for a, b in court_lines() for t in np.linspace(0, 1, 120)])

    def cost(p):
        Hm = np.append(p, 1).reshape(3, 3)
        q = samples @ Hm.T
        front = q[:, 2] > 1e-6                     # drop points behind the camera
        q = q[front, :2] / q[front, 2:]
        ok = (q[:, 0] >= 0) & (q[:, 0] < w - 1) & (q[:, 1] >= floor_top) & (q[:, 1] < h - 1)
        if ok.sum() < 150:
            return 1e6
        s = seed_h @ Hm.T
        drift = np.hypot(*(s[:, :2] / s[:, 2:] - img_pts).T)
        anchor = 0.05 * np.maximum(drift - 25, 0).sum()
        return np.minimum(dist[q[ok, 1].astype(int), q[ok, 0].astype(int)], 12).mean() + anchor

    p0 = (H0 / H0[2, 2]).flatten()[:8]
    res = minimize(cost, p0, method='Powell', options={'maxiter': 20000, 'xtol': 1e-6, 'ftol': 1e-6})
    H = np.append(res.x, 1).reshape(3, 3)

    # focal length from the plane homography (square pixels, principal point at centre)
    cx, cy = w / 2, h / 2
    A = np.array([[1, 0, -cx], [0, 1, -cy], [0, 0, 1]]) @ H
    h1, h2 = A[:, 0], A[:, 1]
    f2 = -(h1[0] * h2[0] + h1[1] * h2[1]) / (h1[2] * h2[2])
    f = float(np.sqrt(f2)) if f2 > 0 else float(w)
    K = np.array([[f, 0, cx], [0, f, cy], [0, 0, 1]])

    grid = np.float64([[x, y, 0] for x in np.linspace(0, W, 7) for y in np.linspace(-HALF, HALF, 15)])
    q = np.c_[grid[:, :2], np.ones(len(grid))] @ H.T          # homogeneous floor points
    front = q[:, 2] > 1e-6
    proj = q[front, :2] / q[front, 2:]
    _, rvec, tvec = cv2.solvePnP(grid[front], proj, K, None, flags=cv2.SOLVEPNP_ITERATIVE)
    R = cv2.Rodrigues(rvec)[0]
    cam = (-R.T @ tvec).ravel()
    return {'H': H.tolist(), 'K': K.tolist(), 'rvec': rvec.ravel().tolist(), 'tvec': tvec.ravel().tolist(),
            'camera_m': cam.round(3).tolist(), 'fit_cost_px': round(float(res.fun), 3),
            'seed_cost_px': round(float(cost(p0)), 3), 'size': [w, h]}


class Camera:
    """Calibrated camera: project court points, cast view rays."""

    def __init__(self, calib):
        self.H = np.array(calib['H'])
        self.Hi = np.linalg.inv(self.H)
        self.K = np.array(calib['K'])
        self.rvec = np.array(calib['rvec'])
        self.tvec = np.array(calib['tvec'])
        self.R = cv2.Rodrigues(self.rvec)[0]
        self.pos = (-self.R.T @ self.tvec).ravel()
        self.size = calib['size']

    def project(self, pts):
        q, _ = cv2.projectPoints(np.float64(pts).reshape(-1, 3), self.rvec, self.tvec, self.K, None)
        return q.reshape(-1, 2)

    def to_floor(self, px):
        """Pixel -> court (X, Y) assuming the point lies on the floor."""
        return cv2.perspectiveTransform(np.float64([[px]]), self.Hi)[0, 0]

    def ray(self, px):
        d = self.R.T @ np.linalg.inv(self.K) @ np.array([px[0], px[1], 1.0])
        return d / np.linalg.norm(d)

    def region_mask(self, xs, ys, zs):
        """Image mask of a court-space box, sampled densely; points behind the camera are dropped."""
        w, h = self.size
        g = np.float64(np.meshgrid(xs, ys, zs)).reshape(3, -1).T
        g = g[(g @ self.R.T + self.tvec.ravel())[:, 2] > 0.3]
        m = np.zeros((h, w), np.uint8)
        if len(g):
            pts = np.clip(self.project(g), -4 * w, 4 * w).astype(np.float32)
            cv2.fillPoly(m, [cv2.convexHull(pts).astype(np.int32)], 255)
        return m

    def court_volume_mask(self, margin=1.5, height=10.0):
        """Image region covered by the box above our court (+margin). Shuttles of other courts
        that never enter this region can be rejected outright."""
        return self.region_mask(np.linspace(-margin, W + margin, 12),
                                np.linspace(-HALF - margin, HALF + margin, 24), np.linspace(0, height, 6))
