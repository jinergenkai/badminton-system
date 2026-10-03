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

  test('one set: cut 5 s after the end, named with id and score, times from the first frame', () {
    fakeAsync((fa) {
      setUpSession();
      s.begin();
      fa.flushMicrotasks();
      expect(sink.calls, ['start 2026-10-03_191502_rec.mp4']);
      s.onStartWall(t0 + 400);
      s.onStartWall(t0 + 300); // a better (earlier) estimate wins

      clock = t0 + 74300;
      s.handle({'type': 'match_start', 'matchId': 'b10-1-abc123'}, clock);
      clock = t0 + 92600;
      s.handle({'type': 'point', 'matchId': 'b10-1-abc123', 'team': 'A', 'scoreA': 1, 'scoreB': 0}, clock);
      clock = t0 + 1012800;
      s.handle({'type': 'match_end', 'matchId': 'b10-1-abc123', 'status': 'completed', 'scoreA': 21, 'scoreB': 18}, clock);
      fa.flushMicrotasks();
      expect(sink.calls.where((c) => c == 'stop'), isEmpty);

      fa.elapse(const Duration(seconds: 5));
      expect(sink.calls.last, 'stop');
      s.onFinalized('vid0');
      fa.flushMicrotasks();

      expect(sink.names['vid0'], '2026-10-03_191502_abc123_21-18.mp4');
      final j = jsonNamed('_abc123_21-18.json');
      expect(j['match']['startS'], 74.0); // 74.3 s after request, first frame at +0.3
      expect(j['match']['endS'], 1012.5);
      expect(j['match']['winner'], 'A');
      expect(j['events'][1], {'type': 'point', 'team': 'A', 'scoreA': 1, 'scoreB': 0, 's': 92.3});
      expect(j['clockOffsetMs'], -132);
      // The next file starts right after the old one is finalized.
      expect(sink.calls.last, startsWith('start 2026-10-03_'));
      expect(s.current!.match, isNull);
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

  test('undo inside the 5 s tail cancels the cut', () {
    fakeAsync((fa) {
      setUpSession();
      s.begin();
      fa.flushMicrotasks();
      s.handle({'type': 'match_start', 'matchId': 'm1'}, clock);
      s.handle({'type': 'match_end', 'matchId': 'm1', 'status': 'completed', 'scoreA': 21, 'scoreB': 3}, clock);
      fa.elapse(const Duration(seconds: 2));
      s.handle({'type': 'match_reopen', 'matchId': 'm1'}, clock);
      fa.elapse(const Duration(seconds: 10));
      expect(sink.calls.where((c) => c == 'stop'), isEmpty);
      expect(s.current!.match!.ended, isFalse);
    });
  });

  test('undo after the cut marks the old file reopened and carries the set on', () {
    fakeAsync((fa) {
      setUpSession();
      s.begin();
      fa.flushMicrotasks();
      s.handle({'type': 'match_start', 'matchId': 'm1'}, clock);
      s.handle({'type': 'match_end', 'matchId': 'm1', 'status': 'completed', 'scoreA': 21, 'scoreB': 19}, clock);
      fa.elapse(const Duration(seconds: 5));
      s.onFinalized('vid0');
      fa.flushMicrotasks();
      s.handle({'type': 'match_reopen', 'matchId': 'm1'}, clock);
      fa.flushMicrotasks();
      expect(jsonNamed('_m1_21-19.json')['match']['reopened'], isTrue);
      expect(s.current!.match!.matchId, 'm1');
      expect(s.current!.match!.continuedFrom, 'reopened');
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
}
