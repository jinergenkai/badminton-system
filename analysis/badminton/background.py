"""Empty-court background from a fixed (tripod) camera.

Players keep moving, so each pixel shows the floor in most frames. Taking the per-pixel
median over frames spread across the whole video removes them. Someone who stands in one
spot for more than half the sampled frames would still leave a ghost.
"""
import cv2
import numpy as np


def median_background(video, samples=60):
    cap = cv2.VideoCapture(video)
    n = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    frames = []
    for i in np.linspace(0, n - 1, samples).astype(int):   # spread out, not consecutive
        cap.set(cv2.CAP_PROP_POS_FRAMES, i)
        ok, f = cap.read()
        if ok:
            frames.append(f)
    # (samples, H, W, 3) -> per-pixel, per-channel median over time
    return np.median(np.stack(frames), axis=0).astype(np.uint8)


def white_mask(img, sat_max=60, val_min=170):
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    return ((hsv[..., 1] < sat_max) & (hsv[..., 2] > val_min)).astype(np.uint8) * 255
