import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../views/ui_kit.dart';
import 'camera_platform.dart';

/// The recordings in Download/Godminton on this device, newest first,
/// grouped by day. Each card: a frame of the video with its length and the
/// set's score over the bottom edge. Tap plays it in the phone's player;
/// long-press starts selecting, for deleting several at once.
class VideoGalleryScreen extends StatefulWidget {
  const VideoGalleryScreen({super.key});

  @override
  State<VideoGalleryScreen> createState() => _VideoGalleryScreenState();
}

class _VideoGalleryScreenState extends State<VideoGalleryScreen> {
  late Future<List<Map<String, dynamic>>> _videos = CameraPlatform.listVideos();
  List<Map<String, dynamic>> _list = const [];

  /// Selected uris; selecting while non-empty.
  final _selected = <String>{};
  bool get _selecting => _selected.isNotEmpty;

  /// Thumbnails already fetched, by uri: scrolling back does not refetch.
  static final _thumbs = <String, Future<Uint8List?>>{};

  Future<void> _reload() async {
    setState(() {
      _selected.clear();
      _videos = CameraPlatform.listVideos();
    });
    await _videos;
  }

  void _toggle(String uri) => setState(() => _selected.contains(uri) ? _selected.remove(uri) : _selected.add(uri));

  Future<void> _deleteSelected() async {
    final chosen = _list.where((v) => _selected.contains(v['uri'])).toList();
    final bytes = chosen.fold<int>(0, (s, v) => s + ((v['size'] as num?)?.toInt() ?? 0));
    final ok = await uiConfirm(
      context,
      title: 'Delete ${chosen.length} video${chosen.length == 1 ? '' : 's'}?',
      message: '${(bytes / 1e9).toStringAsFixed(2)} GB, with their .json files. This cannot be undone.',
    );
    if (!ok) return;
    final n = await CameraPlatform.deleteVideos(chosen.map((v) => v['uri'] as String).toList());
    for (final v in chosen) {
      _thumbs.remove(v['uri']);
    }
    if (mounted && n < chosen.length) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Deleted $n of ${chosen.length}: the rest were not recorded by this app')));
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back leaves selection first.
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: UiPage(
        title: _selecting ? '${_selected.length} selected' : 'Videos',
        actions: _selecting
            ? [
                IconButton(
                  tooltip: 'Select all',
                  icon: const Icon(Icons.select_all),
                  onPressed: () => setState(() => _selected.addAll(_list.map((v) => v['uri'] as String))),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: _deleteSelected,
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
              ]
            : [IconButton(icon: const Icon(Icons.refresh), onPressed: _reload)],
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _videos,
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final list = snap.data!;
            _list = list;
            if (list.isEmpty) {
              return const UiEmpty(
                icon: Icons.videocam_off,
                title: 'No videos yet',
                hint: 'Recordings land in Download/Godminton',
              );
            }
            // Day -> videos, keeping the newest-first order.
            final days = <String, List<Map<String, dynamic>>>{};
            for (final v in list) {
              days.putIfAbsent(_Name.parse(v['name'] as String).day, () => []).add(v);
            }
            final total = list.fold<int>(0, (s, v) => s + ((v['size'] as num?)?.toInt() ?? 0));
            return RefreshIndicator(
              onRefresh: _reload,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text(
                        '${list.length} videos · ${(total / 1e9).toStringAsFixed(1)} GB · Download/Godminton',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ),
                  ),
                  for (final e in days.entries) ...[
                    SliverToBoxAdapter(
                      child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: UiSection(e.key)),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 320,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 16 / 12,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _card(e.value[i]),
                          childCount: e.value.length,
                        ),
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> v) {
    final uri = v['uri'] as String;
    final n = _Name.parse(v['name'] as String);
    final dur = Duration(milliseconds: (v['durationMs'] as num?)?.toInt() ?? 0);
    final mb = ((v['size'] as num?)?.toDouble() ?? 0) / 1e6;
    final thumb = _thumbs.putIfAbsent(uri, () => CameraPlatform.thumbnail(uri));
    final picked = _selected.contains(uri);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _selecting ? _toggle(uri) : CameraPlatform.openVideo(uri),
      onLongPress: () => _toggle(uri),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<Uint8List?>(
                    future: thumb,
                    builder: (context, s) => s.data == null
                        ? Container(
                            color: Colors.white10,
                            child: const Icon(Icons.movie, color: Colors.white24),
                          )
                        : Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true),
                  ),
                  if (_selecting)
                    Container(
                      decoration: BoxDecoration(
                        color: picked ? Colors.amber.withOpacity(0.25) : Colors.black26,
                        border: picked ? Border.all(color: Colors.amber, width: 3) : null,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.topRight,
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        picked ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: picked ? Colors.amber : Colors.white70,
                      ),
                    ),
                  // Bottom strip: length on the left, the set's score on the right.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 18, 10, 6),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.play_arrow, size: 18, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            _dur(dur),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          if (n.a != null) ...[
                            Text(
                              '${n.a}',
                              style: const TextStyle(color: Color(0xFFFF7A7A), fontWeight: FontWeight.bold),
                            ),
                            const Text(' - ', style: TextStyle(color: Colors.white70)),
                            Text(
                              '${n.b}',
                              style: const TextStyle(color: Color(0xFF7AAEFF), fontWeight: FontWeight.bold),
                            ),
                          ] else
                            const Text('no set', style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('${n.time} · ${mb.toStringAsFixed(0)} MB', style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }

  static String _dur(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }
}

/// `2026-10-03_142540_424242_21-19.mp4` / `2026-10-03_135958_nomatch.mp4`
class _Name {
  final String day;
  final String time;
  final int? a;
  final int? b;
  const _Name(this.day, this.time, this.a, this.b);

  static _Name parse(String name) {
    final m = RegExp(r'^(\d{4}-\d{2}-\d{2})_(\d{2})(\d{2})(\d{2})(?:_[^_]+_(\d+)-(\d+))?').firstMatch(name);
    if (m == null) return _Name('Other', name, null, null);
    return _Name(
      m.group(1)!,
      '${m.group(2)}:${m.group(3)}',
      m.group(5) == null ? null : int.parse(m.group(5)!),
      m.group(6) == null ? null : int.parse(m.group(6)!),
    );
  }
}
