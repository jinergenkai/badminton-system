"""BWF doubles court geometry, in metres.

Court frame: X across the court (0 = left doubles sideline, 6.1 = right), Y along it
(0 = net, + = far half, - = near/camera half), Z up from the floor.
"""
import numpy as np

W, HALF = 6.10, 6.70                 # doubles width, half length
SINGLES_INSET = 0.46                 # singles sideline inset from doubles sideline
SHORT = 1.98                         # short service line, from the net
LONG_DOUBLES = HALF - 0.76           # doubles long service line, from the net
NET_POST, NET_CENTRE, NET_BOTTOM = 1.55, 1.524, 0.79


def court_lines():
    """Floor lines as ((x0, y0), (x1, y1)) segments."""
    L = []
    for x in (0, SINGLES_INSET, W - SINGLES_INSET, W):
        L.append(((x, -HALF), (x, HALF)))
    for s in (-1, 1):
        L.append(((0, s * HALF), (W, s * HALF)))
        L.append(((0, s * LONG_DOUBLES), (W, s * LONG_DOUBLES)))
        L.append(((0, s * SHORT), (W, s * SHORT)))
        L.append(((W / 2, s * SHORT), (W / 2, s * HALF)))
    return L


def net_top(n=40):
    """Net tape: 1.55 m at the posts, sagging to 1.524 m at the centre."""
    xs = np.linspace(0, W, n)
    return np.stack([xs, np.zeros(n), NET_POST - (NET_POST - NET_CENTRE) * (1 - np.abs(xs - W / 2) / (W / 2))], 1)


def is_in(x, y):
    return 0 <= x <= W and -HALF <= y <= HALF
