import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

import 'lang_parser.dart';
import 'phrases.dart';

// ---------------------------------------------------------------------------
// TutorModel — load NeuTTS nano multilingual, stream a tagged script span by span
// ---------------------------------------------------------------------------
/// Demo flow:
/// 1. Load `neutts-nano-multilingual` once.
/// 2. Parse the editable tagged script (`<en>…</en><es>…</es>` …).
/// 3. Stream each span with its own `language` (and the voice picked for
///    that language) into one audio player, with a short gap between
///    spans.
class TutorModel extends ChangeNotifier {
  // -------------------------------------------------------------------------
  // Public Attributes (UI bindings)
  // -------------------------------------------------------------------------
  TutorPhrase selected = TutorPhraseBook.all.first;
  String script = TutorPhraseBook.all.first.tagged;
  String status = 'Load model, then Play';
  String stats = '';
  bool loading = false;
  bool loaded = false;
  bool running = false;
  String? loadPhase;
  double? loadFraction;

  /// The bundle's voices (from the start_model status).
  List<String> voices = const [];

  /// Voice per language tag; a tag without one uses [defaultVoice].
  final Map<String, String> voiceFor = {};
  String defaultVoice = 'paul';

  // -------------------------------------------------------------------------
  // Private Attributes
  // -------------------------------------------------------------------------
  static const _modelName = 'tutor_tts';
  static const _sampleRate = 24000;

  /// Silence between language spans (ms).
  static const _gapMs = 250;

  static const _enginesPath = String.fromEnvironment(
    'TTS_ENGINES_PATH',
    defaultValue: 'TheStageAI/neutts-nano-multilingual',
  );

  // Empty resolves the repo's SDK-pinned commit.
  static const _revision = String.fromEnvironment('TTS_REVISION');

  final _player = TSAudioPlayer(sampleRate: _sampleRate);
  StreamSubscription<Map<String, dynamic>>? _progressSub;
  bool _stopRequested = false;
  String? _streamId;

  // -------------------------------------------------------------------------
  // Public Methods
  // -------------------------------------------------------------------------
  void select(TutorPhrase phrase) {
    if (running) return;
    selected = phrase;
    script = phrase.tagged;
    stats = '';
    status = loaded ? 'ready — ${phrase.title}' : 'Load model, then Play';
    notifyListeners();
  }

  void setVoice(String tag, String voice) {
    voiceFor[tag] = voice;
    notifyListeners();
  }

  Future<void> load(String apiToken) async {
    if (loading || loaded) return;
    loading = true;
    status = 'loading NeuTTS nano…';
    notifyListeners();
    _progressSub = TheStageFlutterSDK.on_progress.listen((e) {
      if (e['model_name'] != _modelName) return;
      loadPhase = e['phase'] as String?;
      loadFraction = (e['progress'] as num?)?.toDouble();
      notifyListeners();
    });
    try {
      await TheStageFlutterSDK.initialize(api_token: apiToken);
      final st = await TheStageFlutterSDK.start_model(
        model_name: _modelName,
        engines_path: _enginesPath,
        // The bundle's manifest type (both NeuTTS families).
        model_type: 'neutts',
        revision: _revision,
        config: {'voice_id': defaultVoice, 'language': 'english'},
      );
      voices = ((st['voices'] as List?) ?? const []).cast<String>();
      if (voices.isNotEmpty && !voices.contains(defaultVoice)) {
        defaultVoice = voices.first;
      }
      loaded = true;
      status = 'ready — pick a phrase';
    } catch (e) {
      status = 'load error: $e';
    } finally {
      loading = false;
      loadPhase = null;
      await _progressSub?.cancel();
      _progressSub = null;
      notifyListeners();
    }
  }

  Future<void> play() async {
    if (running || !loaded) return;
    final List<LangSegment> segments;
    try {
      segments = LangTagParser.parse(
        script.trim().isEmpty ? selected.tagged : script,
      );
    } on LangParseError catch (e) {
      status = 'error: $e';
      notifyListeners();
      return;
    }
    running = true;
    _stopRequested = false;
    stats = '';
    notifyListeners();

    if (_player.isPlaying) await _player.stop();
    await _player.start();
    final gap = Float32List(_sampleRate * _gapMs ~/ 1000);
    var samples = 0;
    final failures = <String>[];
    double? firstAudio;
    final t0 = DateTime.now();
    try {
      for (var i = 0; i < segments.length && !_stopRequested; i++) {
        final seg = segments[i];
        status = '[${i + 1}/${segments.length}] ${seg.tag}: ${seg.text}';
        notifyListeners();
        final tSpan = DateTime.now();
        _streamId = 'tutor-${t0.microsecondsSinceEpoch}-$i';
        final stream = TheStageFlutterSDK.infer_stream(
          model_name: _modelName,
          stream_id: _streamId,
          input_json: {
            'text': seg.text,
            'language': seg.language,
            'voice_id': voiceFor[seg.tag] ?? defaultVoice,
          },
        );
        await for (final chunk in stream) {
          if (_stopRequested) break;
          // A failed span ends with its error on the final chunk.
          final error = chunk['error'];
          if (error != null) {
            failures.add('${seg.tag}: $error');
            break;
          }
          final audio = chunk['audio'] as Float32List?;
          if (audio == null || audio.isEmpty) continue;
          firstAudio ??= _seconds(tSpan);
          samples += audio.length;
          _player.enqueue(audio);
        }
        if (!_stopRequested && i + 1 < segments.length) {
          _player.enqueue(gap);
          samples += gap.length;
        }
      }
      final wall = _seconds(t0);
      stats = '${(samples / _sampleRate).toStringAsFixed(1)} s audio · '
          'first audio ${(firstAudio ?? 0).toStringAsFixed(2)} s · '
          'wall ${wall.toStringAsFixed(1)} s · ${segments.length} spans'
          '${failures.isEmpty ? '' : '\nfailed: ${failures.join('; ')}'}';
      if (!_stopRequested) {
        status = 'playing…';
        notifyListeners();
        await _player.drain();
      }
      status = _stopRequested ? 'stopped' : 'done';
    } catch (e) {
      status = 'error: $e';
    } finally {
      running = false;
      _streamId = null;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _stopRequested = true;
    final id = _streamId;
    if (id != null) {
      try {
        await TheStageFlutterSDK.stop_stream(stream_id: id);
      } catch (_) {}
    }
    await _player.stop();
    status = 'stopped';
    notifyListeners();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _player.stop();
    if (loaded) TheStageFlutterSDK.stop_model(model_name: _modelName);
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Private Methods
  // -------------------------------------------------------------------------
  static double _seconds(DateTime since) =>
      DateTime.now().difference(since).inMicroseconds / 1e6;
}
