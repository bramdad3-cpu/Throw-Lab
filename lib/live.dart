import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'core.dart';
import 'main.dart' show editRep, snack;
import 'store.dart';

class LiveScreen extends StatefulWidget {
  final String sessionId;
  final bool athleteMode;
  const LiveScreen({super.key, required this.sessionId, required this.athleteMode});
  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  static const int sampleRate = 44100;
  final AudioRecorder _rec = AudioRecorder();
  final FlutterTts _tts = FlutterTts();
  StreamSubscription<Uint8List>? _sub;
  OnsetDetector? _det;
  RepPairer? _pair;
  bool listening = false;
  bool _speaking = false;
  double level = 0;
  int _flashUntil = 0;
  String status = 'Press Start, then set the phone down.';
  RepFeedback? last;
  late TextEditingController distCtl;

  Session get s => store.sessions[widget.sessionId]!;

  @override
  void initState() {
    super.initState();
    distCtl = TextEditingController(text: fmtNum(s.distance, 2));
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _stop(updateUi: false);
    _rec.dispose();
    _tts.stop();
    distCtl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final d = double.tryParse(distCtl.text.trim());
    if (d != null && d > 0) {
      s.distance = d;
      store.saveSession(s);
    }
    if (!await _rec.hasPermission()) {
      if (mounted) snack(context, 'Throw Lab needs the microphone to hear the reps.');
      return;
    }
    _pair = RepPairer.forKind(s.kind);
    _det = OnsetDetector(
      sampleRate: sampleRate,
      sensitivity: store.settings.sensitivity,
      onOnset: _onOnset,
      onLevel: (l) => level = l,
    );
    try {
      final stream = await _rec.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      ));
      _sub = stream.listen(_onAudio, onError: (Object e) {
        if (mounted) setState(() => status = 'Microphone error: $e');
      });
    } catch (e) {
      if (mounted) snack(context, 'Could not start the microphone: $e');
      return;
    }
    WakelockPlus.enable();
    setState(() {
      listening = true;
      status = s.kind == 'throw' ? 'Listening for the catch…' : 'Listening for contact…';
    });
  }

  Future<void> _stop({bool updateUi = true}) async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _rec.stop();
    } catch (_) {}
    WakelockPlus.disable();
    listening = false;
    if (updateUi && mounted) setState(() => status = 'Stopped. Press Start to keep going.');
  }

  int _lastUi = 0;
  void _onAudio(Uint8List data) {
    final det = _det, pair = _pair;
    if (det == null || pair == null) return;
    det.addPcm16(data);
    _handle(pair.tick(det.timeSec));
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastUi > 80 && mounted) {
      _lastUi = now;
      setState(() {
        if (pair.waiting && !_speaking) {
          status = s.kind == 'throw' ? 'Heard the catch — waiting for the base…' : 'Heard contact — waiting for the net…';
        }
      });
    }
  }

  void _onOnset(double t, double strength) {
    if (_speaking) return;
    _flashUntil = DateTime.now().millisecondsSinceEpoch + 150;
    _handle(_pair?.onOnset(t, strength));
  }

  void _handle(List<double>? res) {
    if (res == null) return;
    if (res.length == 1) {
      status = s.kind == 'throw'
          ? 'Only heard one sound — no catch at the base. Listening again…'
          : 'Only heard contact — nothing at the net. Listening again…';
      return;
    }
    final m = computeRep(s.kind, res[0], res[1], s.distance, s.phoneAt);
    final ok = s.kind == 'throw' ? (m['pop']! > 0.8 && m['pop']! < 4.0) : (m['ev']! > 5 && m['ev']! < 130);
    if (!ok) {
      status = 'That one didn\'t look like a real rep. Listening again…';
      return;
    }
    final r = Rep(id: newId(), t1: res[0], t2: res[1], m: m, at: DateTime.now().millisecondsSinceEpoch);
    s.reps.add(r);
    store.saveSession(s);
    final fb = feedbackFor(r, s, store.athletes[s.athleteId]);
    last = fb;
    status = 'Rep ${s.reps.length} saved. Listening…';
    _say(fb.speech);
  }

  Future<void> _say(String text) async {
    if (!store.settings.speak || text.isEmpty) return;
    _speaking = true;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
    _speaking = false;
    final det = _det;
    if (det != null) _pair?.pauseUntil(det.timeSec + 0.3);
  }

  @override
  Widget build(BuildContext context) {
    final a = store.athletes[s.athleteId];
    final flash = DateTime.now().millisecondsSinceEpoch < _flashUntil;
    final reps = s.reps;
    return Scaffold(
      appBar: AppBar(title: Text('${a?.name ?? ''} · ${drillOf(s.drill).short}')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        _resultCard(),
        const SizedBox(height: 12),
        Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: !listening ? Colors.grey : (flash ? Colors.orange : Colors.green),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(status, style: const TextStyle(fontSize: 15))),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: listening ? (level / 1.5).clamp(0.0, 1.0) : 0,
            minHeight: 10,
            color: level >= 1 ? Colors.orange : null,
          ),
        ),
        const Text('Sound level — orange means loud enough to count', style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 12),
        SizedBox(
          height: 64,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: listening ? Colors.red.shade700 : null),
            onPressed: listening ? () => _stop() : _start,
            icon: Icon(listening ? Icons.stop : Icons.mic, size: 28),
            label: Text(listening ? 'Stop' : 'Start', style: const TextStyle(fontSize: 22)),
          ),
        ),
        const SizedBox(height: 12),
        if (!listening) _setupCard(),
        if (reps.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Reps (${reps.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          for (var i = reps.length - 1; i >= 0; i--) _repRow(i),
        ],
      ]),
    );
  }

  Widget _resultCard() {
    final fb = last;
    return Card(
      color: const Color(0xFFF3F6FB),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: fb == null
            ? const SizedBox(
                height: 90,
                child: Center(child: Text('Results show here after each rep', style: TextStyle(color: Colors.black54))))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fb.headLabel, style: const TextStyle(color: Colors.black54)),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(fb.headValue, style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w800, height: 1)),
                  const SizedBox(width: 6),
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(fb.headUnit, style: const TextStyle(fontSize: 20))),
                  const Spacer(),
                  if (fb.total > 0)
                    Text(fb.hits == fb.total ? '✓ Target' : '${fb.hits}/${fb.total} targets',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: fb.hits == fb.total ? Colors.green.shade800 : Colors.orange.shade900)),
                ]),
                const SizedBox(height: 6),
                for (final l in fb.lines)
                  if (l.label != fb.headLabel)
                    Text('${l.ok == true ? '✓ ' : l.ok == false ? '✗ ' : ''}${l.label}: ${l.value} ${l.unit}  ${l.goal}'),
                for (final c in fb.cues)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFE3EDFB), borderRadius: BorderRadius.circular(8)),
                    child: Text('Coach: $c', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ]),
      ),
    );
  }

  Widget _setupCard() {
    final isThrow = s.kind == 'throw';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Setup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          TextField(
            controller: distCtl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: isThrow ? 'Throw distance (ft)' : 'Distance from ball to net (ft)'),
          ),
          if (isThrow) ...[
            const SizedBox(height: 10),
            const Text('Where is the phone?'),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'home', label: Text('Near home')),
                ButtonSegment(value: 'middle', label: Text('Halfway')),
                ButtonSegment(value: 'base', label: Text('Near base')),
              ],
              selected: {s.phoneAt},
              onSelectionChanged: (v) => setState(() {
                s.phoneAt = v.first;
                store.saveSession(s);
              }),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            isThrow
                ? 'The app hears the glove pop at home, then the catch at the base, and corrects for how long the sound takes to reach the phone. Keep talking to a minimum during reps.'
                : 'Put the phone near the tee. The app hears bat contact, then the ball hitting the net. A net that makes a sound (a tarp or backstop behind it) works best.',
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ]),
      ),
    );
  }

  Widget _repRow(int i) {
    final r = s.reps[i];
    final fb = feedbackFor(r, s, store.athletes[s.athleteId]);
    return Card(
      child: ListTile(
        dense: true,
        leading: CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
        title: Text('${fb.headValue} ${fb.headUnit}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        subtitle: Text([
          for (final l in fb.lines)
            if (l.label != fb.headLabel) '${l.label} ${l.value}',
          if (fb.total > 0) fb.hits == fb.total ? '✓' : '${fb.hits}/${fb.total}',
        ].join(' · ')),
        onTap: () async {
          await editRep(context, s, i, widget.athleteMode);
          if (mounted) setState(() {});
        },
      ),
    );
  }
}
