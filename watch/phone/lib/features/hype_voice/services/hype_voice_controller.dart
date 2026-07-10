import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_counter/services/tts_service.dart';
import '../models/hype_state_snapshot.dart';
import '../models/hype_display_event.dart';

class HypeVoiceController extends GetxController {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final List<HypeStateSnapshot> _historyStack = [];

  final RxBool isEnabled = true.obs;
  final RxDouble volume = 0.2.obs;
  final RxBool koEffectEnabled = true.obs;

  final RxString currentStreakTeam = ''.obs;
  final RxInt streakCount = 0.obs;
  final Rx<HypeDisplayEvent?> displayEvent = Rx<HypeDisplayEvent?>(null);
  DateTime? _lastEventTime;

  // Set to true the first time a team has trailed by >=4 within the current
  // match; cleared when that team scores and reaches tied/leading (comeback
  // fired). Allowed to be re-armed if the team later trails again by 4+.
  bool _comebackPendingA = false;
  bool _comebackPendingB = false;

  // Global per-file play count for least-played-random selection.
  // Single namespace for the whole match: a file selected from one pool
  // cannot immediately re-fire from another pool that also contains it.
  // Reset on resetState (new match), restored from snapshot on undo.
  final Map<String, int> _playCounts = {};

  static const int _setPoint = 21;
  static const int _comebackDeficitThreshold = 4;

  final List<String> _bundledFiles = [];

  static const Map<String, String> _displayTexts = {
    'double_kill': 'DOUBLE KILL',
    'double_shot': 'DOUBLE SHOT',
    'nice_pair': 'NICE PAIR',
    'triple_kill': 'TRIPLE KILL',
    'triple_shot': 'TRIPLE SHOT',
    'hat_trick': 'HAT TRICK',
    'quadra_kill': 'QUADRA KILL',
    'quadra_shot': 'QUADRA SHOT',
    'dominating': 'DOMINATING',
    'penta_shot': 'PENTA SHOT',
    'unstoppable': 'UNSTOPPABLE',
    'badminton_slayer': 'BADMINTON\nSLAYER',
    'rampage': 'RAMPAGE',
    'did_you_see_that': 'DID YOU\nSEE THAT?',
    'godlike': 'GODLIKE',
    'legendary': 'LEGENDARY',
    'to_the_moon': 'TO THE MOON',
    'the_chosen_one': 'THE CHOSEN ONE',
    'mom_are_you_watching': 'MOM, ARE YOU\nWATCHING?',
    'shutdown': 'SHUTDOWN!',
    'comeback_king': 'COMEBACK\nKING',
    'unbelievable': 'UNBELIEVABLE',
    'written_in_history': 'WRITTEN IN\nHISTORY',
    'game_on': 'GAME ON',
    'lets_dance': "LET'S DANCE",
    'here_we_go': 'HERE WE GO',
    // Vietnamese female pack
    'dinh_noc_kich_tran': 'ĐỈNH NÓC\nKÍCH TRẦN',
    'cu_danh_dep': 'CÚ ĐÁNH ĐẸP',
    'cu_danh_sam_set': 'CÚ ĐÁNH\nSẤM SÉT',
    'man_nhan': 'MÃN NHÃN',
    'dinh_cua_chop': 'ĐỈNH CỦA CHÓP',
    'cu_nay_khet': 'CÚ NÀY KHÉT',
    'khet_let': 'KHÉT LẸT',
    'phong_do_dinh_cao': 'PHONG ĐỘ\nĐỈNH CAO',
    'dinh_cao_phong_do': 'ĐỈNH CAO\nPHONG ĐỘ',
    'ai_can_noi': 'AI CẢN NỔI',
    'nhu_tron_khong_nguoi': 'NHƯ TRỐNG\nKHÔNG NGƯỜI',
    'quay_xe_cuc_gat': 'QUAY XE\nCỰC GẮT',
    'lat_keo': 'LẬT KÈO',
    'dinh_the_nho': 'ĐỈNH THẾ NHỜ',
    'cham_dut': 'CHẤM DỨT',
    'khong_the_tin_duoc': 'KHÔNG THỂ\nTIN ĐƯỢC',
    'sam_set_giua_troi_quang': 'SẤM SÉT\nGIỮA TRỜI QUANG',
    'thuc_tinh_he_thong': 'THỨC TỈNH\nHỆ THỐNG',
    'vo_dich_thien_ha': 'VÔ ĐỊCH\nTHIÊN HẠ',
    'cao_thu_cao_thu': 'CAO THỦ\nCAO THỦ',
    'mot_phat_chet_tuoi': 'MỘT PHÁT\nCHẾT TƯƠI',
    'dep_nhu_mo': 'ĐẸP NHƯ MƠ',
    'co_may_ghi_diem': 'CỖ MÁY\nGHI ĐIỂM',
    'de_bep': 'DẸP BẸP',
    'manh_ho_xuat_son': 'MÃNH HỔ\nXUẤT SƠN',
    'khong_ngung_bo_cuoc': 'KHÔNG NGỪNG\nBỎ CUỘC',
    'xuat_quy_nhap_than': 'XUẤT QUỶ\nNHẬP THẦN',
    'sao_ma_hay_vay_troi': 'SAO MÀ HAY\nVẬY TRỜI',
    'sao_bang_xe_troi': 'SAO BĂNG\nXẸT TRỜI',
    'mua_rao_giua_ha': 'MƯA RÀO\nGIỮA HẠ',
    'manh_ho_vo_moi': 'MÃNH HỔ\nVÔ MỒI',
    'cu_dap_ca_map': 'CÚ ĐẬP\nCÁ MẬP',
    'tro_lai_tu_dong_tro_tan': 'TRỞ LẠI TỪ\nĐỐNG TRO TÀN',
    'can_loi_can_y': 'CẢN LỜI\nCẢN Ý',
    'khoi_can_ban_cao_nhan_an_the': 'CAO NHÂN\nẨN THẾ',
    'chan_buoc_di_dau_khong_quay_lai': 'CHÂN BƯỚC\nKHÔNG QUAY LẠI',
    'chay_the_nho': 'CHẠY THẾ NHỚ',
    'xinh_trai_co_gi_sai': 'XINH TRAI\nCÓ GÌ SAI',
    'qua_tang_mien_phi': 'QUÀ TẶNG\nMIỄN PHÍ',
    'an_sung_troi_ban': 'ĂN SÚNG\nTRỜI BAN',
    'nhu_dieu_dut_day': 'NHƯ DIỀU\nĐỨT DÂY',
    'duong_cau_lam_tho': 'ĐƯỜNG CẦU\nLÀM THƠ',
    'con_mua_ban_thang': 'CƠN MƯA\nBÀN THẮNG',
    'toi_cong_chuyen': 'TÔI CÔNG\nCHUYÊN',
  };

  String _getDisplayText(String id) {
    // Strip subfolder prefix (e.g. female_pack/cham_dut_f -> cham_dut_f)
    final fileName = id.contains('/') ? id.split('/').last : id;
    // Strip _f suffix (female pack) and numeric suffix (e.g. _1, _2)
    final baseId = fileName
        .replaceAll(RegExp(r'_f$'), '')
        .replaceAll(RegExp(r'_\d+$'), '');
    return _displayTexts[baseId] ?? baseId.toUpperCase().replaceAll('_', ' ');
  }

  static Color _glowColor(String id) {
    // Strip subfolder prefix and _f / numeric suffixes for color lookup
    final fileName = id.contains('/') ? id.split('/').last : id;
    final baseId = fileName
        .replaceAll(RegExp(r'_f$'), '')
        .replaceAll(RegExp(r'_\d+$'), '');
    const legendary = {
      'godlike', 'legendary', 'to_the_moon', 'the_chosen_one',
      'mom_are_you_watching', 'comeback_king', 'written_in_history',
      'unbelievable',
    };
    const fire = {
      'penta_shot', 'unstoppable', 'badminton_slayer', 'rampage',
      'did_you_see_that', 'streak_7_plus',
    };
    const danger = {'shutdown'};

    if (legendary.contains(baseId)) return Colors.amberAccent;
    if (fire.contains(baseId)) return Colors.deepOrangeAccent;
    if (danger.contains(baseId)) return Colors.redAccent;
    return Colors.cyanAccent; // default streaks
  }

  // Called after hype audio finishes (or immediately if no hype queued)
  Function? onPlaybackCompleted;

  // Called when MP3 is missing — ScoreController injects this to speak via TTS
  Function(String text)? onTtsFallback;

  int _lastOpponentStreak = 0;
  int _maxDeficitTeamA = 0;
  int _maxDeficitTeamB = 0;

  List<dynamic> _triggers = [];
  String? _pendingHypeId;

  // TTS fallback texts when MP3 file is missing
  static const Map<String, String> _ttsFallback = {
    'double_kill': 'Double kill!',
    'double_shot': 'Double shot!',
    'nice_pair': 'Nice pair!',
    'triple_kill': 'Triple kill!',
    'triple_shot': 'Triple shot!',
    'hat_trick': 'Hat trick!',
    'quadra_kill': 'Quadra kill!',
    'quadra_shot': 'Quadra shot!',
    'dominating': 'Dominating!',
    'penta_shot': 'Penta shot!',
    'unstoppable': 'Unstoppable!',
    'badminton_slayer': 'Badminton slayer!',
    'rampage': 'Rampage!',
    'did_you_see_that': 'Did you see that?',
    'godlike': 'Godlike!',
    'legendary': 'Legendary!',
    'to_the_moon': 'To the moon!',
    'the_chosen_one': 'The chosen one!',
    'mom_are_you_watching': 'Mom, are you watching?',
    'shutdown': 'Shutdown!',
    'comeback_king': 'Comeback king!',
    'unbelievable': 'Unbelievable!',
    'written_in_history': 'Written in history!',
    'game_on': 'Game on!',
    'lets_dance': "Let's dance!",
    'here_we_go': 'Here we go!',
  };

  static const String _prefPrefix = 'hype_';

  @override
  void onInit() {
    super.onInit();
    _loadConfig();
    _loadPreferences();
    _setupAudio();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    isEnabled.value = prefs.getBool('${_prefPrefix}enabled') ?? true;
    volume.value = prefs.getDouble('${_prefPrefix}volume') ?? 0.2;
    koEffectEnabled.value = prefs.getBool('${_prefPrefix}ko_enabled') ?? true;
  }

  Future<void> savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('${_prefPrefix}enabled', isEnabled.value);
    await prefs.setDouble('${_prefPrefix}volume', volume.value);
    await prefs.setBool('${_prefPrefix}ko_enabled', koEffectEnabled.value);
  }

  Future<void> _loadConfig() async {
    try {
      final String response =
          await rootBundle.loadString('assets/config/hype_voice_config.json');
      final data = json.decode(response);
      _triggers = data['triggers'];
      print('🔥 [Hype] Config loaded: ${_triggers.length} triggers');
      await _validateConfigAgainstAssets();
    } catch (e) {
      print('🔥 [Hype] Config load error: $e');
    }
  }

  /// Cross-checks the config pools against bundled mp3 files. Purely
  /// informational — logs warnings, never throws. Helps catch:
  ///   • files dropped into assets/audio/hype/ but forgotten in config
  ///   • files referenced in config but missing on disk (rename/typo)
  Future<void> _validateConfigAgainstAssets() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      const String dir = 'assets/audio/hype/';
      const String ext = '.mp3';
      final bundled = <String>{
        for (final p in manifest.listAssets())
          if (p.startsWith(dir) && p.endsWith(ext))
            p.substring(dir.length, p.length - ext.length),
      };

      _bundledFiles.clear();
      _bundledFiles.addAll(bundled.toList()..sort());

      final referenced = <String>{};
      for (final t in _triggers) {
        final pool = t['pool'];
        if (pool is List) {
          for (final f in pool) {
            referenced.add(f.toString());
          }
        }
      }

      final unreferenced = bundled.difference(referenced).toList()..sort();
      final missing = referenced.difference(bundled).toList()..sort();

      if (unreferenced.isEmpty && missing.isEmpty) {
        print('🔥 [Hype] ✓ Config valid: ${bundled.length} files wired up');
        return;
      }
      if (unreferenced.isNotEmpty) {
        print('🔥 [Hype] ⚠️  Unreferenced mp3 files (drop them into a pool in hype_voice_config.json):');
        for (final f in unreferenced) {
          print('🔥 [Hype]    • $f');
        }
      }
      if (missing.isNotEmpty) {
        print('🔥 [Hype] ⚠️  Missing mp3 files (referenced in config but not bundled):');
        for (final f in missing) {
          final users = _triggers
              .where((t) {
                final pool = t['pool'];
                return pool is List && pool.contains(f);
              })
              .map((t) => t['id'])
              .join(', ');
          print('🔥 [Hype]    • $f (used by: $users)');
        }
      }
    } catch (e) {
      print('🔥 [Hype] Validator skipped (manifest load failed): $e');
    }
  }

  void _setupAudio() {
    // Request NO audio focus so hype voice lines mix on top of tension music
    // instead of pausing/ducking it — both are meant to play together.
    _audioPlayer.setAudioContext(AudioContext(
      android: AudioContextAndroid(
        audioFocus: AndroidAudioFocus.none,
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.media,
        stayAwake: false,
        isSpeakerphoneOn: false,
      ),
    ));
    _audioPlayer.setVolume(volume.value);
    volume.listen((v) => _audioPlayer.setVolume(v));
    // Fire onPlaybackCompleted when audio finishes naturally
    _audioPlayer.onPlayerComplete.listen((_) {
      onPlaybackCompleted?.call();
    });
  }

  void processScoreUpdate(int oldA, int oldB, int newA, int newB, {String? manualHype}) {
    if (!isEnabled.value) return;

    try {
      // Snapshot pre-event state for undo
      _historyStack.add(HypeStateSnapshot(
        currentStreakTeam: currentStreakTeam.value,
        streakCount: streakCount.value,
        lastOpponentStreak: _lastOpponentStreak,
        maxDeficitTeamA: _maxDeficitTeamA,
        maxDeficitTeamB: _maxDeficitTeamB,
        comebackPendingA: _comebackPendingA,
        comebackPendingB: _comebackPendingB,
        playCounts: Map<String, int>.from(_playCounts),
      ));
      if (_historyStack.length > 20) _historyStack.removeAt(0);

      final String scoringTeam = newA > oldA ? 'A' : 'B';

      // Streak tracking
      if (currentStreakTeam.value == scoringTeam) {
        streakCount.value++;
      } else {
        _lastOpponentStreak = streakCount.value;
        currentStreakTeam.value = scoringTeam;
        streakCount.value = 1;
      }

      // Deficit tracking (legacy max-ever)
      final int deficitA = newB - newA;
      final int deficitB = newA - newB;
      if (deficitA > _maxDeficitTeamA) _maxDeficitTeamA = deficitA;
      if (deficitB > _maxDeficitTeamB) _maxDeficitTeamB = deficitB;

      // Arm comeback flag for the team currently trailing by >=4. Sticky until
      // that team scores back to tied/leading and the comeback trigger fires.
      if (deficitA >= _comebackDeficitThreshold) _comebackPendingA = true;
      if (deficitB >= _comebackDeficitThreshold) _comebackPendingB = true;

      if (manualHype != null) {
        // Check if manualHype is a trigger ID (for randomization from pool)
        final bool isTrigger = _triggers.any((t) => t['id'] == manualHype);
        if (isTrigger) {
          print('🔥 [Hype] Manual trigger group: $manualHype');
          _prepareHype([manualHype]);
        } else {
          print('🔥 [Hype] Manual specific sound: $manualHype');
          _prepareHypeDirectly(manualHype);
        }
        return;
      }

      final List<String> matched = _evaluateTriggers(newA, newB, scoringTeam);
      if (matched.isNotEmpty) {
        // Comeback consumes the pending flag for the scoring team.
        if (matched.contains('comeback')) {
          if (scoringTeam == 'A') {
            _comebackPendingA = false;
          } else {
            _comebackPendingB = false;
          }
        }
        _prepareHype(matched);
      }
    } catch (e) {
      print('🔥 [Hype] processScoreUpdate error: $e');
    }
  }

  void _prepareHypeDirectly(String voiceId) {
    _pendingHypeId = voiceId;

    // Trigger display overlay immediately
    if (koEffectEnabled.value) {
      displayEvent.value = HypeDisplayEvent(
        voiceId: voiceId,
        displayText: _getDisplayText(voiceId),
        team: currentStreakTeam.value.isEmpty ? 'A' : currentStreakTeam.value,
        glowColor: _glowColor(voiceId),
      );
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (displayEvent.value?.voiceId == voiceId) {
          displayEvent.value = null;
        }
      });
    }
    print('🔥 [Hype] Manual trigger via score update: $voiceId');
  }

  List<Map<String, String>> getHypeList() {
    if (_bundledFiles.isEmpty) {
      // Fallback if manifest not loaded yet
      return _ttsFallback.keys.map((id) {
        return {
          'id': id,
          'name': _getDisplayText(id),
        };
      }).toList();
    }
    return _bundledFiles.map((id) {
      return {
        'id': id,
        'name': _getDisplayText(id),
      };
    }).toList();
  }

  Future<void> playManualHype(String voiceId) async {
    // 1. Set as pending (overwrites auto-hype for the next playback slot)
    _pendingHypeId = voiceId;

    // 2. Trigger display overlay immediately
    if (koEffectEnabled.value) {
      displayEvent.value = HypeDisplayEvent(
        voiceId: voiceId,
        displayText: _getDisplayText(voiceId),
        team: currentStreakTeam.value.isEmpty ? 'A' : currentStreakTeam.value,
        glowColor: _glowColor(voiceId),
      );
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (displayEvent.value?.voiceId == voiceId) {
          displayEvent.value = null;
        }
      });
    }

    // 3. Play logic:
    // If TTS is active, we do nothing. ScoreController.onSpeechCompleted will
    // eventually call playHype() which will pick up our _pendingHypeId.
    // If TTS is silent, play immediately.
    try {
      final ttsService = Get.find<TtsService>();
      if (!ttsService.isSpeaking.value) {
        await playHype();
      }
    } catch (e) {
      // Fallback if TtsService not found
      await playHype();
    }
  }

  Future<void> stopAudio() async {
    _pendingHypeId = null;
    await _audioPlayer.stop();
  }

  /// Returns ALL matched trigger ids at the top priority (so their pools can
  /// be merged in `_prepareHype`). Empty list if nothing matched.
  ///
  /// Same-priority triggers are intentionally additive: e.g. when streak=2
  /// both `streak_low` (generic) and `streak_2` (audio says "double") match
  /// at priority 50 and their pools merge.
  List<String> _evaluateTriggers(int newA, int newB, String scoringTeam) {
    int highestPriority = -1;
    final List<String> winners = [];

    for (final trigger in _triggers) {
      final String id = trigger['id'];
      final int priority = trigger['priority'];

      if (!_triggerMatches(id, newA, newB, scoringTeam)) continue;
      if (priority > highestPriority) {
        highestPriority = priority;
        winners
          ..clear()
          ..add(id);
      } else if (priority == highestPriority) {
        winners.add(id);
      }
    }
    return winners;
  }

  bool _triggerMatches(String id, int newA, int newB, String scoringTeam) {
    switch (id) {
      case 'match_end':
        return _hasWinner(newA, newB);

      case 'crucial_moment':
        // Tied at setPoint-1 or higher; OR exactly at setPoint-1 while leading.
        if (newA >= _setPoint - 1 && newA == newB) return true;
        if (newA == _setPoint - 1 && newA > newB) return true;
        if (newB == _setPoint - 1 && newB > newA) return true;
        return false;

      case 'streak_high':
        return streakCount.value >= 4;

      case 'streak_4':
        return streakCount.value == 4;

      case 'streak_5_plus':
        return streakCount.value >= 5;

      case 'comeback':
        final bool pending = scoringTeam == 'A' ? _comebackPendingA : _comebackPendingB;
        if (!pending) return false;
        // Scoring brought scoring team to tied or leading.
        return scoringTeam == 'A' ? newA >= newB : newB >= newA;

      case 'streak_low':
        final int s = streakCount.value;
        return s >= 2 && s <= 3;

      case 'streak_2':
        return streakCount.value == 2;

      case 'streak_3':
        return streakCount.value == 3;

      case 'shutdown':
        return _lastOpponentStreak >= 5 && streakCount.value == 1;

      case 'random_meme':
        // Merges with whichever same-priority streak triggers are matching;
        // selection within the merged pool keeps these "meme" files in
        // rotation alongside the regular streak voices.
        return streakCount.value >= 2;

      case 'first_point_of_match':
      case 'manual_trigger':
        // Not auto-matched from score events. first_point_of_match is fired
        // explicitly via playStartOfMatchHype(); manual_trigger goes through
        // playManualHype() or the manualHype param.
        return false;
    }
    return false;
  }

  bool _hasWinner(int a, int b) {
    if (a == 30 || b == 30) return true;
    if (a >= _setPoint && (a - b) >= 2) return true;
    if (b >= _setPoint && (b - a) >= 2) return true;
    return false;
  }

  void _prepareHype(List<String> triggerIds) {
    if (triggerIds.isEmpty) return;

    // Merge pools (deduped, order-preserved) across all matched triggers.
    final List<String> mergedPool = [];
    final Set<String> seen = {};
    for (final id in triggerIds) {
      final trigger = _triggers.firstWhere(
        (t) => t['id'] == id,
        orElse: () => null,
      );
      if (trigger == null) continue;
      final pool = trigger['pool'];
      if (pool is! List) continue;
      for (final f in pool) {
        final s = f.toString();
        if (seen.add(s)) mergedPool.add(s);
      }
    }
    if (mergedPool.isEmpty) {
      print('🔥 [Hype] Empty merged pool for triggers: $triggerIds');
      return;
    }

    final String chosen = _chooseFromPool(mergedPool);
    _pendingHypeId = chosen;

    print('🔥 [Hype] Triggers: $triggerIds → pending: $chosen');

    // Emit display event for full-screen overlay
    if (koEffectEnabled.value) {
      // Allow interruption if the previous event has been showing for a while (2.5s+)
      final now = DateTime.now();
      if (displayEvent.value != null && _lastEventTime != null) {
        if (now.difference(_lastEventTime!).inMilliseconds < 1500) {
          print('🔥 [Hype] Overlay too recent, skipping: $chosen');
          return;
        }
      }

      _lastEventTime = now;
      displayEvent.value = HypeDisplayEvent(
        voiceId: chosen,
        displayText: _getDisplayText(chosen),
        team: currentStreakTeam.value.isEmpty ? 'A' : currentStreakTeam.value,
        glowColor: _glowColor(chosen),
      );
      // Auto-clear after overlay animation completes (~1.5s)
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (displayEvent.value?.voiceId == chosen) {
          displayEvent.value = null;
        }
      });
    }
  }

  /// Least-played random over GLOBAL per-file counts: pick uniformly among
  /// files in the pool with the minimum play count, then increment that
  /// file's count. A file shared between pools rotates more slowly than a
  /// pool-exclusive file — by design.
  String _chooseFromPool(List<String> pool) {
    int minCount = 1 << 30;
    for (final f in pool) {
      final c = _playCounts[f] ?? 0;
      if (c < minCount) minCount = c;
    }

    final candidates = [for (final f in pool) if ((_playCounts[f] ?? 0) == minCount) f];
    final chosen = candidates[Random().nextInt(candidates.length)];
    _playCounts[chosen] = (_playCounts[chosen] ?? 0) + 1;
    return chosen;
  }

  /// Play pending hype. Called after TTS finishes.
  Future<void> playHype() async {
    if (_pendingHypeId == null || !isEnabled.value) {
      onPlaybackCompleted?.call();
      return;
    }

    final String id = _pendingHypeId!;
    _pendingHypeId = null;
    final String assetPath = 'audio/hype/$id.mp3';

    // Pre-check: verify asset is actually bundled before handing to AudioPlayer
    try {
      await rootBundle.load('assets/$assetPath');
    } catch (_) {
      print('🔥 [Hype] Asset not bundled: $assetPath — needs rebuild');
      _doTtsFallback(id);
      return;
    }

    try {
      await _audioPlayer.play(AssetSource(assetPath));
      print('🔥 [Hype] Playing: $id');
      // onPlaybackCompleted fires via onPlayerComplete listener
    } catch (e) {
      print('🔥 [Hype] Player error for $id: $e');
      _doTtsFallback(id);
    }
  }

  void _doTtsFallback(String id) {
    if (onTtsFallback != null) {
      final text = _getDisplayText(id);
      onTtsFallback!.call(text);
    } else {
      onPlaybackCompleted?.call();
    }
  }

  void playStartOfMatchHype() {
    _prepareHype(['first_point_of_match']);
    playHype();
  }

  void handleUndo() {
    if (_historyStack.isEmpty) return;
    final snapshot = _historyStack.removeLast();
    currentStreakTeam.value = snapshot.currentStreakTeam ?? '';
    streakCount.value = snapshot.streakCount;
    _lastOpponentStreak = snapshot.lastOpponentStreak;
    _maxDeficitTeamA = snapshot.maxDeficitTeamA;
    _maxDeficitTeamB = snapshot.maxDeficitTeamB;
    _comebackPendingA = snapshot.comebackPendingA;
    _comebackPendingB = snapshot.comebackPendingB;
    // Restore global play counts (copy so future mutations don't reach back
    // into the snapshot).
    _playCounts
      ..clear()
      ..addAll(snapshot.playCounts);
    _pendingHypeId = null;
  }

  void resetState() {
    currentStreakTeam.value = '';
    streakCount.value = 0;
    _lastOpponentStreak = 0;
    _maxDeficitTeamA = 0;
    _maxDeficitTeamB = 0;
    _comebackPendingA = false;
    _comebackPendingB = false;
    _playCounts.clear();
    _historyStack.clear();
    _pendingHypeId = null;
  }

  @override
  void onClose() {
    _audioPlayer.dispose();
    super.onClose();
  }
}
