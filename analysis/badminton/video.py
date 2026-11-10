"""Small video-file helpers shared by the steps (OpenCV)."""
import cv2


def video_fps(video):
    """Frame rate stored in the file."""
    return cv2.VideoCapture(video).get(cv2.CAP_PROP_FPS)


def iter_frames(cap):
    """Yield the BGR frames of an opened cv2.VideoCapture until the stream ends."""
    while True:
        ok, img = cap.read()
        if not ok:
            return
        yield img
