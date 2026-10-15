import 'package:flutter_test/flutter_test.dart';
import 'package:voice_counter/services/sound_library_service.dart';

SoundLibraryService lib() => SoundLibraryService()
  ..applyDefaults({
    'sounds': [
      {'id': 'double_kill_1', 'display': 'DOUBLE KILL', 'text': 'Double kill!'},
      {'id': 'double_shot_1', 'display': 'DOUBLE SHOT', 'text': 'Double shot!'},
      {'id': 'godlike_1', 'display': 'GODLIKE', 'text': 'Godlike!', 'glow': 'legendary'},
    ],
    'triggers': [
      {'id': 'streak_2', 'priority': 50, 'pool': ['double_kill_1', 'double_shot_1', 'missing_x']},
      {'id': 'streak_5_plus', 'priority': 50, 'pool': ['godlike_1']},
      {'id': 'match_end', 'priority': 95, 'pool': []},
    ],
  }, bundled: {'double_kill_1', 'double_shot_1', 'godlike_1'});

void main() {
  test('pool = defaults minus unknown ids', () {
    expect(lib().pool('streak_2'), ['double_kill_1', 'double_shot_1']);
    expect(lib().pool('nope'), isEmpty);
  });

  test('user layer: add, remove, off', () {
    final l = lib()
      ..applyUser({
        'custom': [
          {'id': 'u_ba_khi', 'display': 'BÁ KHÍ', 'text': 'Bá khí!'},
        ],
        'add': {
          'streak_2': ['u_ba_khi'],
          'match_end': ['godlike_1'],
        },
        'remove': {
          'streak_2': ['double_shot_1'],
        },
        'off': ['godlike_1'],
      });
    expect(l.pool('streak_2'), ['double_kill_1', 'u_ba_khi']);
    // switched off: gone from every pool, still listed
    expect(l.pool('streak_5_plus'), isEmpty);
    expect(l.pool('match_end'), isEmpty);
    expect(l.triggersOf('godlike_1'), {'streak_5_plus', 'match_end'});
    expect(l.sounds.map((d) => d.id), contains('u_ba_khi'));
  });

  test('toggling membership of a default sound round-trips', () async {
    final l = lib();
    await l.setInTrigger('double_kill_1', 'streak_2', false);
    expect(l.pool('streak_2'), ['double_shot_1']);
    await l.setInTrigger('double_kill_1', 'streak_2', true);
    expect(l.pool('streak_2'), ['double_kill_1', 'double_shot_1']);
    await l.setInTrigger('double_kill_1', 'match_end', true);
    expect(l.pool('match_end'), ['double_kill_1']);
    expect(l.triggersOf('double_kill_1'), {'streak_2', 'match_end'});
  });

  test('custom line: slug id, unique, deletable', () async {
    final l = lib();
    final a = await l.addCustom(text: 'Bá Khí!', triggers: {'streak_2'});
    final b = await l.addCustom(text: 'Bá khí');
    expect(a, 'u_ba_khi');
    expect(b, 'u_ba_khi_2');
    expect(l.sound(a)!.display, 'BÁ KHÍ');
    expect(l.pool('streak_2').last, a);
    await l.deleteCustom(a);
    expect(l.sound(a), isNull);
    expect(l.pool('streak_2'), ['double_kill_1', 'double_shot_1']);
  });

  test('editing a bundled sound overrides its text; reset restores it', () async {
    final l = lib();
    await l.edit('godlike_1', text: 'Thần thánh!');
    expect(l.sound('godlike_1')!.text, 'Thần thánh!');
    expect(l.isOverridden('godlike_1'), isTrue);
    await l.deleteCustom('godlike_1');
    expect(l.sound('godlike_1')!.text, 'Godlike!');
    expect(l.pool('streak_5_plus'), ['godlike_1']);
  });

  test('bundled beats TTS', () async {
    final l = lib()..applyUser({'custom': [{'id': 'u_x', 'text': 'x'}]});
    expect((await l.source('double_kill_1'))!.kind, SoundKind.asset);
    final tts = (await l.source('u_x'))!;
    expect(tts.kind, SoundKind.ttsLive);
    expect(tts.value, 'x');
    expect(await l.source('nope'), isNull);
  });
}
