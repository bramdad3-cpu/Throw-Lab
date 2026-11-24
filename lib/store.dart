import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'core.dart';

/// Everything is kept in one JSON file on the phone.
class AppStore extends ChangeNotifier {
  final Map<String, Athlete> athletes = {};
  final Map<String, Session> sessions = {};
  AppSettings settings = AppSettings();
  File? _file;
  Timer? _saveTimer;
  bool loaded = false;

  Future<void> load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/throwlab.json');
      if (await _file!.exists()) {
        final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        for (final a in (j['athletes'] as List? ?? const [])) {
          final x = Athlete.fromJson(Map<String, dynamic>.from(a as Map));
          athletes[x.id] = x;
        }
        for (final s in (j['sessions'] as List? ?? const [])) {
          final x = Session.fromJson(Map<String, dynamic>.from(s as Map));
          sessions[x.id] = x;
        }
        if (j['settings'] is Map) {
          settings = AppSettings.fromJson(Map<String, dynamic>.from(j['settings'] as Map));
        }
      }
    } catch (e) {
      debugPrint('load failed: $e');
    }
    loaded = true;
    notifyListeners();
  }

  void changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), saveNow);
  }

  Future<void> saveNow() async {
    final f = _file;
    if (f == null) return;
    final data = jsonEncode({
      'version': 1,
      'athletes': athletes.values.map((a) => a.toJson()).toList(),
      'sessions': sessions.values.map((s) => s.toJson()).toList(),
      'settings': settings.toJson(),
    });
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(f.path);
  }

  List<Athlete> athleteList() {
    final l = athletes.values.toList();
    l.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return l;
  }

  List<Session> sessionsFor(String athleteId) {
    final l = sessions.values.where((s) => s.athleteId == athleteId).toList();
    l.sort((a, b) {
      final c = b.date.compareTo(a.date);
      return c != 0 ? c : b.created.compareTo(a.created);
    });
    return l;
  }

  void saveAthlete(Athlete a) {
    athletes[a.id] = a;
    changed();
  }

  void deleteAthlete(String id) {
    athletes.remove(id);
    sessions.removeWhere((k, s) => s.athleteId == id);
    if (settings.athleteMode == id) settings.athleteMode = null;
    changed();
  }

  void saveSession(Session s) {
    sessions[s.id] = s;
    changed();
  }

  void deleteSession(String id) {
    sessions.remove(id);
    changed();
  }
}

final store = AppStore();
