"""Players: 2D pose per frame (RTMPose-x + YOLOX-x via rtmlib), identity tracking on the court,
and a 3D lift of every keypoint.

3D lift: the feet touch the floor, so the floor homography gives the player's (X, Y) exactly.
Each other keypoint is taken to lie on the vertical plane through the feet that faces the
camera; its ray hits that plane at the keypoint's 3D position. Good for height (head, wrist),
less exact for an arm reaching straight towards or away from the camera.
"""
from pathlib import Path

import cv2
import numpy as np
import pandas as pd
from scipy.optimize import linear_sum_assignment

from .court import W, HALF

ROOT = Path(__file__).resolve().parent.parent
DET = ROOT / 'models' / 'pose' / 'yolox_x_humanart.onnx'
POSE = ROOT / 'models' / 'pose' / 'rtmpose_x_body7_384x288.onnx'

# COCO-17 keypoints
NOSE, L_SH, R_SH, L_EL, R_EL, L_WR, R_WR, L_HIP, R_HIP, L_ANK, R_ANK = 0, 5, 6, 7, 8, 9, 10, 11, 12, 15, 16
BONES = [(5, 7), (7, 9), (6, 8), (8, 10), (5, 6), (5, 11), (6, 12), (11, 12), (11, 13), (13, 15), (12, 14),
         (14, 16), (0, 5), (0, 6)]


def estimate(video, device='cuda'):
    """Run detector + pose on every frame. Returns frame (M,), kpts (M, 17, 2), scores (M, 17)."""
    import torch  # noqa: F401  (loads the CUDA/cuDNN DLLs that onnxruntime-gpu reuses)
    from rtmlib import Body
    body = Body(det=str(DET), det_input_size=(640, 640), pose=str(POSE), pose_input_size=(288, 384),
                backend='onnxruntime', device=device)
    cap = cv2.VideoCapture(video)
    frames, kpts, scores, f = [], [], [], 0
    while True:
        ok, img = cap.read()
        if not ok:
            break
        k, s = body(img)
        for i in range(len(k)):
            frames.append(f)
            kpts.append(k[i])
            scores.append(s[i])
        f += 1
    return np.array(frames), np.float32(kpts).reshape(-1, 17, 2), np.float32(scores).reshape(-1, 17)


def foot_pixel(k, s, thr=0.3):
    ok = [j for j in (L_ANK, R_ANK) if s[j] > thr]
    if ok:
        return k[ok].mean(0) + [0, 4]               # ankle joint sits a few px above the sole
    return k[np.argmax(k[:, 1])]                     # fallback: lowest keypoint


def lift(cam, foot_xy, px):
    """3D points of pixels px (N, 2) on the vertical plane through foot_xy facing the camera."""
    F = np.array([foot_xy[0], foot_xy[1], 0.0])
    n = F - cam.pos
    n[2] = 0
    n /= np.linalg.norm(n)
    out = []
    for p in px:
        d = cam.ray(p)
        t = n @ (F - cam.pos) / (n @ d)
        out.append(cam.pos + t * d)
    return np.array(out)


def track_players(cam, frames, kpts, scores, margin=1.2, max_jump=1.2, max_age=30):
    """Keep people standing on (or just around) our court; give them stable ids by floor position."""
    rows, k3d = [], []
    live = {}                                         # pid -> (last_frame, X, Y)
    next_id = 0
    for f in np.unique(frames):
        idx = np.nonzero(frames == f)[0]
        cand = []
        for i in idx:
            X, Y = cam.to_floor(foot_pixel(kpts[i], scores[i]))
            if -margin <= X <= W + margin and -HALF - margin <= Y <= HALF + margin and scores[i].mean() > 0.4:
                cand.append((i, X, Y))
        live = {p: v for p, v in live.items() if f - v[0] <= max_age}
        pids = list(live)
        assign = {}
        if pids and cand:
            cost = np.array([[np.hypot(live[p][1] - X, live[p][2] - Y) for (_, X, Y) in cand] for p in pids])
            for r, c in zip(*linear_sum_assignment(cost)):
                if cost[r, c] < max_jump + 0.05 * (f - live[pids[r]][0]):
                    assign[c] = pids[r]
        for c, (i, X, Y) in enumerate(cand):
            pid = assign.get(c)
            if pid is None:
                pid, next_id = next_id, next_id + 1
            live[pid] = (f, X, Y)
            P = lift(cam, (X, Y), kpts[i])
            rows.append((f, pid, X, Y, 'near' if Y < 0 else 'far', P[NOSE, 2], P[L_WR, 2], P[R_WR, 2], i))
            k3d.append(P)
    df = pd.DataFrame(rows, columns=['frame', 'pid', 'X', 'Y', 'side', 'nose_z', 'lwrist_z', 'rwrist_z', 'det'])
    return df, np.float32(k3d)
