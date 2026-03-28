import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reciter_project/screen/widget/weekly_report_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../model/user_reciter_model.dart';

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
        (ref) => DailyProgressNotifier());

// Bookmarks
final bookmarksProvider =
StateNotifierProvider<BookmarksNotifier, Set<int>>((ref) => BookmarksNotifier());

// Highlighted ayah
final highlightedAyahProvider = StateProvider<int>((ref) => -1);

// Playback speed
final playbackSpeedProvider = StateProvider<double>((ref) => 0.5);

// Bottom player visibility and reciter
final bottomPlayerProvider =
StateNotifierProvider<BottomPlayerNotifier, BottomPlayerState>(
        (ref) => BottomPlayerNotifier());

// Current reciter URL
final currentReciterProvider = StateProvider<String?>((ref) => null);

/// ================= STATE MODELS =================

class DailyProgressState {
  final int goalMinutes;
  final int listenedSeconds;

  DailyProgressState({required this.goalMinutes, required this.listenedSeconds});

  DailyProgressState copyWith({int? goalMinutes, int? listenedSeconds}) {
    return DailyProgressState(
      goalMinutes: goalMinutes ?? this.goalMinutes,
      listenedSeconds: listenedSeconds ?? this.listenedSeconds,
    );
  }
}

class DailyProgressNotifier extends StateNotifier<DailyProgressState> {
  DailyProgressNotifier() : super(DailyProgressState(goalMinutes: 5, listenedSeconds: 0)) {
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

class BookmarksNotifier extends StateNotifier<Set<int>> {
  BookmarksNotifier() : super({}) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getStringList('bookmarks') ?? [];
    state = keys.map((e) => int.parse(e)).toSet();
  }

  Future<void> toggle(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final newSet = Set<int>.from(state);
    if (newSet.contains(index)) {
      newSet.remove(index);
    } else {
      newSet.add(index);
    }
    state = newSet;
    await prefs.setStringList('bookmarks', state.map((e) => e.toString()).toList());
  }
}

class BottomPlayerState {
  final bool visible;
  final String? reciterName;

  BottomPlayerState({required this.visible, this.reciterName});
}

class BottomPlayerNotifier extends StateNotifier<BottomPlayerState> {
  BottomPlayerNotifier() : super(BottomPlayerState(visible: false, reciterName: null));

  void show(String reciterName) => state = BottomPlayerState(visible: true, reciterName: reciterName);
  void hide() => state = BottomPlayerState(visible: false, reciterName: null);
  void setReciter(String reciterName) => state = BottomPlayerState(visible: true, reciterName: reciterName);
}

/// ================= SURAH DETAIL SCREEN =================

class SurahDetailScreen extends ConsumerStatefulWidget {
  final Surah surah;
  const SurahDetailScreen({super.key, required this.surah});

  @override
  ConsumerState<SurahDetailScreen> createState() => _SurahDetailScreenState();
}

class _SurahDetailScreenState extends ConsumerState<SurahDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  int? _lastScrolledIndex;

  final List<String> reciterNames = [
    "Abdulbasit Abdulsamad",
    "Abdullah Al-Johany",
    "Ibrahim Al-Akdar",
    "Ali Hajjaj Alsouasi",
  ];

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Downloading...')));
      await Dio().download(url, file.path);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloaded $reciterName')));
      _playAudio(file.path, url);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download failed')));
    }
  }

  void _playAudio(String path, [String? reciterUrl]) async {
    final player = ref.read(audioPlayerProvider);
    await player.stop();

    final reciterIndex = reciterUrl != null ? widget.surah.audioUrls.indexOf(reciterUrl) : 0;
    final playbackSpeed = ref.read(playbackSpeedProvider);

    ref.read(highlightedAyahProvider.notifier).state = -1;
    ref.read(bottomPlayerProvider.notifier).show(reciterNames[reciterIndex]);
    ref.read(currentReciterProvider.notifier).state = widget.surah.audioUrls[reciterIndex];

    await player.setFilePath(path);
    await player.setSpeed(playbackSpeed);
    await player.play();

    // ================= Listen to audio position =================
    player.positionStream.listen((position) async {
      final time = position.inMilliseconds / 1000.0;

      final reciterUrl = ref.read(currentReciterProvider);
      if (reciterUrl == null) return;

      final reciterIndex = widget.surah.audioUrls.indexOf(reciterUrl);
      if (reciterIndex == -1) return;

      for (int i = 0; i < widget.surah.ayahs.length; i++) {
        final ayah = widget.surah.ayahs[i];
        if (ayah.timings.length <= reciterIndex || ayah.timings[reciterIndex].length < 2) continue;

        final start = ayah.timings[reciterIndex][0];
        final end = ayah.timings[reciterIndex][1];

        if (time >= start && time <= end) {
          if (ref.read(highlightedAyahProvider) != i) {
            ref.read(highlightedAyahProvider.notifier).state = i;
            _scrollToCurrentAyah(i);
          }
          break;
        }
      }

      await ref.read(dailyProgressProvider.notifier).incrementListening();
    });
  }

  void _scrollToCurrentAyah(int index) {
    if (_lastScrolledIndex == index) return;
    _lastScrolledIndex = index;

    final key = _itemKeys[index];
    if (key == null) return;

    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        alignment: 0.4,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.surah.audioUrls.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final firstUrl = widget.surah.audioUrls.first;
        ref.read(currentReciterProvider.notifier).state = firstUrl;
        final file = await _getLocalFile(firstUrl);
        if (await file.exists()) {
          _playAudio(file.path, firstUrl);
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
    final progress = (dailyProgress.listenedSeconds / goalSeconds).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.surah.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const WeeklyReportScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final savedReciterUrl = prefs.getString('saved_reciter');
              final downloadedMap = await _checkDownloadedStatus();

              await showDialog(
                context: context,
                builder: (context) {
                  return StatefulBuilder(
                    builder: (context, setState) {
                      return AlertDialog(
                        title: const Text("Select Reciter"),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(widget.surah.audioUrls.length, (i) {
                            final url = widget.surah.audioUrls[i];
                            final isSaved = url == savedReciterUrl;
                            final isDownloaded = downloadedMap[url] ?? false;

                            return ListTile(
                              title: Text(reciterNames[i]),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isDownloaded)
                                    const Icon(Icons.check_circle, color: Colors.green, size: 20)
                                  else
                                    IconButton(
                                      icon: const Icon(Icons.download, color: Colors.grey, size: 20),
                                      onPressed: () async {
                                        await _downloadAndPlay(url, reciterNames[i]);
                                        setState(() => downloadedMap[url] = true);
                                      },
                                    ),
                                  if (isSaved) ...[
                                    const SizedBox(width: 6),
                                    const Icon(Icons.star, color: Colors.orange, size: 20),
                                  ],
                                ],
                              ),
                              onTap: () async {
                                await prefs.setString('saved_reciter', url);
                                Navigator.pop(context);

                                final file = await _getLocalFile(url);
                                if (await file.exists()) {
                                  _playAudio(file.path, url);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Audio not downloaded')));
                                }
                              },
                            );
                          }),
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
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's Progress: ${ (dailyProgress.listenedSeconds / 60).floor() } / ${dailyProgress.goalMinutes} min",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: progress),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: widget.surah.ayahs.length,
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
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isHighlighted ? Colors.yellow[100] : Colors.white,
                          border: Border.all(
                              color: isHighlighted ? Colors.orange : Colors.grey.shade300
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListTile(
                          title: Text(ayah.arabic),
                          subtitle: Text(ayah.english),
                          trailing: bookmarks.contains(index)
                              ? const Icon(Icons.bookmark, color: Colors.orange)
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              ),

            ],
          ),
          // Bottom Player
          if (bottomPlayer.visible)
            Positioned(
              bottom: 50,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Consumer(builder: (context, ref, _) {
                      final player = ref.watch(audioPlayerProvider);
                      final isPlaying = player.playing;
                      return IconButton(
                        onPressed: () async {
                          if (isPlaying) {
                            await player.pause();
                          } else {
                            await player.play();
                          }
                        },
                        icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle, size: 36),
                      );
                    }),
                    Row(
                      children: [
                        Text(bottomPlayer.reciterName ?? '',style: TextStyle(fontSize: 12),),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Decrease Button
                            IconButton(
                              onPressed: () {
                                double current = ref.read(playbackSpeedProvider);
                                if (current > 0.5) {
                                  current -= 0.5;
                                  ref.read(playbackSpeedProvider.notifier).state = current;
                                  ref.read(audioPlayerProvider).setSpeed(current);
                                }
                              },
                              icon: const Icon(Icons.arrow_left),
                            ),
                            // Current speed display
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "${ref.watch(playbackSpeedProvider).toStringAsFixed(1)} x",
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            // Increase Button
                            IconButton(
                              onPressed: () {
                                double current = ref.read(playbackSpeedProvider);
                                if (current < 2.0) {
                                  current += 0.5;
                                  ref.read(playbackSpeedProvider.notifier).state = current;
                                  ref.read(audioPlayerProvider).setSpeed(current);
                                }
                              },
                              icon: const Icon(Icons.arrow_right),
                            ),
                          ],
                        )
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ayahBottomSheet(int index, Ayah ayah) {
    return Consumer(builder: (context, ref, _) {
      final isPlaying = ref.watch(audioPlayerProvider).playing;
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
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(ayah.english),

            const SizedBox(height: 20),

            /// -------- DOWNLOAD / PLAY BUTTON --------
            FutureBuilder<File>(
              future: currentReciter != null ? _getLocalFile(currentReciter) : null,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();

                final file = snapshot.data!;
                final isDownloaded = file.existsSync();

                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor:
                      isDownloaded ? Colors.green : Colors.blue,
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
                            const SnackBar(content: Text('Download complete')),
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
                          _playAudio(file.path, currentReciter);

                          ref.read(bottomPlayerProvider.notifier).setReciter(
                              reciterNames[
                              widget.surah.audioUrls.indexOf(currentReciter)]);
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
                    color: bookmarks.contains(index)
                        ? Colors.orange
                        : Colors.grey,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  ref.read(bookmarksProvider.notifier).toggle(index);
                },
                icon: Icon(
                  bookmarks.contains(index)
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                  color: bookmarks.contains(index)
                      ? Colors.orange
                      : Colors.grey,
                ),
                label: Text(
                  bookmarks.contains(index)
                      ? "Remove Bookmark"
                      : "Add Bookmark",
                  style: TextStyle(
                    color: bookmarks.contains(index)
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
    });
  }
}