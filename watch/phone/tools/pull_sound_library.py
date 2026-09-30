"""Make the phone's Sound Library edits the new defaults.

What you change in the app (custom TTS lines, sounds moved between
triggers, sounds switched off, MP3s pushed into the sounds folder) lives on
the phone in <files>/sounds/. This pulls that folder over adb and merges it
into the code:

  library_user.json  -> assets/config/sound_library.json
      custom      new lines appended; edits of bundled sounds replace their text
      add/remove  applied to the trigger pools
      off         taken out of every pool (the sound stays listed)
  <id>.mp3           -> audio_src/hype/<id>.mp3 (then run normalize_voice.py
                        so it lands in assets/audio/hype/ at the right level)

Usage (from bandcounter-flutter/):
  python tools/pull_sound_library.py              merge
  python tools/pull_sound_library.py --dry-run    show what would change
  python tools/pull_sound_library.py --clear-device
        after merging, empty the phone's sounds folder — do it once the new
        build is installed, so the phone does not keep a stale copy
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

PKG = 'com.hung.bandcounter'
DEVICE_DIR = f'/sdcard/Android/data/{PKG}/files/sounds'
LIB = os.path.join('assets', 'config', 'sound_library.json')
ADB = os.environ.get('ADB') or shutil.which('adb') or 'adb'


def adb(*args, check=True):
    return subprocess.run([ADB, *args], capture_output=True, text=True, check=check)


def main():
    dry = '--dry-run' in sys.argv
    clear = '--clear-device' in sys.argv
    if not os.path.exists(LIB):
        sys.exit(f'run from bandcounter-flutter/ ({LIB} not found)')

    tmp = tempfile.mkdtemp(prefix='sounds_')
    r = adb('pull', DEVICE_DIR, tmp, check=False)
    if r.returncode != 0:
        sys.exit(f'adb pull failed: {r.stderr.strip() or r.stdout.strip()}')
    src = os.path.join(tmp, 'sounds')

    lib = json.load(open(LIB, encoding='utf-8'))
    sounds = {s['id']: s for s in lib['sounds']}
    triggers = {t['id']: t for t in lib['triggers']}
    changes = []

    user_path = os.path.join(src, 'library_user.json')
    if os.path.exists(user_path):
        user = json.load(open(user_path, encoding='utf-8'))
        for c in user.get('custom', []):
            entry = {k: c[k] for k in ('id', 'display', 'text', 'glow') if k in c}
            if c['id'] in sounds:
                if {k: sounds[c['id']].get(k) for k in entry} != entry:
                    sounds[c['id']].update(entry)
                    changes.append(f"edit   {c['id']}: {entry.get('text')!r}")
            else:
                lib['sounds'].append(entry)
                sounds[c['id']] = entry
                changes.append(f"new    {c['id']}: {entry.get('text')!r}")
        for tid, ids in user.get('add', {}).items():
            if tid not in triggers:
                print(f'!! unknown trigger {tid}, skipped {ids}')
                continue
            for i in ids:
                if i not in triggers[tid]['pool']:
                    triggers[tid]['pool'].append(i)
                    changes.append(f'add    {i} -> {tid}')
        for tid, ids in user.get('remove', {}).items():
            for i in ids:
                if tid in triggers and i in triggers[tid]['pool']:
                    triggers[tid]['pool'].remove(i)
                    changes.append(f'remove {i} from {tid}')
        for i in user.get('off', []):
            for t in triggers.values():
                if i in t['pool']:
                    t['pool'].remove(i)
                    changes.append(f"off    {i} (out of {t['id']})")
    else:
        print('(no library_user.json on the phone)')

    mp3s = []
    for root, _, names in os.walk(src):
        for n in names:
            if n.lower().endswith('.mp3'):
                rel = os.path.relpath(os.path.join(root, n), src).replace('\\', '/')
                mp3s.append(rel)
                sid = rel[:-4]
                if sid not in sounds:
                    words = sid.split('/')[-1].replace('_', ' ')
                    entry = {'id': sid, 'display': words.upper(), 'text': words}
                    lib['sounds'].append(entry)
                    sounds[sid] = entry
                    changes.append(f'new    {sid} (from its MP3; set display/text in the JSON)')
                changes.append(f'mp3    {rel} -> audio_src/hype/{rel}')

    for c in changes:
        print(c)
    if not changes:
        print('nothing to merge')
    if dry:
        print('(dry run: nothing written)')
        return

    if changes:
        with open(LIB, 'w', encoding='utf-8', newline='\n') as f:
            json.dump(lib, f, ensure_ascii=False, indent=2)
            f.write('\n')
        for rel in mp3s:
            dst = os.path.join('audio_src', 'hype', rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(os.path.join(src, rel), dst)
        print(f'\nwrote {LIB}' + (f' and {len(mp3s)} MP3(s) into audio_src/hype/' if mp3s else ''))
        if mp3s:
            print('next: python tools/normalize_voice.py   (levels them into assets/audio/hype/)')
        print('then: rebuild + install, and check git diff before committing')

    if clear:
        adb('shell', 'rm', '-rf', f'{DEVICE_DIR}/*', check=False)
        print('phone sounds folder emptied')
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    main()
