import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reciter_project/common/custom_text.dart';
import 'package:reciter_project/screen/widget/reciter_select_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../model/settings_view_model.dart';

class SettingsBottomSheet extends ConsumerStatefulWidget {
  const SettingsBottomSheet({
    super.key,
    required this.audioUrls,
    required this.reciterNames,
    required this.downloadAndPlay,
    required this.getLocalFile,
    required this.playAudio,
  });

  final List<String> audioUrls;
  final List<String> reciterNames;

  final Future<void> Function(String url, String name) downloadAndPlay;
  final Future<File> Function(String url) getLocalFile;
  final Function(String path, String url) playAudio;

  @override
  ConsumerState<SettingsBottomSheet> createState() =>
      _SettingsBottomSheetState();
}

class _SettingsBottomSheetState
    extends ConsumerState<SettingsBottomSheet> {
  String? selectedReciterName;

  @override
  void initState() {
    super.initState();
    _loadSelectedReciter();
  }

  /// 🔥 Load selected reciter
  Future<void> _loadSelectedReciter() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('saved_reciter');

    if (savedUrl != null) {
      final index = widget.audioUrls.indexOf(savedUrl);
      if (index != -1) {
        setState(() {
          selectedReciterName = widget.reciterNames[index];
        });
      }
    }
  }

  /// 🔥 Navigate & refresh after back
  Future<void> _openReciterScreen(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReciterScreen(
          audioUrls: widget.audioUrls,
          reciterNames: widget.reciterNames,
          downloadAndPlay: widget.downloadAndPlay,
          getLocalFile: widget.getLocalFile,
          playAudio: widget.playAudio,
        ),
      ),
    );

    /// Refresh after returning
    await _loadSelectedReciter();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F5F5),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          24,
          16,
          MediaQuery.of(context).viewInsets.bottom + 50,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            /// Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Settings",
                  style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close),
                )
              ],
            ),

            const SizedBox(height: 16),

            /// Tabs
            Row(
              children: [
                _tab("Display", 0, state, notifier),
                _tab("Text", 1, state, notifier),
                _tab("Audio", 2, state, notifier),
              ],
            ),

            const SizedBox(height: 40),

            if (state.selectedTab == 0) ...[
              _displaySection(state, notifier),
            ] else if (state.selectedTab == 1) ...[
              _textSection(state, notifier),
            ] else if (state.selectedTab == 2) ...[
              _audioSection(state, notifier, context),
            ],
          ],
        ),
      ),
    );
  }

  /// ================= AUDIO SECTION =================
  Widget _audioSection(
      SettingsState state, SettingsNotifier notifier, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title("Quran Reciter"),
        const SizedBox(height: 20),

        GestureDetector(
          onTap: () => _openReciterScreen(context),

          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xffE5E7EB),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomText(
                      text: "Select Reciter",
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                    const SizedBox(height: 8),

                    /// 🔥 Dynamic Reciter Name
                    CustomText(
                      text: selectedReciterName ?? "Select Reciter",
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xff6A7282),
                    ),
                  ],
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              ],
            ),
          ),
        ),

        const SizedBox(height: 300),
      ],
    );
  }

  /// ================= COMMON WIDGETS =================

  Widget _tab(String text, int index, SettingsState state,
      SettingsNotifier notifier) {
    final selected = state.selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => notifier.setTab(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.green : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(
              color: selected ? Colors.white : Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text,
          style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }


  Widget _displaySection(SettingsState state, SettingsNotifier notifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title("Themes"),
        const SizedBox(height: 10),
        Row(
          children: [
            _theme("Modern", Colors.white, Colors.black, 0, state, notifier),
            const SizedBox(width: 10),
            _theme("Paper", Colors.white, Colors.green, 1, state, notifier),
            const SizedBox(width: 10),
            _theme("Dark", const Color(0xFF0D1B2A), Colors.white, 2, state, notifier),
          ],
        ),

        SizedBox(height: 40),

        /// Slider
        _title("Text Size"),
        Slider(
          value: state.textSize,
          onChanged: notifier.setTextSize,
          activeColor: Colors.green,
        ),

        const SizedBox(height: 20),

        /// Reading Mode
        _title("Reading mode"),
        SizedBox(height: 10,),
        Row(
          children: [
            _reading("List", Icons.menu, 0, state, notifier),
            const SizedBox(width: 10),
            _reading("Page", Icons.menu_book, 1, state, notifier),
          ],
        ),

        const SizedBox(height: 40),

        /// Switch
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Keep screen on while reading"),
            value: state.keepScreenOn,
            activeColor: Colors.green,
            onChanged: notifier.toggleScreen,
          ),
        ),
      ],
    );
  }

  Widget _textSection(SettingsState state, SettingsNotifier notifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [


        _title("Script Options"),
        SizedBox(height: 20),

        Row(
          children: [
            _readingIndoPak("IndoPak", Icons.menu, 0, state, notifier, "اَلْقُرْآنُ الْكَرِيمُ"),
            const SizedBox(width: 20),
            _readingIndoPak("Uthmani", Icons.menu_book, 1, state, notifier, "الْقُرْآنُ الْكَرِيمُ"),
          ],
        ),

        const SizedBox(height: 30),
        _title("Translation"),
        SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Show Translation"),
            value: state.keepScreenOn,
            activeColor: Colors.green,
            onChanged: notifier.toggleScreen,
          ),
        ),
        SizedBox(height: 200,)
      ],
    );
  }




  Widget _theme(String title, Color bg, Color txt, int index,
      SettingsState state, SettingsNotifier notifier) {
    final selected = state.selectedTheme == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => notifier.setTheme(index),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Colors.green : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Text("بِسْمِ ٱللّٰهِ", style: TextStyle(color: txt)),
              const SizedBox(height: 6),
              Text(title,style: TextStyle(color:txt)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reading(String title, IconData icon, int index,
      SettingsState state, SettingsNotifier notifier) {
    final selected = state.readingMode == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => notifier.setReadingMode(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? Colors.green.withOpacity(0.1) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Colors.green : Colors.grey.shade300,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? Colors.green : Colors.black),
              const SizedBox(height: 6),
              Text(title),
            ],
          ),
        ),
      ),
    );
  }

  Widget _readingIndoPak(
      String title,
      IconData icon,
      int index,
      SettingsState state,
      SettingsNotifier notifier,
      String arabic,
      ) {
    final selected = state.readingMode == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => notifier.setReadingMode(index),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center, // ✅ important
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
                width: double.infinity, // ✅ fill full width
                height: 85,
                padding: const EdgeInsets.symmetric(vertical: 14,horizontal: 16),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.green.withOpacity(0.1)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: selected ? Colors.green : Colors.grey.shade300,
                  ),
                ),
                child: Center(child: CustomText(text:arabic, color: selected ? Colors.green : Colors.black,fontWeight: selected?FontWeight.w700:FontWeight.w500,),
                )),

            const SizedBox(height: 6),

            // 🔥 OPTIONAL: remove if duplicate
            CustomText(
              text: title,
              fontSize: 14,
              fontWeight: FontWeight.w400,
              textAlign: TextAlign.center, // ✅ better alignment
            ),
          ],
        ),
      ),
    );
  }



/// Keep your other methods (_displaySection, _textSection, etc.) unchanged
}