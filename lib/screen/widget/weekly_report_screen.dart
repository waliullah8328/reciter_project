// WeeklyReportScreen remains same as previous

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      appBar: AppBar(title: const Text("7-Day Progress")),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: entries.map((entry) {
            final minutes = (entry.value / 60).toStringAsFixed(1);
            final percentage = ((entry.value / (_dailyGoal * 60) * 100).clamp(
              0.0,
              100.0,
            )).toDouble();
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                title: Text(entry.key),
                subtitle: LinearProgressIndicator(value: percentage / 100),
                trailing: Text(
                  "${minutes} min (${percentage.toStringAsFixed(0)}%)",
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}