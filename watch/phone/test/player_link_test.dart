import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_counter/services/player_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('player typed on court can be linked to the web person by hand', () async {
    final s = await PlayerService().init();
    final hung = await s.add('Hùng');
    // The web knows him by his full name: the pull cannot match "Hùng",
    // so it creates a second player for the web entry.
    await s.importBackend([
      {'id': 'w7', 'name': 'Nguyễn Mạnh Hùng', 'short': ''},
    ]);
    expect(s.roster.length, 2);
    expect(s.webIdOf(hung.id), hung.id); // not linked: would push as unknown
    expect(s.web.map((w) => w.id), ['w7']);

    await s.link(hung.id, 'w7');
    expect(s.webIdOf(hung.id), 'w7');
    final spare = s.linkedTo('w7', except: hung.id).single;

    // Removing a linked player keeps his old matches pointing at the web id.
    await s.remove(hung.id);
    expect(s.webIdOf(hung.id), 'w7');
    expect(s.webIdOf(spare.id), 'w7');

    // Web roster and retired links survive a restart.
    final again = await PlayerService().init();
    expect(again.web.single.name, 'Nguyễn Mạnh Hùng');
    expect(again.webIdOf(hung.id), 'w7');
  });

  test('unlink', () async {
    final s = await PlayerService().init();
    final p = await s.add('An');
    await s.link(p.id, 'w1');
    await s.link(p.id, null);
    expect(s.byId(p.id)!.externalId, isNull);
    expect(s.webIdOf(p.id), p.id);
  });
}
