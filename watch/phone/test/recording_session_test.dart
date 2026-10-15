import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_counter/features/camera/recording_session.dart';

class FakeSink implements VideoSink {
  final calls = <String>[];
  final texts = <String, String>{}; // uri -> text
  final names = <String, String>{}; // uri -> name
  int n = 0;

  @override
  Future<void> start(String dir, String name) async => calls.add('start $name');

  @override
  Future<void> stop() async => calls.add('stop');

  final discarded = <String>[];

  @override
  Future<void> discard(String uri) async => discarded.add(uri);

  @override
  Future<bool> rename(String uri, String name) async {
    names[uri] = name;
    return true;
  }

  @override
  Future<String?> writeText(String dir, String name, String text, {String? uri}) async {
    final u = uri ?? 'json${n++}';
    texts[u] = text;
    names[u] = name;
    return u;
  }
}

void main() {
  // 2026-10-03 19:15:02 local
  final t0 = DateTime(2026, 10, 3, 19, 15, 2).millisecondsSinceEpoch;

  late FakeSink sink;
  late int clock;
  late RecordingSession s;

  void setUpSession() {
    sink = FakeSink();
    clock = t0;
    s = RecordingSession(
      sink: sink,
      now: () => clock,
      clock: () => const ClockInfo(-132, 5, 18),
      deviceInfo: const {'device': 'test'},
    );
  }

  Map<String, dynamic> jsonNamed(String suffix) {
    final e = sink.texts.entries.firstWhere((e) => sink.names[e.key]!.endsWith(suffix));
    return jsonDecode(e.value) as Map<String, dynamic>;
  }

  test('a set started cuts the file at the tap; its end does not', () {
    fakeAsync((fa) {
      setUpSession();
      s.begin();
      fa.flushMicrotasks();
      s.onStartWall(t0 + 400);
      s.onStartWall(t0 + 300); // a better (earlier) estimate wins

      // Warm-up before the set: the tap at +74.3 s cuts that off.
      clock = t0 + 74300;
      s.handle({'type': 'match_start', 'matchId': 'b10-1-abc123'}, clock);
      fa.flushMicrotasks();
      expect(sink.calls.last, 'stop');
      s.onFinalized('vid0');
      fa.flushMicrotasks();
      expect(sink.names['vid0'], '2026-10-03_191502_nomatch.mp4');
      expect(sink.calls.last, 'start 2026-10-03_191616_rec.mp4');
      s.onStartWall(t0 + 75100); // the new file's first frame, 0.8 s after the tap

      clock = t0 + 92600;
      s.handle({'type': 'point', 'matchId': 'b10-1-abc123', 'team': 'A', 'scoreA': 1, 'scoreB': 0}, clock);
      clock = t0 + 1012800;
      s.handle({'type': 'match_end', 'matchId': 'b10-1-abc123', 'status': 'completed', 'scoreA': 21, 'scoreB': 18}, clock);
      // Break after the set: still the same file, however long.
      fa.elapse(const Duration(minutes: 5));
      expect(sink.calls.where((c) => c == 'stop').length, 1);

      clock = t0 + 1400000;
      s.handle({'type': 'match_start', 'matchId': 'b10-2-def456'}, clock);
      fa.flushMicrotasks();
      s.onFinalized('vid1');
      fa.flushMicrotasks();

      expect(sink.names['vid1'], '2026-10-03_191616_abc123_21-18.mp4');
      final j = jsonNamed('_abc123_21-18.json');
      expect(j['match']['startS'], -0.8); // the tap is just before the file
      expect(j['match']['endS'], 937.7);
      expect(j['match']['winner'], 'A');
      expect(j['events'][1], {'type': 'point', 'team': 'A', 'scoreA': 1, 'scoreB': 0, 's': 17.5});
      expect(j['clockOffsetMs'], -132);
      expect(s.current!.match!.matchId, 'b10-2-def456');
    });
  });

  test('a set started right after Start recording keeps that file', () {
    fakeAsync((fa) {
      setUpSession();
      s.begin();
      fa.flushMicrotasks();
      clock = t0 + 1500;
      s.handle({'type': 'match_start', 'matchId': 'm1'}, clock);
      fa.flushMicrotasks();
      expect(sink.calls.where((c) => c == 'stop'), isEmpty);
      expect(s.current!.match!.matchId, 'm1');
    });
  });

  test('a set joined mid-way does not cut a file with no set', () {
    fakeAsync((fa) {
      setUpSession();
      s.begin();
      fa.flushMicrotasks();
      clock = t0 + 60000;
      s.handle({'type': 'match_start', 'matchId': 'm1', 'joined': true, 'scoreA': 7, 'scoreB': 5}, clock);
      fa.flushMicrotasks();
      expect(sink.calls.where((c) => c == 'stop'), isEmpty);
      expect(s.current!.match!.continuedFrom, 'joined');
      expect(s.current!.match!.scoreA, 7);
      expect(s.jsonOf(s.current!)['match']['startS'], isNull);
    });
  });

  test('stopping with no set in the file names it _nomatch', () {
    fakeAsync((fa) {
      setUpSession();
      s.begin();
      fa.flushMicrotasks();
      s.end();
      fa.flushMicrotasks();
      s.onFinalized('vid0');
      fa.flushMicrotasks();
      expect(sink.names['vid0'], '2026-10-03_191502_nomatch.mp4');
      expect(sink.calls.where((c) => c.startsWith('start')).length, 1);
    });
  });

  test('undo of the winning point stays in the same file', () {
    fakeAsync((fa) {
      setUpSession();
      s.begin();
      fa.flushMicrotasks();
      s.handle({'type': 'match_start', 'matchId': 'm1'}, clock);
      s.handle({'type': 'match_end', 'matchId': 'm1', 'status': 'completed', 'scoreA': 21, 'scoreB': 3}, clock);
      fa.elapse(const Duration(seconds: 30));
      s.handle({'type': 'match_reopen', 'matchId': 'm1'}, clock);
      fa.elapse(const Duration(minutes: 2));
      expect(sink.calls.where((c) => c == 'stop'), isEmpty);
      expect(s.current!.match!.ended, isFalse);
    });
  });

  test('a new set while the file already holds one gets a file of its own', () {
    fakeAsync((fa) {
      setUpSession();
      s.begin();
      fa.flushMicrotasks();
      s.handle({'type': 'match_start', 'matchId': 'm1'}, clock);
      s.handle({'type': 'point', 'matchId': 'm1', 'team': 'B', 'scoreA': 0, 'scoreB': 1}, clock);
      // m1 never ended (link lost); m2 starts.
      s.handle({'type': 'match_start', 'matchId': 'm2'}, clock);
      fa.flushMicrotasks();
      expect(sink.calls.last, 'stop');
      expect(s.current!.match!.matchId, 'm2');
      s.onFinalized('vid0');
      fa.flushMicrotasks();
      expect(sink.names['vid0'], '2026-10-03_191502_m1_0-1.mp4');
    });
  });

  test('40 minutes: cut, and the set goes on in the next file', () {
    fakeAsync((fa) {
      setUpSession();
      s.begin();
      fa.flushMicrotasks();
      s.onStartWall(t0);
      s.handle({'type': 'match_start', 'matchId': 'm1'}, clock);
      clock = t0 + 40 * 60 * 1000;
      s.tick();
      fa.flushMicrotasks();
      expect(sink.calls.last, 'stop');
      expect(s.current!.match!.continuedFrom, 'split');
    });
  });

  test('a link gap is recorded in file seconds', () {
    fakeAsync((fa) {
      setUpSession();
      s.begin();
      fa.flushMicrotasks();
      s.onStartWall(t0);
      clock = t0 + 300000;
      s.linkDown();
      clock = t0 + 312500;
      s.linkUp();
      final j = s.jsonOf(s.current!);
      expect(j['gaps'], [
        {'fromS': 300.0, 'toS': 312.5, 'reason': 'ws_disconnected'}
      ]);
    });
  });

  test('a file under 30 s is deleted, not saved', () {
    fakeAsync((fa) {
      setUpSession();
      s.begin();
      fa.flushMicrotasks();
      clock = t0 + 10000;
      s.handle({'type': 'match_start', 'matchId': 'm1'}, clock); // cuts the 10 s warm-up
      fa.flushMicrotasks();
      s.onFinalized('vid0', durationMs: 10000);
      fa.flushMicrotasks();
      expect(sink.discarded, ['vid0']);
      expect(sink.names.containsKey('vid0'), isFalse); // no rename, no json
      expect(s.discarded, 1);
      expect(s.finished, isEmpty);
      // The next file still starts.
      expect(sink.calls.last, startsWith('start '));

      // A real set: kept.
      clock = t0 + 900000;
      s.end();
      fa.flushMicrotasks();
      s.onFinalized('vid1', durationMs: 890000);
      fa.flushMicrotasks();
      expect(sink.names['vid1'], endsWith('_m1_0-0.mp4'));
      expect(s.finished.length, 1);
    });
  });
}
