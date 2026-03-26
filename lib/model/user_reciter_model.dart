// models/user_reciter_model.dart
import 'dart:convert';

UserReciterModel userReciterModelFromJson(String str) =>
    UserReciterModel.fromJson(json.decode(str));

String userReciterModelToJson(UserReciterModel data) =>
    json.encode(data.toJson());

class UserReciterModel {
  final List<Reciter> reciters;
  final int totalReciters;
  final int totalSurahs;
  final List<Surah> surahs;

  UserReciterModel({
    required this.reciters,
    required this.totalReciters,
    required this.totalSurahs,
    required this.surahs,
  });

  factory UserReciterModel.fromJson(Map<String, dynamic> json) =>
      UserReciterModel(
        reciters: (json["reciters"] as List<dynamic>?)
            ?.map((x) => Reciter.fromJson(x))
            .toList() ??
            [],
        totalReciters: json["total_reciters"] ?? 0,
        totalSurahs: json["total_surahs"] ?? 0,
        surahs: (json["surahs"] as List<dynamic>?)
            ?.map((x) => Surah.fromJson(x))
            .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
    "reciters": reciters.map((x) => x.toJson()).toList(),
    "total_reciters": totalReciters,
    "total_surahs": totalSurahs,
    "surahs": surahs.map((x) => x.toJson()).toList(),
  };
}

class Reciter {
  final int id;
  final int externalId;
  final String name;
  final String arName;
  final String country;
  final String imageUrl;

  Reciter({
    required this.id,
    required this.externalId,
    required this.name,
    required this.arName,
    required this.country,
    required this.imageUrl,
  });

  factory Reciter.fromJson(Map<String, dynamic> json) => Reciter(
    id: json["id"] ?? 0,
    externalId: json["external_id"] ?? 0,
    name: json["name"] ?? "",
    arName: json["ar_name"] ?? "",
    country: json["country"] ?? "",
    imageUrl: json["image_url"] ?? "",
  );

  Map<String, dynamic> toJson() => {
    "id": id,
    "external_id": externalId,
    "name": name,
    "ar_name": arName,
    "country": country,
    "image_url": imageUrl,
  };
}

class Surah {
  final int id;
  final String name;
  final String arName;
  final List<String> audioUrls;
  final List<Ayah> ayahs;
  final String revelationPlace;
  final int totalAyahs;

  Surah({
    required this.id,
    required this.name,
    required this.arName,
    required this.audioUrls,
    required this.ayahs,
    required this.revelationPlace,
    required this.totalAyahs,
  });

  factory Surah.fromJson(Map<String, dynamic> json) => Surah(
    id: json["id"] ?? 0,
    name: json["name"] ?? "",
    arName: json["ar_name"] ?? "",
    audioUrls: (json["audio_urls"] as List<dynamic>?)
        ?.map((x) => x?.toString() ?? "")
        .toList() ??
        [],
    ayahs: (json["ayahs"] as List<dynamic>?)
        ?.map((x) => Ayah.fromJson(x))
        .toList() ??
        [],
    revelationPlace: json["revelation_place"] ?? "",
    totalAyahs: json["total_ayahs"] ?? 0,
  );

  Map<String, dynamic> toJson() => {
    "id": id,
    "name": name,
    "ar_name": arName,
    "audio_urls": audioUrls,
    "ayahs": ayahs.map((x) => x.toJson()).toList(),
    "revelation_place": revelationPlace,
    "total_ayahs": totalAyahs,
  };
}

class Ayah {
  final int ayah;
  final String english;
  final String arabic;
  final List<List<double>> timings;
  final String uthmani;
  final String indopak;

  Ayah({
    required this.ayah,
    required this.english,
    required this.arabic,
    required this.timings,
    required this.uthmani,
    required this.indopak,
  });

  factory Ayah.fromJson(Map<String, dynamic> json) {
    final rawTimings = json["timings"];
    List<List<double>> safeTimings = [];

    if (rawTimings != null && rawTimings is List) {
      safeTimings = rawTimings.map<List<double>>((inner) {
        if (inner == null || inner is! List) return [];
        return inner.map<double>((e) {
          if (e == null) return 0;
          if (e is int) return e.toDouble();
          if (e is double) return e;
          return double.tryParse(e.toString()) ?? 0;
        }).toList();
      }).toList();
    }

    return Ayah(
      ayah: json["ayah"] ?? 0,
      english: json["english"] ?? "",
      arabic: json["arabic"] ?? "",
      timings: safeTimings,
      uthmani: json["uthmani"] ?? "",
      indopak: json["indopak"] ?? "",
    );
  }

  Map<String, dynamic> toJson() => {
    "ayah": ayah,
    "english": english,
    "arabic": arabic,
    "timings": timings.map((inner) => inner.map((e) => e).toList()).toList(),
    "uthmani": uthmani,
    "indopak": indopak,
  };
}