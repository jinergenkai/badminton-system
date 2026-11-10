"""Pipeline entry point.

    python -m badminton configs/danh-cau-02.json            # run everything (cached steps skipped)
    python -m badminton configs/danh-cau-02.json --force calibrate detect
    python -m badminton configs/danh-cau-02.json --only calibrate

Steps: background -> calibrate -> detect -> track -> pose -> players -> hits -> flight -> landing -> analytics
-> render. Each step writes one main file to outputs/<config name>/ and is skipped when that file exists
(unless --force). Headless (no GUI), so it can run on a remote GPU box.
"""
import argparse
import json
import shutil
import subprocess
import time
from pathlib import Path

import cv2
import numpy as np
import pandas as pd

from . import analytics, background, calibrate, flight, hits, identity, landing, players, render, track
from .calibrate import Camera
from .video import video_fps

ROOT = Path(__file__).resolve().parent.parent
INDENT = ' ' * 13                                  # detail lines line up under the step's log message


# ---------------------------------------------------------------- files

def output_files(out, name, layout='horizontal'):
    """The main output of every step (its existence means 'done'), plus shared side outputs."""
    return {'background': out / 'background.png', 'calibrate': out / 'calib.json',
            'detect': out / 'candidates.csv', 'track': out / 'shuttle.csv', 'pose': out / 'pose.npz',
            'players': out / 'players.csv', 'hits': out / 'hits.json', 'flight': out / 'flights.json',
            'landing': out / 'landings.json', 'analytics': out / 'report.json',
            'render': out / (f'{name}_3d_9x16.mp4' if layout == 'vertical' else f'{name}_3d.mp4'),
            # not step markers
            'k3d': out / 'players_k3d.npy', 'report_md': out / 'report.md',
            'court_overlay': out / 'court_overlay.png', 'court_volume': out / 'court_volume.png',
            'render_raw': out / 'render_raw.mp4'}


def load_json(path, **kw):
    with open(path, **kw) as f:
        return json.load(f)


def save_json(obj, path):
    tmp = path.with_suffix('.tmp')                 # write-then-rename: a crash never leaves a half file
    with open(tmp, 'w') as f:
        json.dump(obj, f, indent=1)
    tmp.replace(path)


def ffmpeg():
    exe = shutil.which('ffmpeg')
    if exe:
        return exe
    local = sorted((ROOT.parent / 'yt-downloader').glob('ffmpeg-*/bin/ffmpeg.exe'))
    return str(local[0]) if local else None


class Run:
    """One pipeline run: config, paths, and lazily loaded shared inputs."""

    def __init__(self, cfg, name, layout, panel_position):
        self.cfg, self.name = cfg, name
        self.out = ROOT / 'outputs' / name
        self.out.mkdir(parents=True, exist_ok=True)
        self.video = str(ROOT / cfg['video'])
        self.floor_top, self.ignore = cfg.get('floor_top', 0), cfg.get('ignore', [])
        self.layout, self.panel_position = layout, panel_position
        self.files = output_files(self.out, name, layout)
        self.t0 = 0.0
        self._bg = self._fps = None

    @property
    def bg(self):
        if self._bg is None:
            self._bg = cv2.imread(str(self.files['background']))
        return self._bg

    @property
    def fps(self):
        if self._fps is None:
            self._fps = video_fps(self.video)
        return self._fps

    def cam(self):
        return Camera(load_json(self.files['calibrate']))

    def shuttle(self):
        return pd.read_csv(self.files['track'])

    def players(self):
        return pd.read_csv(self.files['players'])

    def k3d(self):
        return np.load(self.files['k3d'])

    def pose(self):
        return np.load(self.files['pose'])


# ---------------------------------------------------------------- steps
# Each step computes and saves its outputs; it returns the log message and optional detail lines.

def step_background(run):
    cv2.imwrite(str(run.files['background']), background.median_background(run.video))
    return ''


def step_calibrate(run):
    calib = calibrate.fit(run.bg, run.cfg['seeds'], run.floor_top, run.ignore)
    save_json(calib, run.files['calibrate'])
    cv2.imwrite(str(run.files['court_overlay']), render.draw_court(run.bg, Camera(calib)))
    return 'line fit %.2f px (seed %.2f), camera at X=%.2f Y=%.2f Z=%.2f m' % (
        calib['fit_cost_px'], calib['seed_cost_px'], *calib['camera_m'])


def step_detect(run):
    official = ROOT / 'models' / 'tracknetv3_official' / 'ckpts' / 'TrackNet_best.pt'
    if run.cfg.get('detector', 'official') == 'official' and official.exists():
        # official TrackNetV3 (background + 8 frames): ~20% more shuttle explained by physics, 2.5x faster
        from . import shuttle_v3
        cands, n = shuttle_v3.detect(run.video, str(official), run.bg, stride=4)
    else:
        from . import shuttle                      # obsolete own TrackNet port, kept as a fallback
        cands, n = shuttle.detect(run.video, str(ROOT / 'models' / 'tracknet_v3.pt'))
    cands.to_csv(run.files['detect'], index=False)
    return f'{len(cands)} candidates in {n} frames ({n / (time.time() - run.t0):.0f} fps)'


def step_track(run):
    cam, cands = run.cam(), pd.read_csv(run.files['detect'])
    vol = cam.court_volume_mask()
    cv2.imwrite(str(run.files['court_volume']),
                cv2.addWeighted(run.bg, 0.6, cv2.cvtColor(vol, cv2.COLOR_GRAY2BGR), 0.4, 0))
    tracks = track.build_tracks(cands, vol)
    df = track.select(tracks)
    df.to_csv(run.files['track'], index=False)
    return (f'{len(tracks)} raw tracks -> {df.track.nunique()} kept, '
            f'{int(df.detected.sum())} detected + {int((~df.detected).sum())} interpolated frames')


def step_pose(run):
    fr, k, s = players.estimate(run.video)
    np.savez_compressed(run.files['pose'], frame=fr, kpts=k, scores=s)
    return f'{len(fr)} people-detections in {fr.max() + 1} frames'


def step_players(run):
    cam, z = run.cam(), run.pose()
    pl, k3d = players.track_players(cam, z['frame'], z['kpts'], z['scores'])
    # stable identities P1..Pn from shirt/shorts colours (the floor tracker breaks ids constantly)
    feats = identity.appearance(run.video, pl, z['kpts'], z['scores'])
    pl, _, per_side = identity.assign(pl, feats, run.fps)
    pl.to_csv(run.files['players'], index=False)
    np.save(run.files['k3d'], k3d)
    msg = (f'{pl.pid.nunique()} track ids -> {per_side["near"]} + {per_side["far"]} players, '
           f'{100 * (pl.player >= 0).mean():.0f}% of detections identified')
    details = ['P%d: %5d frames, side %-4s, head height ~%.2f m' % (
        p + 1, len(g), g.side.mode()[0], g.nose_z.quantile(0.9) + 0.12) for p, g in pl[pl.player >= 0].groupby('player')]
    return msg, details


def step_hits(run):
    fps = run.fps
    events = hits.find_hits(run.cam(), run.shuttle(), run.players(), run.k3d(), fps=fps)
    save_json(events, run.files['hits'])
    details = ['t=%6.1fs  player %d (%s)  contact ~%.2f m high, %.2f m from wrist' % (
        e['frame'] / fps, e['pid'], e['side'], e['contact'][2], e['wrist_dist']) for e in events[:40]]
    return f'{len(events)} hits', details


def step_flight(run):
    cam, df, hh, fps = run.cam(), run.shuttle(), load_json(run.files['hits']), run.fps
    shots = flight.fit_rally(cam, df, hh, fps)          # may swap the hitter of ambiguous hits
    save_json(hh, run.files['hits'])
    n_direct = sum(s['good'] for s in shots)
    swapped = sum(h.get('side_by') == 'flight fit' for h in hh)
    if swapped:
        print(f'{INDENT}physics re-assigned the hitter of {swapped} hits')
    shots, added = flight.recover_missed(cam, shots, df, hh, run.players(), run.k3d(), fps)
    save_json(shots, run.files['flight'])
    good = [s for s in shots if s['good']]
    details = ['t=%6.1fs  P%-3d %-4s  %5.1f km/h  from %.2f m high  %d obs, %.1f px%s' % (
        s['hit_frame'] / fps, s['pid'], s['side'], s['speed_kmh'], s['p0'][2], s['n_obs'], s['median_px'],
        '  -> lands %s %s' % (s['landing']['court'], 'IN' if s['landing']['in'] else 'OUT')
        if s.get('landing') else '') for s in good[:30]]
    return f'{n_direct} good shots from detected hits + {added} recovered from missed hits', details


def step_landing(run):
    cam, df, fps = run.cam(), run.shuttle(), run.fps
    roi = landing.floor_roi(cam, run.bg, run.floor_top, run.ignore)
    blobs = landing.still_blobs(run.video, run.bg, roi, fps=fps)
    events = landing.find_landings(track.falling_ends(df), blobs, cam)
    for e in events:
        e['source'] = 'still shuttle on the floor'
    if run.files['flight'].exists():
        landing.add_physics_landings(events, load_json(run.files['flight']), cam, fps)
    events.sort(key=lambda e: e['frame'])
    save_json(events, run.files['landing'])
    details = ['t=%6.1fs  X=%.2f Y=%.2f  %-3s (%s%s)' % (
        e['frame'] / fps, *e['court'], 'IN' if e['in'] else 'OUT', e['source'],
        ', %.2fs extrapolated' % e['extrapolated_s'] if 'extrapolated_s' in e else '') for e in events]
    return f'{len(events)} landings', details


def step_analytics(run):
    z = run.pose()
    rep = analytics.analyse(load_json(run.files['flight']), load_json(run.files['hits']), run.players(),
                            run.k3d(), z['kpts'], z['scores'], load_json(run.files['landing']), run.fps)
    save_json(rep, run.files['analytics'])
    run.files['report_md'].write_text(analytics.to_markdown(rep, run.name), encoding='utf8')
    s = rep['summary']
    details = []
    for k, p in sorted(rep['players'].items()):
        a = p['at_opponent_contact']
        details.append(f"{k} ({p['side']}): {p['distance_m']:.0f} m run, top {p['top_speed_ms']} m/s, "
                       f"{p['shots']} shots, smash {p['smash_kmh']['mean']} km/h, ready {a['ready_stance_pct']}%, "
                       f"reaction {a['reaction_s']} s")
    return f"{s['players']} players, {s['rallies']} rallies, {s['shots']} shots {s['shot_types']}", details


def render_inputs(out, cam, fps):
    """Optional render_video keyword arguments from whatever later-step outputs exist in `out`."""
    files = output_files(out, '')
    extra = {}
    if files['players'].exists():
        z = np.load(files['pose'])
        pl = pd.read_csv(files['players'])
        extra = dict(players=pl, k3d=np.load(files['k3d']), kpts=z['kpts'], scores=z['scores'],
                     tracks=analytics.player_tracks(pl, fps) if 'player' in pl else None)
    if files['flight'].exists():
        extra['shots'] = [s for s in load_json(files['flight']) if s['good']]
        # contacts shown = the fitted shots' starts (the same set the report describes)
        extra['hits'] = [{'frame': s['hit_frame'], 'contact': s['p0'],
                          'px': cam.project([s['p0']])[0].tolist()} for s in extra['shots']]
    if files['analytics'].exists():
        extra['report'] = load_json(files['analytics'], encoding='utf8')
    return extra


def step_render(run):
    cam, df, events = run.cam(), run.shuttle(), load_json(run.files['landing'])
    extra = render_inputs(run.out, cam, run.fps)
    raw, dst = run.files['render_raw'], run.files['render']
    n = render.render_video(run.video, str(raw), cam, df, events, layout=run.layout,
                            panel_position=run.panel_position, **extra)
    ff = ffmpeg()
    if ff:   # browser/phone friendly H.264 + original audio
        subprocess.run([ff, '-loglevel', 'error', '-y', '-i', str(raw), '-i', run.video, '-map', '0:v',
                        '-map', '1:a?', '-c:v', 'libx264', '-crf', '22', '-preset', 'fast', '-c:a', 'copy',
                        '-shortest', str(dst)], check=True)
        raw.unlink()
    else:
        raw.replace(dst)
    return f'{n} frames -> {dst.relative_to(ROOT)}'


STEPS = {'background': step_background, 'calibrate': step_calibrate, 'detect': step_detect,
         'track': step_track, 'pose': step_pose, 'players': step_players, 'hits': step_hits,
         'flight': step_flight, 'landing': step_landing, 'analytics': step_analytics, 'render': step_render}


# ---------------------------------------------------------------- runner

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('config')
    ap.add_argument('--force', nargs='*', default=[], choices=list(STEPS), help='recompute these steps')
    ap.add_argument('--only', nargs='*', choices=list(STEPS), help='run only these steps')
    ap.add_argument('--layout', choices=['horizontal', 'vertical'], help='render: side by side, or 9:16 portrait')
    ap.add_argument('--panel', choices=['below', 'above'], help='vertical layout: analysis below/above the video')
    args = ap.parse_args()

    cfg = load_json(args.config, encoding='utf8')
    run = Run(cfg, Path(args.config).stem, args.layout or cfg.get('layout', 'horizontal'),
              args.panel or cfg.get('panel', 'below'))
    for step, fn in STEPS.items():
        if args.only is not None and step not in args.only:
            continue
        if step not in args.force and run.files[step].exists():
            continue
        run.t0 = time.time()
        res = fn(run)
        msg, details = res if isinstance(res, tuple) else (res, [])
        print(f'[{step:10s}] {time.time() - run.t0:6.1f}s  {msg}')
        for line in details:
            print(INDENT + line)


if __name__ == '__main__':
    main()
