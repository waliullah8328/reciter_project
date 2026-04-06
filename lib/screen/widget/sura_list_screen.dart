// screen/surah_list_screen.dart

import 'package:flutter/cupertino.dart';
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
    final currentGoal = ref.read(goalProvider); // for selection highlight

    showCupertinoModalPopup(
      context: context,
      builder: (context) {
        return CupertinoPopupSurface(
          isSurfacePainted: true,
          child: Container(
            padding: const EdgeInsets.only(bottom: 16, top: 10),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  /// 🔹 Drag Handle
                  Container(
                    width: 36,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemGrey3,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),

                  /// 🔹 Title
                  const Text(
                    "Goal Time",
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 6),

                  const Text(
                    "Choose your daily goal",
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),

                  const SizedBox(height: 16),

                  /// 🔹 Options Card
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: CupertinoColors.secondarySystemGroupedBackground,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: goalOptions.map((min) {
                        final isSelected = currentGoal == min;

                        return Column(
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () async {
                                await ref
                                    .read(goalProvider.notifier)
                                    .setGoal(min);
                                Navigator.pop(context);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14, horizontal: 16),
                                child: Row(
                                  mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "$min minutes",
                                      style: const TextStyle(fontSize: 16),
                                    ),

                                    /// ✅ Selected checkmark
                                    if (isSelected)
                                      const Icon(
                                        CupertinoIcons.check_mark,
                                        size: 18,
                                        color: CupertinoColors.activeBlue,
                                      ),
                                  ],
                                ),
                              ),
                            ),

                            /// Divider (iOS style)
                            if (min != goalOptions.last)
                              const Divider(
                                height: 1,
                                thickness: 0.5,
                                color: CupertinoColors.separator,
                              ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 14),

                  /// 🔹 Cancel Button (separate iOS block)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      borderRadius: BorderRadius.circular(14),
                      color:
                      CupertinoColors.secondarySystemGroupedBackground,
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        "Cancel",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

          return ListView.separated(
            separatorBuilder: (context, index) => SizedBox(height: 8),

            itemCount: surahs.length,
            itemBuilder: (context, index) {
              final surah = surahs[index];

              return Padding(
                padding: const EdgeInsets.only(left: 16,right: 16),
                child: Container(
                  padding: EdgeInsets.all(8),


                  decoration: BoxDecoration(
                    color: Color(0xffF4F2FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: Text("${index+1}",style: TextStyle(fontSize: 16,fontWeight: FontWeight.w500),),
                    title: Text(surah.arName ?? '',style: TextStyle(fontSize: 16,fontWeight: FontWeight.w500),),

                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(surah.name?? '',style: TextStyle(fontSize: 14,fontWeight: FontWeight.w500),),
                        Text(surah.revelationPlace?? '',style: TextStyle(fontSize: 12,fontWeight: FontWeight.w400,color: Colors.grey),),
                      ],
                    ),

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
                  ),
                ),
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