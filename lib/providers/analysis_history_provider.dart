import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/analysis_history_entry.dart';
import '../models/video_metadata.dart';

class AnalysisHistoryProvider extends ChangeNotifier {
  AnalysisHistoryProvider() {
    _ready = _load();
  }

  static const _storageKey = 'analysis_history_v1';
  static const _maximumEntries = 20;

  final List<AnalysisHistoryEntry> _entries = [];
  late final Future<void> _ready;

  List<AnalysisHistoryEntry> get entries => List.unmodifiable(_entries);
  Future<void> get ready => _ready;

  Future<void> add(VideoMetadata metadata) async {
    await _ready;
    _entries.removeWhere((entry) => entry.originalUrl == metadata.originalUrl);
    _entries.insert(
      0,
      AnalysisHistoryEntry.fromMetadata(metadata, analyzedAt: DateTime.now()),
    );
    if (_entries.length > _maximumEntries) {
      _entries.removeRange(_maximumEntries, _entries.length);
    }
    await _save();
    notifyListeners();
  }

  Future<void> remove(String originalUrl) async {
    await _ready;
    _entries.removeWhere((entry) => entry.originalUrl == originalUrl);
    await _save();
    notifyListeners();
  }

  Future<void> clear() async {
    await _ready;
    _entries.clear();
    await _save();
    notifyListeners();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final values = jsonDecode(raw) as List<dynamic>;
      _entries
        ..clear()
        ..addAll(
          values.whereType<Map<String, dynamic>>().map(
            AnalysisHistoryEntry.fromJson,
          ),
        );
      // Rewrite legacy entries immediately so temporary signed CDN URLs do
      // not remain in local preferences until the next analysis. Only legacy
      // entries carry the nested `metadata` object; rewriting an already
      // compact store re-encoded the whole list and wrote preferences on every
      // app start for no gain.
      final hasLegacyEntries = values.any(
        (value) => value is Map<String, dynamic> && value['metadata'] is Map,
      );
      if (hasLegacyEntries) await _save();
    } catch (_) {
      await prefs.remove(_storageKey);
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(_entries.map((entry) => entry.toJson()).toList()),
    );
  }
}
