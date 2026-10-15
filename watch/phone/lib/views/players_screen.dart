import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/player_service.dart';
import 'ui_kit.dart';

/// Club roster + who is here today. Today's picks are what the band's
/// player picker offers, so keep that to the 8-10 on this court.
class PlayersScreen extends StatefulWidget {
  const PlayersScreen({super.key});

  @override
  State<PlayersScreen> createState() => _PlayersScreenState();
}

class _PlayersScreenState extends State<PlayersScreen> {
  final PlayerService _svc = Get.find<PlayerService>();
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Player> _visible() {
    final q = _query.trim().toLowerCase();
    final list = _svc.roster
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q) || p.short.toLowerCase().contains(q))
        .toList();
    // Today's players on top, then alphabetical.
    list.sort((a, b) {
      final ta = _svc.today.contains(a.id) ? 0 : 1;
      final tb = _svc.today.contains(b.id) ? 0 : 1;
      if (ta != tb) return ta - tb;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  Future<void> _edit({Player? player}) async {
    final nameCtl = TextEditingController(text: player?.name ?? '');
    final shortCtl = TextEditingController(text: player?.short ?? '');
    bool shortTouched = player != null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(player == null ? 'Add player' : 'Edit player'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                autofocus: player == null,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Full name (read aloud)'),
                onChanged: (v) {
                  if (!shortTouched) {
                    shortCtl.text = PlayerService.defaultShort(v);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: shortCtl,
                maxLength: PlayerService.shortMax,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Band name (max 8)'),
                onChanged: (_) => shortTouched = true,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: TextButton.styleFrom(foregroundColor: Colors.white60),
                child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || nameCtl.text.trim().isEmpty) return;
    if (player == null) {
      await _svc.add(nameCtl.text, short: shortCtl.text);
    } else {
      await _svc.edit(player.id, name: nameCtl.text, short: shortCtl.text);
    }
  }

  Future<bool> _confirmDelete(Player p) async {
    final ok = await uiConfirm(context,
        title: 'Remove ${p.name}?', message: 'Past matches keep their name.', confirm: 'Remove');
    if (ok) await _svc.remove(p.id);
    return false; // the Obx list rebuilds itself; Dismissible must not also remove
  }

  String _sentText(DateTime? t) {
    if (t == null) return 'not sent this session';
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return 'sent $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return UiPage(
      title: 'Players',
      fab: FloatingActionButton(
        onPressed: () => _edit(),
        child: const Icon(Icons.person_add),
      ),
      body: Obx(() {
        final todayCount = _svc.today.length;
        final dups = _svc.duplicateShorts;
        final visible = _visible();
        return Column(
          children: [
            // Today summary + band sync
            UiPanel(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Today: $todayCount',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (todayCount > 0)
                        TextButton(onPressed: _svc.clearToday, child: const Text('Clear')),
                      FilledButton.icon(
                        onPressed: _svc.sendToBand,
                        icon: const Icon(Icons.watch, size: 18),
                        label: const Text('Send to band'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_sentText(_svc.lastSent.value)} · the band list shows its own sync time',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  if (dups.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Same band name today: ${dups.join(', ')} — edit one so the band can tell them apart',
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: Colors.white38),
                  filled: true,
                  fillColor: Ui.panel,
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Ui.line)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Ui.accent)),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _svc.roster.isEmpty
                  ? const UiEmpty(
                      icon: Icons.groups_outlined,
                      title: 'No players yet',
                      hint: 'Tap + to add the people you play with.')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 88),
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final p = visible[i];
                        final isToday = _svc.today.contains(p.id);
                        final isDup = isToday && dups.contains(p.short.toLowerCase());
                        return Dismissible(
                          key: ValueKey(p.id),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (_) => _confirmDelete(p),
                          background: Container(
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          ),
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            tileColor: isToday ? Colors.greenAccent.withOpacity(0.06) : null,
                            onTap: () => _svc.toggleToday(p.id),
                            onLongPress: () => _edit(player: p),
                            leading: Icon(
                              isToday ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: isToday ? Colors.greenAccent : Colors.white38,
                            ),
                            title: Text(p.name, style: const TextStyle(color: Colors.white)),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isDup ? Colors.orangeAccent.withOpacity(0.25) : Colors.white10,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(p.short,
                                  style: TextStyle(
                                      color: isDup ? Colors.orangeAccent : Colors.white70,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Tap: here today · Long-press: edit · Swipe left: remove',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          ],
        );
      }),
    );
  }
}
