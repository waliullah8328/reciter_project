import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reciter_project/screen/widget/weekly_report_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../model/user_reciter_model.dart';

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

/// ================= RIVERPOD PROVIDERS =================

// Audio player
final audioPlayerProvider = Provider<AudioPlayer>((ref) {
  final player = AudioPlayer();
  ref.onDispose(() => player.dispose());
  return player;
});

// Daily goal & listened seconds
final dailyProgressProvider =
    StateNotifierProvider<DailyProgressNotifier, DailyProgressState>(
      (ref) => DailyProgressNotifier(),
    );

// Bookmarks with sura and ayah info
final bookmarksProvider =
    StateNotifierProvider<BookmarksNotifier, List<Bookmark>>(
      (ref) => BookmarksNotifier(),
    );

// Highlighted ayah
final highlightedAyahProvider = StateProvider<int>((ref) => -1);

// Playback speed
final playbackSpeedProvider = StateProvider<double>((ref) => 0.5);

// Bottom player visibility and reciter
final bottomPlayerProvider =
    StateNotifierProvider<BottomPlayerNotifier, BottomPlayerState>(
      (ref) => BottomPlayerNotifier(),
    );

// Current reciter URL
final currentReciterProvider = StateProvider<String?>((ref) => null);

// Playing state stream provider for real-time play/pause button updates
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
  final List<Surah> allSurahs; // Add list of all surahs for auto-play next
  final int surahIndex; // Current surah index in the list

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

  // Store position listener subscription to cancel when needed
  dynamic _positionStreamSubscription;

  // Track last incremented second to avoid multiple increments per second
  int _lastIncrementedSecond = -1;

  // Local playing state for immediate UI feedback
  bool _localIsPlaying = false;

  final List<String> reciterNames = [
    "Abdulbasit Abdulsamad",
    "Abdullah Al-Johany",
    "Ibrahim Al-Akdar",
    "Ali Hajjaj Alsouasi",
  ];

  /// ================= AUTO-PLAY NEXT SURAH =================
  Future<void> _autoPlayNextSurah() async {
    try {
      // Check if there's a next surah
      if (widget.surahIndex < widget.allSurahs.length - 1) {
        final nextSurah = widget.allSurahs[widget.surahIndex + 1];
        final reciterUrl = ref.read(currentReciterProvider);

        if (reciterUrl != null) {
          final file = await _getLocalFile(reciterUrl);

          if (await file.exists()) {
            print('Auto-playing next surah: ${nextSurah.name}');

            // Navigate to next surah
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

            // Delay to ensure navigation is complete
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

  void onAyahTap(int index) async {
    final player = ref.read(audioPlayerProvider);
    final reciterUrl = ref.read(currentReciterProvider);

    if (reciterUrl == null) return;

    final reciterIndex = widget.surah.audioUrls.indexOf(reciterUrl);
    if (reciterIndex == -1) return;

    final ayah = widget.surah.ayahs[index];

    if (ayah.timings.length <= reciterIndex ||
        ayah.timings[reciterIndex].isEmpty)
      return;

    final startTime = ayah.timings[reciterIndex][0];

    // 🔥 Fix starts here
    final wasPlaying = player.playing;

    await player.seek(Duration(milliseconds: (startTime * 1000).toInt()));

    if (wasPlaying) {
      await player.play();
    }

    // Update UI
    ref.read(highlightedAyahProvider.notifier).state = index;
    _scrollToCurrentAyah(index);
  }

  void _playAudio(
    String path, [
    String? reciterUrl,
    int? startingAyahIndex,
  ]) async {
    try {
      // Cancel previous listener
      await _positionStreamSubscription?.cancel();

      // Reset last incremented second
      _lastIncrementedSecond = -1;

      final player = ref.read(audioPlayerProvider);

      // Stop any existing playback first
      try {
        if (player.playing) {
          await player.stop();
        }
      } catch (e) {
        print('Error stopping player: $e');
      }

      final reciterIndex = reciterUrl != null
          ? widget.surah.audioUrls.indexOf(reciterUrl)
          : 0;
      final playbackSpeed = ref.read(playbackSpeedProvider);

      // Determine starting ayah (use provided index or start from 0)
      final initialAyahIndex = startingAyahIndex ?? 0;

      // Highlight starting ayah immediately
      ref.read(highlightedAyahProvider.notifier).state = initialAyahIndex;
      _scrollToCurrentAyah(initialAyahIndex);

      ref.read(bottomPlayerProvider.notifier).show(reciterNames[reciterIndex]);
      ref.read(currentReciterProvider.notifier).state =
          widget.surah.audioUrls[reciterIndex];

      // Verify file exists
      final file = File(path);
      if (!await file.exists()) {
        print('Audio file does not exist: $path');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Audio file not found')));
        return;
      }

      // Set audio source
      await player.setFilePath(path);
      await player.setSpeed(playbackSpeed);

      // If starting from a specific ayah, seek to that ayah's start time
      if (startingAyahIndex != null &&
          startingAyahIndex > 0 &&
          startingAyahIndex < widget.surah.ayahs.length) {
        final startingAyah = widget.surah.ayahs[startingAyahIndex];
        if (startingAyah.timings.length > reciterIndex &&
            startingAyah.timings[reciterIndex].length >= 1) {
          final startTime = startingAyah.timings[reciterIndex][0];
          await player.seek(Duration(milliseconds: (startTime * 1000).toInt()));
        }
      }

      // Play audio
      await player.play();
      print('Audio playback started successfully');

      // Listen to player state changes (completion detection)
      player.playerStateStream.listen((playerState) {
        // Check if audio has completed
        if (playerState.processingState == ProcessingState.completed) {
          print('Current surah audio finished, auto-playing next...');
          _autoPlayNextSurah();
        }
      });

      // ================= Listen to audio position =================
      _positionStreamSubscription = player.positionStream.listen((
        position,
      ) async {
        final time = position.inMilliseconds / 1000.0;
        final currentSecond = time.floor();

        final reciterUrl = ref.read(currentReciterProvider);
        if (reciterUrl == null) return;

        final reciterIndex = widget.surah.audioUrls.indexOf(reciterUrl);
        if (reciterIndex == -1) return;

        // Find matching ayah based on current time - check from beginning to find the correct one
        int matchedIndex = -1;
        for (int i = 0; i < widget.surah.ayahs.length; i++) {
          final ayah = widget.surah.ayahs[i];

          // Skip if timing data is invalid
          if (ayah.timings.length <= reciterIndex ||
              ayah.timings[reciterIndex].isEmpty)
            continue;
          if (ayah.timings[reciterIndex].length < 2) continue;

          final start = ayah.timings[reciterIndex][0];
          final end = ayah.timings[reciterIndex][1];

          // Check if current position is within this ayah's time range
          if (time >= start && time <= end) {
            matchedIndex = i;
            break;
          }
        }

        // Automatically update highlighting when ayah changes
        final currentHighlight = ref.read(highlightedAyahProvider);
        if (matchedIndex != -1 && currentHighlight != matchedIndex) {
          // Update highlighting immediately
          ref.read(highlightedAyahProvider.notifier).state = matchedIndex;

          // Scroll to the new ayah with animation
          _scrollToCurrentAyah(matchedIndex);
        }

        // Only increment listening time once per second when audio is actively playing
        if (player.playing && currentSecond != _lastIncrementedSecond) {
          _lastIncrementedSecond = currentSecond;
          await ref.read(dailyProgressProvider.notifier).incrementListening();
        }
      });
    } catch (e) {
      print('Error in _playAudio: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Playback error: $e')));
    }
  }

  void _scrollToCurrentAyah(int index) {
    if (_lastScrolledIndex == index) return;
    _lastScrolledIndex = index;

    // Use post frame callback to ensure widget is rendered and visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final key = _itemKeys[index];
        if (key == null) return;

        final context = key.currentContext;
        if (context != null && context.mounted) {
          // Scroll smoothly to the ayah
          Scrollable.ensureVisible(
            context,
            alignment:
                0.35, // Position ayah at 35% from top for better visibility
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      } catch (e) {
        // Silently handle any scroll errors
        print('Scroll error: $e');
      }
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.surah.audioUrls.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final savedReciterUrl = prefs.getString('saved_reciter');

          // Use saved reciter if available, otherwise use first
          final firstUrl = savedReciterUrl ?? widget.surah.audioUrls.first;

          if (!widget.surah.audioUrls.contains(firstUrl)) {
            // Fallback to first if saved is invalid
            ref.read(currentReciterProvider.notifier).state =
                widget.surah.audioUrls.first;
          } else {
            ref.read(currentReciterProvider.notifier).state = firstUrl;
          }

          // Don't auto-play - wait for user to click play button
        } catch (e) {
          print('Error in initState: $e');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dailyProgress = ref.watch(dailyProgressProvider);
    final highlightedIndex = ref.watch(highlightedAyahProvider);
    final bookmarks = ref.watch(bookmarksProvider);
    final bottomPlayer = ref.watch(bottomPlayerProvider);
    final playbackSpeed = ref.watch(playbackSpeedProvider);

    final goalSeconds = dailyProgress.goalMinutes * 60;
    final progress = (dailyProgress.listenedSeconds / goalSeconds).clamp(
      0.0,
      1.0,
    );

    return Scaffold(
      // appBar: AppBar(
      //   title: Text(widget.surah.name),
      //   actions: [
      //     IconButton(
      //       icon: const Icon(Icons.bar_chart),
      //       onPressed: () => Navigator.push(
      //           context, MaterialPageRoute(builder: (_) => const WeeklyReportScreen())),
      //     ),
      //     IconButton(
      //       icon: const Icon(Icons.settings),
      //       onPressed: () async {
      //         final prefs = await SharedPreferences.getInstance();
      //         final savedReciterUrl = prefs.getString('saved_reciter');
      //         final downloadedMap = await _checkDownloadedStatus();
      //
      //         await showDialog(
      //           context: context,
      //           builder: (context) {
      //             return StatefulBuilder(
      //               builder: (context, setState) {
      //                 return AlertDialog(
      //                   title: const Text("Select Reciter"),
      //                   content: Column(
      //                     mainAxisSize: MainAxisSize.min,
      //                     children: List.generate(widget.surah.audioUrls.length, (i) {
      //                       final url = widget.surah.audioUrls[i];
      //                       final isSaved = url == savedReciterUrl;
      //                       final isDownloaded = downloadedMap[url] ?? false;
      //
      //                       return ListTile(
      //                         title: Text(reciterNames[i]),
      //                         trailing: Row(
      //                           mainAxisSize: MainAxisSize.min,
      //                           children: [
      //                             if (isDownloaded)
      //                               const Icon(Icons.check_circle, color: Colors.green, size: 20)
      //                             else
      //                               IconButton(
      //                                 icon: const Icon(Icons.download, color: Colors.grey, size: 20),
      //                                 onPressed: () async {
      //                                   await _downloadAndPlay(url, reciterNames[i]);
      //                                   setState(() => downloadedMap[url] = true);
      //                                 },
      //                               ),
      //                             if (isSaved) ...[
      //                               const SizedBox(width: 6),
      //                               const Icon(Icons.star, color: Colors.orange, size: 20),
      //                             ],
      //                           ],
      //                         ),
      //                         onTap: () async {
      //                           await prefs.setString('saved_reciter', url);
      //                           Navigator.pop(context);
      //
      //                           final file = await _getLocalFile(url);
      //                           if (await file.exists()) {
      //                             _playAudio(file.path, url);
      //                           } else {
      //                             ScaffoldMessenger.of(context).showSnackBar(
      //                                 const SnackBar(content: Text('Audio not downloaded')));
      //                           }
      //                         },
      //                       );
      //                     }),
      //                   ),
      //                 );
      //               },
      //             );
      //           },
      //         );
      //       },
      //     ),
      //   ],
      // ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/image/white_quran_back_ground.png"),
            fit: BoxFit.cover,
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                /// 🔹 HEADER
                Padding(
                  padding:  EdgeInsets.only(left: 10,right: 16,top: 30,),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 10),

                      Expanded(
                        child: Text(
                          widget.surah.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      // IconButton(
                      //   icon: const Icon(Icons.bar_chart,size: ,),
                      //   onPressed: () => Navigator.push(
                      //     context,
                      //     MaterialPageRoute(
                      //       builder: (_) => const WeeklyReportScreen(),
                      //     ),
                      //   ),
                      // ),

                      IconButton(
                        icon: const Icon(Icons.settings),
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          final savedReciterUrl = prefs.getString(
                            'saved_reciter',
                          );
                          final downloadedMap =
                              await _checkDownloadedStatus();

                          await showDialog(
                            context: context,
                            builder: (context) {
                              return StatefulBuilder(
                                builder: (context, setState) {
                                  return AlertDialog(
                                    title: const Text("Select Reciter"),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: List.generate(
                                        widget.surah.audioUrls.length,
                                        (i) {
                                          final url =
                                              widget.surah.audioUrls[i];
                                          final isSaved =
                                              url == savedReciterUrl;
                                          final isDownloaded =
                                              downloadedMap[url] ?? false;

                                          return ListTile(
                                            title: Text(reciterNames[i]),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (isDownloaded)
                                                  const Icon(
                                                    Icons.check_circle,
                                                    color: Colors.green,
                                                    size: 20,
                                                  )
                                                else
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.download,
                                                      size: 20,
                                                    ),
                                                    onPressed: () async {
                                                      await _downloadAndPlay(
                                                        url,
                                                        reciterNames[i],
                                                      );
                                                      setState(
                                                        () =>
                                                            downloadedMap[url] =
                                                                true,
                                                      );
                                                    },
                                                  ),
                                                if (isSaved)
                                                  const Padding(
                                                    padding: EdgeInsets.only(
                                                      left: 6,
                                                    ),
                                                    child: Icon(
                                                      Icons.star,
                                                      color: Colors.orange,
                                                      size: 20,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            onTap: () async {
                                              await prefs.setString(
                                                'saved_reciter',
                                                url,
                                              );
                                              Navigator.pop(context);

                                              final file =
                                                  await _getLocalFile(url);
                                              if (await file.exists()) {
                                                _playAudio(file.path, url);
                                              } else {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Audio not downloaded',
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),

                /// 🔹 PROGRESS
                Padding(
                  padding: EdgeInsets.only(left: 12,right: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        "Reading Goal: ${(dailyProgress.listenedSeconds / 60).floor()} / ${dailyProgress.goalMinutes} min",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 4,
                          backgroundColor: Colors.grey.withOpacity(0.25),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF00BCDD),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: (){
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const WeeklyReportScreen(),
                            ),
                          );
                        },
                          child: Icon(Icons.arrow_forward_ios_rounded,size: 16,)),
                    ],
                  ),
                ),
                SizedBox(height: 48),
                 Text(widget.surah.arName,style: TextStyle(fontSize: 16,fontWeight: FontWeight.w600),),
                SizedBox(height: 32),



                /// 🔹 LIST
                SizedBox(
                  height: 620,
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    controller: _scrollController,
                    itemCount: widget.surah.ayahs.length,
                    key: Key('ayah_list_${widget.surah.id}'),
                    itemBuilder: (context, index) {
                      final ayah = widget.surah.ayahs[index];
                      _itemKeys[index] = _itemKeys[index] ?? GlobalKey();
                      final isHighlighted = highlightedIndex == index;

                      return GestureDetector(
                        onTap: () async {
                          await showModalBottomSheet(
                            context: context,
                            builder: (_) => _ayahBottomSheet(index, ayah),
                          );
                        },
                        child: Container(
                          key: _itemKeys[index],
                          margin: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 6,
                          ),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isHighlighted
                                ? Color(0xffC8E6C9)
                                : Colors.white.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isHighlighted
                                  ? Color(0xffC8E6C9)
                                  : Colors.grey.shade300,
                              width: isHighlighted ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Stack(
                                children: [
                                  SizedBox(
                                    height: 35,
                                    width: 35,
                                    child: SvgPicture.asset(
                                      "assets/icon/sura_icon_1.svg",
                                    ),
                                  ),
                                  Positioned(
                                    left: id < 10
                                        ? 14.w
                                        : id < 100
                                        ? 11.5.w
                                        : 10.w,
                                    top: id < 100 ? 8.h : 10.h,
                                    child: CustomText(
                                      text: toArabicNumber(id),
                                      fontSize: id < 10
                                          ? 14.sp
                                          : id < 100
                                          ? 12.sp
                                          : 10.sp,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  ayah.arabic,
                                  style: TextStyle(
                                    fontWeight: isHighlighted
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: isHighlighted ? 17 : 16,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(ayah.english),
                                ),
                                trailing:
                                    bookmarks.any(
                                      (b) =>
                                          b.suraId == widget.surah.id &&
                                          b.ayahId == ayah.ayah,
                                    )
                                    ? const Icon(
                                        Icons.bookmark,
                                        color: Colors.orange,
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),

            /// 🔻 Bottom Player (UNCHANGED LOGIC)
            if (bottomPlayer.visible)
              Positioned(
                bottom: 50,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Consumer(
                        builder: (context, ref, _) {
                          final playingAsync = ref.watch(
                            playingStreamProvider,
                          );
                          final isPlaying = playingAsync.when(
                            data: (playing) => playing,
                            loading: () => false,
                            error: (_, __) => false,
                          );

                          return IconButton(
                            onPressed: () async {
                              final player = ref.read(audioPlayerProvider);
                              if (isPlaying) {
                                await player.pause();
                              } else {
                                await player.play();
                              }
                            },
                            icon: Icon(
                              isPlaying
                                  ? Icons.pause_circle
                                  : Icons.play_circle,
                              size: 36,
                            ),
                          );
                        },
                      ),

                      Expanded(
                        child: Text(
                          bottomPlayer.reciterName ?? '',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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
              // Ayah Text
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

                        // ---------------- DOWNLOAD ----------------
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
                        }
                        // ---------------- PLAY / PAUSE ----------------
                        else {
                          final player = ref.read(audioPlayerProvider);

                          if (isPlaying) {
                            await player.pause();
                          } else {
                            // Save selected reciter preference
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString(
                              'saved_reciter',
                              currentReciter!,
                            );

                            // Play from this specific ayah (pass the index)
                            // await player.pause();
                            _playAudio(file.path, currentReciter, index);
                            //onAyahTap( index);

                            ref
                                .read(bottomPlayerProvider.notifier)
                                .setReciter(
                                  reciterNames[widget.surah.audioUrls.indexOf(
                                    currentReciter,
                                  )],
                                );

                            // Close modal to see the highlighting
                            Navigator.pop(context);
                          }
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

              /// -------- BOOKMARK BUTTON (FULL WIDTH) --------
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(
                      color:
                          bookmarks.any(
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
                    color:
                        bookmarks.any(
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
                      color:
                          bookmarks.any(
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
}
