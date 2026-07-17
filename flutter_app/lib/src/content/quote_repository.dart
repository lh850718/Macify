import 'dart:convert';

import 'package:flutter/services.dart';

abstract class QuoteRepository {
  Future<List<QuoteItem>> load();
}

class AssetQuoteRepository implements QuoteRepository {
  const AssetQuoteRepository({this.assetPath = 'assets/content/quotes.json'});

  final String assetPath;

  @override
  Future<List<QuoteItem>> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .map((item) => QuoteItem.fromJson(_jsonMap(item)))
        .where((item) => item.content.isNotEmpty)
        .toList(growable: false);
  }
}

class QuoteItem {
  const QuoteItem({required this.content, required this.author});

  final String content;
  final String author;

  factory QuoteItem.fromJson(Map<String, Object?> json) {
    return QuoteItem(
      content: _stringValue(json['content']),
      author: _stringValue(json['author']),
    );
  }
}

Map<String, Object?> _jsonMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

String _stringValue(Object? value) => value == null ? '' : value.toString();
