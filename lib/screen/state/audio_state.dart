import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../model/user_reciter_model.dart';

final audioControllerProvider =
StateNotifierProvider<AudioController, AudioState>((ref) {
  return AudioController();
});

class AudioState {
  final bool isPlaying;
  final int currentAyahIndex;
  final Duration position;

  AudioState({
    this.isPlaying = false,
    this.currentAyahIndex = 0,
    this.position = Duration.zero,
  });

  AudioState copyWith({
    bool? isPlaying,
    int? currentAyahIndex,
    Duration? position,
  }) {
    return AudioState(
      isPlaying: isPlaying ?? this.isPlaying,
      currentAyahIndex: currentAyahIndex ?? this.currentAyahIndex,
      position: position ?? this.position,
    );
  }
}

class AudioController extends StateNotifier<AudioState> {
  AudioController() : super(AudioState());

  final AudioPlayer _player = AudioPlayer();

  Future<void> playSurah({
    required List<String> audioUrls,
    required List<Ayah> ayahs,
  }) async {
    try {
      await _player.setUrl(audioUrls.first);

      _player.positionStream.listen((position) {
        int index = _findCurrentAyah(position, ayahs);
        state = state.copyWith(
          position: position,
          currentAyahIndex: index,
        );
      });

      _player.play();
      state = state.copyWith(isPlaying: true);
    } catch (e) {
      print("Error: $e");
    }
  }

  void pause() {
    _player.pause();
    state = state.copyWith(isPlaying: false);
  }

  int _findCurrentAyah(Duration position, List<Ayah> ayahs) {
    for (int i = 0; i < ayahs.length; i++) {
      final timing = ayahs[i].timings;
      if (timing != null && timing.isNotEmpty) {
        double? start = timing.first?.first.toDouble();
        double? end = timing.last?.last;

        if (position.inMilliseconds >= start! &&
            position.inMilliseconds <= end!) {
          return i;
        }
      }
    }
    return 0;
  }
}