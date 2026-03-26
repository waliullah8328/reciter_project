// screen/surah_detail_screen.dart
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../model/user_reciter_model.dart';

class SurahDetailScreen extends ConsumerStatefulWidget {
  final Surah surah;
  const SurahDetailScreen({super.key, required this.surah});

  @override
  ConsumerState<SurahDetailScreen> createState() => _SurahDetailScreenState();
}

class _SurahDetailScreenState extends ConsumerState<SurahDetailScreen> {

  // Get a unique local file for each URL
  Future<File> _getLocalFile(String url) async {
    final dir = await getApplicationDocumentsDirectory();

    // Use a hash of the URL to create a unique filename
    final bytes = utf8.encode(url);
    final filename = sha1.convert(bytes).toString() + ".mp3";

    return File('${dir.path}/$filename');
  }

// Check which reciters are downloaded
  Future<Map<String, bool>> _checkDownloadedStatus() async {
    final map = <String, bool>{};
    for (String url in widget.surah.audioUrls!) {
      final file = await _getLocalFile(url);
      map[url] = await file.exists();
    }
    return map;
  }

// Download and play audio
  Future<void> _downloadAndPlay(String url) async {
    final file = await _getLocalFile(url);

    try {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Downloading...')));

      await Dio().download(url, file.path, onReceiveProgress: (received, total) {
        if (total != -1) {
          debugPrint(
              'Download progress: ${(received / total * 100).toStringAsFixed(0)}%');
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded ${url.split('/').last}')));

      setState(() {}); // Refresh the dropdown

      // Play the downloaded file
      playAudioWithHighlight(file.path);
    } catch (e) {
      debugPrint('Download failed: $e');
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Download failed')));
    }
  }
  final player = AudioPlayer();
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {}; // Store keys for each ayah

  int highlightedAyah = -1;
  String? currentReciterUrl;
  int? _lastScrolledIndex;

  @override
  void initState() {
    super.initState();
    if (widget.surah.audioUrls != null && widget.surah.audioUrls!.isNotEmpty) {
      currentReciterUrl = widget.surah.audioUrls!.first;
      playAudioWithHighlight(currentReciterUrl!);
    }
  }

  void playAudioWithHighlight(String url) async {
    try {
      await player.stop(); // Stop any previous playback
      highlightedAyah = -1; // reset highlight
      _lastScrolledIndex = null;

      await player.setUrl(url);
      await player.play();

      // Listen to playback position
      player.positionStream.listen((position) {
        final seconds = position.inMilliseconds / 1000.0;

        for (int i = 0; i < (widget.surah.ayahs?.length ?? 0); i++) {
          final ayah = widget.surah.ayahs![i];

          // Get timing for the current reciter
          // Assume ayah.timings is List<List<double>>, each sublist = timings for a reciter
          int reciterIndex = widget.surah.audioUrls!.indexOf(currentReciterUrl!);
          final timing = (ayah.timings != null &&
              ayah.timings!.length > reciterIndex &&
              ayah.timings![reciterIndex].isNotEmpty)
              ? ayah.timings![reciterIndex]
              : [0, 0];

          final start = timing.isNotEmpty ? timing[0] : 0;
          final end = timing.length > 1 ? timing[1] : start + 3;

          if (seconds >= start && seconds <= end) {
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

  /// Auto-scroll to the currently playing ayah
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
  void dispose() {
    player.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.surah.name ?? ''),
        actions: [
          if (widget.surah.audioUrls != null && widget.surah.audioUrls!.isNotEmpty)
            FutureBuilder<Map<String, bool>>(
              future: _checkDownloadedStatus(),
              builder: (context, snapshot) {
                final downloadedMap = snapshot.data ?? {};

                final reciterNames = [
                  "Abdulbasit Abdulsamad",
                  "Abdullah Al-Johany",
                  "Ibrahim Al-Akdar",
                  "Ali Hajjaj Alsouasi"
                ];

                return DropdownButton<String>(
                  underline: const SizedBox(), // remove default underline
                  value: currentReciterUrl,
                  items: List.generate(widget.surah.audioUrls!.length, (index) {
                    final url = widget.surah.audioUrls![index];
                    final isDownloaded = downloadedMap[url] ?? false;
                    final reciterName = reciterNames.length > index
                        ? reciterNames[index]
                        : url.split('/').last; // fallback

                    return DropdownMenuItem<String>(
                      value: url,
                      child: SizedBox(
                        width: 180, // enough width for names
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                reciterName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            if (!isDownloaded)
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
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
                            content: Text('Audio not downloaded. Tap download icon.'),
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
      body: ListView.builder(
        controller: _scrollController,
        itemCount: widget.surah.ayahs?.length ?? 0,
        itemBuilder: (context, index) {
          final ayah = widget.surah.ayahs![index];
          final isHighlighted = index == highlightedAyah;

          _itemKeys[index] = _itemKeys[index] ?? GlobalKey();

          return Container(
            key: _itemKeys[index],
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isHighlighted ? Colors.yellow[100] : Colors.white,
              border: Border.all(
                color: isHighlighted ? Colors.orange : Colors.grey.shade300,
                width: isHighlighted ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: isHighlighted
                  ? [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ]
                  : [],
            ),
            child: ListTile(
              title: Text(
                ayah.arabic ?? '',
                style: TextStyle(
                  fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
                  fontSize: 18,
                ),
              ),
              subtitle: Text(ayah.english ?? ''),
              onTap: () {
                if (currentReciterUrl != null) {
                  final timing =
                  (ayah.timings != null && ayah.timings!.isNotEmpty)
                      ? ayah.timings!.first
                      : [0, 0];
                  final start = timing.isNotEmpty ? timing[0] : 0;
                  player.seek(Duration(milliseconds: (start * 1000).toInt()));
                }
              },
            ),
          );
        },
      ),
      bottomNavigationBar: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [5, 10, 15].map((min) {
          return ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Daily target set: $min minutes")),
              );
            },
            child: Text("$min min"),
          );
        }).toList(),
      ),
    );
  }
}