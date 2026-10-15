"""Pipeline entry point.

    python -m badminton configs/danh-cau-02.json            # run everything (cached steps skipped)
    python -m badminton configs/danh-cau-02.json --force calibrate detect
    python -m badminton configs/danh-cau-02.json --only calibrate

Steps: background -> calibrate -> detect -> track -> pose -> players -> hits -> flight -> landing -> render.
Outputs go to outputs/<config name>/. Headless (no GUI), so it can run on a remote GPU box.
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

from . import background, calibrate, flight, hits, landing, players, render, shuttle, track
from .calibrate import Camera

ROOT = Path(__file__).resolve().parent.parent
STEPS = ['background', 'calibrate', 'detect', 'track', 'pose', 'players', 'hits', 'flight', 'landing', 'render']


def ffmpeg():
    exe = shutil.which('ffmpeg')
    if exe:
        return exe
    local = sorted((ROOT.parent / 'yt-downloader').glob('ffmpeg-*/bin/ffmpeg.exe'))
    return str(local[0]) if local else None


def save_json(obj, path):
    tmp = path.with_suffix('.tmp')                 # write-then-rename: a crash never leaves a half file
    with open(tmp, 'w') as f:
        json.dump(obj, f, indent=1)
    tmp.replace(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('config')
    ap.add_argument('--force', nargs='*', default=[], choices=STEPS, help='recompute these steps')
    ap.add_argument('--only', nargs='*', choices=STEPS, help='run only these steps')
    args = ap.parse_args()

    cfg = json.load(open(args.config, encoding='utf8'))
    name = Path(args.config).stem
    out = ROOT / 'outputs' / name
    out.mkdir(parents=True, exist_ok=True)
    video = str(ROOT / cfg['video'])
    floor_top, ignore = cfg.get('floor_top', 0), cfg.get('ignore', [])
    files = {'background': out / 'background.png', 'calibrate': out / 'calib.json',
             'detect': out / 'candidates.csv', 'track': out / 'shuttle.csv',
             'pose': out / 'pose.npz', 'players': out / 'players.csv', 'hits': out / 'hits.json', 'flight': out / 'flights.json',
             'landing': out / 'landings.json', 'render': out / f'{name}_3d.mp4'}

    def todo(step):
        if args.only is not None and step not in args.only:
            return False
        return step in args.force or not files[step].exists()

    def log(step, t0, msg=''):
        print(f'[{step:10s}] {time.time() - t0:6.1f}s  {msg}')

    if todo('background'):
        t0 = time.time()
        cv2.imwrite(str(files['background']), background.median_background(video))
        log('background', t0)
    bg = cv2.imread(str(files['background']))
    load_cam = lambda: Camera(json.load(open(files['calibrate'])))

    if todo('calibrate'):
        t0 = time.time()
        calib = calibrate.fit(bg, cfg['seeds'], floor_top, ignore)
        save_json(calib, files['calibrate'])
        cam = Camera(calib)
        cv2.imwrite(str(out / 'court_overlay.png'), render.draw_court(bg, cam))
        log('calibrate', t0, 'line fit %.2f px (seed %.2f), camera at X=%.2f Y=%.2f Z=%.2f m' % (
            calib['fit_cost_px'], calib['seed_cost_px'], *calib['camera_m']))
    if todo('detect'):
        t0 = time.time()
        cands, n = shuttle.detect(video, str(ROOT / 'models' / 'tracknet_v3.pt'))
        cands.to_csv(files['detect'], index=False)
        log('detect', t0, f'{len(cands)} candidates in {n} frames ({n / (time.time() - t0):.0f} fps)')

    if todo('track'):
        t0 = time.time()
        cam, cands = load_cam(), pd.read_csv(files['detect'])
        vol = cam.court_volume_mask()
        cv2.imwrite(str(out / 'court_volume.png'), cv2.addWeighted(bg, 0.6, cv2.cvtColor(vol, cv2.COLOR_GRAY2BGR), 0.4, 0))
        tracks = track.build_tracks(cands, vol)
        df = track.select(tracks)
        df.to_csv(files['track'], index=False)
        log('track', t0, f'{len(tracks)} raw tracks -> {df.track.nunique()} kept, '
                         f'{int(df.detected.sum())} detected + {int((~df.detected).sum())} interpolated frames')

    if todo('pose'):
        t0 = time.time()
        fr, k, s = players.estimate(video)
        np.savez_compressed(files['pose'], frame=fr, kpts=k, scores=s)
        log('pose', t0, f'{len(fr)} people-detections in {fr.max() + 1} frames')

    if todo('players'):
        t0 = time.time()
        cam, z = load_cam(), np.load(files['pose'])
        pl, k3d = players.track_players(cam, z['frame'], z['kpts'], z['scores'])
        pl.to_csv(files['players'], index=False)
        np.save(out / 'players_k3d.npy', k3d)
        log('players', t0, f'{pl.pid.nunique()} ids on/around our court')
        for pid, g in pl.groupby('pid'):
            if len(g) > 300:
                print('             player %d: %5d frames, side %-4s, head height ~%.2f m' % (
                    pid, len(g), g.side.mode()[0], g.nose_z.quantile(0.9) + 0.12))

    if todo('hits'):
        t0 = time.time()
        cam, df, pl = load_cam(), pd.read_csv(files['track']), pd.read_csv(files['players'])
        events = hits.find_hits(cam, df, pl, np.load(out / 'players_k3d.npy'))
        save_json(events, files['hits'])
        fps = cv2.VideoCapture(video).get(cv2.CAP_PROP_FPS)
        log('hits', t0, f'{len(events)} hits')
        for e in events[:40]:
            print('             t=%6.1fs  player %d (%s)  contact ~%.2f m high, %.2f m from wrist' % (
                e['frame'] / fps, e['pid'], e['side'], e['contact'][2], e['wrist_dist']))

    if todo('flight'):
        t0 = time.time()
        cam, df, hh = load_cam(), pd.read_csv(files['track']), json.load(open(files['hits']))
        fps = cv2.VideoCapture(video).get(cv2.CAP_PROP_FPS)
        shots = flight.fit_rally(cam, df, hh, fps)
        n_direct = sum(s['good'] for s in shots)
        shots, added = flight.recover_missed(cam, shots, df, hh, pd.read_csv(files['players']),
                                             np.load(out / 'players_k3d.npy'), fps)
        save_json(shots, files['flight'])
        good = [s for s in shots if s['good']]
        log('flight', t0, f'{n_direct} good shots from detected hits + {added} recovered from missed hits')
        for s in good[:30]:
            print('             t=%6.1fs  P%-3d %-4s  %5.1f km/h  from %.2f m high  %d obs, %.1f px%s' % (
                s['hit_frame'] / fps, s['pid'], s['side'], s['speed_kmh'], s['p0'][2], s['n_obs'],
                s['median_px'], '  -> lands %s %s' % (s['landing']['court'], 'IN' if s['landing']['in'] else 'OUT')
                if s.get('landing') else ''))

    if todo('landing'):
        t0 = time.time()
        cam, df = load_cam(), pd.read_csv(files['track'])
        roi = landing.floor_roi(cam, bg, floor_top, ignore)
        fps = cv2.VideoCapture(video).get(cv2.CAP_PROP_FPS)
        blobs = landing.still_blobs(video, bg, roi, fps=fps)
        events = landing.find_landings(track.falling_ends(df), blobs, cam)
        for e in events:
            e['source'] = 'still shuttle on the floor'
        if files['flight'].exists():           # physics landings of well-fitted final shots
            for s in json.load(open(files['flight'])):
                if s['good'] and s.get('landing') and not any(abs(e['frame'] - s['landing']['frame']) < 45 for e in events):
                    L = s['landing']
                    events.append({'frame': L['frame'], 'px': cam.project([[*L['court'], 0]])[0].round(1).tolist(),
                                   'court': L['court'], 'in': L['in'], 'source': 'physics fit',
                                   'extrapolated_s': round((L['frame'] - s['fit_last_frame']) / fps, 2)})
        events.sort(key=lambda e: e['frame'])
        save_json(events, files['landing'])
        log('landing', t0, f'{len(events)} landings')
        for e in events:
            print('             t=%6.1fs  X=%.2f Y=%.2f  %-3s (%s%s)' % (
                e['frame'] / fps, *e['court'], 'IN' if e['in'] else 'OUT', e['source'],
                ', %.2fs extrapolated' % e['extrapolated_s'] if 'extrapolated_s' in e else ''))

    if todo('render'):
        t0 = time.time()
        cam, df, events = load_cam(), pd.read_csv(files['track']), json.load(open(files['landing']))
        extra = {}
        if files['hits'].exists():
            extra = dict(hits=json.load(open(files['hits'])), players=pd.read_csv(files['players']),
                         k3d=np.load(out / 'players_k3d.npy'), kpts=np.load(files['pose'])['kpts'])
        if files['flight'].exists():
            extra['shots'] = [s for s in json.load(open(files['flight'])) if s['good']]
            for s in extra['shots']:            # recovered (previously missed) hits get a marker too
                if s.get('inferred_hit') and 'hits' in extra:
                    extra['hits'].append({'frame': s['hit_frame'], 'pid': s['pid'], 'px': cam.project([s['p0']])[0].tolist(),
                                          'contact': s['p0'], 'recovered': True})
        raw = out / 'render_raw.mp4'
        n = render.render_video(video, str(raw), cam, df, events, **extra)
        ff = ffmpeg()
        if ff:   # browser/phone friendly H.264 + original audio
            subprocess.run([ff, '-loglevel', 'error', '-y', '-i', str(raw), '-i', video, '-map', '0:v',
                            '-map', '1:a?', '-c:v', 'libx264', '-crf', '22', '-preset', 'fast', '-c:a', 'copy',
                            '-shortest', str(files['render'])], check=True)
            raw.unlink()
        else:
            raw.replace(files['render'])
        log('render', t0, f'{n} frames -> {files["render"].relative_to(ROOT)}')


if __name__ == '__main__':
    main()
