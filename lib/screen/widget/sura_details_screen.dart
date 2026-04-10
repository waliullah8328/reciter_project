import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reciter_project/screen/widget/settings_bottom_sheet.dart';
import 'package:reciter_project/screen/widget/weekly_report_screen.dart';

import '../../common/custom_text.dart';
import '../../model/settings_view_model.dart';
import '../../model/user_reciter_model.dart';

final playbackSpeedProvider = StateProvider<double>((ref) => 0.5);

/// ================= BOOKMARK MODEL =================
class Bookmark {
  final int suraId;
  final int ayahId;
  final String arabicText;
  final String englishText;

  Bookmark({
    required this.suraId,
    required this.ayahId,
    required this.arabicText,
    required this.englishText,
  });

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    suraId: json['sura_id'],
    ayahId: json['ayah_id'],
    arabicText: json['arabic_text'] ?? '',
    englishText: json['english_text'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'sura_id': suraId,
    'ayah_id': ayahId,
    'arabic_text': arabicText,
    'english_text': englishText,
  };
}

/// ================= AYAH SELECTION HELPER =================
class AyahSelector {
  /// Select ayah index by time range (for audio sync) - WITH TOLERANCE
  static int? findByTime(
      List<Ayah> ayahs,
      double currentTime,
      int reciterIndex,
      double audioDuration,
      ) {
    const tolerance = 0.15; // 150ms tolerance for floating point precision

    for (int i = 0; i < ayahs.length; i++) {
      final ayah = ayahs[i];

      if (ayah.timings.length <= reciterIndex ||
          ayah.timings[reciterIndex].length < 1)
        continue;

      final start = ayah.timings[reciterIndex][0];
      final end = ayah.timings[reciterIndex].length > 1
          ? ayah.timings[reciterIndex][1]
          : (i == ayahs.length - 1 ? audioDuration : null);

      if (end != null) {
        if (currentTime >= start - tolerance &&
            currentTime <= end + tolerance) {
          return i;
        }
      } else {
        if (currentTime >= start - tolerance) {
          return i;
        }
      }
    }

    // Fallback: nearest start time with tolerance
    int? nearestIndex;
    double minDiff = double.infinity;
    for (int i = 0; i < ayahs.length; i++) {
      final ayah = ayahs[i];
      if (ayah.timings.length <= reciterIndex ||
          ayah.timings[reciterIndex].isEmpty)
        continue;
      final start = ayah.timings[reciterIndex][0];
      final diff = (currentTime - start).abs();
      if (diff < minDiff && currentTime >= start - 0.5) {
        minDiff = diff;
        nearestIndex = i;
      }
    }
    return nearestIndex;
  }

  static int? findById(List<Ayah> ayahs, int targetAyahNumber) {
    return ayahs.indexWhere((ayah) => ayah.ayah == targetAyahNumber);
  }

  static double? getStartTime(Ayah ayah, int reciterIndex) {
    if (ayah.timings.length <= reciterIndex ||
        ayah.timings[reciterIndex].isEmpty)
      return null;
    return ayah.timings[reciterIndex][0];
  }

  static double? getEndTime(Ayah ayah, int reciterIndex) {
    if (ayah.timings.length <= reciterIndex ||
        ayah.timings[reciterIndex].length < 2)
      return null;
    return ayah.timings[reciterIndex][1];
  }
}

/// ================= RIVERPOD PROVIDERS =================

final audioPlayerProvider = Provider<AudioPlayer>((ref) {
  final player = AudioPlayer();
  ref.onDispose(() => player.dispose());
  return player;
});

final dailyProgressProvider =
StateNotifierProvider<DailyProgressNotifier, DailyProgressState>(
      (ref) => DailyProgressNotifier(),
);

final bookmarksProvider =
StateNotifierProvider<BookmarksNotifier, List<Bookmark>>(
      (ref) => BookmarksNotifier(),
);

final highlightedAyahProvider = StateProvider<int>((ref) => -1);

final bottomPlayerProvider =
StateNotifierProvider<BottomPlayerNotifier, BottomPlayerState>(
      (ref) => BottomPlayerNotifier(),
);

final currentReciterProvider = StateProvider<String?>((ref) => null);

final playingStreamProvider = StreamProvider<bool>((ref) {
  final player = ref.watch(audioPlayerProvider);
  return player.playingStream;
});

/// ================= STATE MODELS =================

class DailyProgressState {
  final int goalMinutes;
  final int listenedSeconds;
  DailyProgressState({
    required this.goalMinutes,
    required this.listenedSeconds,
  });
  DailyProgressState copyWith({int? goalMinutes, int? listenedSeconds}) {
    return DailyProgressState(
      goalMinutes: goalMinutes ?? this.goalMinutes,
      listenedSeconds: listenedSeconds ?? this.listenedSeconds,
    );
  }
}

class DailyProgressNotifier extends StateNotifier<DailyProgressState> {
  DailyProgressNotifier()
      : super(DailyProgressState(goalMinutes: 5, listenedSeconds: 0)) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final todayStr = "${today.year}-${today.month}-${today.day}";
    final savedDate = prefs.getString('date') ?? '';
    if (savedDate != todayStr) {
      await prefs.setString('date', todayStr);
      await prefs.setInt(todayStr, 0);
    }
    state = DailyProgressState(
      goalMinutes: prefs.getInt('goal') ?? 5,
      listenedSeconds: prefs.getInt(todayStr) ?? 0,
    );
  }

  Future<void> incrementListening() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final todayStr = "${today.year}-${today.month}-${today.day}";
    state = state.copyWith(listenedSeconds: state.listenedSeconds + 1);
    await prefs.setInt(todayStr, state.listenedSeconds);
  }
}

class BookmarksNotifier extends StateNotifier<List<Bookmark>> {
  BookmarksNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final bookmarksJson = prefs.getStringList('bookmarks') ?? [];
    state = bookmarksJson
        .map((e) => Bookmark.fromJson(json.decode(e)))
        .toList();
  }

  Future<void> toggle(
      int suraId,
      int ayahId,
      String arabicText,
      String englishText,
      ) async {
    final prefs = await SharedPreferences.getInstance();
    final bookmark = Bookmark(
      suraId: suraId,
      ayahId: ayahId,
      arabicText: arabicText,
      englishText: englishText,
    );
    final newList = List<Bookmark>.from(state);
    final index = newList.indexWhere(
          (b) => b.suraId == suraId && b.ayahId == ayahId,
    );
    if (index != -1) {
      newList.removeAt(index);
    } else {
      newList.add(bookmark);
    }
    state = newList;
    await prefs.setStringList(
      'bookmarks',
      newList.map((b) => json.encode(b.toJson())).toList(),
    );
  }

  bool isBookmarked(int suraId, int ayahId) {
    return state.any((b) => b.suraId == suraId && b.ayahId == ayahId);
  }

  Future<void> navigateToBookmark(
      BuildContext context,
      Bookmark bookmark,
      List<Surah> allSurahs,
      Function(Surah, int) onSurahLoaded,
      ) async {
    final surahIndex = allSurahs.indexWhere((s) => s.id == bookmark.suraId);
    if (surahIndex == -1) return;
    final surah = allSurahs[surahIndex];
    final ayahIndex = AyahSelector.findById(surah.ayahs, bookmark.ayahId);
    if (ayahIndex == -1) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SurahDetailScreen(
          surah: surah,
          allSurahs: allSurahs,
          surahIndex: surahIndex,
        ),
      ),
    );
    await Future.delayed(const Duration(milliseconds: 500));
    onSurahLoaded(surah, ayahIndex!);
  }
}

class BottomPlayerState {
  final bool visible;
  final String? reciterName;
  BottomPlayerState({required this.visible, this.reciterName});
}

class BottomPlayerNotifier extends StateNotifier<BottomPlayerState> {
  BottomPlayerNotifier()
      : super(BottomPlayerState(visible: false, reciterName: null));
  void show(String reciterName) =>
      state = BottomPlayerState(visible: true, reciterName: reciterName);
  void hide() => state = BottomPlayerState(visible: false, reciterName: null);
  void setReciter(String reciterName) =>
      state = BottomPlayerState(visible: true, reciterName: reciterName);
}

/// ================= SURAH DETAIL SCREEN =================

class SurahDetailScreen extends ConsumerStatefulWidget {
  final Surah surah;
  final List<Surah> allSurahs;
  final int surahIndex;

  const SurahDetailScreen({
    super.key,
    required this.surah,
    required this.allSurahs,
    required this.surahIndex,
  });

  @override
  ConsumerState<SurahDetailScreen> createState() => _SurahDetailScreenState();
}

class _SurahDetailScreenState extends ConsumerState<SurahDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  int? _lastScrolledIndex;

  StreamSubscription<Duration>? _positionStreamSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  // 🔥 FIX: _playingStreamSubscription REMOVED — resume-এ wrong re-evaluation বন্ধ করতে

  int _lastIncrementedSecond = -1;
  bool _localIsPlaying = false;
  double _audioDuration = 0;
  int? _currentSurahId;

  bool _isProcessingPosition = false;

  final List<String> reciterNames = [
    "Abdulbasit Abdulsamad",
    "Abdullah Al-Johany",
    "Ibrahim Al-Akdar",
    "Ali Hajjaj Alsouasi",
  ];

  /// ================= RESET STATE FOR NEW SURAH =================
  void _resetSurahState() {
    _positionStreamSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _lastIncrementedSecond = -1;
    _audioDuration = 0;
    _lastScrolledIndex = null;
    _isProcessingPosition = false;
    ref.read(highlightedAyahProvider.notifier).state = -1;

    final player = ref.read(audioPlayerProvider);
    player.stop();
    player.seek(Duration.zero);

    ref.read(bottomPlayerProvider.notifier).hide();
    print('Surah state reset for new surah: ${widget.surah.id}');
  }

  /// ================= AUTO-PLAY NEXT SURAH =================
  Future<void> _autoPlayNextSurah() async {
    try {
      if (widget.surahIndex < widget.allSurahs.length - 1) {
        final nextSurah = widget.allSurahs[widget.surahIndex + 1];
        final reciterUrl = ref.read(currentReciterProvider);
        if (reciterUrl != null) {
          final file = await _getLocalFile(reciterUrl);
          if (await file.exists()) {
            print('Auto-playing next surah: ${nextSurah.name}');
            _resetSurahState();
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => SurahDetailScreen(
                  surah: nextSurah,
                  allSurahs: widget.allSurahs,
                  surahIndex: widget.surahIndex + 1,
                ),
              ),
            );
            await Future.delayed(const Duration(milliseconds: 500));
          } else {
            print('Next surah audio not downloaded');
          }
        }
      } else {
        print('No more surahs to play');
      }
    } catch (e) {
      print('Error auto-playing next surah: $e');
    }
  }

  /// ================= FILE HANDLING =================
  Future<File> _getLocalFile(String url) async {
    final dir = await getApplicationDocumentsDirectory();
    final bytes = utf8.encode(url);
    final filename = "${sha1.convert(bytes)}.mp3";
    return File('${dir.path}/$filename');
  }

  Future<Map<String, bool>> _checkDownloadedStatus() async {
    final map = <String, bool>{};
    for (String url in widget.surah.audioUrls) {
      final file = await _getLocalFile(url);
      map[url] = await file.exists();
    }
    return map;
  }

  Future<void> _downloadAndPlay(String url, String reciterName) async {
    final file = await _getLocalFile(url);
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Downloading...')));
      await Dio().download(url, file.path);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Downloaded $reciterName')));
      _playAudio(file.path, url);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Download failed')));
    }
  }

  /// ================= AYAH TAP HANDLER =================
  void onAyahTap(int index) async {
    final player = ref.read(audioPlayerProvider);
    final reciterUrl = ref.read(currentReciterProvider);
    if (reciterUrl == null) return;
    final reciterIndex = widget.surah.audioUrls.indexOf(reciterUrl);
    if (reciterIndex == -1) return;
    final ayah = widget.surah.ayahs[index];
    final startTime = AyahSelector.getStartTime(ayah, reciterIndex);
    if (startTime == null) return;

    final wasPlaying = player.playing;
    await player.seek(Duration(milliseconds: (startTime * 1000).toInt()));

    // Immediately update highlight when tapping
    ref.read(highlightedAyahProvider.notifier).state = index;
    _scrollToCurrentAyah(index);

    if (wasPlaying) {
      await player.play();
    }
  }

  /// ================= PLAY AUDIO FROM SPECIFIC AYAH =================
  Future<void> _playAudioFromAyah(
      String path,
      String reciterUrl,
      int startingAyahIndex,
      ) async {
    try {
      await _positionStreamSubscription?.cancel();
      await _playerStateSubscription?.cancel();

      _lastIncrementedSecond = -1;
      _audioDuration = 0;
      _isProcessingPosition = false;

      final player = ref.read(audioPlayerProvider);
      try {
        if (player.playing) await player.stop();
      } catch (e) {
        print('Error stopping player: $e');
      }

      final reciterIndex = widget.surah.audioUrls.indexOf(reciterUrl);
      if (reciterIndex == -1) return;

      final playbackSpeed = ref.read(playbackSpeedProvider);
      await player.setSpeed(playbackSpeed);

      // Highlight starting ayah immediately
      ref.read(highlightedAyahProvider.notifier).state = startingAyahIndex;
      _scrollToCurrentAyah(startingAyahIndex);
      ref.read(bottomPlayerProvider.notifier).show(reciterNames[reciterIndex]);
      ref.read(currentReciterProvider.notifier).state = reciterUrl;

      final file = File(path);
      if (!await file.exists()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Audio file not found')));
        return;
      }

      await player.setFilePath(path);

      final duration = await player.duration;
      if (duration != null) _audioDuration = duration.inMilliseconds / 1000.0;

      final startingAyah = widget.surah.ayahs[startingAyahIndex];
      final startTime = AyahSelector.getStartTime(startingAyah, reciterIndex);
      if (startTime != null) {
        await player.seek(Duration(milliseconds: (startTime * 1000).toInt()));
      }

      await player.play();
      print(
        'Audio playback started from ayah $startingAyahIndex at ${playbackSpeed}x speed',
      );

      // Listen to player state changes (completion detection)
      _playerStateSubscription = player.playerStateStream.listen((playerState) {
        if (playerState.processingState == ProcessingState.completed) {
          print('Current surah audio finished, auto-playing next...');
          _autoPlayNextSurah();
        }
      });

      // 🔥 FIX: positionStream-এ শুধু player.playing == true হলেই ayah index change হবে
      _positionStreamSubscription = player.positionStream.listen((
          position,
          ) async {
        if (_isProcessingPosition) return;
        _isProcessingPosition = true;

        try {
          // 🔥 KEY FIX 1: Pause state-এ ayah index change হবে না
          if (!player.playing) return;

          final time = position.inMilliseconds / 1000.0;
          final currentSecond = time.floor();

          final currentReciterUrl = ref.read(currentReciterProvider);
          if (currentReciterUrl == null) return;
          final currentReciterIndex = widget.surah.audioUrls.indexOf(
            currentReciterUrl,
          );
          if (currentReciterIndex == -1) return;

          // Find matching ayah using helper with tolerance
          final matchedIndex = AyahSelector.findByTime(
            widget.surah.ayahs,
            time,
            currentReciterIndex,
            _audioDuration,
          );

          // 🔥 KEY FIX 2: শুধু playing state-এ highlight update হবে
          final currentHighlight = ref.read(highlightedAyahProvider);
          if (matchedIndex != null && currentHighlight != matchedIndex) {
            ref.read(highlightedAyahProvider.notifier).state = matchedIndex;
            _scrollToCurrentAyah(matchedIndex);
            print(
              'Auto-highlighted ayah $matchedIndex at ${time.toStringAsFixed(2)}s',
            );
          }

          // Track listening progress (once per second, only when playing)
          if (currentSecond != _lastIncrementedSecond) {
            _lastIncrementedSecond = currentSecond;
            await ref.read(dailyProgressProvider.notifier).incrementListening();
          }
        } finally {
          await Future.delayed(const Duration(milliseconds: 50));
          _isProcessingPosition = false;
        }
      });
    } catch (e) {
      print('Error in _playAudioFromAyah: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Playback error: $e')));
    }
  }

  void _playAudio(
      String path, [
        String? reciterUrl,
        int? startingAyahIndex,
      ]) async {
    final startIndex = startingAyahIndex ?? 0;
    if (reciterUrl != null) {
      await _playAudioFromAyah(path, reciterUrl, startIndex);
    }
  }

  void _scrollToCurrentAyah(int index) {
    if (_lastScrolledIndex == index) return;
    _lastScrolledIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final key = _itemKeys[index];
        if (key == null) return;
        final context = key.currentContext;
        if (context != null && context.mounted) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.35,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      } catch (e) {
        print('Scroll error: $e');
      }
    });
  }

  Future<void> navigateToAyahById(int targetAyahId) async {
    final ayahIndex = AyahSelector.findById(widget.surah.ayahs, targetAyahId);
    if (ayahIndex != -1) {
      ref.read(highlightedAyahProvider.notifier).state = ayahIndex!;
      _scrollToCurrentAyah(ayahIndex!);
      final player = ref.read(audioPlayerProvider);
      final reciterUrl = ref.read(currentReciterProvider);
      if (reciterUrl != null) {
        final ayah = widget.surah.ayahs[ayahIndex];
        final reciterIndex = widget.surah.audioUrls.indexOf(reciterUrl);
        final startTime = AyahSelector.getStartTime(ayah, reciterIndex);
        if (startTime != null) {
          await player.seek(Duration(milliseconds: (startTime * 1000).toInt()));
        }
      }
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _currentSurahId = widget.surah.id;
    if (widget.surah.audioUrls.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final savedReciterUrl = prefs.getString('saved_reciter');
          final firstUrl = savedReciterUrl ?? widget.surah.audioUrls.first;
          if (!widget.surah.audioUrls.contains(firstUrl)) {
            ref.read(currentReciterProvider.notifier).state =
                widget.surah.audioUrls.first;
          } else {
            ref.read(currentReciterProvider.notifier).state = firstUrl;
          }
        } catch (e) {
          print('Error in initState: $e');
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant SurahDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.surah.id != widget.surah.id) {
      print('Surah changed from ${oldWidget.surah.id} to ${widget.surah.id}');
      _currentSurahId = widget.surah.id;
      _resetSurahState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dailyProgress = ref.watch(dailyProgressProvider);
    final highlightedIndex = ref.watch(highlightedAyahProvider);
    final bookmarks = ref.watch(bookmarksProvider);
    final bottomPlayer = ref.watch(bottomPlayerProvider);
    final playbackSpeed = ref.watch(playbackSpeedProvider);
    final selectedTheme = ref.watch(
      settingsProvider.select((s) => s.selectedTheme),
    );

    final goalSeconds = dailyProgress.goalMinutes * 60;
    final progress = (dailyProgress.listenedSeconds / goalSeconds).clamp(
      0.0,
      1.0,
    );

    return Scaffold(
      backgroundColor: selectedTheme == 0
          ? Colors.white
          : selectedTheme == 1
          ? Color(0xffF5F1E8)
          : Color(0xff101828),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(
              selectedTheme == 0
                  ? "assets/image/white_quran_back_ground.png"
                  : selectedTheme == 1
                  ? "assets/image/paper_theme.png"
                  : "assets/image/black_theme.png",
            ),
            fit: BoxFit.fitHeight,
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                /// 🔹 HEADER
                Padding(
                  padding: EdgeInsets.only(left: 10, right: 16, top: 30),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Icon(
                          Icons.arrow_back,
                          color: selectedTheme == 0
                              ? Colors.black
                              : selectedTheme == 1
                              ? Colors.black
                              : Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.surah.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: selectedTheme == 0
                                ? Colors.black
                                : selectedTheme == 1
                                ? Colors.black
                                : Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.settings,
                          color: selectedTheme == 0
                              ? Colors.black
                              : selectedTheme == 1
                              ? Colors.black
                              : Colors.white,
                        ),
                        onPressed: () async {
                          showSettingsBottomSheet(
                            context,
                            audioUrls: widget.surah.audioUrls,
                            reciterNames: reciterNames,
                            downloadAndPlay: _downloadAndPlay,
                            getLocalFile: _getLocalFile,
                            playAudio: _playAudio,
                          );
                        },
                      ),
                    ],
                  ),
                ),

                /// 🔹 PROGRESS
                Padding(
                  padding: EdgeInsets.only(left: 12, right: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        "Reading Goal: ${(dailyProgress.listenedSeconds / 60).floor()} / ${dailyProgress.goalMinutes} min",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: selectedTheme == 0
                              ? Colors.black
                              : selectedTheme == 1
                              ? Colors.black
                              : Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 4,
                          backgroundColor: selectedTheme == 0
                              ? Colors.grey.withOpacity(0.25)
                              : Colors.white,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF00BCDD),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const WeeklyReportScreen(),
                            ),
                          );
                        },
                        child: Icon(Icons.arrow_forward_ios_rounded, size: 16),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 48),
                Text(
                  widget.surah.arName,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 32),

                /// 🔹 LIST
                SizedBox(
                  height: 580,
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    controller: _scrollController,
                    itemCount: widget.surah.ayahs.length,
                    key: Key('ayah_list_${widget.surah.id}'),
                    itemBuilder: (context, index) {
                      final ayah = widget.surah.ayahs[index];
                      _itemKeys[index] = _itemKeys[index] ?? GlobalKey();
                      final isHighlighted = highlightedIndex == index;
                      final id = ayah.ayah;

                      return Padding(
                        padding: EdgeInsets.only(left: 20, right: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(left: 20),
                                  child: Row(
                                    children: [
                                      CustomText(
                                        text: "Aya 1 : ${index + 1}",
                                        color: selectedTheme == 0
                                            ? Color(0xff364153)
                                            : selectedTheme == 1
                                            ? Color(0xff364153)
                                            : Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 18,
                                        color: selectedTheme == 0
                                            ? Color(0xff364153)
                                            : selectedTheme == 1
                                            ? Color(0xff364153)
                                            : Colors.white,
                                      ),
                                    ],
                                  ),
                                ),
                                if (bookmarks.any(
                                      (b) =>
                                  b.suraId == widget.surah.id &&
                                      b.ayahId == ayah.ayah,
                                ))
                                  Padding(
                                    padding: EdgeInsets.only(right: 20),
                                    child: const Icon(
                                      Icons.bookmark,
                                      color: Colors.orange,
                                    ),
                                  ),
                              ],
                            ),
                            SizedBox(height: 10),
                            GestureDetector(
                              onTap: () async {
                                await showModalBottomSheet(
                                  context: context,
                                  builder: (_) => _ayahBottomSheet(index, ayah),
                                );
                              },
                              child: Container(
                                width: double.infinity,
                                key: _itemKeys[index],
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 6,
                                ),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isHighlighted
                                      ? Color(0xffC8E6C9)
                                      : selectedTheme == 0
                                      ? Colors.white
                                      : selectedTheme == 1
                                      ? Color(0xffF5F1E8)
                                      : Color(0xff101828),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isHighlighted
                                        ? Color(0xffC8E6C9)
                                        : selectedTheme == 0
                                        ? Colors.white
                                        : selectedTheme == 1
                                        ? Color(0xffF5F1E8)
                                        : Color(0xff101828),
                                    width: isHighlighted ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Stack(
                                      children: [
                                        SizedBox(
                                          height: 35,
                                          width: 35,
                                          child: SvgPicture.asset(
                                            "assets/icon/sura_icon_1.svg",
                                            colorFilter: ColorFilter.mode(
                                              Color(0xff2F7D33),
                                              BlendMode.srcIn,
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          left: id < 10
                                              ? 14
                                              : id < 100
                                              ? 11.5
                                              : 10,
                                          top: id < 100 ? 8 : 10,
                                          child: CustomText(
                                            text: toArabicNumber(id),
                                            fontSize: id < 10
                                                ? 14
                                                : id < 100
                                                ? 12
                                                : 10,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xff2F7D33),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    CustomText(
                                      text: ayah.arabic,
                                      fontWeight: isHighlighted
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontSize: isHighlighted ? 26 : 24,
                                      textAlign: TextAlign.end,
                                      color: isHighlighted
                                          ? Color(0xff101828)
                                          : selectedTheme == 0
                                          ? Color(0xff364153)
                                          : selectedTheme == 1
                                          ? Color(0xff364153)
                                          : Colors.white,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),

            /// 🔻 Bottom Player
            if (bottomPlayer.visible)
              Positioned(
                bottom: 50,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9CFB5),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      /// ▶️ Play / Pause Button
                      Consumer(
                        builder: (context, ref, _) {
                          final playingAsync = ref.watch(playingStreamProvider);
                          final isPlaying = playingAsync.when(
                            data: (p) => p,
                            loading: () => false,
                            error: (_, __) => false,
                          );

                          return Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF2F3A4A),
                            ),
                            child: IconButton(
                              onPressed: () async {
                                final player = ref.read(audioPlayerProvider);

                                if (isPlaying) {
                                  await player.pause();
                                } else {
                                  // 🔥 FIX 3: Resume-এ speed set করি, কিন্তু
                                  // _reevaluateCurrentAyah CALL করি না।
                                  // positionStream নিজেই সঠিক ayah detect করবে
                                  // যখন player.playing == true হবে।
                                  final speed = ref.read(playbackSpeedProvider);
                                  await player.setSpeed(speed);
                                  await player.play();
                                }
                              },
                              icon: Icon(
                                isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(width: 12),

                      /// 🎵 Reciter Name
                      Expanded(
                        child: Text(
                          bottomPlayer.reciterName ?? "Saad Al-Hamdi",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Color(0xFF2F3A4A),
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      /// ➖ Decrease Speed
                      Consumer(
                        builder: (context, ref, _) {
                          final speed = ref.watch(playbackSpeedProvider);

                          return IconButton(
                            onPressed: () async {
                              final player = ref.read(audioPlayerProvider);
                              final newSpeed = (speed - 0.5).clamp(0.5, 3.0);
                              ref.read(playbackSpeedProvider.notifier).state =
                                  newSpeed;
                              await player.setSpeed(newSpeed);
                            },
                            icon: const Icon(
                              Icons.skip_previous,
                              color: Color(0xFF2F3A4A),
                            ),
                          );
                        },
                      ),

                      /// ⚡ Speed Display
                      Consumer(
                        builder: (context, ref, _) {
                          final speed = ref.watch(playbackSpeedProvider);

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              "${speed.toStringAsFixed(1)}x",
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                                color: Color(0xFF2F3A4A),
                              ),
                            ),
                          );
                        },
                      ),

                      /// ➕ Increase Speed
                      Consumer(
                        builder: (context, ref, _) {
                          final speed = ref.watch(playbackSpeedProvider);

                          return IconButton(
                            onPressed: () async {
                              final player = ref.read(audioPlayerProvider);
                              final newSpeed = (speed + 0.5).clamp(0.5, 3.0);
                              ref.read(playbackSpeedProvider.notifier).state =
                                  newSpeed;
                              await player.setSpeed(newSpeed);
                            },
                            icon: const Icon(
                              Icons.skip_next,
                              color: Color(0xFF2F3A4A),
                            ),
                          );
                        },
                      ),

                      const SizedBox(width: 6),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _ayahBottomSheet(int index, Ayah ayah) {
    return Consumer(
      builder: (context, ref, _) {
        final playingAsync = ref.watch(playingStreamProvider);
        final isPlaying = playingAsync.when(
          data: (playing) => playing,
          loading: () => false,
          error: (_, __) => false,
        );
        final bookmarks = ref.watch(bookmarksProvider);
        final currentReciter = ref.watch(currentReciterProvider);

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ayah.arabic,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(ayah.english),
              const SizedBox(height: 20),

              /// -------- DOWNLOAD / PLAY BUTTON --------
              FutureBuilder<File>(
                future: currentReciter != null
                    ? _getLocalFile(currentReciter)
                    : null,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox();
                  final file = snapshot.data!;
                  final isDownloaded = file.existsSync();

                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: isDownloaded
                            ? Colors.green
                            : Colors.blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        if (currentReciter == null) return;
                        if (!isDownloaded) {
                          try {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Downloading...')),
                            );
                            await Dio().download(currentReciter, file.path);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Download complete'),
                              ),
                            );
                            setState(() {});
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Download failed')),
                            );
                          }
                        } else {
                          final player = ref.read(audioPlayerProvider);

                          await player.pause();

                          setState(() {});

                          await Future.delayed(
                            const Duration(milliseconds: 300),
                          );

                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString(
                            'saved_reciter',
                            currentReciter,
                          );

                          // Play from tapped ayah index
                          _playAudioFromAyah(
                            file.path,
                            currentReciter,
                            index,
                          );

                          ref.read(bottomPlayerProvider.notifier).setReciter(
                            reciterNames[
                            widget.surah.audioUrls.indexOf(currentReciter)],
                          );

                          Navigator.pop(context);
                        }
                      },
                      icon: Icon(
                        isDownloaded
                            ? (isPlaying ? Icons.pause : Icons.play_arrow)
                            : Icons.download,
                      ),
                      label: Text(
                        isDownloaded
                            ? (isPlaying ? "Pause Audio" : "Play Audio")
                            : "Download Audio",
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              /// -------- BOOKMARK BUTTON --------
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(
                      color: bookmarks.any(
                            (b) =>
                        b.suraId == widget.surah.id &&
                            b.ayahId == ayah.ayah,
                      )
                          ? Colors.orange
                          : Colors.grey,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    ref
                        .read(bookmarksProvider.notifier)
                        .toggle(
                      widget.surah.id,
                      ayah.ayah,
                      ayah.arabic,
                      ayah.english,
                    );
                  },
                  icon: Icon(
                    bookmarks.any(
                          (b) =>
                      b.suraId == widget.surah.id &&
                          b.ayahId == ayah.ayah,
                    )
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                    color: bookmarks.any(
                          (b) =>
                      b.suraId == widget.surah.id &&
                          b.ayahId == ayah.ayah,
                    )
                        ? Colors.orange
                        : Colors.grey,
                  ),
                  label: Text(
                    bookmarks.any(
                          (b) =>
                      b.suraId == widget.surah.id &&
                          b.ayahId == ayah.ayah,
                    )
                        ? "Remove Bookmark"
                        : "Add Bookmark",
                    style: TextStyle(
                      color: bookmarks.any(
                            (b) =>
                        b.suraId == widget.surah.id &&
                            b.ayahId == ayah.ayah,
                      )
                          ? Colors.orange
                          : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  String toArabicNumber(int number) {
    const arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number
        .toString()
        .split('')
        .map((e) => arabicDigits[int.parse(e)])
        .join();
  }

  void showSettingsBottomSheet(
      BuildContext context, {
        required List<String> audioUrls,
        required List<String> reciterNames,
        required Future<void> Function(String url, String name) downloadAndPlay,
        required Future<File> Function(String url) getLocalFile,
        required Function(String path, String url) playAudio,
      }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.6,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            child: SettingsBottomSheet(
              audioUrls: audioUrls,
              reciterNames: reciterNames,
              downloadAndPlay: downloadAndPlay,
              getLocalFile: getLocalFile,
              playAudio: playAudio,
            ),
          );
        },
      ),
    );
  }
}