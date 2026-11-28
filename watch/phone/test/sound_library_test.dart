import 'dart:convert';
import 'dart:io';

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

  group('playablePool: voices and spicy mode', () {
    SoundLibraryService voiced() => SoundLibraryService()
      ..applyDefaults({
        'sounds': [
          {'id': 'ma_hay', 'text': 'Hay vậy bà!', 'voice': 'mai_anh'},
          {'id': 'ma_vai', 'text': 'Hay vãi lon!', 'voice': 'mai_anh', 'spicy': true},
          {'id': 'g12_nin', 'text': 'Nín!', 'voice': 'lyria_nu'},
          {'id': 'old_en', 'text': 'Godlike!'},
          {'id': 'weird', 'text': 'x', 'voice': 'nobody'},
        ],
        'triggers': [
          {'id': 'any', 'priority': 0, 'pool': ['ma_hay', 'ma_vai', 'g12_nin', 'old_en', 'weird']},
          {'id': 'only_old', 'priority': 0, 'pool': ['old_en']},
          {'id': 'only_spicy', 'priority': 0, 'pool': ['ma_vai']},
        ],
      });

    test('defaults: every voice, no spicy line', () {
      expect(voiced().playablePool('any'), ['ma_hay', 'g12_nin', 'old_en', 'weird']);
    });

    test('unknown voice counts as "others"', () {
      expect(voiced().sound('weird')!.voice, HypeVoice.other);
    });

    test('spicy mode adds the rude lines', () {
      expect(voiced().playablePool('any', spicy: true), ['ma_hay', 'ma_vai', 'g12_nin', 'old_en', 'weird']);
    });

    test('voice switches keep only the chosen voices', () {
      expect(voiced().playablePool('any', voices: {HypeVoice.maiAnh}), ['ma_hay']);
      expect(voiced().playablePool('any', voices: {HypeVoice.maiAnh, HypeVoice.lyriaNu}, spicy: true),
          ['ma_hay', 'ma_vai', 'g12_nin']);
    });

    test('no line in the chosen voices: all voices again, never silent', () {
      expect(voiced().playablePool('only_old', voices: {HypeVoice.maiAnh}), ['old_en']);
      expect(voiced().playablePool('any', voices: const {}), ['ma_hay', 'g12_nin', 'old_en', 'weird']);
    });

    test('spicy stays off even when it is the only line', () {
      expect(voiced().playablePool('only_spicy'), isEmpty);
    });

    test('voice and spicy survive the JSON round trip', () {
      final d = voiced().sound('ma_vai')!;
      expect(d.toJson(), containsPair('voice', 'mai_anh'));
      expect(d.toJson(), containsPair('spicy', true));
      expect(voiced().sound('old_en')!.toJson().containsKey('voice'), isFalse);
    });
  });

  test('the shipped sound_library.json is consistent with its MP3s', () {
    final j = json.decode(File('assets/config/sound_library.json').readAsStringSync()) as Map<String, dynamic>;
    final sounds = [for (final s in j['sounds'] as List) SoundDef.fromJson(Map<String, dynamic>.from(s))];
    final ids = {for (final s in sounds) s.id};
    expect(ids.length, sounds.length, reason: 'duplicate ids');
    for (final t in j['triggers'] as List) {
      for (final p in t['pool'] as List) {
        expect(ids, contains(p), reason: '${t['id']} names an unknown sound');
      }
    }
    for (final s in sounds) {
      expect(File('assets/audio/hype/${s.id}.mp3').existsSync(), isTrue, reason: '${s.id}.mp3 missing');
      if (s.voice == HypeVoice.maiAnh) {
        expect(File('audio_src/hype/${s.id}.mp3').existsSync(), isTrue, reason: '${s.id}: no source to re-level');
      }
    }
    // Spicy lines stay on the hand-picked band menu, never on automatic moments.
    for (final t in j['triggers'] as List) {
      if ((t['id'] as String).startsWith('manual_')) continue;
      for (final p in t['pool'] as List) {
        expect(sounds.firstWhere((s) => s.id == p).spicy, isFalse, reason: '$p is spicy in ${t['id']}');
      }
    }
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
