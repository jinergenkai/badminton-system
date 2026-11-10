"""Shuttle detection with the official TrackNetV3 (Chen & Wang, MMAsia 2023; MIT license, incl. weights).

https://github.com/qaz812345/TrackNetV3 — the network below is re-declared from its model.py so no
external code is imported; the checkpoint is loaded with weights_only=True (tensors only).

Differences from the alenzenx TrackNet in shuttle.py:
- input = the median background + 8 consecutive frames (27 channels, RGB / 255): the background
  tells the network what is static (lights, white lines, logos), the 8 frames give more motion context;
- one call covers 8 frames instead of 3, so it is ~2.7x cheaper per frame;
- overlapping windows (stride < 8) are averaged ("temporal ensemble"), which the paper found more
  accurate than single windows.
As in shuttle.py every blob above the threshold is kept, so the tracker can pick our court's shuttle.
"""
import cv2
import numpy as np
import pandas as pd
import torch
import torch.nn as nn

IN_H, IN_W = 288, 512


class _Conv(nn.Module):
    def __init__(self, i, o):
        super().__init__()
        self.conv = nn.Conv2d(i, o, kernel_size=3, padding='same', bias=False)
        self.bn = nn.BatchNorm2d(o)
        self.relu = nn.ReLU()

    def forward(self, x):
        return self.relu(self.bn(self.conv(x)))


class _Stack(nn.Module):
    def __init__(self, i, o, n):
        super().__init__()
        names = ['conv_1', 'conv_2', 'conv_3'][:n]
        for k, name in enumerate(names):
            setattr(self, name, _Conv(i if k == 0 else o, o))
        self.names = names

    def forward(self, x):
        for n in self.names:
            x = getattr(self, n)(x)
        return x


class TrackNet(nn.Module):
    def __init__(self, in_dim, out_dim):
        super().__init__()
        self.down_block_1 = _Stack(in_dim, 64, 2)
        self.down_block_2 = _Stack(64, 128, 2)
        self.down_block_3 = _Stack(128, 256, 3)
        self.bottleneck = _Stack(256, 512, 3)
        self.up_block_1 = _Stack(768, 256, 3)
        self.up_block_2 = _Stack(384, 128, 2)
        self.up_block_3 = _Stack(192, 64, 2)
        self.predictor = nn.Conv2d(64, out_dim, (1, 1))

    def forward(self, x):
        pool, up = nn.functional.max_pool2d, lambda t: nn.functional.interpolate(t, scale_factor=2)
        x1 = self.down_block_1(x)
        x2 = self.down_block_2(pool(x1, 2))
        x3 = self.down_block_3(pool(x2, 2))
        x = self.bottleneck(pool(x3, 2))
        x = self.up_block_1(torch.cat([up(x), x3], 1))
        x = self.up_block_2(torch.cat([up(x), x2], 1))
        x = self.up_block_3(torch.cat([up(x), x1], 1))
        return torch.sigmoid(self.predictor(x))


def load_model(weights, device='cuda'):
    ckpt = torch.load(weights, map_location=device, weights_only=True)
    p = ckpt['param_dict']
    assert p['bg_mode'] == 'concat', p['bg_mode']
    model = TrackNet((p['seq_len'] + 1) * 3, p['seq_len']).to(device)
    model.load_state_dict(ckpt['model'])
    return model.eval(), p['seq_len']


def _prep(img_bgr):
    """BGR frame -> (3, 288, 512) uint8 RGB (kept small; /255 on the GPU)."""
    rgb = cv2.cvtColor(cv2.resize(img_bgr, (IN_W, IN_H), interpolation=cv2.INTER_CUBIC), cv2.COLOR_BGR2RGB)
    return np.ascontiguousarray(rgb.transpose(2, 0, 1))


def _blobs(heat, sx, sy, thr=0.5):
    m = (heat > thr).astype(np.uint8)
    n, lab, st, cen = cv2.connectedComponentsWithStats(m)
    return [(cen[i, 0] * sx, cen[i, 1] * sy, int(st[i, 4]), float(heat[lab == i].max())) for i in range(1, n)]


@torch.inference_mode()
def detect(video, weights, background_bgr, stride=4, batch=8, device='cuda', fp16=True, thr=0.5):
    """All candidates per frame (frame, x, y, area, score). stride < seq_len averages overlapping windows."""
    model, L = load_model(weights, device)
    cap = cv2.VideoCapture(video)
    w, h = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    sx, sy = w / IN_W, h / IN_H
    bg = torch.from_numpy(_prep(background_bgr)).to(device)
    frames = {}                 # frame index -> uint8 tensor on the GPU, only those still needed
    acc, cnt = {}, {}           # frame index -> summed heatmap / number of windows, until finalised
    rows = []
    next_read, done_reading, s = 0, False, 0

    def read_until(i):
        nonlocal next_read, done_reading
        while not done_reading and next_read <= i:
            ok, f = cap.read()
            if not ok:
                done_reading = True
                break
            frames[next_read] = torch.from_numpy(_prep(f)).to(device)
            next_read += 1

    def finalise(upto):
        for i in sorted(k for k in acc if k < upto):
            for bx, by, area, score in _blobs(acc.pop(i) / cnt.pop(i), sx, sy, thr):
                rows.append((i, bx, by, area, score))
            frames.pop(i, None)

    while True:
        ss = []
        while len(ss) < batch:
            read_until(s + L - 1)
            if s >= next_read:
                break
            ss.append(s)
            if s + L >= next_read and done_reading:
                break
            s += stride
        if not ss:
            break
        last = next_read - 1
        x = torch.stack([torch.cat([bg] + [frames[min(t + k, last)] for k in range(L)]) for t in ss]).float() / 255.
        with torch.autocast('cuda', enabled=fp16 and device == 'cuda'):
            y = model(x).float().cpu().numpy()
        for t, hm in zip(ss, y):
            for k in range(L):
                i = t + k
                if i <= last:
                    acc[i] = acc.get(i, 0) + hm[k]
                    cnt[i] = cnt.get(i, 0) + 1
        if done_reading and ss[-1] + L >= next_read:
            break
        finalise(ss[-1] + stride)       # frames before the next window's start get no more votes
    finalise(next_read)
    return pd.DataFrame(rows, columns=['frame', 'x', 'y', 'area', 'score']), next_read
