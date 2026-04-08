import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReciterScreen extends StatefulWidget {
  final List<String> audioUrls;
  final List<String> reciterNames;

  final Future<void> Function(String url, String name) downloadAndPlay;
  final Future<File> Function(String url) getLocalFile;
  final Function(String path, String url) playAudio;

  const ReciterScreen({
    super.key,
    required this.audioUrls,
    required this.reciterNames,
    required this.downloadAndPlay,
    required this.getLocalFile,
    required this.playAudio,
  });

  @override
  State<ReciterScreen> createState() => _ReciterScreenState();
}

class _ReciterScreenState extends State<ReciterScreen> {
  Map<String, bool> downloadedMap = {};
  String? savedReciterUrl;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    savedReciterUrl = prefs.getString('saved_reciter');

    downloadedMap = await _checkDownloadedStatus();

    setState(() {});
  }

  Future<Map<String, bool>> _checkDownloadedStatus() async {
    final map = <String, bool>{};

    for (final url in widget.audioUrls) {
      final file = await widget.getLocalFile(url);
      map[url] = await file.exists();
    }

    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),

      /// 🔥 APP BAR
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Reciters & Narrators",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      /// 🔥 LIST
      body: ListView.builder(
        itemCount: widget.audioUrls.length,
        itemBuilder: (context, i) {
          final url = widget.audioUrls[i];
          final isSaved = url == savedReciterUrl;
          final isDownloaded = downloadedMap[url] ?? false;

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              /// 🔥 AVATAR
              leading: CircleAvatar(
                radius: 24,
                backgroundImage: AssetImage(
                  "assets/images/reciters/${i + 1}.png",
                ),
              ),

              /// 🔥 TITLE
              title: Text(
                widget.reciterNames[i],
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),

              /// 🔥 SUBTITLE
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.circle, size: 8, color: Colors.green),
                      SizedBox(width: 6),
                      Text("Arabic"),
                    ],
                  ),
                  Text(
                    isDownloaded
                        ? "114/114 downloaded"
                        : "0/114 downloaded",
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),

              /// 🔥 TRAILING
              trailing: GestureDetector(
                onTap: () async {
                  if (!isDownloaded) {
                    await widget.downloadAndPlay(
                      url,
                      widget.reciterNames[i],
                    );

                    setState(() {
                      downloadedMap[url] = true;
                    });
                  } else {
                    final prefs =
                    await SharedPreferences.getInstance();
                    await prefs.setString('saved_reciter', url);

                    setState(() {
                      savedReciterUrl = url;
                    });

                    final file = await widget.getLocalFile(url);
                    if (await file.exists()) {
                      widget.playAudio(file.path, url);
                    }
                  }
                },
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.green,
                  child: Icon(
                    isSaved
                        ? Icons.check
                        : isDownloaded
                        ? Icons.play_arrow
                        : Icons.download,
                    color: Colors.white,
                  ),
                ),
              ),

              /// 🔥 TAP SELECT
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('saved_reciter', url);

                setState(() {
                  savedReciterUrl = url;
                });

                final file = await widget.getLocalFile(url);
                if (await file.exists()) {
                  widget.playAudio(file.path, url);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Audio not downloaded'),
                    ),
                  );
                }
              },
            ),
          );
        },
      ),
    );
  }
}