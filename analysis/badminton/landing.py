"""Where did the shuttle land?

TrackNet sees the shuttle while it flies, not once it lies still. A landing is therefore:
a flight that ends while falling, followed shortly by a small white blob lying still within
~45 px of that end point. If several blobs qualify (a white shoe right next to it), the
smallest wins: at the same depth a shuttle (~7 cm) is always smaller than a shoe (~28 cm).
"""
import cv2
import numpy as np

from .background import white_mask
from .court import W, HALF, is_in


def floor_roi(cam, bg, floor_top, ignore, margin=1.0):
    roi = cam.region_mask(np.linspace(-margin, W + margin, 30), np.linspace(-HALF - margin, HALF + margin, 60), [0])
    roi[:floor_top] = 0
    for x0, y0, x1, y1 in ignore:
        roi[y0:y1, x0:x1] = 0
    return roi & (255 - cv2.dilate(white_mask(bg), np.ones((7, 7), np.uint8)))   # painted lines out


def nothing_above(stat, changed, max_busy=0.25):
    """A shuttle lies on empty floor; a white shoe or knee sleeve always has a leg right above it.
    Looks at a column above the blob only (a shoe *beside* the shuttle must not reject it)."""
    x, y, w, h = stat[:4]
    top = max(0, y - max(10, int(2.5 * h)))
    col = changed[top:max(top + 1, y - 1), max(0, x - 2):x + w + 2]
    return col.size == 0 or (col > 0).mean() < max_busy


def still_blobs(video, bg, roi, step=2, min_still_s=0.5, fps=30):
    """(first_frame, last_frame, x, y, area) of small new white blobs that stay put."""
    cap = cv2.VideoCapture(video)
    alive, done, f = [], [], 0
    while True:
        ok, img = cap.read()
        if not ok:
            break
        if f % step == 0:
            changed = (cv2.absdiff(img, bg).max(axis=2) > 35).astype(np.uint8) * 255
            m = cv2.morphologyEx(white_mask(img, 70) & roi & changed, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
            n, _, st, cen = cv2.connectedComponentsWithStats(m)
            pts = [(cen[i], st[i, 4]) for i in range(1, n)
                   if 6 <= st[i, 4] <= 500 and st[i, 2] < 40 and st[i, 3] < 30
                   and nothing_above(st[i], changed)]
            nxt, used = [], set()
            for p, area in pts:
                for k, b in enumerate(alive):
                    if k not in used and np.hypot(*(b[2:4] - p)) < 5:
                        nxt.append(np.array([b[0], f, *b[2:4], b[4]]))
                        used.add(k)
                        break
                else:
                    nxt.append(np.array([f, f, *p, area]))
            done += [b for k, b in enumerate(alive) if k not in used]
            alive = nxt
        f += 1
    done += alive
    return [b for b in done if (b[1] - b[0]) / fps >= min_still_s]


def find_landings(ends, blobs, cam, max_dist=45, window=(-5, 20)):
    events = []
    for e in ends:
        near = [b for b in blobs if window[0] <= b[0] - e[0] <= window[1] and np.hypot(*(b[2:4] - e[1:])) < max_dist]
        if not near:
            continue
        b = min(near, key=lambda b: b[4])
        X, Y = cam.to_floor(b[2:4])
        events.append({'frame': int(b[0]), 'px': [round(float(b[2]), 1), round(float(b[3]), 1)],
                       'court': [round(float(X), 2), round(float(Y), 2)], 'in': bool(is_in(X, Y))})
    return events
