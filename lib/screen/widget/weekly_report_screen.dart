import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class WeeklyReportScreen extends StatefulWidget {
  const WeeklyReportScreen({super.key});

  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  Map<String, int> _weeklyData = {};
  int _dailyGoal = 5;

  @override
  void initState() {
    super.initState();
    _loadWeeklyData();
  }

  Future<void> _loadWeeklyData() async {
    final prefs = await SharedPreferences.getInstance();
    _dailyGoal = prefs.getInt('goal') ?? 5;

    final now = DateTime.now();
    final Map<String, int> data = {};

    for (int i = 0; i < 7; i++) {
      final day = now.subtract(Duration(days: i));
      final key = "${day.year}-${day.month}-${day.day}";
      data[key] = prefs.getInt(key) ?? 0;
    }

    setState(() {
      _weeklyData = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _weeklyData.entries.toList();
    entries.sort((a, b) => b.key.compareTo(a.key));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text(
          "Weekly Progress",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            /// 🔥 TODAY CARD (BIG + MODERN)
            _buildTodayCard(entries.first),

            const SizedBox(height: 20),

            /// 🔥 LAST 6 DAYS
            Expanded(
              child: ListView.builder(
                itemCount: entries.length - 1,
                itemBuilder: (context, index) {
                  final entry = entries[index + 1];
                  return _buildDayCard(entry);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ================= TODAY =================
  Widget _buildTodayCard(MapEntry<String, int> entry) {
    final minutes = (entry.value / 60);
    final percentage =
    (entry.value / (_dailyGoal * 60)).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Today",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),

          Text(
            "${minutes.toStringAsFixed(1)} min",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          LinearProgressIndicator(
            value: percentage,
            minHeight: 8,
            borderRadius: BorderRadius.circular(10),
            backgroundColor: Colors.white24,
            valueColor:
            const AlwaysStoppedAnimation<Color>(Colors.white),
          ),

          const SizedBox(height: 8),

          Text(
            "${(percentage * 100).toStringAsFixed(0)}% of goal",
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  /// ================= DAY CARD =================
  Widget _buildDayCard(MapEntry<String, int> entry) {
    final date = _parseDate(entry.key);
    final minutes = (entry.value / 60);
    final percentage =
    (entry.value / (_dailyGoal * 60)).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          /// DATE
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat.E().format(date), // Mon, Tue
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                DateFormat.d().format(date), // 12
                style: const TextStyle(
                  color: Colors.grey,
                ),
              ),
            ],
          ),

          const SizedBox(width: 16),

          /// PROGRESS
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: percentage,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(10),
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Colors.green,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "${minutes.toStringAsFixed(1)} min",
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          /// %
          Text(
            "${(percentage * 100).toStringAsFixed(0)}%",
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// ================= HELPER =================
  DateTime _parseDate(String key) {
    final parts = key.split("-");
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }
}