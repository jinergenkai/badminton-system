// Numbers for "does the skeleton look right": run on buildPoses() output, the same way for web and desktop data.
import { posesAt, headOf, torsoLen, boneScale, plausibleBone, BONES } from '../ui/render.js';

const mid = (a, b) => (a && b ? [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2] : null);

/**
 * dup:      frames where two identified players sit on the same person (hip centres < 0.35 torso apart)
 * head:     heads further than 1.5 median bones from the neck (absurd neck)
 * bones:    bones longer than 2.4 median bones (stray keypoints, would be drawn as long lines)
 * jumps:    a player's hip centre moving > 0.6 torso in one frame (flicker / teleport / swap)
 * torsoVar: torso length changing > 40 % in one frame (stretched / squashed body)
 */
export function skeletonQA(poses, nFrames) {
  const q = { frames: 0, people: 0, dup: 0, head: 0, bones: 0, jumps: 0, torsoVar: 0 };
  const prev = new Map();
  for (let f = 0; f < nFrames; f++) {
    const ps = posesAt(poses, f);
    if (!ps.length) continue;
    q.frames++;
    const info = ps.map(({ player, k2 }) => ({ player, k2, T: torsoLen(k2), S: boneScale(k2), hip: mid(k2[11], k2[12]) }));
    for (let i = 0; i < info.length; i++) for (let j = i + 1; j < info.length; j++) {
      const a = info[i], b = info[j];
      const T = Math.max(a.T || 0, b.T || 0);
      if (a.hip && b.hip && T > 0 && Math.hypot(a.hip[0] - b.hip[0], a.hip[1] - b.hip[1]) < 0.35 * T) { q.dup++; break; }
    }
    for (const a of info) {
      q.people++;
      const hd = headOf(a.k2, false);
      if (hd && hd.neck && a.S > 0 && Math.hypot(hd.p[0] - hd.neck[0], hd.p[1] - hd.neck[1]) > 1.5 * a.S) q.head++;
      for (const [x, y] of BONES) if (x && y && a.k2[x] && a.k2[y] && !plausibleBone(x, y, a.k2, a.S)) q.bones++;
      const p = prev.get(a.player);
      if (p && p.f === f - 1) {
        if (a.hip && p.hip && a.T > 0 && Math.hypot(a.hip[0] - p.hip[0], a.hip[1] - p.hip[1]) > 0.6 * a.T) q.jumps++;
        if (a.T > 0 && p.T > 0 && Math.abs(a.T - p.T) / p.T > 0.4) q.torsoVar++;
      }
      prev.set(a.player, { f, hip: a.hip, T: a.T });
    }
  }
  return q;
}
