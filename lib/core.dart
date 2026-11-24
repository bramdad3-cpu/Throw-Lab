import 'dart:math' as math;
import 'dart:typed_data';

const double soundFtPerSec = 1125.0;
const double ftPerSecToMph = 3600.0 / 5280.0;

String newId() =>
    DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
    math.Random().nextInt(1 << 30).toRadixString(36);

String fmtNum(double? v, int d) =>
    (v == null || v.isNaN || v.isInfinite) ? '—' : v.toStringAsFixed(d);

String isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String prettyDate(String iso) {
  final p = iso.split('-');
  if (p.length != 3) return iso;
  final m = int.tryParse(p[1]) ?? 1;
  return '${_months[(m - 1).clamp(0, 11)]} ${int.tryParse(p[2]) ?? p[2]}, ${p[0]}';
}

/* ------------------------------------------------------------------ drills */

class Drill {
  final String key, label, short, kind, base;
  const Drill(this.key, this.label, this.short, this.kind, this.base);
}

const Map<String, Drill> drills = {
  'C-1B': Drill('C-1B', 'Catcher → 1st', 'C → 1B', 'throw', '1B'),
  'C-2B': Drill('C-2B', 'Catcher → 2nd', 'C → 2B', 'throw', '2B'),
  'C-3B': Drill('C-3B', 'Catcher → 3rd', 'C → 3B', 'throw', '3B'),
  'H-NET': Drill('H-NET', 'Exit velo — tee into net', 'Tee/net', 'net', 'NET'),
};

Drill drillOf(String key) => drills[key] ?? drills['C-2B']!;

class MetricDef {
  final String label, unit;
  final int decimals;
  final bool lowerIsBetter;
  const MetricDef(this.label, this.unit, this.decimals, this.lowerIsBetter);
}

const Map<String, MetricDef> metricDefs = {
  'pop': MetricDef('Pop time', 's', 2, true),
  'ev': MetricDef('Exit velo', 'mph', 1, false),
  'time': MetricDef('Time to net', 's', 3, true),
};

const Map<String, List<String>> kindMetrics = {
  'throw': ['pop'],
  'net': ['ev', 'time'],
};
const Map<String, String> primaryMetric = {'throw': 'pop', 'net': 'ev'};
const List<String> accuracyTags = ['On target', 'High', 'Low', 'Left', 'Right', 'Missed'];

/* ------------------------------------------------------------------ models */

class Cue {
  String drill; // a drill key, 'any', 'throws' or 'hits'
  String metric; // metric key or 'acc'
  String op; // '>' or '<'
  double value;
  String text;
  Cue({this.drill = 'C-2B', this.metric = 'pop', this.op = '>', this.value = 2.0, this.text = ''});
  Map<String, dynamic> toJson() => {'drill': drill, 'metric': metric, 'op': op, 'value': value, 'text': text};
  factory Cue.fromJson(Map<String, dynamic> j) => Cue(
        drill: (j['drill'] ?? 'any') as String,
        metric: (j['metric'] ?? 'pop') as String,
        op: (j['op'] ?? '>') as String,
        value: ((j['value'] ?? 0) as num).toDouble(),
        text: (j['text'] ?? '') as String,
      );
}

class Athlete {
  String id, name, throws, bats, team;
  double? batLength;
  Map<String, Map<String, double>> targets;
  List<Cue> cues;
  Athlete({
    required this.id,
    required this.name,
    this.throws = 'R',
    this.bats = 'R',
    this.team = '',
    this.batLength,
    Map<String, Map<String, double>>? targets,
    List<Cue>? cues,
  })  : targets = targets ?? {},
        cues = cues ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'throws': throws,
        'bats': bats,
        'team': team,
        'batLength': batLength,
        'targets': targets,
        'cues': cues.map((c) => c.toJson()).toList(),
      };

  factory Athlete.fromJson(Map<String, dynamic> j) {
    final t = <String, Map<String, double>>{};
    final rawT = j['targets'];
    if (rawT is Map) {
      rawT.forEach((k, v) {
        if (v is Map) {
          t[k as String] = v.map((kk, vv) => MapEntry(kk as String, (vv as num).toDouble()));
        }
      });
    }
    final rawC = j['cues'];
    return Athlete(
      id: j['id'] as String,
      name: (j['name'] ?? '') as String,
      throws: (j['throws'] ?? 'R') as String,
      bats: (j['bats'] ?? 'R') as String,
      team: (j['team'] ?? '') as String,
      batLength: (j['batLength'] as num?)?.toDouble(),
      targets: t,
      cues: rawC is List ? rawC.map((e) => Cue.fromJson(Map<String, dynamic>.from(e as Map))).toList() : [],
    );
  }
}

class Rep {
  String id;
  double t1, t2; // seconds since listening started (raw, as heard)
  Map<String, double> m; // metrics
  String? accuracy;
  int at; // epoch ms
  Rep({required this.id, required this.t1, required this.t2, required this.m, this.accuracy, required this.at});
  Map<String, dynamic> toJson() => {'id': id, 't1': t1, 't2': t2, 'm': m, 'accuracy': accuracy, 'at': at};
  factory Rep.fromJson(Map<String, dynamic> j) => Rep(
        id: j['id'] as String,
        t1: ((j['t1'] ?? 0) as num).toDouble(),
        t2: ((j['t2'] ?? 0) as num).toDouble(),
        m: ((j['m'] ?? {}) as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
        accuracy: j['accuracy'] as String?,
        at: ((j['at'] ?? 0) as num).toInt(),
      );
}

class Session {
  String id, athleteId, drill, date, phoneAt, notes;
  double distance;
  List<Rep> reps;
  int created;
  Session({
    required this.id,
    required this.athleteId,
    required this.drill,
    required this.date,
    required this.distance,
    this.phoneAt = 'home',
    this.notes = '',
    List<Rep>? reps,
    required this.created,
  }) : reps = reps ?? [];
  String get kind => drillOf(drill).kind;
  Map<String, dynamic> toJson() => {
        'id': id,
        'athleteId': athleteId,
        'drill': drill,
        'date': date,
        'distance': distance,
        'phoneAt': phoneAt,
        'notes': notes,
        'reps': reps.map((r) => r.toJson()).toList(),
        'created': created,
      };
  factory Session.fromJson(Map<String, dynamic> j) => Session(
        id: j['id'] as String,
        athleteId: j['athleteId'] as String,
        drill: (j['drill'] ?? 'C-2B') as String,
        date: (j['date'] ?? '') as String,
        distance: ((j['distance'] ?? 84.85) as num).toDouble(),
        phoneAt: (j['phoneAt'] ?? 'home') as String,
        notes: (j['notes'] ?? '') as String,
        reps: ((j['reps'] ?? []) as List).map((e) => Rep.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        created: ((j['created'] ?? 0) as num).toInt(),
      );
}

class AppSettings {
  Map<String, double> dist;
  bool speak;
  double sensitivity; // trigger = noise floor x this (lower = more sensitive)
  String phoneAt; // 'home', 'base', 'middle'
  String? athleteMode; // athlete id when the app is locked to one athlete
  AppSettings({Map<String, double>? dist, this.speak = true, this.sensitivity = 8, this.phoneAt = 'home', this.athleteMode})
      : dist = dist ?? {'1B': 60, '2B': 84.85, '3B': 60, 'NET': 15};
  Map<String, dynamic> toJson() =>
      {'dist': dist, 'speak': speak, 'sensitivity': sensitivity, 'phoneAt': phoneAt, 'athleteMode': athleteMode};
  factory AppSettings.fromJson(Map<String, dynamic> j) {
    final s = AppSettings();
    final d = j['dist'];
    if (d is Map) d.forEach((k, v) => s.dist[k as String] = (v as num).toDouble());
    s.speak = (j['speak'] ?? true) as bool;
    s.sensitivity = ((j['sensitivity'] ?? 8) as num).toDouble();
    s.phoneAt = (j['phoneAt'] ?? 'home') as String;
    s.athleteMode = j['athleteMode'] as String?;
    return s;
  }
}

/* ------------------------------------------------------------ calculations */

/// Turns two heard sounds into the rep's numbers, correcting for how long each
/// sound took to reach the phone.
Map<String, double> computeRep(String kind, double t1, double t2, double distanceFt, String phoneAt) {
  final delay = distanceFt / soundFtPerSec;
  if (kind == 'throw') {
    double pop = t2 - t1;
    if (phoneAt == 'home') pop -= delay; // the catch at the base is heard late
    if (phoneAt == 'base') pop += delay; // the catch at home is heard late
    return {'pop': pop};
  }
  // tee into net: the phone sits near the hitter, so the net is heard late
  final time = (t2 - t1) - delay;
  return {'time': time, 'ev': time > 0 ? distanceFt / time * ftPerSecToMph : 0};
}

class Summary {
  final int n;
  final Map<String, double?> avg, best, sd;
  final int accN, onTarget;
  Summary(this.n, this.avg, this.best, this.sd, this.accN, this.onTarget);
}

Summary summarize(Session s) {
  final avg = <String, double?>{}, best = <String, double?>{}, sdv = <String, double?>{};
  for (final k in kindMetrics[s.kind] ?? const <String>[]) {
    final v = s.reps.map((r) => r.m[k]).whereType<double>().where((x) => x > 0 && x.isFinite).toList();
    if (v.isEmpty) {
      avg[k] = null;
      best[k] = null;
      sdv[k] = null;
      continue;
    }
    final mean = v.reduce((a, b) => a + b) / v.length;
    avg[k] = mean;
    best[k] = metricDefs[k]!.lowerIsBetter ? v.reduce(math.min) : v.reduce(math.max);
    sdv[k] = v.length < 2
        ? null
        : math.sqrt(v.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / (v.length - 1));
  }
  final acc = s.reps.where((r) => r.accuracy != null).toList();
  return Summary(s.reps.length, avg, best, sdv, acc.length, acc.where((r) => r.accuracy == 'On target').length);
}

class FeedbackLine {
  final String label, value, unit, goal;
  final bool? ok;
  FeedbackLine(this.label, this.value, this.unit, this.goal, this.ok);
}

class RepFeedback {
  final String headLabel, headValue, headUnit;
  final List<FeedbackLine> lines;
  final List<String> cues;
  final int hits, total;
  final String speech;
  RepFeedback(this.headLabel, this.headValue, this.headUnit, this.lines, this.cues, this.hits, this.total, this.speech);
}

RepFeedback feedbackFor(Rep r, Session s, Athlete? a) {
  final kind = s.kind;
  final tg = a?.targets[s.drill] ?? const <String, double>{};
  final lines = <FeedbackLine>[];
  var hits = 0, total = 0;
  for (final k in kindMetrics[kind] ?? const <String>[]) {
    final v = r.m[k];
    if (v == null) continue;
    final d = metricDefs[k]!;
    bool? ok;
    var goal = '';
    final t = tg[k];
    if (t != null) {
      total++;
      ok = d.lowerIsBetter ? v <= t : v >= t;
      if (ok) hits++;
      goal = 'goal ${d.lowerIsBetter ? '≤' : '≥'} ${fmtNum(t, d.decimals)}';
    }
    lines.add(FeedbackLine(d.label, fmtNum(v, d.decimals), d.unit, goal, ok));
  }
  if (r.accuracy != null) {
    lines.add(FeedbackLine('Accuracy', r.accuracy!, '', '', r.accuracy == 'On target'));
  }
  final cues = <String>[];
  for (final c in a?.cues ?? const <Cue>[]) {
    final scopeOk = c.drill == 'any' ||
        c.drill == s.drill ||
        (c.drill == 'throws' && kind == 'throw') ||
        (c.drill == 'hits' && kind != 'throw');
    if (!scopeOk || c.text.trim().isEmpty) continue;
    bool fire = false;
    if (c.metric == 'acc') {
      fire = r.accuracy != null && r.accuracy != 'On target';
    } else {
      final v = r.m[c.metric];
      if (v != null) fire = c.op == '>' ? v > c.value : v < c.value;
    }
    if (fire) cues.add(c.text.trim());
  }
  final pk = primaryMetric[kind]!;
  final pd = metricDefs[pk]!;
  final speech = <String>[];
  for (final l in lines) {
    if (l.label == 'Accuracy') continue;
    final word = l.unit == 'mph' ? ' miles per hour' : (l.unit == 's' ? ' seconds' : '');
    speech.add('${l.label} ${l.value}$word');
  }
  if (total > 0) speech.add(hits == total ? 'Target hit.' : '$hits of $total targets.');
  speech.addAll(cues);
  return RepFeedback(pd.label, fmtNum(r.m[pk], pd.decimals), pd.unit, lines, cues, hits, total, speech.join('. '));
}

String sessionsToCsv(List<Session> sessions, Athlete? Function(String id) athleteOf) {
  String q(Object? v) {
    final x = (v ?? '').toString();
    return (x.contains(',') || x.contains('"') || x.contains('\n')) ? '"${x.replaceAll('"', '""')}"' : x;
  }

  final out = StringBuffer(
      'Athlete,Date,Drill,Rep #,Pop (s),Exit velo (mph),Time to net (s),Accuracy,Distance (ft),Phone position,Targets hit,Session notes\n');
  final sorted = [...sessions]..sort((a, b) => a.date.compareTo(b.date));
  for (final s in sorted) {
    final a = athleteOf(s.athleteId);
    for (var i = 0; i < s.reps.length; i++) {
      final r = s.reps[i];
      final fb = feedbackFor(r, s, a);
      out.writeln([
        a?.name ?? '',
        s.date,
        drillOf(s.drill).label,
        i + 1,
        r.m['pop']?.toStringAsFixed(3) ?? '',
        r.m['ev']?.toStringAsFixed(1) ?? '',
        r.m['time']?.toStringAsFixed(3) ?? '',
        r.accuracy ?? '',
        s.distance,
        s.phoneAt,
        fb.total > 0 ? '${fb.hits}/${fb.total}' : '',
        s.notes,
      ].map(q).join(','));
    }
  }
  return out.toString();
}

/* -------------------------------------------------------- sound detection */

/// Finds sharp sounds (glove pops, bat contact, ball into a net) in a stream of
/// 16-bit microphone samples. Time is counted in samples, so it is exact
/// relative to the start of listening, whatever the phone is doing.
class OnsetDetector {
  final int sampleRate;
  double sensitivity;
  final void Function(double t, double strength) onOnset;
  final void Function(double level)? onLevel; // 0..1+, 1 = trigger line

  final int _win;
  int _wi = 0;
  double _winMax = 0;
  int _prev = 0;
  int _ms = 0;
  double _noise = 0.01;
  int _lastOnsetMs = -100000;
  double _levelMax = 0;
  int _pendingMs = -1;
  double _pendingThr = 1;
  double _pendingPeak = 0;
  static const int refractoryMs = 80;
  static const int warmupMs = 800;
  static const double minAbs = 0.012;

  OnsetDetector({required this.sampleRate, required this.sensitivity, required this.onOnset, this.onLevel})
      : _win = math.max(1, (sampleRate / 1000).round());

  double get timeSec => _ms / 1000.0;

  void addPcm16(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final n = bytes.lengthInBytes ~/ 2;
    for (var i = 0; i < n; i++) {
      final s = bd.getInt16(i * 2, Endian.little);
      final d = (s - _prev).abs() / 32768.0;
      _prev = s;
      if (d > _winMax) _winMax = d;
      _wi++;
      if (_wi >= _win) {
        _processMs(_winMax);
        _wi = 0;
        _winMax = 0;
      }
    }
  }

  void _processMs(double env) {
    final ms = _ms++;
    final thr = math.max(_noise * sensitivity, minAbs);
    final level = env / thr;
    if (level > _levelMax) _levelMax = level;
    if (ms % 50 == 0) {
      onLevel?.call(_levelMax);
      _levelMax = 0;
    }
    // an onset is timed at its first loud millisecond, and rated by its peak over the next 10 ms
    if (_pendingMs >= 0) {
      if (env / _pendingThr > _pendingPeak) _pendingPeak = env / _pendingThr;
      if (ms - _pendingMs >= 10) {
        onOnset(_pendingMs / 1000.0, _pendingPeak);
        _pendingMs = -1;
      }
    } else if (ms > warmupMs && env > thr && ms - _lastOnsetMs > refractoryMs) {
      _lastOnsetMs = ms;
      _pendingMs = ms;
      _pendingThr = thr;
      _pendingPeak = level;
    }
    // slowly follow the background noise, ignoring loud spikes
    final clipped = math.min(env, _noise * 3);
    _noise = _noise * 0.998 + clipped * 0.002;
    if (_noise < 0.0005) _noise = 0.0005;
  }
}

/// Pairs sounds into reps: the first sound starts a rep, and the loudest sound
/// inside the time window after it ends the rep.
class RepPairer {
  final double minGap, maxGap, cooldown;
  double? _a;
  final List<List<double>> _cands = [];
  double _cooldownUntil = -1;
  RepPairer({required this.minGap, required this.maxGap, this.cooldown = 1.5});

  factory RepPairer.forKind(String kind) => kind == 'throw'
      ? RepPairer(minGap: 1.0, maxGap: 3.6, cooldown: 1.5)
      : RepPairer(minGap: 0.04, maxGap: 1.2, cooldown: 1.2);

  bool get waiting => _a != null;
  double? get firstAt => _a;

  /// Returns a finished pair [t1, t2], a missed rep [t1] or null.
  List<double>? onOnset(double t, double strength) {
    final done = tick(t);
    if (t < _cooldownUntil) return done;
    if (_a == null) {
      _a = t;
      _cands.clear();
      return done;
    }
    final g = t - _a!;
    if (g >= minGap && g <= maxGap) _cands.add([t, strength]);
    return done;
  }

  List<double>? tick(double now) {
    final a = _a;
    if (a == null || now - a <= maxGap) return null;
    _a = null;
    if (_cands.isEmpty) return [a];
    _cands.sort((x, y) => y[1].compareTo(x[1]));
    final b = _cands.first[0];
    _cands.clear();
    _cooldownUntil = now + cooldown;
    return [a, b];
  }

  void reset() {
    _a = null;
    _cands.clear();
  }

  void pauseUntil(double t) {
    _cooldownUntil = math.max(_cooldownUntil, t);
    _a = null;
    _cands.clear();
  }
}
