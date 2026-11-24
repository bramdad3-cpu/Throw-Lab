import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'core.dart';
import 'live.dart';
import 'store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ThrowLabApp());
  store.load();
}

class ThrowLabApp extends StatelessWidget {
  const ThrowLabApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Throw Lab',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1C5CAB), useMaterial3: true),
      home: const Root(),
    );
  }
}

class Root extends StatelessWidget {
  const Root({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final am = store.settings.athleteMode;
        if (am != null && store.athletes[am] != null) {
          return AthleteScreen(key: ValueKey('am-$am'), athleteId: am, athleteMode: true);
        }
        return const HomeScreen();
      },
    );
  }
}

/* ------------------------------------------------------------- helpers */

Future<bool> confirm(BuildContext context, String message, {String ok = 'Delete'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

void snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

Future<void> shareCsv(BuildContext context, List<Session> sessions, String name) async {
  if (sessions.every((s) => s.reps.isEmpty)) {
    snack(context, 'No reps to export yet');
    return;
  }
  final csv = sessionsToCsv(sessions, (id) => store.athletes[id]);
  final dir = await getTemporaryDirectory();
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
  final f = File('${dir.path}/$safe.csv');
  await f.writeAsString(csv);
  await Share.shareXFiles([XFile(f.path)], subject: safe);
}

Widget statTile(String label, String value, String unit) {
  return Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 2),
        Text.rich(TextSpan(children: [
          TextSpan(text: value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          TextSpan(text: unit.isEmpty ? '' : ' $unit', style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ])),
      ]),
    ),
  );
}

String targetSummary(Athlete a) {
  final parts = <String>[];
  a.targets.forEach((drill, tg) {
    final bits = <String>[];
    tg.forEach((k, v) {
      final d = metricDefs[k];
      if (d != null) bits.add('${d.label} ${d.lowerIsBetter ? '≤' : '≥'} ${fmtNum(v, d.decimals)} ${d.unit}');
    });
    if (bits.isNotEmpty) parts.add('${drillOf(drill).label}: ${bits.join(' · ')}');
  });
  return parts.isEmpty ? 'No targets set yet.' : parts.join('\n');
}

/* ---------------------------------------------------------------- home */

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final list = store.athleteList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Throw Lab'),
        actions: [
          IconButton(
            tooltip: 'Athlete mode',
            icon: const Icon(Icons.person_pin_outlined),
            onPressed: () => startAthleteMode(context),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AthleteEditScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Add athlete'),
      ),
      body: list.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Add your first athlete, set her targets and coaching cues, then start a live session.\n\n'
                'Put the phone on a tripod and press Start. The app listens for each glove pop or bat contact, '
                'times the rep and says the result out loud.',
                style: TextStyle(fontSize: 16),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: [
                for (final a in list)
                  Card(
                    child: ListTile(
                      title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          'Throws ${a.throws} · Bats ${a.bats}${a.team.isNotEmpty ? ' · ${a.team}' : ''} · ${store.sessionsFor(a.id).length} sessions'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => AthleteScreen(athleteId: a.id, athleteMode: false))),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> startAthleteMode(BuildContext context) async {
    final list = store.athleteList();
    if (list.isEmpty) {
      snack(context, 'Add an athlete first');
      return;
    }
    final id = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Athlete mode'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
                'A simple screen for the athlete working alone: her drills, her numbers and your feedback. '
                'Editing, targets and deleting are hidden. Everything she records is saved here for you.'),
          ),
          for (final a in list) SimpleDialogOption(onPressed: () => Navigator.pop(c, a.id), child: Text(a.name)),
        ],
      ),
    );
    if (id != null) {
      store.settings.athleteMode = id;
      store.changed();
    }
  }
}

/* --------------------------------------------------------- athlete edit */

class AthleteEditScreen extends StatefulWidget {
  final String? athleteId;
  const AthleteEditScreen({super.key, this.athleteId});
  @override
  State<AthleteEditScreen> createState() => _AthleteEditScreenState();
}

class _AthleteEditScreenState extends State<AthleteEditScreen> {
  late Athlete a;
  late bool isNew;
  final name = TextEditingController();
  final team = TextEditingController();
  final bat = TextEditingController();

  @override
  void initState() {
    super.initState();
    final existing = widget.athleteId == null ? null : store.athletes[widget.athleteId];
    isNew = existing == null;
    a = existing ?? Athlete(id: newId(), name: '');
    name.text = a.name;
    team.text = a.team;
    bat.text = a.batLength == null ? '' : fmtNum(a.batLength, 1);
  }

  @override
  void dispose() {
    name.dispose();
    team.dispose();
    bat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'Add athlete' : 'Edit athlete')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Name'), textCapitalization: TextCapitalization.words),
        const SizedBox(height: 16),
        const Text('Throws'),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'R', label: Text('Right')), ButtonSegment(value: 'L', label: Text('Left'))],
          selected: {a.throws},
          onSelectionChanged: (v) => setState(() => a.throws = v.first),
        ),
        const SizedBox(height: 12),
        const Text('Bats'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'R', label: Text('Right')),
            ButtonSegment(value: 'L', label: Text('Left')),
            ButtonSegment(value: 'S', label: Text('Switch')),
          ],
          selected: {a.bats},
          onSelectionChanged: (v) => setState(() => a.bats = v.first),
        ),
        const SizedBox(height: 12),
        TextField(
            controller: bat,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Bat length (inches)')),
        TextField(controller: team, decoration: const InputDecoration(labelText: 'Team / grad year (optional)')),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            if (name.text.trim().isEmpty) {
              snack(context, 'Enter a name');
              return;
            }
            a.name = name.text.trim();
            a.team = team.text.trim();
            a.batLength = double.tryParse(bat.text.trim());
            store.saveAthlete(a);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
        if (!isNew) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: () async {
              if (await confirm(context, 'Delete ${a.name} and all of her sessions?')) {
                store.deleteAthlete(a.id);
                if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              }
            },
            child: const Text('Delete athlete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ]),
    );
  }
}

/* -------------------------------------------------------------- athlete */

class AthleteScreen extends StatelessWidget {
  final String athleteId;
  final bool athleteMode;
  const AthleteScreen({super.key, required this.athleteId, required this.athleteMode});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final a = store.athletes[athleteId];
        if (a == null) return const Scaffold(body: Center(child: Text('Athlete not found')));
        final ss = store.sessionsFor(a.id);
        return Scaffold(
          appBar: AppBar(
            title: Text(athleteMode ? 'Hi, ${a.name}' : a.name),
            actions: [
              if (athleteMode)
                TextButton(
                  onPressed: () async {
                    if (await confirm(context, 'Switch to coach mode?', ok: 'Coach mode')) {
                      store.settings.athleteMode = null;
                      store.changed();
                    }
                  },
                  child: const Text('Coach mode'),
                )
              else ...[
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AthleteEditScreen(athleteId: a.id))),
                ),
                IconButton(
                  tooltip: 'Spreadsheet',
                  icon: const Icon(Icons.ios_share),
                  onPressed: () => shareCsv(context, ss, '${a.name} - all sessions'),
                ),
              ],
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => startSession(context, a),
            icon: const Icon(Icons.mic),
            label: const Text('Start session'),
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                        child: Text(athleteMode ? 'Your targets' : 'Targets & coaching cues',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
                    if (!athleteMode)
                      TextButton(
                        onPressed: () =>
                            Navigator.push(context, MaterialPageRoute(builder: (_) => TargetsScreen(athleteId: a.id))),
                        child: const Text('Edit'),
                      ),
                  ]),
                  Text(targetSummary(a)),
                  if (!athleteMode && a.cues.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('${a.cues.length} coaching cue${a.cues.length == 1 ? '' : 's'} set',
                          style: const TextStyle(color: Colors.black54)),
                    ),
                ]),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Text('Sessions', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            if (ss.isEmpty)
              const Padding(padding: EdgeInsets.all(8), child: Text('No sessions yet. Tap Start session.')),
            for (final s in ss) _sessionTile(context, s),
          ]),
        );
      },
    );
  }

  Widget _sessionTile(BuildContext context, Session s) {
    final sum = summarize(s);
    final pk = primaryMetric[s.kind]!;
    final d = metricDefs[pk]!;
    return Card(
      child: ListTile(
        title: Text('${prettyDate(s.date)} · ${drillOf(s.drill).label}'),
        subtitle: Text(
            '${sum.n} rep${sum.n == 1 ? '' : 's'} · avg ${d.label.toLowerCase()} ${fmtNum(sum.avg[pk], d.decimals)} ${d.unit} · best ${fmtNum(sum.best[pk], d.decimals)}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => SessionScreen(sessionId: s.id, athleteMode: athleteMode))),
      ),
    );
  }

  Future<void> startSession(BuildContext context, Athlete a) async {
    final key = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
              padding: EdgeInsets.all(14),
              child: Text('Which drill?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
          for (final d in drills.values)
            ListTile(
              leading: Icon(d.kind == 'throw' ? Icons.sports_baseball_outlined : Icons.sports_cricket_outlined),
              title: Text(d.label),
              onTap: () => Navigator.pop(c, d.key),
            ),
        ]),
      ),
    );
    if (key == null || !context.mounted) return;
    final d = drillOf(key);
    final s = Session(
      id: newId(),
      athleteId: a.id,
      drill: key,
      date: isoDate(DateTime.now()),
      distance: store.settings.dist[d.base] ?? (d.kind == 'net' ? 15 : 84.85),
      phoneAt: d.kind == 'net' ? 'home' : store.settings.phoneAt,
      created: DateTime.now().millisecondsSinceEpoch,
    );
    store.saveSession(s);
    Navigator.push(context, MaterialPageRoute(builder: (_) => LiveScreen(sessionId: s.id, athleteMode: athleteMode)));
  }
}

/* -------------------------------------------------------------- session */

class SessionScreen extends StatelessWidget {
  final String sessionId;
  final bool athleteMode;
  const SessionScreen({super.key, required this.sessionId, required this.athleteMode});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final s = store.sessions[sessionId];
        if (s == null) return const Scaffold(body: Center(child: Text('Session deleted')));
        final a = store.athletes[s.athleteId];
        final sum = summarize(s);
        final tiles = <Widget>[statTile('Reps', '${sum.n}', '')];
        for (final k in kindMetrics[s.kind]!) {
          final d = metricDefs[k]!;
          tiles.add(statTile('Avg ${d.label.toLowerCase()}', fmtNum(sum.avg[k], d.decimals), d.unit));
          tiles.add(statTile('Best ${d.label.toLowerCase()}', fmtNum(sum.best[k], d.decimals), d.unit));
        }
        final pk = primaryMetric[s.kind]!;
        tiles.add(statTile('Consistency', sum.sd[pk] == null ? '—' : '±${fmtNum(sum.sd[pk], metricDefs[pk]!.decimals)}',
            metricDefs[pk]!.unit));
        if (s.kind == 'throw' && sum.accN > 0) {
          tiles.add(statTile('On target', '${(sum.onTarget * 100 / sum.accN).round()}%', '${sum.onTarget}/${sum.accN}'));
        }
        return Scaffold(
          appBar: AppBar(
            title: Text('${drillOf(s.drill).short} · ${prettyDate(s.date)}'),
            actions: [
              IconButton(
                  tooltip: 'Spreadsheet',
                  icon: const Icon(Icons.ios_share),
                  onPressed: () => shareCsv(context, [s], '${a?.name ?? 'athlete'} ${s.date} ${s.drill}')),
              if (!athleteMode)
                IconButton(
                  tooltip: 'Delete session',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (await confirm(context, 'Delete this session and all its reps?')) {
                      store.deleteSession(s.id);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => LiveScreen(sessionId: s.id, athleteMode: athleteMode))),
            icon: const Icon(Icons.mic),
            label: const Text('Keep going'),
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.5,
              children: tiles,
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < s.reps.length; i++) RepTile(session: s, index: i, athleteMode: athleteMode),
          ]),
        );
      },
    );
  }
}

class RepTile extends StatelessWidget {
  final Session session;
  final int index;
  final bool athleteMode;
  const RepTile({super.key, required this.session, required this.index, required this.athleteMode});

  @override
  Widget build(BuildContext context) {
    final r = session.reps[index];
    final fb = feedbackFor(r, session, store.athletes[session.athleteId]);
    final details = fb.lines.where((l) => l.label != fb.headLabel).map((l) => '${l.label} ${l.value} ${l.unit}').join(' · ');
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('${index + 1}')),
        title: Text('${fb.headValue} ${fb.headUnit}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        subtitle: Text([
          if (details.isNotEmpty) details,
          if (fb.total > 0) fb.hits == fb.total ? '✓ all targets' : '${fb.hits}/${fb.total} targets',
        ].join('\n')),
        onTap: () => editRep(context, session, index, athleteMode),
      ),
    );
  }
}

Future<void> editRep(BuildContext context, Session s, int index, bool athleteMode) async {
  final r = s.reps[index];
  await showModalBottomSheet<void>(
    context: context,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Rep ${index + 1}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          if (s.kind == 'throw') ...[
            const SizedBox(height: 8),
            const Text('Accuracy'),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in accuracyTags)
                ChoiceChip(
                  label: Text(t),
                  selected: r.accuracy == t,
                  onSelected: (on) {
                    r.accuracy = on ? t : null;
                    store.saveSession(s);
                    Navigator.pop(c);
                  },
                ),
            ]),
          ],
          if (!athleteMode) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                s.reps.removeAt(index);
                store.saveSession(s);
                Navigator.pop(c);
              },
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text('Delete this rep', style: TextStyle(color: Colors.red)),
            ),
          ],
        ]),
      ),
    ),
  );
}

/* -------------------------------------------------------------- targets */

class TargetsScreen extends StatefulWidget {
  final String athleteId;
  const TargetsScreen({super.key, required this.athleteId});
  @override
  State<TargetsScreen> createState() => _TargetsScreenState();
}

class _TargetsScreenState extends State<TargetsScreen> {
  late Athlete a;
  late Map<String, Map<String, double>> targets;
  late List<Cue> cues;
  String drill = 'C-2B';
  final Map<String, TextEditingController> ctl = {};

  @override
  void initState() {
    super.initState();
    a = store.athletes[widget.athleteId]!;
    targets = a.targets.map((k, v) => MapEntry(k, Map<String, double>.from(v)));
    cues = a.cues.map((c) => Cue.fromJson(c.toJson())).toList();
    _loadFields();
  }

  void _loadFields() {
    for (final c in ctl.values) {
      c.dispose();
    }
    ctl.clear();
    for (final k in kindMetrics[drillOf(drill).kind]!) {
      if (k == 'time') continue;
      final v = targets[drill]?[k];
      ctl[k] = TextEditingController(text: v == null ? '' : fmtNum(v, metricDefs[k]!.decimals));
    }
  }

  void _readFields() {
    final m = <String, double>{};
    ctl.forEach((k, c) {
      final v = double.tryParse(c.text.trim());
      if (v != null) m[k] = v;
    });
    targets[drill] = m;
  }

  @override
  void dispose() {
    for (final c in ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scopes = <String, String>{
      'any': 'Any drill',
      'throws': 'Any throw',
      'hits': 'Any hitting',
      for (final d in drills.values) d.key: d.label,
    };
    final metricChoices = <String, String>{
      for (final e in metricDefs.entries) e.key: e.value.label,
      'acc': 'Accuracy (not on target)',
    };
    return Scaffold(
      appBar: AppBar(title: Text('Targets & cues — ${a.name}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Targets', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        DropdownButton<String>(
          value: drill,
          isExpanded: true,
          items: [for (final d in drills.values) DropdownMenuItem(value: d.key, child: Text(d.label))],
          onChanged: (v) {
            if (v == null) return;
            _readFields();
            setState(() {
              drill = v;
              _loadFields();
            });
          },
        ),
        for (final e in ctl.entries)
          TextField(
            controller: e.value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText:
                  '${metricDefs[e.key]!.label} ${metricDefs[e.key]!.lowerIsBetter ? 'at most' : 'at least'} (${metricDefs[e.key]!.unit})',
            ),
          ),
        const SizedBox(height: 24),
        const Text('Coaching cues', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const Text('When a rep meets the condition, the app shows and speaks your cue.',
            style: TextStyle(color: Colors.black54)),
        for (var i = 0; i < cues.length; i++)
          Card(
            key: ObjectKey(cues[i]),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: DropdownButton<String>(
                      value: scopes.containsKey(cues[i].drill) ? cues[i].drill : 'any',
                      isExpanded: true,
                      items: [for (final e in scopes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                      onChanged: (v) => setState(() => cues[i].drill = v ?? 'any'),
                    ),
                  ),
                  IconButton(onPressed: () => setState(() => cues.removeAt(i)), icon: const Icon(Icons.close)),
                ]),
                Row(children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButton<String>(
                      value: metricChoices.containsKey(cues[i].metric) ? cues[i].metric : 'pop',
                      isExpanded: true,
                      items: [for (final e in metricChoices.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                      onChanged: (v) => setState(() => cues[i].metric = v ?? 'pop'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (cues[i].metric != 'acc') ...[
                    DropdownButton<String>(
                      value: cues[i].op,
                      items: const [
                        DropdownMenuItem(value: '>', child: Text('over')),
                        DropdownMenuItem(value: '<', child: Text('under')),
                      ],
                      onChanged: (v) => setState(() => cues[i].op = v ?? '>'),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 70,
                      child: TextFormField(
                        initialValue: fmtNum(cues[i].value, 2),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (v) => cues[i].value = double.tryParse(v) ?? cues[i].value,
                      ),
                    ),
                  ],
                ]),
                TextFormField(
                  initialValue: cues[i].text,
                  decoration: const InputDecoration(labelText: 'What to tell her'),
                  onChanged: (v) => cues[i].text = v,
                ),
              ]),
            ),
          ),
        TextButton.icon(
          onPressed: () => setState(() => cues.add(Cue(drill: drill, metric: drillOf(drill).kind == 'throw' ? 'pop' : 'ev', op: drillOf(drill).kind == 'throw' ? '>' : '<', value: drillOf(drill).kind == 'throw' ? 2.0 : 50))),
          icon: const Icon(Icons.add),
          label: const Text('Add cue'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            _readFields();
            targets.removeWhere((k, v) => v.isEmpty);
            a.targets = targets;
            a.cues = cues.where((c) => c.text.trim().isNotEmpty).toList();
            store.saveAthlete(a);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ]),
    );
  }
}

/* ------------------------------------------------------------- settings */

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Map<String, TextEditingController> ctl = {};
  @override
  void initState() {
    super.initState();
    for (final k in ['1B', '2B', '3B', 'NET']) {
      ctl[k] = TextEditingController(text: fmtNum(store.settings.dist[k], 2));
    }
  }

  @override
  void dispose() {
    for (final c in ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = store.settings;
    const labels = {'1B': 'Home → 1st (ft)', '2B': 'Home → 2nd (ft)', '3B': 'Home → 3rd (ft)', 'NET': 'Tee → net (ft)'};
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Default distances', style: TextStyle(fontWeight: FontWeight.w600)),
        for (final k in ['1B', '2B', '3B', 'NET'])
          TextField(
            controller: ctl[k],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: labels[k]),
          ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Speak results out loud'),
          value: st.speak,
          onChanged: (v) => setState(() => st.speak = v),
        ),
        const SizedBox(height: 8),
        const Text('Where the phone usually sits for throws', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'home', label: Text('Near home')),
            ButtonSegment(value: 'middle', label: Text('Halfway')),
            ButtonSegment(value: 'base', label: Text('Near base')),
          ],
          selected: {st.phoneAt},
          onSelectionChanged: (v) => setState(() => st.phoneAt = v.first),
        ),
        const SizedBox(height: 16),
        Text('Sound trigger: ${st.sensitivity.toStringAsFixed(0)}× the background noise',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Slider(
          value: st.sensitivity.clamp(3, 25),
          min: 3,
          max: 25,
          divisions: 22,
          label: st.sensitivity.toStringAsFixed(0),
          onChanged: (v) => setState(() => st.sensitivity = v),
        ),
        const Text('Lower = picks up quieter sounds. Raise it if talking or footsteps set it off.',
            style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            ctl.forEach((k, c) {
              final v = double.tryParse(c.text.trim());
              if (v != null && v > 0) st.dist[k] = v;
            });
            store.changed();
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ]),
    );
  }
}
