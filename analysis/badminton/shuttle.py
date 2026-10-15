"""Shuttle detection with TrackNetV3, keeping *every* candidate per frame.

The upstream predict.py keeps only the largest blob of each heatmap, so when the shuttle of a
neighbouring court is also visible it can win. Here all blobs are kept and the tracker decides.
"""
import sys
from pathlib import Path

import cv2
import numpy as np
import pandas as pd
import torch

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'third_party' / 'TrackNetV3'))
from model import TrackNetV2 as TrackNet   # noqa: E402  (the V3 architecture, upstream naming)

IN_H, IN_W = 288, 512


def load_model(weights, device='cuda'):
    ckpt = torch.load(weights, map_location=device)          # weights_only=True by default
    p = ckpt['param_dict']
    model = TrackNet(in_dim=p['num_frame'] * 3, out_dim=p['num_frame']).to(device)
    model.load_state_dict(ckpt['model_state_dict'])
    return model.eval(), p['num_frame']


def _to_input(frames, num_frame):
    """Groups of num_frame frames -> (B, num_frame*3, 288, 512), same preprocessing as upstream."""
    x = np.stack([cv2.resize(f, (IN_W, IN_H)) for f in frames]).astype(np.float32) / 255.
    x = x.transpose(0, 3, 1, 2).reshape(-1, num_frame * 3, IN_H, IN_W)
    return torch.from_numpy(x)


def _blobs(heat, sx, sy, thr=0.5):
    m = (heat > thr).astype(np.uint8)
    n, lab, st, cen = cv2.connectedComponentsWithStats(m)
    out = []
    for i in range(1, n):
        out.append((cen[i, 0] * sx, cen[i, 1] * sy, int(st[i, 4]), float(heat[lab == i].max())))
    return out


@torch.inference_mode()
def detect(video, weights, batch=8, device='cuda', fp16=True):
    """Return a DataFrame of all candidates: frame, x, y, area (heatmap px), score."""
    model, nf = load_model(weights, device)
    cap = cv2.VideoCapture(video)
    w, h = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    sx, sy = w / IN_W, h / IN_H
    rows, f0, done = [], 0, False
    while not done:
        frames = []
        while len(frames) < nf * batch:
            ok, f = cap.read()
            if not ok:
                done = True
                break
            frames.append(f)
        if not frames:
            break
        real = len(frames)
        frames += [frames[-1]] * (-len(frames) % nf)          # pad the last group
        x = _to_input(frames, nf).to(device)
        with torch.autocast('cuda', enabled=fp16):
            y = model(x).float()
        heat = y.reshape(-1, IN_H, IN_W).cpu().numpy()
        for i in range(real):
            for bx, by, area, score in _blobs(heat[i], sx, sy):
                rows.append((f0 + i, bx, by, area, score))
        f0 += real
    return pd.DataFrame(rows, columns=['frame', 'x', 'y', 'area', 'score']), f0
