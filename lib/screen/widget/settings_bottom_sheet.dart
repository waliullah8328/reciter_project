import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/settings_view_model.dart';

class SettingsBottomSheet extends ConsumerWidget {
  const SettingsBottomSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

            /// Themes
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
        ),
      ),
    );
  }

  /// Widgets

  Widget _tab(String text, int index, SettingsState state, SettingsNotifier notifier) {
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
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
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
}