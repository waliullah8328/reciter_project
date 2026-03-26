// screen/surah_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reciter_project/screen/widget/sura_details_screen.dart';
import '../../view_model/reciter_view_model.dart';


class SurahListScreen extends ConsumerWidget {
  const SurahListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quranAsync = ref.watch(quranProvider1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Surahs'),
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
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SurahDetailScreen(surah: surah),
                    ),
                  );
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _){
          debugPrint(e.toString());
          return
            Center(child: Text(e.toString()));

        },
      ),
    );
  }
}