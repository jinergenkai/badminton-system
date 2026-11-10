"""COCO-17 body keypoint indices (RTMPose output order) and the skeleton drawn by render.py."""

NOSE = 0
L_SH, R_SH = 5, 6                 # shoulders
L_EL, R_EL = 7, 8                 # elbows
L_WR, R_WR = 9, 10                # wrists
L_HIP, R_HIP = 11, 12
L_KNEE, R_KNEE = 13, 14
L_ANK, R_ANK = 15, 16
N_KPTS = 17

# arms, shoulder line, torso, legs, and the nose joined to both shoulders (no eyes / ears)
BONES = [(5, 7), (7, 9), (6, 8), (8, 10), (5, 6), (5, 11), (6, 12), (11, 12), (11, 13), (13, 15), (12, 14),
         (14, 16), (0, 5), (0, 6)]
