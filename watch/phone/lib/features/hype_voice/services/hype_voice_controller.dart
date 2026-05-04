import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/hype_state_snapshot.dart';

class HypeVoiceController extends GetxController {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final List<HypeStateSnapshot> _historyStack = [];

  final RxBool isEnabled = true.obs;
  final RxDouble volume = 0.8.obs;

  // Called after hype audio finishes (or immediately if no hype queued)
  Function? onPlaybackCompleted;

  // Called when MP3 is missing — ScoreController injects this to speak via TTS
  Function(String text)? onTtsFallback;

  String? _currentStreakTeam;
  int _streakCount = 0;
  int _lastOpponentStreak = 0;
  int _maxDeficitTeamA = 0;
  int _maxDeficitTeamB = 0;
  final List<String> _recentVoiceIds = [];

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

  @override
  void onInit() {
    super.onInit();
    _loadConfig();
    _setupAudio();
  }

  Future<void> _loadConfig() async {
    try {
      final String response =
          await rootBundle.loadString('assets/config/hype_voice_config.json');
      final data = json.decode(response);
      _triggers = data['triggers'];
      print('🔥 [Hype] Config loaded: ${_triggers.length} triggers');
    } catch (e) {
      print('🔥 [Hype] Config load error: $e');
    }
  }

  void _setupAudio() {
    _audioPlayer.setVolume(volume.value);
    volume.listen((v) => _audioPlayer.setVolume(v));
    // Fire onPlaybackCompleted when audio finishes naturally
    _audioPlayer.onPlayerComplete.listen((_) {
      onPlaybackCompleted?.call();
    });
  }

  void processScoreUpdate(int oldA, int oldB, int newA, int newB) {
    if (!isEnabled.value) return;

    _historyStack.add(HypeStateSnapshot(
      currentStreakTeam: _currentStreakTeam,
      streakCount: _streakCount,
      lastOpponentStreak: _lastOpponentStreak,
      maxDeficitTeamA: _maxDeficitTeamA,
      maxDeficitTeamB: _maxDeficitTeamB,
      recentVoiceIds: List.from(_recentVoiceIds),
    ));
    if (_historyStack.length > 20) _historyStack.removeAt(0);

    final String scoringTeam = newA > oldA ? 'A' : 'B';

    if (_currentStreakTeam == scoringTeam) {
      _streakCount++;
    } else {
      _lastOpponentStreak = _streakCount;
      _currentStreakTeam = scoringTeam;
      _streakCount = 1;
    }

    final int deficitA = newB - newA;
    final int deficitB = newA - newB;
    if (deficitA > _maxDeficitTeamA) _maxDeficitTeamA = deficitA;
    if (deficitB > _maxDeficitTeamB) _maxDeficitTeamB = deficitB;

    _evaluateTriggers(newA, newB, scoringTeam);
  }

  void _evaluateTriggers(int newA, int newB, String scoringTeam) {
    String? matchedId;
    int highestPriority = -1;

    for (var trigger in _triggers) {
      final String id = trigger['id'];
      final int priority = trigger['priority'];
      bool isMatch = false;

      switch (id) {
        case 'comeback_king':
          final isAWin = (newA >= 21 && (newA - newB) >= 2) || newA == 30;
          final isBWin = (newB >= 21 && (newB - newA) >= 2) || newB == 30;
          if (isAWin && scoringTeam == 'A' && _maxDeficitTeamA >= 5) isMatch = true;
          if (isBWin && scoringTeam == 'B' && _maxDeficitTeamB >= 5) isMatch = true;
          break;
        case 'shutdown':
          if (_lastOpponentStreak >= 5 && _streakCount == 1) isMatch = true;
          break;
        case 'streak_7_plus':
          if (_streakCount >= 7) isMatch = true;
          break;
        case 'streak_6':
          if (_streakCount == 6) isMatch = true;
          break;
        case 'streak_5':
          if (_streakCount == 5) isMatch = true;
          break;
        case 'streak_4':
          if (_streakCount == 4) isMatch = true;
          break;
        case 'streak_3':
          if (_streakCount == 3) isMatch = true;
          break;
        case 'streak_2':
          if (_streakCount == 2) isMatch = true;
          break;
        case 'first_point_of_match':
          break;
      }

      if (isMatch && priority > highestPriority) {
        highestPriority = priority;
        matchedId = id;
      }
    }

    if (matchedId != null) _prepareHype(matchedId);
  }

  void _prepareHype(String triggerId) {
    final trigger = _triggers.firstWhere((t) => t['id'] == triggerId);
    final List<dynamic> pool = trigger['pool'];

    final available = pool.where((v) => !_recentVoiceIds.contains(v)).toList();
    final finalPool = available.isEmpty ? pool : available;
    final String chosen = finalPool[Random().nextInt(finalPool.length)];

    _pendingHypeId = chosen;

    _recentVoiceIds.add(chosen);
    if (_recentVoiceIds.length > 3) _recentVoiceIds.removeAt(0);

    print('🔥 [Hype] Trigger: $triggerId → pending: $chosen');
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
      final text = _ttsFallback[id] ?? id.replaceAll('_', ' ');
      onTtsFallback!.call(text);
    } else {
      onPlaybackCompleted?.call();
    }
  }

  void playStartOfMatchHype() {
    _prepareHype('first_point_of_match');
    playHype();
  }

  void handleUndo() {
    if (_historyStack.isEmpty) return;
    final snapshot = _historyStack.removeLast();
    _currentStreakTeam = snapshot.currentStreakTeam;
    _streakCount = snapshot.streakCount;
    _lastOpponentStreak = snapshot.lastOpponentStreak;
    _maxDeficitTeamA = snapshot.maxDeficitTeamA;
    _maxDeficitTeamB = snapshot.maxDeficitTeamB;
    _recentVoiceIds.clear();
    _recentVoiceIds.addAll(snapshot.recentVoiceIds);
    _pendingHypeId = null;
  }

  void resetState() {
    _currentStreakTeam = null;
    _streakCount = 0;
    _lastOpponentStreak = 0;
    _maxDeficitTeamA = 0;
    _maxDeficitTeamB = 0;
    _historyStack.clear();
    _pendingHypeId = null;
  }

  @override
  void onClose() {
    _audioPlayer.dispose();
    super.onClose();
  }
}
