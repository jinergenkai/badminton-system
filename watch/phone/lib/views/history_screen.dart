import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/match.dart';
import '../services/database_service.dart';
import 'match_detail_screen.dart';
import 'ui_kit.dart';

/// Saved sets, newest first, grouped by day. #1 is the most recent.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Match> _all = [];
  List<Match> _matches = [];

  /// Complete sets by default: those are what analysis uses. Stopped sets
  /// (reset mid-game) are one tap away.
  String _filter = 'completed';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    try {
      _all = DatabaseService.getAllMatches();
    } catch (e) {
      print('Error loading matches: $e');
      _all = [];
    }
    _applyFilter();
  }

  void _applyFilter() {
    setState(() {
      _matches = _filter == 'all' ? _all : _all.where((m) => m.status == _filter).toList();
    });
  }

  int _count(String f) => f == 'all' ? _all.length : _all.where((m) => m.status == f).length;

  Future<bool> _delete(Match m) async {
    final ok = await uiConfirm(context,
        title: 'Delete this set?', message: '${m.teamAScore} – ${m.teamBScore}, ${uiDay(m.startTime)} ${uiTime(m.startTime)}');
    if (!ok) return false;
    // By id: the list index is not a Hive key (keys are never reused and the
    // list is sorted), so deleting by index removed the wrong set.
    await DatabaseService.deleteMatchById(m.id);
    _load();
    return false; // the list rebuilt itself; Dismissible must not also remove
  }

  Future<void> _clearAll() async {
    final ok = await uiConfirm(context,
        title: 'Clear all history?',
        message: 'Every saved set is deleted. This cannot be undone.',
        confirm: 'Clear all');
    if (!ok) return;
    await DatabaseService.deleteAllMatches();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return UiPage(
      title: 'History',
      actions: [
        if (_all.isNotEmpty)
          IconButton(icon: const Icon(Icons.delete_sweep_outlined), tooltip: 'Clear all', onPressed: _clearAll),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              for (final f in const [['completed', 'Completed'], ['stopped', 'Stopped'], ['all', 'All']])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${f[1]}  ${_count(f[0])}'),
                    selected: _filter == f[0],
                    showCheckmark: false,
                    onSelected: (_) {
                      _filter = f[0];
                      _applyFilter();
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      body: _matches.isEmpty
          ? UiEmpty(
              icon: Icons.history,
              title: _all.isEmpty ? 'No sets yet' : 'Nothing here',
              hint: _all.isEmpty ? 'Finished sets from the band land here.' : 'Try another filter.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: _matches.length,
              itemBuilder: (context, i) {
                final m = _matches[i];
                final day = uiDay(m.startTime);
                final newDay = i == 0 || uiDay(_matches[i - 1].startTime) != day;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (newDay) UiSection(day),
                    Dismissible(
                      key: ValueKey(m.id),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) => _delete(m),
                      background: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(Ui.radius),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      ),
                      child: _MatchCard(
                        match: m,
                        number: i + 1,
                        onTap: () => Get.to(() => MatchDetailScreen(match: m, number: i + 1)),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  final Match match;
  final int number;
  final VoidCallback onTap;

  const _MatchCard({required this.match, required this.number, required this.onTap});

  /// Band names of a pair ("Hùng · Quỳnh"), or the stored team name.
  String _names(String team) {
    final lu = match.lineup;
    if (lu == null) return team == 'A' ? match.teamAName : match.teamBName;
    return lu.pair(team).map(lu.shortOf).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final stopped = match.status == 'stopped';
    final meta = [
      uiTime(match.startTime),
      '${match.durationEstimated ? '~' : ''}${match.formattedDuration}',
    ].join('  ·  ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Ui.radius),
        child: UiPanel(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('#$number',
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 10),
                  Text(meta, style: const TextStyle(color: Ui.muted, fontSize: 12)),
                  const Spacer(),
                  if (stopped)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orangeAccent.withOpacity(0.6)),
                      ),
                      child: const Text('STOPPED',
                          style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.w900)),
                    ),
                  const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _side('A', stopped)),
                  const SizedBox(width: 10),
                  Expanded(child: _side('B', stopped)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One team: its colour always, bright when it won, dim when it lost.
  Widget _side(String team, bool stopped) {
    final c = Ui.team(team);
    final score = team == 'A' ? match.teamAScore : match.teamBScore;
    final won = !stopped && match.winner == team;
    final lost = !stopped && match.winner.isNotEmpty && !won;
    return Opacity(
      opacity: lost ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.withOpacity(won ? 0.22 : 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withOpacity(won ? 0.9 : 0.3), width: won ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Text('$score',
                style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, height: 1.1,
                    shadows: won ? [Shadow(color: c, blurRadius: 12)] : null)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _names(team),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.withOpacity(0.95), fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            if (won) const Text('🏆', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
