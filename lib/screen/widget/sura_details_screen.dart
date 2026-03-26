// screen/surah_detail_screen.dart
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../model/user_reciter_model.dart';

class SurahDetailScreen extends ConsumerStatefulWidget {
  final Surah surah;
  const SurahDetailScreen({super.key, required this.surah});

  @override
  ConsumerState<SurahDetailScreen> createState() => _SurahDetailScreenState();
}

class _SurahDetailScreenState extends ConsumerState<SurahDetailScreen> {
  /// ================= DAILY GOAL =================
  int _dailyGoalMinutes = 5;
  int _listenedSecondsToday = 0;
  DateTime _today = DateTime.now();
  int _lastTrackedSecond = 0;

  /// ================= AUDIO =================
  final player = AudioPlayer();
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  Set<int> _bookmarkedAyahs = {};

  int highlightedAyah = -1;
  String? currentReciterUrl;
  int? _lastScrolledIndex;
  bool isPlaying = false;
  double playbackSpeed = 0.5; // start at 0.5x

  @override
  void initState() {
    super.initState();
    _loadDailyProgress();
    _loadBookmarks();

    if (widget.surah.audioUrls != null && widget.surah.audioUrls!.isNotEmpty) {
      currentReciterUrl = widget.surah.audioUrls!.first;
    }

    player.playerStateStream.listen((state) {
      setState(() {
        isPlaying = state.playing;
      });
    });
  }

  /// ================= FILE =================
  Future<File> _getLocalFile(String url) async {
    final dir = await getApplicationDocumentsDirectory();
    final bytes = utf8.encode(url);
    final filename = sha1.convert(bytes).toString() + ".mp3";
    return File('${dir.path}/$filename');
  }

  Future<Map<String, bool>> _checkDownloadedStatus() async {
    final map = <String, bool>{};
    for (String url in widget.surah.audioUrls!) {
      final file = await _getLocalFile(url);
      map[url] = await file.exists();
    }
    return map;
  }

  Future<void> _downloadAndPlay(String url) async {
    final file = await _getLocalFile(url);

    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Downloading...')));

      await Dio().download(url, file.path);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded ${url.split('/').last}')),
      );

      setState(() {});

      playAudioWithHighlight(file.path);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Download failed')));
    }
  }

  /// ================= DAILY =================
  Future<void> _loadDailyProgress() async {
    final prefs = await SharedPreferences.getInstance();

    final todayStr = "${_today.year}-${_today.month}-${_today.day}";
    final savedDate = prefs.getString('date') ?? '';

    if (savedDate != todayStr) {
      await prefs.setString('date', todayStr);
      await prefs.setInt(todayStr, 0); // initialize today
    }

    setState(() {
      _dailyGoalMinutes = prefs.getInt('goal') ?? 5;
      _listenedSecondsToday = prefs.getInt(todayStr) ?? 0;
    });
  }

  Future<void> _saveListening() async {
    final prefs = await SharedPreferences.getInstance();
    final todayStr = "${_today.year}-${_today.month}-${_today.day}";
    await prefs.setInt(todayStr, _listenedSecondsToday);
  }

  Future<void> _setGoal(int min) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('goal', min);

    setState(() {
      _dailyGoalMinutes = min;
    });
  }

  /// ================= BOOKMARK =================
  Future<void> _loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getStringList('bookmarks') ?? [];
    setState(() {
      _bookmarkedAyahs = keys.map((e) => int.parse(e)).toSet();
    });
  }

  Future<void> _toggleBookmark(int index) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_bookmarkedAyahs.contains(index)) {
        _bookmarkedAyahs.remove(index);
      } else {
        _bookmarkedAyahs.add(index);
      }
    });
    await prefs.setStringList(
      'bookmarks',
      _bookmarkedAyahs.map((e) => e.toString()).toList(),
    );
  }

  /// ================= PLAY =================
  void playAudioWithHighlight(String url, {int startSecond = 0}) async {
    try {
      await player.stop();
      highlightedAyah = -1;
      _lastScrolledIndex = null;
      _lastTrackedSecond = startSecond;

      await player.setUrl(url);
      await player.setSpeed(playbackSpeed);
      await player.seek(Duration(seconds: startSecond));
      await player.play();

      player.positionStream.listen((position) async {
        final seconds = position.inSeconds;

        /// ✅ TRACK LISTEN TIME
        if (seconds != _lastTrackedSecond) {
          _lastTrackedSecond = seconds;
          _listenedSecondsToday += 1;
          await _saveListening();
          setState(() {});
        }

        final time = position.inMilliseconds / 1000.0;

        for (int i = 0; i < (widget.surah.ayahs?.length ?? 0); i++) {
          final ayah = widget.surah.ayahs![i];

          int reciterIndex = widget.surah.audioUrls!.indexOf(
            currentReciterUrl!,
          );

          final timing =
              (ayah.timings != null &&
                  ayah.timings!.length > reciterIndex &&
                  ayah.timings![reciterIndex].isNotEmpty)
              ? ayah.timings![reciterIndex]
              : [0, 0];

          final start = timing.isNotEmpty ? timing[0] : 0;
          final end = timing.length > 1 ? timing[1] : start + 3;

          if (time >= start && time <= end) {
            if (highlightedAyah != i) {
              setState(() {
                highlightedAyah = i;
              });
              _scrollToCurrentAyah(i);
            }
            break;
          }
        }
      });
    } catch (e) {
      debugPrint("Audio playback failed: $e");
    }
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
      );
    }
  }

  /// ================= AYAH TAP =================
  void _onAyahTap(int index) async {
    final ayah = widget.surah.ayahs![index];
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(ayah.arabic ?? '', style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 6),
                  Text(ayah.english ?? ''),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                        onPressed: () async {
                          if (isPlaying) {
                            await player.pause();
                          } else {
                            final localFile = await _getLocalFile(
                              currentReciterUrl!,
                            );
                            if (await localFile.exists()) {
                              playAudioWithHighlight(localFile.path);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Audio not downloaded'),
                                ),
                              );
                            }
                          }
                          setModalState(() {});
                        },
                        icon: Icon(
                          isPlaying ? Icons.pause_circle : Icons.play_circle,
                          size: 36,
                        ),
                      ),
                      DropdownButton<double>(
                        value: playbackSpeed,
                        items: [0.5, 1.0, 1.5, 2.0]
                            .map(
                              (e) => DropdownMenuItem(
                                value: e,
                                child: Text("${e}x"),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              playbackSpeed = val;
                            });
                            player.setSpeed(playbackSpeed);
                          }
                        },
                      ),
                      IconButton(
                        onPressed: () => _toggleBookmark(index),
                        icon: Icon(
                          _bookmarkedAyahs.contains(index)
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    player.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final goalSeconds = _dailyGoalMinutes * 60;
    final progress = (_listenedSecondsToday / goalSeconds).clamp(0.0, 1.0);

    final reciterNames = [
      "Abdulbasit Abdulsamad",
      "Abdullah Al-Johany",
      "Ibrahim Al-Akdar",
      "Ali Hajjaj Alsouasi",
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.surah.name ?? ''),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WeeklyReportScreen()),
              );
            },
          ),
          if (widget.surah.audioUrls != null &&
              widget.surah.audioUrls!.isNotEmpty)
            FutureBuilder<Map<String, bool>>(
              future: _checkDownloadedStatus(),
              builder: (context, snapshot) {
                final downloadedMap = snapshot.data ?? {};

                return DropdownButton<String>(
                  underline: const SizedBox(),
                  value: currentReciterUrl,
                  items: List.generate(widget.surah.audioUrls!.length, (index) {
                    final url = widget.surah.audioUrls![index];
                    final isDownloaded = downloadedMap[url] ?? false;

                    return DropdownMenuItem<String>(
                      value: url,
                      child: SizedBox(
                        width: 180,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                reciterNames[index],
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!isDownloaded)
                              IconButton(
                                icon: const Icon(Icons.download, size: 18),
                                onPressed: () => _downloadAndPlay(url),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                  onChanged: (val) async {
                    if (val != null) {
                      currentReciterUrl = val;
                      highlightedAyah = -1;

                      final localFile = await _getLocalFile(val);
                      if (await localFile.exists()) {
                        playAudioWithHighlight(localFile.path);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Audio not downloaded.'),
                          ),
                        );
                      }
                      setState(() {});
                    }
                  },
                );
              },
            ),
        ],
      ),

      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Today's Progress: ${(_listenedSecondsToday / 60).toStringAsFixed(1)} / $_dailyGoalMinutes min",
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
              itemCount: widget.surah.ayahs?.length ?? 0,
              itemBuilder: (context, index) {
                final ayah = widget.surah.ayahs![index];
                final isHighlighted = index == highlightedAyah;

                _itemKeys[index] = _itemKeys[index] ?? GlobalKey();

                return GestureDetector(
                  onTap: () => _onAyahTap(index),
                  child: Container(
                    key: _itemKeys[index],
                    margin: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isHighlighted ? Colors.yellow[100] : Colors.white,
                      border: Border.all(
                        color: isHighlighted
                            ? Colors.orange
                            : Colors.grey.shade300,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      title: Text(ayah.arabic ?? ''),
                      subtitle: Text(ayah.english ?? ''),
                      trailing: _bookmarkedAyahs.contains(index)
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

      bottomNavigationBar: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [5, 10, 15].map((min) {
          return ElevatedButton(
            onPressed: () async {
              await _setGoal(min);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text("Goal set: $min minutes")));
            },
            child: Text("$min min"),
          );
        }).toList(),
      ),
    );
  }
}

// WeeklyReportScreen remains same as previous

class WeeklyReportScreen extends StatefulWidget {
  const WeeklyReportScreen({super.key});
  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  Map<String, int> _weeklyData = {};
  int _dailyGoal = 5;
  @override
  void initState() {
    super.initState();
    _loadWeeklyData();
  }

  Future<void> _loadWeeklyData() async {
    final prefs = await SharedPreferences.getInstance();
    _dailyGoal = prefs.getInt('goal') ?? 5;
    final now = DateTime.now();
    final Map<String, int> data = {};
    for (int i = 0; i < 7; i++) {
      final day = now.subtract(Duration(days: i));
      final key = "${day.year}-${day.month}-${day.day}";
      data[key] = prefs.getInt(key) ?? 0;
    }
    setState(() {
      _weeklyData = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _weeklyData.entries.toList();
    entries.sort((a, b) => b.key.compareTo(a.key));
    return Scaffold(
      appBar: AppBar(title: const Text("7-Day Progress")),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: entries.map((entry) {
            final minutes = (entry.value / 60).toStringAsFixed(1);
            final percentage = ((entry.value / (_dailyGoal * 60) * 100).clamp(
              0.0,
              100.0,
            )).toDouble();
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                title: Text(entry.key),
                subtitle: LinearProgressIndicator(value: percentage / 100),
                trailing: Text(
                  "${minutes} min (${percentage.toStringAsFixed(0)}%)",
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
