import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../features/hype_voice/services/hype_voice_controller.dart';
import '../services/music_service.dart';
import '../services/sound_library_service.dart';

/// Every sound the app can play, and when.
///
/// Hype: grouped by trigger. Tap a row to edit its text, overlay and the
/// triggers it is in; the switch takes it out of rotation; "+ TTS line"
/// adds a new one spoken by TTS. All of it is the phone's own layer
/// (library_user.json) — tools/pull_sound_library.py turns it into defaults.
class SoundLibraryScreen extends StatelessWidget {
  const SoundLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1B4B),
          title: const Text('SOUND LIBRARY',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
          bottom: const TabBar(
            indicatorColor: Colors.amber,
            labelColor: Colors.amber,
            unselectedLabelColor: Colors.white54,
            tabs: [Tab(text: 'HYPE'), Tab(text: 'MUSIC')],
          ),
        ),
        body: const TabBarView(children: [_HypeTab(), _MusicTab()]),
      ),
    );
  }
}

String _flat(String display) => display.replaceAll('\n', ' ');

// ── Hype ──────────────────────────────────────────────────────────────────

class _HypeTab extends StatelessWidget {
  const _HypeTab();

  @override
  Widget build(BuildContext context) {
    final lib = SoundLibraryService.maybe;
    if (lib == null) {
      return const Center(child: Text('Sound library not loaded', style: TextStyle(color: Colors.white54)));
    }
    return Obx(() {
      lib.revision.value; // rebuild on any change
      final sounds = lib.sounds;
      final membership = {for (final d in sounds) d.id: lib.triggersOf(d.id)};
      final orphans = sounds.where((d) => membership[d.id]!.isEmpty).toList();
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
        children: [
          _header(context, lib),
          const SizedBox(height: 8),
          for (final t in lib.triggers)
            _group(
              context,
              title: HypeVoiceController.triggerLabels[t.id] ?? '${t.id} (never fires)',
              subtitle: '${lib.pool(t.id).length} playing · ${t.id} · priority ${t.priority}',
              sounds: [for (final d in sounds) if (membership[d.id]!.contains(t.id)) d],
            ),
          if (orphans.isNotEmpty)
            _group(context,
                title: 'Not in any trigger',
                subtitle: '${orphans.length} sounds — tap one to put it in a trigger',
                sounds: orphans),
        ],
      );
    });
  }

  Widget _header(BuildContext context, SoundLibraryService lib) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => _SoundEditor.open(context, null),
                icon: const Icon(Icons.add),
                label: const Text('TTS line'),
                style: FilledButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: lib.rescanFiles,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Rescan MP3s'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'MP3 > TTS: drop <id>.mp3 into the folder below (adb push) to replace any '
            'sound, or give a TTS line a recorded voice. Edits are saved there too '
            '(library_user.json).',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 4),
          SelectableText(lib.userDirPath,
              style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _group(BuildContext context,
      {required String title, required String subtitle, required List<SoundDef> sounds}) {
    return Card(
      color: Colors.white.withOpacity(0.04),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        shape: const Border(),
        collapsedIconColor: Colors.white38,
        iconColor: Colors.amber,
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        children: [for (final d in sounds) _SoundRow(d)],
      ),
    );
  }
}

class _SoundRow extends StatelessWidget {
  final SoundDef def;
  const _SoundRow(this.def);

  @override
  Widget build(BuildContext context) {
    final lib = SoundLibraryService.maybe!;
    final off = lib.isOff(def.id);
    final src = lib.sourceLabel(def.id);
    final srcColor = src == 'FILE'
        ? Colors.lightGreenAccent
        : src == 'MP3'
            ? Colors.white54
            : Colors.amberAccent;
    return ListTile(
      dense: true,
      onTap: () => _SoundEditor.open(context, def),
      leading: IconButton(
        icon: const Icon(Icons.play_circle_outline, color: Colors.cyanAccent),
        onPressed: () => Get.find<HypeVoiceController>().previewSound(def.id),
      ),
      title: Text(_flat(def.display),
          style: TextStyle(
              color: off ? Colors.white30 : Colors.white,
              fontWeight: FontWeight.w600,
              decoration: off ? TextDecoration.lineThrough : null)),
      subtitle: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: srcColor.withOpacity(0.6)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(src, style: TextStyle(color: srcColor, fontSize: 9, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(def.custom ? '${def.text}  · edited' : def.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ),
        ],
      ),
      trailing: Switch(
        value: !off,
        activeColor: Colors.cyanAccent,
        onChanged: (v) => lib.setOff(def.id, !v),
      ),
    );
  }
}

/// Bottom sheet: new TTS line (def == null) or edit an existing sound.
class _SoundEditor extends StatefulWidget {
  final SoundDef? def;
  const _SoundEditor(this.def);

  static Future<void> open(BuildContext context, SoundDef? def) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF1E1B4B),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => _SoundEditor(def),
      );

  @override
  State<_SoundEditor> createState() => _SoundEditorState();
}

class _SoundEditorState extends State<_SoundEditor> {
  final lib = SoundLibraryService.maybe!;
  late final TextEditingController _text;
  late final TextEditingController _display;
  late String? _glow;
  late Set<String> _triggers;
  late final Set<String> _triggersBefore;
  bool _busy = false;

  bool get _isNew => widget.def == null;

  @override
  void initState() {
    super.initState();
    final d = widget.def;
    _text = TextEditingController(text: d?.text ?? '');
    // Line breaks are typed as \n in the single-line field.
    _display = TextEditingController(text: d == null ? '' : d.display.replaceAll('\n', r'\n'));
    _glow = d?.glow;
    _triggersBefore = d == null ? {} : lib.triggersOf(d.id);
    _triggers = {..._triggersBefore};
  }

  @override
  void dispose() {
    _text.dispose();
    _display.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    final d = widget.def;
    final display = _display.text.trim().replaceAll(r'\n', '\n');
    if (d == null) {
      await lib.addCustom(text: text, display: display, glow: _glow, triggers: _triggers);
    } else {
      if (text != d.text || display != d.display || _glow != d.glow) {
        await lib.edit(d.id, text: text, display: display, glow: _glow);
      }
      for (final t in {..._triggers, ..._triggersBefore}) {
        final now = _triggers.contains(t);
        if (now != _triggersBefore.contains(t)) await lib.setInTrigger(d.id, t, now);
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    await lib.deleteCustom(widget.def!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.def;
    final hasFile = d != null && (lib.isBundled(d.id) || lib.hasUserFile(d.id));
    final canDelete = d != null && d.custom && !lib.isBundled(d.id) && !lib.hasUserFile(d.id);
    final canReset = d != null && lib.isOverridden(d.id);
    InputDecoration deco(String label, String hint) => InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: Colors.white54),
          hintStyle: const TextStyle(color: Colors.white24),
          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_isNew ? 'New TTS line' : _flat(d!.display),
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            if (d != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  hasFile
                      ? 'id ${d.id} · plays its MP3; the text is used only if the file goes missing'
                      : 'id ${d.id} · spoken by TTS (cached). Recorded voice: push ${d.id}.mp3',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            TextField(
              controller: _text,
              autofocus: _isNew,
              style: const TextStyle(color: Colors.white),
              decoration: deco('Spoken text', 'Bá khí!'),
            ),
            TextField(
              controller: _display,
              style: const TextStyle(color: Colors.white),
              decoration: deco('Overlay text (optional)', 'BÁ KHÍ — use \\n for a line break'),
            ),
            const SizedBox(height: 14),
            const Text('Glow', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              for (final g in const [null, 'fire', 'legendary', 'danger'])
                ChoiceChip(
                  label: Text(g ?? 'default'),
                  selected: _glow == g,
                  onSelected: (_) => setState(() => _glow = g),
                ),
            ]),
            const SizedBox(height: 14),
            const Text('Plays on', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final t in lib.triggers)
                FilterChip(
                  label: Text(HypeVoiceController.triggerLabels[t.id] ?? t.id, style: const TextStyle(fontSize: 12)),
                  selected: _triggers.contains(t.id),
                  onSelected: (v) => setState(() => v ? _triggers.add(t.id) : _triggers.remove(t.id)),
                ),
            ]),
            const SizedBox(height: 18),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    final hype = Get.find<HypeVoiceController>();
                    // An unchanged sound plays as it would in a match; edited
                    // text is heard as the new TTS line.
                    if (d != null && _text.text.trim() == d.text) {
                      hype.previewSound(d.id);
                    } else {
                      hype.previewText(_text.text);
                    }
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Preview'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.cyanAccent),
                ),
                const SizedBox(width: 8),
                if (canDelete || canReset)
                  TextButton(
                    onPressed: _delete,
                    child: Text(canReset ? 'Reset text' : 'Delete',
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Music ─────────────────────────────────────────────────────────────────

class _MusicTab extends StatelessWidget {
  const _MusicTab();

  @override
  Widget build(BuildContext context) {
    final music = Get.find<MusicService>();
    return Obx(() {
      final tracks = music.playlist.toList();
      final playing = music.currentTrackName.value;
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${tracks.length} tracks',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => music.stopMusic(),
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('Stop'),
                    ),
                    TextButton.icon(
                      onPressed: music.resyncFromAssets,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Resync'),
                    ),
                  ],
                ),
                const Text(
                  'Bundled with the app (assets/audio/music). Tension picks tracks '
                  'with "tension" in the name, otherwise any track.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final path in tracks)
            ListTile(
              dense: true,
              leading: Icon(
                playing.isNotEmpty && path.endsWith(playing) ? Icons.graphic_eq : Icons.music_note,
                color: Colors.pinkAccent,
              ),
              title: Text(path.split('/').last.replaceAll(RegExp(r'\.(mp3|m4a|aac)$'), ''),
                  style: const TextStyle(color: Colors.white)),
              trailing: IconButton(
                icon: const Icon(Icons.play_arrow, color: Colors.white70),
                onPressed: () => music.playTrackByPath(path),
              ),
            ),
        ],
      );
    });
  }
}
