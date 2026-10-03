import 'dart:convert';

/// What the session needs from the recorder. The real one is the CameraX
/// channel ([CameraPlatform]); tests use a fake.
abstract class VideoSink {
  /// Starts a new file Download/[dir]/[name]. The first frame's wall time
  /// comes back through [RecordingSession.onStartWall].
  Future<void> start(String dir, String name);

  /// Ends the current file; [RecordingSession.onFinalized] follows.
  Future<void> stop();

  Future<bool> rename(String uri, String name);

  /// Creates Download/[dir]/[name] or overwrites [uri]; returns the uri.
  Future<String?> writeText(String dir, String name, String text, {String? uri});
}

/// The match a file holds (one per file; docs/camera-recording-requirements.md §5).
class MatchRec {
  final String matchId;
  int? startT; // phone clock, ms
  int? endT;
  String status = 'active';
  int scoreA = 0;
  int scoreB = 0;
  String? winner;
  bool reopened = false;

  /// Started before this file did: joined mid-set, carried over from the
  /// previous file (40-minute split), or reopened by an undo after a win.
  String? continuedFrom;
  Map<String, dynamic>? lineup;
  String rallies = '';
  String ralT = '';
  int? bandStartedAt;
  int? bandEndedAt;

  MatchRec(this.matchId);

  bool get ended => endT != null;

  MatchRec carryOver(String why) => MatchRec(matchId)
    ..status = 'active'
    ..scoreA = scoreA
    ..scoreB = scoreB
    ..lineup = lineup
    ..rallies = rallies
    ..ralT = ralT
    ..bandStartedAt = bandStartedAt
    ..continuedFrom = why;
}

class SessionFile {
  final String dir;
  final String base; // 2026-10-03_191502
  final int requestedAt;
  int? startWall;
  String? uri;
  String? jsonUri;
  String? finalName;
  MatchRec? match;
  final events = <Map<String, dynamic>>[];
  final gaps = <Map<String, dynamic>>[];
  String? error;

  SessionFile(this.dir, this.base, this.requestedAt);

  /// Time zero of this file: its first frame, or when it was asked for.
  int get zero => startWall ?? requestedAt;
}

/// Clock link to the tablet, as the server measured it.
class ClockInfo {
  final int offsetMs; // tablet - phone
  final int samples;
  final int rttMs;
  const ClockInfo(this.offsetMs, this.samples, this.rttMs);
}

/// One recording session: records continuously and cuts the file when a set
/// is started on the band (New game / Same 4 / players picked), so every
/// file begins at its set's start and holds the set plus the break after
/// it (easy to trim). Done, Resume, End set, leaving the app: no cut.
/// All times are phone-clock ms; the server converts the tablet's before
/// they get here.
///
/// The switch to a new file takes ~0.5-1 s (the old one must be finalized
/// first), so a set's `startS` is a little below zero: the tap itself is at
/// the end of the previous file. Serving comes seconds after the tap.
class RecordingSession {
  final VideoSink sink;
  final int Function() now;
  /// Written into every JSON (device model...); filled in as it is learned.
  final Map<String, dynamic> deviceInfo;
  ClockInfo Function() clock;

  static const maxFile = Duration(minutes: 40);

  /// A file younger than this is not cut for a new set (it just began).
  static const minFile = Duration(seconds: 3);

  RecordingSession({
    required this.sink,
    required this.now,
    required this.clock,
    Map<String, dynamic>? deviceInfo,
  }) : deviceInfo = {...?deviceInfo};

  bool running = false;
  SessionFile? current;

  /// Files stopped but not finalized yet, oldest first.
  final _closing = <SessionFile>[];

  /// Finished files by matchId, so a reopen can mark the right JSON.
  final _byMatch = <String, SessionFile>{};
  final finished = <SessionFile>[];

  bool _starting = false;
  int? _gapFrom;

  /// Called on every change worth showing.
  void Function()? onChange;

  /// Called when a new file has started recording (the rig re-measures
  /// exposure there).
  void Function()? onFileStarted;

  // ── Lifecycle ───────────────────────────────────────────────────────────
  Future<void> begin() async {
    if (running) return;
    running = true;
    current = _newFile(now());
    await _startCurrent();
  }

  /// Stop: the last file is closed and named `_nomatch` when no set began
  /// in it (the stretch after the last set).
  Future<void> end() async {
    if (!running) return;
    running = false;
    final f = current;
    current = null;
    if (f != null) {
      _closing.add(f);
      await sink.stop();
    }
    onChange?.call();
  }

  /// Cut now: the next file starts as soon as this one is finalized.
  Future<void> split() async {
    if (!running) return;
    final old = current!;
    final next = _newFile(now());
    final m = old.match;
    // An unfinished set goes on in the next file.
    if (m != null && !m.ended) next.match = m.carryOver('split');
    current = next;
    _closing.add(old);
    await sink.stop();
    onChange?.call();
  }

  /// Every ~10 s: the 40-minute safety cut.
  Future<void> tick() async {
    final f = current;
    if (!running || f == null || f.startWall == null || _closing.isNotEmpty) return;
    if (now() - f.startWall! >= maxFile.inMilliseconds) await split();
  }

  SessionFile _newFile(int t) {
    final d = DateTime.fromMillisecondsSinceEpoch(t);
    String two(int v) => v.toString().padLeft(2, '0');
    final day = '${d.year}-${two(d.month)}-${two(d.day)}';
    return SessionFile('Godminton/$day', '${day}_${two(d.hour)}${two(d.minute)}${two(d.second)}', t);
  }

  Future<void> _startCurrent() async {
    final f = current;
    if (f == null || _starting) return;
    _starting = true;
    try {
      await sink.start(f.dir, '${f.base}_rec.mp4');
    } finally {
      _starting = false;
    }
    onFileStarted?.call();
    onChange?.call();
  }

  // ── Recorder events ────────────────────────────────────────────────────
  void onStartWall(int wall) {
    final f = current;
    if (f == null) return;
    if (f.startWall == null || wall < f.startWall!) f.startWall = wall;
  }

  Future<void> onFinalized(String? uri, {String? error}) async {
    if (_closing.isEmpty) return;
    final f = _closing.removeAt(0);
    f.uri = uri;
    f.error = error;
    await _writeOut(f);
    finished.add(f);
    if (running && current != null) await _startCurrent();
    onChange?.call();
  }

  // ── Link ────────────────────────────────────────────────────────────────
  void linkDown() => _gapFrom ??= now();

  void linkUp() {
    final from = _gapFrom;
    _gapFrom = null;
    final f = current;
    if (from == null || f == null) return;
    f.gaps.add({'fromT': from, 'toT': now(), 'reason': 'ws_disconnected'});
  }

  /// One tablet event, [t] already on the phone clock.
  Future<void> handle(Map<String, dynamic> msg, int t) async {
    final f = current;
    if (!running || f == null) return;
    final type = msg['type'];
    final id = msg['matchId']?.toString();
    if (id == null || id.isEmpty) return;

    switch (type) {
      case 'match_start':
        final m = f.match;
        if (m != null && m.matchId == id) return; // repeat
        final joined = msg['joined'] == true;
        // A set started now gets a file starting now. A set joined mid-way
        // (board restarted, camera started late) only gets a new file when
        // this one already holds another set.
        final cut = joined ? m != null : (m != null || now() - f.zero >= minFile.inMilliseconds);
        if (cut) {
          await split();
          if (current!.match?.matchId != id) current!.match = null;
        }
        final nm = MatchRec(id)
          ..lineup = _map(msg['lineup'])
          ..bandStartedAt = _int(msg['bandStartedAt'])
          ..scoreA = _int(msg['scoreA']) ?? 0
          ..scoreB = _int(msg['scoreB']) ?? 0;
        // Joined: the set began before this file, so its start is not here.
        if (joined) {
          nm.continuedFrom = 'joined';
        } else {
          nm.startT = t;
        }
        current!.match = nm;
        current!.events.add({'type': 'match_start', 't': t});
        break;

      case 'point':
      case 'undo':
        final m = _matchFor(id, t);
        m.scoreA = _int(msg['scoreA']) ?? m.scoreA;
        m.scoreB = _int(msg['scoreB']) ?? m.scoreB;
        current!.events.add({
          'type': type,
          if (type == 'point') 'team': msg['team'],
          'scoreA': m.scoreA,
          'scoreB': m.scoreB,
          't': t,
        });
        break;

      case 'match_end':
        final m = _matchFor(id, t);
        if (m.ended) return;
        m
          ..endT = t
          ..status = (msg['status'] ?? 'completed').toString()
          ..scoreA = _int(msg['scoreA']) ?? m.scoreA
          ..scoreB = _int(msg['scoreB']) ?? m.scoreB
          ..rallies = (msg['rallies'] ?? m.rallies).toString()
          ..ralT = (msg['ralT'] ?? m.ralT).toString()
          ..lineup = _map(msg['lineup']) ?? m.lineup
          ..bandStartedAt = _int(msg['startedAt']) ?? m.bandStartedAt
          ..bandEndedAt = _int(msg['endedAt']);
        m.winner = m.status == 'completed' ? (m.scoreA > m.scoreB ? 'A' : 'B') : null;
        // No cut here: the file runs on through the break until the next
        // set is started.
        current!.events.add({'type': 'match_end', 't': t});
        break;

      case 'match_reopen':
        final m = current!.match;
        if (m != null && m.matchId == id) {
          // Undo of the winning point: still the same file.
          m
            ..endT = null
            ..status = 'active'
            ..winner = null;
          current!.events.add({'type': 'match_reopen', 't': t});
          break;
        }
        final old = _byMatch[id];
        if (old != null) {
          old.match!.reopened = true;
          await _writeJson(old);
        }
        current!.match = (old?.match?.carryOver('reopened')) ?? (MatchRec(id)..continuedFrom = 'reopened');
        current!.events.add({'type': 'match_reopen', 't': t});
        break;
    }
    onChange?.call();
  }

  /// The match an event belongs to; created when its start was missed.
  MatchRec _matchFor(String id, int t) {
    final f = current!;
    final m = f.match;
    if (m != null && m.matchId == id) return m;
    final nm = MatchRec(id)..continuedFrom = 'joined';
    f.match = nm;
    return nm;
  }

  // ── Output ─────────────────────────────────────────────────────────────
  String _id6(String id) {
    final clean = id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return clean.length <= 6 ? clean : clean.substring(clean.length - 6);
  }

  String nameOf(SessionFile f) {
    final m = f.match;
    if (m == null) return '${f.base}_nomatch';
    return '${f.base}_${_id6(m.matchId)}_${m.scoreA}-${m.scoreB}';
  }

  Future<void> _writeOut(SessionFile f) async {
    f.finalName = nameOf(f);
    if (f.uri != null) await sink.rename(f.uri!, '${f.finalName}.mp4');
    await _writeJson(f);
    final m = f.match;
    if (m != null) _byMatch[m.matchId] = f;
  }

  Future<void> _writeJson(SessionFile f) async {
    final text = const JsonEncoder.withIndent('  ').convert(jsonOf(f));
    f.jsonUri = await sink.writeText(f.dir, '${f.finalName ?? nameOf(f)}.json', text, uri: f.jsonUri);
  }

  double _s(SessionFile f, int t) => ((t - f.zero) / 1000 * 1000).round() / 1000;

  Map<String, dynamic> jsonOf(SessionFile f) {
    final c = clock();
    final m = f.match;
    return {
      'schema': 1,
      'video': '${f.finalName ?? nameOf(f)}.mp4',
      'role': 'corner',
      ...deviceInfo,
      'width': deviceInfo['width'] ?? 1920,
      'height': deviceInfo['height'] ?? 1080,
      'fps': 30,
      'stabilization': false,
      'recordStartWall': DateTime.fromMillisecondsSinceEpoch(f.zero).toIso8601String(),
      'startWallEstimated': f.startWall == null,
      'clockOffsetMs': c.offsetMs,
      'clockSyncSamples': c.samples,
      'clockRttMs': c.rttMs,
      if (f.error != null) 'recorderError': f.error,
      'match': m == null
          ? null
          : {
              'matchId': m.matchId,
              'status': m.status,
              'scoreA': m.scoreA,
              'scoreB': m.scoreB,
              'winner': m.winner,
              'startS': m.startT == null ? null : _s(f, m.startT!),
              'endS': m.endT == null ? null : _s(f, m.endT!),
              'reopened': m.reopened,
              'continuedFrom': m.continuedFrom,
              'lineup': m.lineup,
              'rallies': m.rallies,
              'ralT': m.ralT,
              'bandStartedAt': m.bandStartedAt,
              'bandEndedAt': m.bandEndedAt,
            },
      'events': [
        for (final e in f.events)
          {for (final k in e.keys) if (k != 't') k: e[k], 's': _s(f, e['t'] as int)}
      ],
      'gaps': [
        for (final g in f.gaps)
          {'fromS': _s(f, g['fromT'] as int), 'toS': _s(f, g['toT'] as int), 'reason': g['reason']}
      ],
    };
  }

  static int? _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

  static Map<String, dynamic>? _map(dynamic v) {
    if (v is Map) return v.map((k, val) => MapEntry('$k', val));
    if (v is String && v.startsWith('{')) {
      try {
        return (jsonDecode(v) as Map).map((k, val) => MapEntry('$k', val));
      } catch (_) {}
    }
    return null;
  }
}
