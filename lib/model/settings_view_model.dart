import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsState {
  final int selectedTab;
  final int selectedTheme;
  final int readingMode;
  final bool keepScreenOn;
  final double textSize;

  SettingsState({
    this.selectedTab = 0,
    this.selectedTheme = 1,
    this.readingMode = 0,
    this.keepScreenOn = true,
    this.textSize = 0.5,
  });

  SettingsState copyWith({
    int? selectedTab,
    int? selectedTheme,
    int? readingMode,
    bool? keepScreenOn,
    double? textSize,
  }) {
    return SettingsState(
      selectedTab: selectedTab ?? this.selectedTab,
      selectedTheme: selectedTheme ?? this.selectedTheme,
      readingMode: readingMode ?? this.readingMode,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      textSize: textSize ?? this.textSize,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(SettingsState());

  void setTab(int index) {
    state = state.copyWith(selectedTab: index);
  }

  void setTheme(int index) {
    state = state.copyWith(selectedTheme: index);
  }

  void setReadingMode(int index) {
    state = state.copyWith(readingMode: index);
  }

  void toggleScreen(bool value) {
    state = state.copyWith(keepScreenOn: value);
  }

  void setTextSize(double value) {
    state = state.copyWith(textSize: value);
  }
}

final settingsProvider =
StateNotifierProvider<SettingsNotifier, SettingsState>(
        (ref) => SettingsNotifier());