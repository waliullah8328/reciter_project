import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reciter_project/features/sura_details_section/sura_details/view/sura_details_screen.dart';
import 'package:reciter_project/features/weekly_report_screen/view/weekly_report_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../common/custom_text.dart';
import '../../model/settings_view_model.dart';
import '../../features/sura_list/model/user_reciter_model.dart';

class SurahDetailScreenTwo extends ConsumerStatefulWidget {
  final Surah surah;
  final List<Surah> allSurahs;
  final int surahIndex;

  const SurahDetailScreenTwo({
    super.key,
    required this.surah,
    required this.allSurahs,
    required this.surahIndex,
  });

  @override
  ConsumerState<SurahDetailScreenTwo> createState() =>
      _SurahDetailScreenState();
}

class _SurahDetailScreenState
    extends ConsumerState<SurahDetailScreenTwo> {

  /// ================= PAGE VIEW =================
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late List<List<Ayah>> _pages;

  /// ================= AUDIO =================
  dynamic _positionStreamSubscription;
  int _lastIncrementedSecond = -1;

  final List<String> reciterNames = [
    "Abdulbasit Abdulsamad",
    "Abdullah Al-Johany",
    "Ibrahim Al-Akdar",
    "Ali Hajjaj Alsouasi",
  ];

  /// ================= INIT =================
  @override
  void initState() {
    super.initState();

    _pages = _paginateAyahs(widget.surah.ayahs);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      final savedReciter = prefs.getString('saved_reciter');

      ref.read(currentReciterProvider.notifier).state =
          savedReciter ?? widget.surah.audioUrls.first;
    });
  }

  /// ================= PAGINATION =================
  List<List<Ayah>> _paginateAyahs(List<Ayah> ayahs) {
    List<List<Ayah>> pages = [];
    List<Ayah> current = [];
    int count = 0;

    for (var a in ayahs) {
      count += a.arabic.length;

      if (count > 900) {
        pages.add(current);
        current = [];
        count = a.arabic.length;
      }
      current.add(a);
    }

    if (current.isNotEmpty) pages.add(current);
    return pages;
  }

  /// ================= PAGE JUMP =================
  void _jumpToPage(int ayahIndex) {
    for (int i = 0; i < _pages.length; i++) {
      if (_pages[i]
          .any((a) => widget.surah.ayahs.indexOf(a) == ayahIndex)) {
        _pageController.animateToPage(
          i,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        break;
      }
    }
  }

  /// ================= AUDIO PLAY =================
  void _playAudio(String path, String url, [int startIndex = 0]) async {
    final player = ref.read(audioPlayerProvider);

    await _positionStreamSubscription?.cancel();
    _lastIncrementedSecond = -1;

    await player.setFilePath(path);
    await player.play();

    _positionStreamSubscription =
        player.positionStream.listen((position) async {
          final time = position.inMilliseconds / 1000;

          final reciterUrl = ref.read(currentReciterProvider);
          if (reciterUrl == null) return;

          final reciterIndex =
          widget.surah.audioUrls.indexOf(reciterUrl);

          int matchedIndex = -1;

          for (int i = 0; i < widget.surah.ayahs.length; i++) {
            final ayah = widget.surah.ayahs[i];

            if (ayah.timings.length <= reciterIndex) continue;
            if (ayah.timings[reciterIndex].length < 2) continue;

            final start = ayah.timings[reciterIndex][0];
            final end = ayah.timings[reciterIndex][1];

            if (time >= start && time <= end) {
              matchedIndex = i;
              break;
            }
          }

          if (matchedIndex != -1) {
            ref
                .read(highlightedAyahProvider.notifier)
                .state = matchedIndex;

            /// 🔥 AUTO PAGE MOVE
            _jumpToPage(matchedIndex);
          }

          final currentSecond = time.floor();
          if (currentSecond != _lastIncrementedSecond) {
            _lastIncrementedSecond = currentSecond;
            await ref
                .read(dailyProgressProvider.notifier)
                .incrementListening();
          }
        });
  }

  /// ================= UI =================
  @override
  Widget build(BuildContext context) {
    final bottomPlayer = ref.watch(bottomPlayerProvider);
    final dailyProgress = ref.watch(dailyProgressProvider);
    final selectedTheme =
    ref.watch(settingsProvider.select((s) => s.selectedTheme));

    return Scaffold(
      backgroundColor: selectedTheme == 2
          ? const Color(0xff101828)
          : Colors.white,

      body: Stack(
        children: [

          /// 📖 FULL PAGE VIEW
          PageView.builder(
            controller: _pageController,
            itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (_, i) => _buildPage(i),
          ),

          /// 🔝 HEADER
          Column(
            children: [
              Padding(
                padding:  EdgeInsets.only(left: 10,right: 16,top: 40,),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child:  Icon(Icons.arrow_back, color: selectedTheme ==0?Colors.black:selectedTheme ==1?Colors.black:Colors.white,),
                    ),
                    const SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        widget.surah.name,
                        style:  TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: selectedTheme ==0?Colors.black:selectedTheme ==1?Colors.black:Colors.white,
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
                    GestureDetector(
                        onTap: (){
                          // showSettingsBottomSheet( context,audioUrls: widget.surah.audioUrls,
                          //   reciterNames: reciterNames,
                          //   downloadAndPlay: _downloadAndPlay,
                          //   getLocalFile: _getLocalFile,
                          //   playAudio: _playAudio,);

                        },
                        child: Icon(Icons.settings,color: selectedTheme ==0?Colors.black:selectedTheme ==1?Colors.black:Colors.white,)),


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
                      style: TextStyle(fontWeight: FontWeight.bold,color: selectedTheme ==0?Colors.black:selectedTheme ==1?Colors.black:Colors.white,),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        value: 2,
                        strokeWidth: 4,
                        backgroundColor:selectedTheme ==0?Colors.grey.withOpacity(0.25):Colors.white,
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
              Text(widget.surah.arName,style: TextStyle(fontSize: 24,fontWeight: FontWeight.w600),),
              SizedBox(height: 32),
            ],
          ),

          /// 📊 PAGE + GOAL
          Positioned(
            bottom: bottomPlayer.visible ? 120 : 40,
            left: 16,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "Page ${_currentPage + 1}/${_pages.length}\n"
                    "${(dailyProgress.listenedSeconds / 60).floor()} / ${dailyProgress.goalMinutes} min",
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),

          /// 🔻 PLAYER
          if (bottomPlayer.visible)
            Positioned(
                bottom: 50,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9CFB5), // beige color like design
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
                      /// ▶️ Play Button
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
                              color: Color(0xFF2F3A4A), // dark circle
                            ),
                            child: IconButton(
                              onPressed: () async {
                                final player = ref.read(audioPlayerProvider);
                                if (isPlaying) {
                                  await player.pause();
                                } else {
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
                    ],
                  ),
                ))

        ],
      ),
    );
  }

  /// ================= PAGE =================
  Widget _buildPage(int index) {
    final pageAyahs = _pages[index];
    final highlighted = ref.watch(highlightedAyahProvider);
    final theme =
    ref.watch(settingsProvider.select((s) => s.selectedTheme));

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 200, 20, 80),
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage(
            theme == 0
                ? "assets/image/white_quran_back_ground.png"
                : theme == 1
                ? "assets/image/paper_theme.png"
                : "assets/image/black_theme.png",
          ),
          fit: BoxFit.cover,
        ),
      ),
      child: RichText(
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.justify,
        text: TextSpan(
          children: pageAyahs.map((a) {
            final i = widget.surah.ayahs.indexOf(a);
            final isH = i == highlighted;
            final id = a.ayah;

            return TextSpan(children: [
              TextSpan(
                text: "${a.arabic} ",
                style: TextStyle(
                  fontSize: isH ? 34 : 32,
                  height: 1.8,
                  fontWeight:
                  isH ? FontWeight.bold : FontWeight.normal,
                  color: isH
                      ? const Color(0xff2F7D33)
                      : (theme == 2
                      ? Colors.white
                      : Colors.black),
                ),
              ),
              WidgetSpan(child:        Stack(
                children: [
                  SizedBox(
                    height: 35,
                    width: 35,
                    child: SvgPicture.asset(
                      "assets/icon/sura_icon_1.svg",
                      colorFilter: ColorFilter.mode(Color(0xff2F7D33), BlendMode.srcIn),
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
                        color: Color(0xff2F7D33)
                    ),
                  ),
                ],
              ),),
              TextSpan(text: " ", style: TextStyle(fontSize: isH ? 34 : 32, height: 1.8)),
              // WidgetSpan(
              //   child: GestureDetector(
              //     onTap: () => _onAyahTap(i),
              //     child: Container(
              //       margin: const EdgeInsets.symmetric(horizontal: 4),
              //       padding: const EdgeInsets.all(6),
              //       decoration: BoxDecoration(
              //         shape: BoxShape.circle,
              //         border: Border.all(color: Colors.grey),
              //       ),
              //       child: Text(toArabicNumber(a.ayah)),
              //     ),
              //   ),
              // ),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  /// ================= TAP =================
  void _onAyahTap(int index) async {
    final player = ref.read(audioPlayerProvider);
    final url = ref.read(currentReciterProvider);

    if (url == null) return;

    final file = await _getLocalFile(url);

    if (await file.exists()) {
      _playAudio(file.path, url, index);
    }
  }

  /// ================= FILE =================
  Future<File> _getLocalFile(String url) async {
    final dir = await getApplicationDocumentsDirectory();
    final filename = "${sha1.convert(utf8.encode(url))}.mp3";
    return File('${dir.path}/$filename');
  }

  String toArabicNumber(int number) {
    const arabic = ['٠','١','٢','٣','٤','٥','٦','٧','٨','٩'];
    return number.toString().split('').map((e)=>arabic[int.parse(e)]).join();
  }
}