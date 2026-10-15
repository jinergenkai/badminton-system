import 'package:flutter/material.dart';

import '../models/match.dart';
import '../models/match_analysis.dart';
import 'ui_kit.dart';

const _red = Ui.red;
const _blue = Ui.blue;

/// One set in detail: lineup, score progression, streaks, rally pace and —
/// for named sets — each player's serve / receive record.
class MatchDetailScreen extends StatelessWidget {
  final Match match;
  final int number;

  const MatchDetailScreen({super.key, required this.match, required this.number});

  @override
  Widget build(BuildContext context) {
    final lu = match.lineup;
    final an = MatchAnalysis.of(
      rallies: match.rallySequence,
      rallyTimes: match.rallyTimes,
      finalA: match.teamAScore,
      finalB: match.teamBScore,
      lineup: lu,
    );
    final hasLog = match.rallySequence.isNotEmpty;

    return UiPage(
      title: 'Set #$number',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Section(child: _header(lu == null)),
          if (lu != null)
            _Section(
              title: 'Players',
              child: Row(
                children: [
                  Expanded(child: _pair([lu.fullOf(lu.red[0]), lu.fullOf(lu.red[1])], _red, false)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('vs', style: TextStyle(color: Colors.white38)),
                  ),
                  Expanded(child: _pair([lu.fullOf(lu.blue[0]), lu.fullOf(lu.blue[1])], _blue, true)),
                ],
              ),
            ),
          if (hasLog)
            _Section(
              title: 'Score progression',
              child: SizedBox(
                height: 160,
                child: CustomPaint(painter: _ProgressionPainter(an.progression), size: Size.infinite),
              ),
            ),
          if (hasLog)
            _Section(
              title: 'Set',
              child: Column(
                children: [
                  _kv('Rallies', '${an.progression.length - 1}'),
                  _kvColored('Longest run', '${an.longestStreakA}', '${an.longestStreakB}'),
                  if (an.avgRallySeconds != null)
                    _kv('Avg rally', '${an.avgRallySeconds!.toStringAsFixed(0)}s'),
                  if (an.longestRallySeconds != null)
                    _kv('Longest rally', '${an.longestRallySeconds}s'),
                  if (match.durationEstimated)
                    _kv('Note', 'joined mid-set: start time estimated'),
                ],
              ),
            ),
          if (an.players.isNotEmpty)
            _Section(
              title: 'Per player (won / played)',
              child: Table(
                columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
                children: [
                  const TableRow(children: [
                    _Cell('', header: true),
                    _Cell('Serve', header: true),
                    _Cell('Receive', header: true),
                  ]),
                  for (final p in an.players)
                    TableRow(children: [
                      _Cell(lu!.shortOf(p.id), color: p.team == 'A' ? _red : _blue),
                      _Cell('${p.servesWon} / ${p.serves}'),
                      _Cell('${p.receivesWon} / ${p.receives}'),
                    ]),
                ],
              ),
            ),
          if (!hasLog)
            const _Section(
              child: Text('No rally log for this set (recorded before logging existed).',
                  style: TextStyle(color: Colors.white54)),
            ),
        ],
      ),
    );
  }

  Widget _header(bool unnamed) {
    final stopped = match.status == 'stopped';
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${match.teamAScore}',
                style: const TextStyle(color: _red, fontSize: 52, fontWeight: FontWeight.w900,
                    shadows: [Shadow(color: _red, blurRadius: 16)])),
            const Text('  –  ', style: TextStyle(color: Colors.white38, fontSize: 32)),
            Text('${match.teamBScore}',
                style: const TextStyle(color: _blue, fontSize: 52, fontWeight: FontWeight.w900,
                    shadows: [Shadow(color: _blue, blurRadius: 16)])),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${stopped ? 'STOPPED' : 'COMPLETED'}  ·  ${uiDay(match.startTime)} ${uiTime(match.startTime)}  ·  '
          '${match.durationEstimated ? '~' : ''}${match.formattedDuration}',
          style: TextStyle(color: stopped ? Colors.orangeAccent : Colors.white70, fontSize: 13),
        ),
        if (unnamed) ...[
          const SizedBox(height: 4),
          Text('${match.teamAName}  vs  ${match.teamBName}',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _pair(List<String> names, Color c, bool alignEnd) => Column(
        crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: names
            .map((n) => Text(n,
                style: TextStyle(color: c, fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: alignEnd ? TextAlign.right : TextAlign.left))
            .toList(),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(k, style: const TextStyle(color: Colors.white60)),
          const Spacer(),
          Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
      );

  Widget _kvColored(String k, String red, String blue) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(k, style: const TextStyle(color: Colors.white60)),
          const Spacer(),
          Text(red, style: const TextStyle(color: _red, fontWeight: FontWeight.bold)),
          const Text('  /  ', style: TextStyle(color: Colors.white38)),
          Text(blue, style: const TextStyle(color: _blue, fontWeight: FontWeight.bold)),
        ]),
      );

}

class _Section extends StatelessWidget {
  final String? title;
  final Widget child;
  const _Section({this.title, required this.child});

  @override
  Widget build(BuildContext context) => UiPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(title!.toUpperCase(),
                  style: const TextStyle(
                      color: Ui.muted, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              const SizedBox(height: 10),
            ],
            child,
          ],
        ),
      );
}

class _Cell extends StatelessWidget {
  final String text;
  final bool header;
  final Color? color;
  const _Cell(this.text, {this.header = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Text(
          text,
          style: TextStyle(
            color: header ? Colors.white54 : (color ?? Colors.white),
            fontWeight: header || color != null ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );
}

/// Two step lines, red and blue, score against rally number.
class _ProgressionPainter extends CustomPainter {
  final List<List<int>> points;
  _ProgressionPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final maxScore = points.fold<int>(1, (m, p) => [m, p[0], p[1]].reduce((a, b) => a > b ? a : b));
    final n = points.length - 1;
    double x(int i) => size.width * i / n;
    double y(int v) => size.height - size.height * v / maxScore;

    final grid = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    for (final v in [0, maxScore ~/ 2, maxScore]) {
      canvas.drawLine(Offset(0, y(v)), Offset(size.width, y(v)), grid);
    }

    for (final team in [0, 1]) {
      final path = Path()..moveTo(x(0), y(points[0][team]));
      for (var i = 1; i <= n; i++) {
        path.lineTo(x(i), y(points[i - 1][team]));
        path.lineTo(x(i), y(points[i][team]));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = team == 0 ? _red : _blue
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressionPainter old) => old.points != points;
}
