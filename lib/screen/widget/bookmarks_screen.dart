import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reciter_project/model/user_reciter_model.dart';
import 'package:reciter_project/screen/widget/sura_details_screen.dart';

class BookmarksScreen extends ConsumerWidget {
  final UserReciterModel model;

  const BookmarksScreen({super.key, required this.model});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(bookmarksProvider);

    if (bookmarks.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bookmarks')),
        body: const Center(
          child: Text('No bookmarks yet'),
        ),
      );
    }

    // Group bookmarks by surah
    Map<int, List<Bookmark>> groupedBysurah = {};
    for (var bookmark in bookmarks) {
      if (!groupedBysurah.containsKey(bookmark.suraId)) {
        groupedBysurah[bookmark.suraId] = [];
      }
      groupedBysurah[bookmark.suraId]!.add(bookmark);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body: ListView.builder(
        itemCount: groupedBysurah.length,
        itemBuilder: (context, index) {
          final suraId = groupedBysurah.keys.toList()[index];
          final surah = model.surahs.firstWhere((s) => s.id == suraId);
          final suraBookmarks = groupedBysurah[suraId]!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Surah Header
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.orange.shade100,
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SurahDetailScreen(surah: surah),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${surah.id}. ${surah.name}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Surah ${surah.id} - ${suraBookmarks.length} bookmark${suraBookmarks.length > 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward, color: Colors.orange),
                    ],
                  ),
                ),
              ),

              // Bookmarked Ayahs
              ...suraBookmarks.map((bookmark) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.orange, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Ayah number and text
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${bookmark.ayahId}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  bookmark.arabicText,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  bookmark.englishText,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Action buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Go to surah button
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SurahDetailScreen(surah: surah),
                                ),
                              );
                            },
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Go to Surah'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),

                          const SizedBox(width: 8),

                          // Remove bookmark button
                          OutlinedButton.icon(
                            onPressed: () {
                              ref.read(bookmarksProvider.notifier).toggle(
                                bookmark.suraId,
                                bookmark.ayahId,
                                bookmark.arabicText,
                                bookmark.englishText,
                              );
                            },
                            icon: const Icon(Icons.delete, size: 16),
                            label: const Text('Remove'),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),

              const SizedBox(height: 12),
            ],
          );
        },
      ),
    );
  }
}

