import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../model/user_reciter_model.dart';


Future<UserReciterModel> loadQuranFromJson() async {
  final String jsonString =
  await rootBundle.loadString('assets/json/reciter_2.json');
  final Map<String, dynamic> jsonData = json.decode(jsonString);
  return UserReciterModel.fromJson(jsonData);
}

final quranProvider1 =
FutureProvider<UserReciterModel>((ref) async => loadQuranFromJson());