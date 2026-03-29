// screen/surah_list_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reciter_project/screen/widget/sura_details_screen.dart';
import 'package:reciter_project/screen/widget/bookmarks_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../view_model/reciter_view_model.dart';

// ------------------- 1. Goal Provider with persistence -------------------
class GoalNotifier extends StateNotifier<int?> {
  GoalNotifier() : super(null) {
    _loadGoal();
  }

  Future<void> _loadGoal() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt('goal');
  }

  Future<void> setGoal(int min) async {
    state = min;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('goal', min);
  }
}

final goalProvider = StateNotifierProvider<GoalNotifier, int?>((ref) {
  return GoalNotifier();
});

// ------------------- 2. SurahListScreen -------------------
class SurahListScreen extends ConsumerWidget {
  const SurahListScreen({super.key});

  // ------------------- Goal Dialog -------------------
  Future<void> _showGoalDialog(BuildContext context, WidgetRef ref) async {
    final goalOptions = [5, 10, 15];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text("Select Goal Time"),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          content: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: goalOptions.map((min) {
              return SizedBox(
                width: 90,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () async {
                    await ref.read(goalProvider.notifier).setGoal(min);
                    Navigator.pop(context);
                  },
                  child: Text("$min min"),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quranAsync = ref.watch(quranProvider1);
    final goal = ref.watch(goalProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          goal != null ? 'Surahs ($goal min goal)' : 'Surahs',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark),
            onPressed: () {
              quranAsync.when(
                data: (data) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BookmarksScreen(model: data),
                    ),
                  );
                },
                loading: () {},
                error: (_, __) {},
              );
            },
          ),
        ],
      ),
      body: quranAsync.when(
        data: (data) {
          final surahs = data.surahs ?? [];

          return ListView.builder(
            itemCount: surahs.length,
            itemBuilder: (context, index) {
              final surah = surahs[index];

              return ListTile(
                title: Text(surah.name ?? ''),
                subtitle: Text(surah.arName ?? ''),
                trailing: Text("${surah.totalAyahs} Ayahs"),

                // ---------------- Tap Logic ----------------
                onTap: () async {
                  // Show goal dialog if not selected
                  if (goal == null) {
                    await _showGoalDialog(context, ref);
                  }

                  final updatedGoal = ref.read(goalProvider);

                  // Navigate only if goal selected
                  if (updatedGoal != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SurahDetailScreen(
                          surah: surah,
                          allSurahs: surahs,
                          surahIndex: index,
                        ),
                      ),
                    );
                  }
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          debugPrint(e.toString());
          return Center(child: Text(e.toString()));
        },
      ),
    );
  }
}