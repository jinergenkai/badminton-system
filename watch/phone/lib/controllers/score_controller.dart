import 'dart:async';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/game_state.dart';
import '../models/match.dart';
import '../models/lineup.dart';
import '../services/tts_service.dart';
import '../services/score_announcer_service.dart';
import '../services/database_service.dart';
import '../services/watch_connectivity_service.dart';
import '../services/music_service.dart';
import '../services/audio_settings.dart';
import '../services/player_service.dart';
import '../services/sound_check_service.dart';
import '../services/voice_clip_service.dart';
import '../services/sound_library_service.dart';
import '../features/hype_voice/services/hype_voice_controller.dart';
import '../features/camera/camera_link_service.dart';
import '../features/camera/board_recorder.dart';

class ScoreController extends GetxController {
  final TtsService _ttsService = Get.put(TtsService());
  final ScoreAnnouncerService _scoreAnnouncer = Get.put(ScoreAnnouncerService());
  final WatchConnectivityService _watchService = Get.put(WatchConnectivityService());
  final HypeVoiceController _hypeController = Get.put(HypeVoiceController());
  final MusicService _musicService = Get.put(MusicService());
  final AudioSettings _audio = AudioSettings.i;
  final Uuid _uuid = const Uuid();

  final Rx<GameState> _gameState = GameState().obs;
  final RxBool isGameEnded = false.obs;
  final RxBool isWatchConnected = false.obs;

  Timer? _autoResetTimer;
  Timer? _watchConnectionPoll;

  // Configurable delay before auto-starting next game after a win
  final RxInt autoResetDelay = 60.obs;

  // New settings
  final RxBool scoreAnnouncementsEnabled = true.obs;

  /// Display-only: which end of the screen each team is drawn on.
  ///
  /// Purely a layout concern — team A stays team A, keeps its score, its name,
  /// its red colour and its watch button (`score_A`). All this does is put the
  /// two team cards in the other order so the phone scoreboard matches where
  /// the players actually stand on court. Nothing downstream (scoring,
  /// announcements, history, hype, watch protocol) reads it.
  ///
  /// Toggled from the watch's settings page, which sends a bare
  /// `{action: 'swap_sides'}` and keeps no state of its own.
  final RxBool sidesSwapped = false.obs;

  /// Band "Blank Phone": black overlay + minimum brightness, e.g. while the
  /// user is off court. Taps on the phone are swallowed until it wakes.
  final RxBool phoneBlank = false.obs;

  void setPhoneBlank(bool on) {
    if (phoneBlank.value == on) return;
    phoneBlank.value = on;
    _watchService.setWindowBlank(on);
    print('⌚ [Controller] phone blank = $on');
  }

  StreamSubscription? _watchCommandSubscription;
  bool _isSyncingFromWatch = false;
  String? _lastBandMatchId;
  int _lastBandRevision = -1;
  String _lastBandRallies = '';

  /// Named players of the band's current set (null = unnamed), straight
  /// from the band's state messages.
  final Rxn<Lineup> lineup = Rxn<Lineup>();

  /// Card label for a team when the set is named: "Hùng · Duyên". Null means
  /// use the team name.
  String? labelFor(String team) {
    final lu = lineup.value;
    if (lu == null) return null;
    return lu.pair(team).map(lu.shortOf).join(' · ');
  }

  /// Winner as shown on the win overlay: the pair's band names when the set
  /// is named ("Hùng · Quỳnh"), otherwise the team name.
  String winnerDisplay() {
    final lu = lineup.value;
    final w = gameState.winner;
    if (lu == null || (w != 'A' && w != 'B')) return gameState.winnerName;
    return lu.pair(w).map(lu.shortOf).join(' · ');
  }

  /// Winner as read aloud: the team plus both full names when the set is
  /// named — "Đội đỏ, Hùng Đại Ca và Như Quỳnh" (then "thắng 21 18").
  String _winnerSpoken() => _winnerSpokenFor(gameState.winner);

  String _winnerSpokenFor(String w) {
    final lu = lineup.value;
    if (lu == null || (w != 'A' && w != 'B')) return gameState.winnerName;
    final vi = _ttsService.currentLanguageRx.value.toLowerCase().startsWith('vi');
    final names = lu.pair(w).map(lu.fullOf).toList();
    if (vi) {
      return '${w == 'A' ? 'Đội đỏ' : 'Đội xanh'}, ${names[0]} và ${names[1]}';
    }
    return '${w == 'A' ? 'Red' : 'Blue'}: ${names[0]} and ${names[1]}';
  }

  /// Both winner lines of this lineup, rendered before the set can end.
  void _prepareVoiceClips(Lineup lu) {
    final clips = VoiceClipService.maybe;
    if (clips == null) return;
    final lang = _ttsService.currentLanguage;
    clips.prepareAll([
      ScoreAnnouncerService.winnerLine(_winnerSpokenFor('A'), lang),
      ScoreAnnouncerService.winnerLine(_winnerSpokenFor('B'), lang),
    ]);
  }
  DateTime? _lastBandSeen;

  /// The set the corner camera has been told about, and whether its end
  /// has been sent (docs/camera-recording-requirements.md §4).
  String? _camMatchId;
  bool _camEnded = false;
  Map<String, dynamic>? _camLast;
  Future<void> _dbChain = Future.value();

  /// The band app has spoken recently, so it is the scoreboard's authority:
  /// phone taps become commands, and saved history comes from band records.
  /// Without a recent band message the phone runs standalone as before.
  bool get _bandLive =>
      _lastBandSeen != null &&
      DateTime.now().difference(_lastBandSeen!) < const Duration(minutes: 15);

  Rx<GameState> get gameStateObservable => _gameState;
  TtsService get ttsService => _ttsService;
  WatchConnectivityService get watchService => _watchService;

  GameState get gameState => _gameState.value;
  int get teamAScore => gameState.teamAScore;
  int get teamBScore => gameState.teamBScore;
  bool get isGameActive => gameState.isGameActive;
  String get winner => gameState.winner;

  @override
  void onInit() {
    super.onInit();
    _loadSettings();
    CameraLinkService.maybe?.onResync = _cameraResync;
    BoardRecorder.maybe?.onStarted = _cameraResync;
    _ttsService.initialize().then((_) {
      _applyTeamNames(_ttsService.currentLanguage);
      // Custom hype lines rendered before they are needed, not on first play.
      SoundLibraryService.maybe?.warmTts();
    });
    // Team names are the colours, in the announcement language.
    _ttsService.currentLanguageRx.listen(_applyTeamNames);
    _scoreAnnouncer.initialize();
    _initializeWatchSync();
    _setupAudioChain();
    _musicService.initialize().then((_) => _applyMode(_audio.mode.value));
    // Switching mode takes effect immediately, from the phone or the watch.
    _audio.mode.listen(_applyMode);
  }

  /// Music mode runs a track continuously; commentary mode leaves the speaker
  /// free for the announcer and hype, with music only at tension and win.
  void _applyMode(String mode) {
    if (mode == PlayMode.music) {
      _musicService.startContinuous();
    } else {
      _musicService.stopMusic();
    }
    _watchService.sendSettingsState();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    autoResetDelay.value = prefs.getInt('auto_reset_delay') ?? 60;
    scoreAnnouncementsEnabled.value = prefs.getBool('score_announcements_enabled') ?? true;
    sidesSwapped.value = prefs.getBool('sides_swapped') ?? false;
  }

  Future<void> setSidesSwapped(bool swapped) async {
    sidesSwapped.value = swapped;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sides_swapped', swapped);
  }

  Future<void> toggleSidesSwapped() => setSidesSwapped(!sidesSwapped.value);

  Future<void> setAutoResetDelay(int seconds) async {
    autoResetDelay.value = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('auto_reset_delay', seconds);
  }

  Future<void> setScoreAnnouncementsEnabled(bool enabled) async {
    scoreAnnouncementsEnabled.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('score_announcements_enabled', enabled);
  }

  void _setupAudioChain() {
    // Score/undo/winner announcement done → hype voice. Two completion
    // sources converge:
    //   1. ScoreAnnouncerService finishes its MP3 chain (score/undo MP3 path)
    //   2. TtsService finishes (covers: winner — always TTS since team name
    //      is dynamic — and any score/undo fallback path)
    // Both wired to the same hype trigger so the chain stays consistent.
    // The sound check plays these sounds on its own: nothing chains off them.
    _scoreAnnouncer.onAnnouncementCompleted = () {
      if (SoundCheckService.active) return;
      _hypeController.playHype();
    };
    _ttsService.onSpeechCompleted = () {
      if (SoundCheckService.active) return;
      _hypeController.playHype();
    };

    // Hype done (or skipped) → win music OR resume/start tension music.
    // Tension music is started HERE (not during score update) so it never
    // competes with TTS or hype for AudioFocus.
    _hypeController.onPlaybackCompleted = () {
      // End of the talking chain (score -> hype): music back up.
      _musicService.unduck();
      if (SoundCheckService.active) return;
      if (isGameEnded.value) {
        _musicService.playWinMusic();
      } else if (_musicService.isTensionMode.value && !_musicService.isPlaying.value) {
        // Defensive: tension should keep playing under hype (no focus stealing
        // anymore), but resume it if it ended up paused for any other reason.
        _musicService.resume();
      } else {
        _checkTensionMusic();
      }
    };

    // When hype MP3 is missing, speak via TTS instead
    _hypeController.onTtsFallback = (String text) {
      _ttsService.speak(text);
    };
  }

  Future<void> _initializeWatchSync() async {
    try {
      await _watchService.initialize();
      _watchCommandSubscription = _watchService.watchCommandStream.listen((event) {
        _handleWatchCommand(event);
      });
      _watchConnectionPoll?.cancel();
      _watchConnectionPoll = Timer.periodic(const Duration(seconds: 5), (timer) async {
        isWatchConnected.value = await _watchService.isWatchConnected();
      });
    } catch (e) {
      print('⌚ [Controller] Watch sync init error: $e');
    }
  }

  void _handleWatchCommand(Map<String, dynamic> event) {
    if (event['type'] != 'command') return;

    final action = event['action'] as String;
    final int newScoreA = event['scoreA'] ?? -1;
    final int newScoreB = event['scoreB'] ?? -1;
    final bool isResetFromWatch = event['reset'] == true;
    // `silent` = sender already mutated its local state (e.g., watch index page).
    // When false (e.g., from settings page), phone MUST echo back so watch index can mirror.
    final bool silent = event['silent'] == true;
    final bool fromBand = event['source'] == 'band';
    final String? bandMatchId = event['matchId'] as String?;
    final int bandRevision = event['revision'] is num
        ? (event['revision'] as num).toInt() : -1;

    // Band history push: upsert by matchId, then ack so the band moves on to
    // the next unsynced record. Upserts are chained so two never race.
    if (action == 'match_record') {
      _lastBandSeen = DateTime.now();
      _storeBandRecord(event);
      // A set closed with End set reaches the board only as its record.
      if (event['status'] == 'stopped' && event['matchId'] == _camMatchId && !_camEnded) {
        _camEnded = true;
        _cameraSend('match_end', _camEndFields(event, 'stopped'));
      }
      // Backstop for a lost live state: the record of the set on court says
      // it is over, but the board has not ended it. Seen with a lineup on
      // board: the winning score_X (sent right after this record) was dropped
      // by the transport, so the phone never showed the win. Replayed as a
      // state; a state that did arrive has an equal revision and is a no-op.
      if (event['status'] == 'completed' &&
          event['matchId'] == _lastBandMatchId &&
          !isGameEnded.value) {
        print('⌚ [Controller] record says set won; live state missing -> applying');
        _handleWatchCommand({...event, 'action': 'record_state'});
      }
      return;
    }

    // Revisions only gate side effects (hype, voice). The score itself is
    // always mirrored: an explicit refresh carries the same revision as the
    // last message, and dropping it would leave a diverged phone diverged.
    bool isNewRev = true;
    if (fromBand) {
      _lastBandSeen = DateTime.now();
      // Every band state carries the version of the player list it holds.
      final pv = event['pv'];
      if (pv is num) PlayerService.maybe?.onBandVersion(pv.toInt());
      if (event['rallies'] != null) _lastBandRallies = event['rallies'].toString();
      final newLu = Lineup.fromBand(event['lu']);
      final changed = newLu?.red.join() != lineup.value?.red.join() ||
          newLu?.blue.join() != lineup.value?.blue.join();
      lineup.value = newLu;
      if (changed && newLu != null) _prepareVoiceClips(newLu);
      if (bandMatchId != null && bandRevision >= 0) {
        isNewRev = !(_lastBandMatchId == bandMatchId && bandRevision <= _lastBandRevision);
        _lastBandMatchId = bandMatchId;
        _lastBandRevision = bandRevision;
      }
      _cameraFromBand(event, action, isNewRev);
      // Band state says this set is open again (undo after a win): reopen it
      // here too, and drop any record already saved for it.
      if (event['status'] == 'active' && isGameEnded.value) {
        _autoResetTimer?.cancel();
        isGameEnded.value = false;
        _gameState.value = gameState.copyWith(isGameActive: true);
        if (bandMatchId != null) {
          _dbChain = _dbChain.then((_) => DatabaseService.deleteMatchById(bandMatchId));
        }
      }
    }

    print('⌚ [Controller] Command from watch: $action (Scores: $newScoreA-$newScoreB, silent=$silent)');

    // Flip which end of the phone screen each team is drawn on. Scores are
    // untouched, so there is nothing to sync back to the watch.
    if (action == 'phone_screen') {
      setPhoneBlank(event['blank'] == true);
      return;
    }

    if (action == 'swap_sides') {
      toggleSidesSwapped();
      return;
    }

    // Handle sync requests
    if (action == 'request_sync' || action == 'request_current_state') {
      _watchService.sendScoreCommand('request_current_state');
      return;
    }

    // Handle reset/next match
    if (action == 'reset' || action == 'next_match' || action == 'new_match') {
      // Echo of a reset the phone already applied optimistically.
      if (fromBand && gameState.teamAScore == 0 && gameState.teamBScore == 0 &&
          !isGameEnded.value) return;
      if (silent) _isSyncingFromWatch = true;
      resetGame();
      if (silent) _isSyncingFromWatch = false;
      return;
    }

    // Handle undo
    if (action == 'undo') {
      if (newScoreA >= 0 && newScoreB >= 0) {
        // Watch sends post-undo target scores — use them as source of truth.
        // Phone's undo stack is independent and may diverge from watch history;
        // using watch scores prevents the score mismatch / feedback loop.
        final int oldA = gameState.teamAScore;
        final int oldB = gameState.teamBScore;
        if (oldA == newScoreA && oldB == newScoreB) return; // duplicate guard

        final stack = List<GameState>.from(gameState.stateStack);
        if (stack.isNotEmpty) stack.removeLast(); // best-effort stack trim

        _gameState.value = gameState.copyWith(
          teamAScore: newScoreA,
          teamBScore: newScoreB,
          stateStack: stack,
        );
            _hypeController.handleUndo();
        // Undo is almost always an immediate misclick correction — announcing
        // "undo, X Y" out loud right before the real point is noisy and gets
        // talked over. Stay silent here; only the hype voice (if any) plays.
        _hypeController.playHype();
        // Do NOT send sync back — watch already applied undo locally (silent=true).
        // Sending phone's own stack result was the root cause of score corruption.
      } else {
        // No target scores provided — fall back to phone's own stack
        if (!gameState.canUndo) {
          _watchService.sendScoreUpdate(gameState, action: 'sync');
          return;
        }
        undo();
      }
      return;
    }

    // Handle score updates
    if (action == 'score_A' || action == 'score_B' || action == 'seed_score' ||
        action == 'band_online' || action == 'band_ready' ||
        action == 'band_reconnected' || action == 'state_reply' ||
        action == 'manual_state' || action == 'record_state') {
      if (newScoreA >= 0 && newScoreB >= 0) {
        final int oldA = gameState.teamAScore;
        final int oldB = gameState.teamBScore;
        final String? manualHype = event['manualHype'];
        
        // Duplicate-message guard. Also absorbs the band's echo of a point
        // the phone already applied optimistically — no second announcement.
        if (newScoreA == oldA && newScoreB == oldB && manualHype == null) return;

        // DEFENSIVE LOGIC: If watch sends a score that is lower than phone (and not a reset), 
        // it likely means the watch app just restarted and hasn't synced yet.
        // We catch this BEFORE the 'hasWinner' reset check to avoid accidental match resets.
        if (!fromBand && !isResetFromWatch && (newScoreA < oldA || newScoreB < oldB)) {
          print('⌚ [Controller] Rejected lower scores from watch. Forcing sync back.');
          _watchService.sendScoreCommand('request_current_state');
          return;
        }

        // If game ended, any score button from watch resets the game (if it's not a stale update from restart)
        if (!fromBand && gameState.hasWinner) {
          resetGame();
          return;
        }

        _isSyncingFromWatch = true;
        
        final currentStack = List<GameState>.from(gameState.stateStack);
        final snapshot = gameState.copyWith(stateStack: []);
        currentStack.add(snapshot);
        if (currentStack.length > 20) currentStack.removeAt(0);

        _gameState.value = gameState.copyWith(
          teamAScore: newScoreA,
          teamBScore: newScoreB,
          stateStack: currentStack,
          history: _appendHistory('Watch: $action${manualHype != null ? " ($manualHype)" : ""}'),
        );

        _isSyncingFromWatch = false;

        final bool isPoint = (action == 'score_A' || action == 'score_B') && isNewRev;
        // Scoring again on the band means the user is back on court.
        if (isPoint) setPhoneBlank(false);
        if (isPoint) {
          _hypeController.processScoreUpdate(oldA, oldB, newScoreA, newScoreB, manualHype: manualHype);
        }
        if (!gameState.hasWinner && isPoint) {
          _announceScoreChange(newScoreA, newScoreB, action == 'score_A' ? 'A' : 'B');
        }
        // _checkTensionMusic() moved to onPlaybackCompleted — avoids AudioFocus conflict
        _checkGameEnd(fromBand: fromBand);
      }
    }
  }

  // ── Corner camera ─────────────────────────────────────────────────────
  // Only queued here: the camera link never slows the band → board path.
  void _cameraSend(String type, Map<String, dynamic> fields) {
    CameraLinkService.maybe?.send(type, fields);
    BoardRecorder.maybe?.feed(type, fields);
  }

  Map<String, dynamic> _camEndFields(Map<String, dynamic> e, String status) => {
        'matchId': e['matchId'],
        'status': status,
        'scoreA': e['scoreA'],
        'scoreB': e['scoreB'],
        'startedAt': e['startedAt'],
        'endedAt': e['endedAt'],
        'rallies': e['rallies'],
        'ralT': e['ralT'],
        'lineup': e['lu'],
      };

  /// A camera started or reconnected mid-set: tell it the set again, as
  /// joined (its start is not in that file) and with the score so far.
  void _cameraResync() {
    final e = _camLast;
    if (e == null || _camMatchId == null || _camEnded) return;
    _cameraSend('match_start', {
      'matchId': _camMatchId,
      'bandStartedAt': e['startedAt'],
      'lineup': e['lu'],
      'joined': true,
      'scoreA': e['scoreA'],
      'scoreB': e['scoreB'],
    });
  }

  void _cameraFromBand(Map<String, dynamic> e, String action, bool isNewRev) {
    if (CameraLinkService.maybe == null && BoardRecorder.maybe == null) return;
    final id = e['matchId']?.toString();
    if (id == null || id.isEmpty) return;
    _camLast = e;
    final startedAt = (e['startedAt'] as num?)?.toInt() ?? 0;
    // A set begins when the band starts its clock (the start screen tap).
    if (id != _camMatchId && startedAt > 0) {
      _camMatchId = id;
      _camEnded = false;
      _cameraSend('match_start', {
        'matchId': id,
        'bandStartedAt': startedAt,
        'lineup': e['lu'],
        // Not the tap itself: the board (re)joined a set already running.
        'joined': !(action == 'match_start' || action == 'new_match'),
        'scoreA': e['scoreA'],
        'scoreB': e['scoreB'],
      });
    }
    if (id != _camMatchId) return;
    if (isNewRev && (action == 'score_A' || action == 'score_B')) {
      _cameraSend('point', {
        'matchId': id,
        'team': action == 'score_A' ? 'A' : 'B',
        'scoreA': e['scoreA'],
        'scoreB': e['scoreB'],
        'rev': e['revision'],
      });
    } else if (isNewRev && action == 'undo') {
      _cameraSend('undo', {'matchId': id, 'scoreA': e['scoreA'], 'scoreB': e['scoreB'], 'rev': e['revision']});
    }
    final status = e['status']?.toString() ?? 'active';
    if (status == 'completed' && !_camEnded) {
      _camEnded = true;
      _cameraSend('match_end', _camEndFields(e, 'completed'));
    } else if (status == 'active' && _camEnded) {
      _camEnded = false;
      _cameraSend('match_reopen', {'matchId': id});
    }
  }

  void _storeBandRecord(Map<String, dynamic> event) {
    final id = event['matchId'];
    final rev = event['revision'] is num ? (event['revision'] as num).toInt() : -1;
    _dbChain = _dbChain.then((_) async {
      try {
        await _persistBandTerminalMatch(event);
      } catch (e) {
        print('⌚ [Controller] band record save failed: $e');
        return; // no ack: the band retries on its next trigger
      }
      if (id is String) {
        _watchService.sendScoreCommand('match_ack', extra: {'matchId': id, 'revision': rev});
      }
    });
  }

  Future<void> _persistBandTerminalMatch(Map<String, dynamic> event) async {
    final id = event['matchId'];
    final status = event['status'];
    if (id is! String || (status != 'completed' && status != 'stopped')) return;
    final a = event['scoreA'] is num ? (event['scoreA'] as num).toInt() : teamAScore;
    final b = event['scoreB'] is num ? (event['scoreB'] as num).toInt() : teamBScore;
    final startMs = event['startedAt'] is num ? (event['startedAt'] as num).toInt() : DateTime.now().millisecondsSinceEpoch;
    final endMs = event['endedAt'] is num ? (event['endedAt'] as num).toInt() : DateTime.now().millisecondsSinceEpoch;
    final seeded = event['seededScoreA'] is num && (event['seededScoreA'] as num) >= 0;
    final rallies = event['rallies']?.toString() ?? '';
    final winner = status == 'completed' ? (a > b ? 'A' : 'B') : '';
    final lu = Lineup.fromBand(event['lu']);
    await DatabaseService.upsertMatch(Match(
      id: id,
      teamAName: lu == null ? gameState.teamAName : '${lu.fullOf(lu.red[0])} & ${lu.fullOf(lu.red[1])}',
      teamBName: lu == null ? gameState.teamBName : '${lu.fullOf(lu.blue[0])} & ${lu.fullOf(lu.blue[1])}',
      teamAScore: a,
      teamBScore: b,
      winner: winner,
      startTime: DateTime.fromMillisecondsSinceEpoch(startMs),
      endTime: DateTime.fromMillisecondsSinceEpoch(endMs),
      actionHistory: rallies.split('').where((x) => x == 'A' || x == 'B').toList(),
      durationSeconds: ((endMs - startMs) ~/ 1000).clamp(0, 1 << 31),
      status: status,
      durationEstimated: seeded,
      rallySequence: rallies,
      rallyTimes: event['ralT']?.toString() ?? '',
      redIds: lu?.red ?? const [],
      blueIds: lu?.blue ?? const [],
      playerNames: lu?.full ?? const {},
      playerShorts: lu?.short ?? const {},
      server0: lu?.srv ?? '',
      receiver0: lu?.rcv ?? '',
      lineupMode: lu?.mode ?? '',
    ));
  }

  void _announceScoreChange(int a, int b, String team) {
    // Music mode: nothing speaks over the track. Talking across a song that is
    // already playing is exactly what kills the mood, so the whole
    // announce-then-hype chain is skipped rather than merely quietened.
    if (_audio.isMusicMode) return;

    // Music steps aside for the whole chain; onPlaybackCompleted restores it.
    _musicService.duck();
    if (scoreAnnouncementsEnabled.value) {
      _scoreAnnouncer.announceScore(a, b, team);
    } else {
      // If score announcement is disabled, we must trigger hype manually
      // so the audio chain continues.
      _hypeController.playHype();
    }
  }

  /// A is red and B is blue everywhere, so that is what the teams are
  /// called: on an unnamed card, in history, and in "Đội đỏ thắng".
  void _applyTeamNames(String lang) {
    final vi = lang.toLowerCase().startsWith('vi');
    _gameState.value = gameState.copyWith(
      teamAName: vi ? 'Đội đỏ' : 'Red',
      teamBName: vi ? 'Đội xanh' : 'Blue',
    );
  }

  // Bound history to last 50 entries — list copy on every score otherwise grows O(n).
  List<String> _appendHistory(String entry) {
    const int maxHistory = 50;
    final h = gameState.history;
    if (h.length < maxHistory) return [...h, entry];
    return [...h.sublist(h.length - maxHistory + 1), entry];
  }

  void _pushStateToStack() {
    final currentStack = List<GameState>.from(gameState.stateStack);
    final snapshot = gameState.copyWith(stateStack: []);
    currentStack.add(snapshot);
    if (currentStack.length > 20) currentStack.removeAt(0);
    _gameState.value = gameState.copyWith(stateStack: currentStack);
  }

  void incrementTeamA() {
    if (!gameState.isGameActive) return;
    final int oldA = gameState.teamAScore;
    final int oldB = gameState.teamBScore;
    _pushStateToStack();
    _gameState.value = gameState.copyWith(
      teamAScore: gameState.teamAScore + 1,
      history: _appendHistory('${gameState.teamAName} scored'),
    );
    // Applied here at once and sent to the band as a command. The band's
    // resulting state overrides this when it arrives, so a lost command
    // snaps back instead of drifting — and if band->phone is the broken
    // direction, the phone board still moves.
    if (!_isSyncingFromWatch) {
      _watchService.sendScoreCommand('point_A');
    }

    _hypeController.processScoreUpdate(oldA, oldB, gameState.teamAScore, gameState.teamBScore);
    if (_bandLive) _lastBandRallies += 'A';
    if (!gameState.hasWinner) {
      _announceScoreChange(gameState.teamAScore, gameState.teamBScore, 'A');
    }
    _checkGameEnd();
  }

  void incrementTeamB() {
    if (!gameState.isGameActive) return;
    final int oldA = gameState.teamAScore;
    final int oldB = gameState.teamBScore;
    _pushStateToStack();
    _gameState.value = gameState.copyWith(
      teamBScore: gameState.teamBScore + 1,
      history: _appendHistory('${gameState.teamBName} scored'),
    );
    // Applied here at once and sent to the band as a command. The band's
    // resulting state overrides this when it arrives, so a lost command
    // snaps back instead of drifting — and if band->phone is the broken
    // direction, the phone board still moves.
    if (!_isSyncingFromWatch) {
      _watchService.sendScoreCommand('point_B');
    }

    _hypeController.processScoreUpdate(oldA, oldB, gameState.teamAScore, gameState.teamBScore);
    if (_bandLive) _lastBandRallies += 'B';
    if (!gameState.hasWinner) {
      _announceScoreChange(gameState.teamAScore, gameState.teamBScore, 'B');
    }
    _checkGameEnd();
  }

  void _checkTensionMusic() {
    final threshold = _musicService.tensionThreshold.value;
    if (gameState.teamAScore >= threshold &&
        gameState.teamBScore >= threshold &&
        !_musicService.isPlaying.value) {
      _musicService.playTensionMusic();
    }
  }

  /// With the band live, -1 is only allowed as an undo of that team's last
  /// rally — anything else would break the band's rally log.
  bool _bandMinus(String team) {
    if (!_bandLive) return false;
    if (_lastBandRallies.isNotEmpty &&
        _lastBandRallies[_lastBandRallies.length - 1] == team) {
      undo();
    } else {
      print('⌚ [Controller] -1 $team refused: last rally is not $team');
    }
    return true;
  }

  void decrementTeamA() {
    if (_bandMinus('A')) return;
    if (gameState.teamAScore > 0) {
      _pushStateToStack();
      _gameState.value = gameState.copyWith(teamAScore: gameState.teamAScore - 1);
    }
  }

  void decrementTeamB() {
    if (_bandMinus('B')) return;
    if (gameState.teamBScore > 0) {
      _pushStateToStack();
      _gameState.value = gameState.copyWith(teamBScore: gameState.teamBScore - 1);
    }
  }

  void undo() {
    if (!_isSyncingFromWatch) _watchService.sendScoreCommand('undo');
    if (_bandLive && _lastBandRallies.isNotEmpty) {
      _lastBandRallies = _lastBandRallies.substring(0, _lastBandRallies.length - 1);
    }
    if (!gameState.canUndo) return;
    final stack = List<GameState>.from(gameState.stateStack);
    final previousState = stack.removeLast();
    _gameState.value = previousState.copyWith(stateStack: stack);
    _hypeController.handleUndo();
    // Undo is almost always an immediate misclick correction — stay silent
    // instead of announcing "undo, X Y" (see matching comment above).
    _hypeController.playHype();
  }

  void _checkGameEnd({bool fromBand = false}) {
    if (gameState.hasWinner) {
      _gameState.value = gameState.copyWith(isGameActive: false);
      isGameEnded.value = true;
      // With the band live, the band's own record (pushed with an ack) is
      // the one that gets saved; saving here too would duplicate it.
      if (!fromBand && !_bandLive) _saveMatchToDatabase();
      _musicService.stopMusic(fadeOut: true);
      
      if (scoreAnnouncementsEnabled.value) {
        _scoreAnnouncer.announceWinner(_winnerSpoken(), gameState.teamAScore, gameState.teamBScore);
      } else {
        _hypeController.playHype();
      }
      
      _watchService.sendWinnerUpdate(gameState.winner, gameState.teamAScore, gameState.teamBScore);
      _autoResetTimer?.cancel();
      // Never auto-reset while the band is live: it would start a new match
      // on the band before the user had a chance to undo the winning point.
      if (!_bandLive) {
        _autoResetTimer = Timer(Duration(seconds: autoResetDelay.value), () {
          if (isGameEnded.value) resetGame();
        });
      }
    }
  }

  Future<void> _saveMatchToDatabase() async {
    try {
      final endTime = DateTime.now();
      final startTime = gameState.startTime ?? endTime;
      final match = Match(
        id: _uuid.v4(),
        teamAName: gameState.teamAName,
        teamBName: gameState.teamBName,
        teamAScore: gameState.teamAScore,
        teamBScore: gameState.teamBScore,
        winner: gameState.winner,
        startTime: startTime,
        endTime: endTime,
        actionHistory: gameState.history,
        durationSeconds: endTime.difference(startTime).inSeconds,
      );
      await DatabaseService.saveMatch(match);
    } catch (e) {}
  }

  void resetGame() {
    final oldState = gameState;
    final teamAName = oldState.teamAName;
    final teamBName = oldState.teamBName;
    
    final newStack = List<GameState>.from(oldState.stateStack);
    newStack.add(oldState.copyWith(stateStack: []));
    if (newStack.length > 20) newStack.removeAt(0);

    _gameState.value = GameState(
      teamAName: teamAName,
      teamBName: teamBName,
      startTime: DateTime.now(),
      stateStack: newStack,
    );
    
    isGameEnded.value = false;
    _autoResetTimer?.cancel();
    _hypeController.resetState();
    _musicService.stopMusic(fadeOut: true);
    _hypeController.playStartOfMatchHype();
    if (!_isSyncingFromWatch) {
      _watchService.sendScoreCommand('new_match');
    }
  }

  void startNewGame() => resetGame();

  Future<void> changeLanguage(String languageCode) async {
    await _ttsService.setLanguage(languageCode);
  }

  @override
  void onClose() {
    _autoResetTimer?.cancel();
    _watchConnectionPoll?.cancel();
    _watchCommandSubscription?.cancel();
    _ttsService.dispose();
    _watchService.dispose();
    super.onClose();
  }
}
