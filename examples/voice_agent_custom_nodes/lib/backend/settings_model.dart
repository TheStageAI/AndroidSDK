import 'package:flutter/foundation.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

// ============================================================================
// BACKEND layer — the config source
// ============================================================================
// `VoiceAgentSettings` holds every user-tunable knob AND knows how to flatten
// them into the `config` map that `agent.start(config:)` expects. It's the
// single place that decides WHICH models the agent uses and HOW the LLM / ASR
// / TTS are wired — so when you ask "how is the LLM connected?", the answer is
// the `llm_*` keys in [toConfig]; "how is ASR connected?" → the `stt` / `vad`
// / `turn_*` / `asr_*` keys.
//
// It's a [ChangeNotifier] so the Settings screen rebuilds live as sliders move.
// ============================================================================
class VoiceAgentSettings extends ChangeNotifier {
  // ── Local BundledModels (android bundle assets) ──────────────────────────
  // When true, [resolveLocalConfig] rewrites vad/stt/tts/turn + starts the
  // on-device LLM from prepare trees. When false (default), HF repo ids are
  // used and HF revisions come from the SDK ModelRevisionMap (do not pass
  // stt_revision / tts_revision / turn_detector_revision).
  bool useLocalBundles = false;

  // Bundled folder names under the app bundle (must match sync_local_bundles).
  String localLlmBundle = 'lfm2.5-350m';
  String localSttBundle = 'thewhisper-large-v3-turbo';
  String localTtsBundle = 'neutts-nano-multilingual';
  String localVadBundle = 'silero-vad';
  String localTurnBundle = 'smart-turn-v3';

  // Handle registered with TheStageAI.start_model for bundled local LLM.
  static const localLlmHandle = 'llm';
  // Default on-device LLM when loading from HuggingFace (handle == repo id).
  static const hfLlmRepo = 'TheStageAI/LFM2.5-350M';
  static const hfSttRepo = 'TheStageAI/thewhisper-large-v3-turbo';
  static const hfTtsRepo = 'TheStageAI/neutts-nano-multilingual';

  /// On-device (local) LLM path is NOT available on Android yet. The picker
  /// shows Local but never routes the agent into the unready on-device path;
  /// [llmProvider] stays remote. Used to gate the Provider dropdown.
  static const bool localLlmAvailable = false;

  /// On-device LLMs shown behind the gated local path (Android fleet).
  static const availableHfLlms = [
    'TheStageAI/LFM2.5-350M',
    'TheStageAI/LFM2.5-230M',
    'TheStageAI/Qwen3-0.6B',
  ];

  /// Shipping HF ASR repos (Android fleet — Whisper turbo only).
  static const availableHfAsr = [
    'TheStageAI/thewhisper-large-v3-turbo',
  ];

  /// Shipping HF TTS repos (Android fleet — NeuTTS families).
  static const availableHfTts = [
    'TheStageAI/neutts-multilingual',
    'TheStageAI/neutts-nano-multilingual',
  ];

  /// BundledModels folder names for local-dev mode (gated local path).
  static const availableLocalLlms = [
    'lfm2.5-350m',
    'lfm2.5-230m',
    'qwen3-0.6b',
  ];
  static const availableLocalAsr = [
    'thewhisper-large-v3-turbo',
  ];
  static const availableLocalTts = [
    'neutts-multilingual',
    'neutts-nano-multilingual',
  ];

  // HF repo ids used when [useLocalBundles] is false.
  String sttRepo = hfSttRepo;
  // NeuTTS engines: an HF repo id, or a local bundle path via
  // --dart-define=NEUTTS_ENGINES_PATH.
  String ttsRepo = const String.fromEnvironment(
    'NEUTTS_ENGINES_PATH',
    defaultValue: hfTtsRepo,
  );

  // ── Voice & language ─────────────────────────────────────────────────────
  String ttsVoice = 'paul';
  String sttLanguage = 'en';
  String systemPrompt =
      'You are a helpful voice assistant. Keep responses concise.';

  // ── LLM provider ─────────────────────────────────────────────────────────
  // Local: llm_model is the start_model handle (bundled: [localLlmHandle];
  // HF: usually the repo id, e.g. [hfLlmRepo]).
  // Cloud: openai_compatible + endpoint + api key.
  //
  // Android defaults to remote (openai_compatible) — the on-device (local)
  // LLM path is not wired up yet ([localLlmAvailable] == false), so the
  // Provider dropdown offers Local but the app stays on remote.
  String llmProvider = 'openai_compatible';
  String llmModel = 'gpt-4o-mini';
  String llmEndpoint = 'https://api.openai.com/v1/chat/completions';
  // Cloud (OpenAI-compatible) only. Local LFM uses the bundle's
  // `arch.decoder.generation` — these are not sent when llmProvider=local.
  int maxTokens = 256;
  double temperature = 0.7;

  /// Voices offered for the selected TTS. Android ships only NeuTTS (both the
  /// multilingual and nano-multilingual families share the same bundle
  /// voices), so this is simply the fixed [availableVoices] set — no
  /// per-TTS-family branching and no persona/clone voices.
  List<String> get voicesForSelectedTts => availableVoices;

  void selectTtsRepo(String repo) {
    ttsRepo = repo;
    final voices = voicesForSelectedTts;
    if (!voices.contains(ttsVoice)) {
      ttsVoice = voices.first;
    }
  }

  void selectLocalTtsBundle(String bundle) {
    localTtsBundle = bundle;
    final voices = voicesForSelectedTts;
    if (!voices.contains(ttsVoice)) {
      ttsVoice = voices.first;
    }
  }

  // Sliding chat window: last N user+assistant turns. System prompt is
  // prepended every LLM call from [systemPrompt] (never trimmed with history).
  int chatMemoryMaxTurns = 10;

  // ── Endpointing (VAD) ────────────────────────────────────────────────────
  int silenceTimeoutMs = 600;
  double vadThreshold = 0.8;
  int vadOnsetMs = 96;
  int maxAccumulationMs = 30000;

  // ── Turn detection (end-of-turn). DNN = pipecat smart-turn. ──────────────
  // On by default, matching iOS's demo app, now that the smart-turn
  // bundle ships at TheStageAI/smart-turn-v3 @ main. Force VAD-silence
  // endpointing with --dart-define=USE_DNN_TURN=false.
  bool useDnnTurn =
      const bool.fromEnvironment('USE_DNN_TURN', defaultValue: true);
  double turnEotThreshold = 0.85;
  int turnEotConfirmCount = 2;
  double turnEotHighConfidence = 1.0;
  int turnPauseTriggerMs = 256;
  int turnReevalIntervalMs = 120;
  int turnMaxSilenceMs = 5000;
  int turnWindowMs = 8000;
  int turnMinSpeechMs = 250;
  // Trailing silence still fed to the streaming decoder after speech stops;
  // the smart-turn model still sees the full pause. Bounds "mm"/"?" filler.
  int turnAsrSilenceHangoverMs = 200;

  // ── Streaming ASR (live caption partials) ────────────────────────────────
  // The committed transcript is identical whether this is on or off; it only
  // controls whether `user_request_partial` captions are emitted.
  bool asrStreaming = true;
  int asrPartialIntervalMs = 600;

  // ── Diagnostics ──────────────────────────────────────────────────────────
  // Emit a single monotonic cross-node event timeline on the `Timeline`
  // os_log category. Stream on a connected Mac with:
  //   log stream --info --predicate
  //     'subsystem == "TheStageAI" AND category == "Timeline"'
  bool debugTimeline = false;

  // ── Wake word ────────────────────────────────────────────────────────────
  bool wakeWordEnabled = false;
  double wwThreshold = 0.5;
  int conversationTimeoutSec = 30;

  // ── Interruption / barge-in ──────────────────────────────────────────────
  bool allowInterruptions = true;
  String interruptMode = 'speech_only';
  int interruptMinSpeechMs = 500;
  // Sustained positive-VAD duration (ms) required to fire a barge-in. 0 =
  // derive from interruptMinSpeechMs. Pair with a high interruptThreshold to
  // reject noise / self-interrupts.
  int interruptOnsetMs = 0;
  // VAD probability threshold for barge-in, independent of the capture
  // (vadThreshold) threshold. Kept strict so the agent doesn't trip on its
  // own TTS / AEC residue while speaking.
  double interruptThreshold = 0.9;

  // Barge-in lockouts / AEC convergence. The initial lockout is a one-time,
  // longer window on the FIRST reply that covers VPIO cold-start; it's set
  // generously here because on a warm restart (models cached) the first reply
  // arrives before AEC has fully converged, which otherwise self-interrupts.
  int interruptMinPlaybackMs = 250;
  int interruptInitialLockoutMs = 1500;
  int interruptThinkingLockoutMs = 600;

  // ── Audio ────────────────────────────────────────────────────────────────
  int preRollMs = 200;
  bool aecEnabled = true;
  // Silence pumped to the speaker at start so VPIO has echo reference samples
  // before the first real TTS. Bumped above the SDK default for restart margin.
  int aecWarmupMs = 400;
  int aecPlaybackGateTailMs = 80;

  // ── Debug toggles ────────────────────────────────────────────────────────
  bool showMetrics = false;
  bool showPartialTranscript = true;
  bool speculativeWhisper = true;

  static const availableVoices = ['paul', 'bril', 'dave', 'jo'];
  static const availableLanguages = ['en', 'auto', 'fr', 'de', 'es'];

  /// Flatten the settings into the `config` map `agent.start(config:)` reads.
  /// Grouped by subsystem so the LLM / ASR / TTS / turn-detection wiring is
  /// obvious at a glance.
  Map<String, dynamic> toConfig(String apiKey) => {
        // ── Models the agent loads ──
        'vad': 'TheStageAI/silero-vad',
        'stt': sttRepo,
        'tts': ttsRepo,
        // Android engines live on the `android` branch (iOS uses `develop`).
        'stt_revision': 'android',
        'tts_revision': 'android',
        'tts_voice': ttsVoice,
        'wake_word': wakeWordEnabled ? 'TheStageAI/wake-word' : null,

        // ── LLM wiring (what produces the assistant's words) ──
        'llm_provider': llmProvider,
        'llm_model': llmModel,
        'llm_endpoint': llmEndpoint,
        'llm_api_key': apiKey,
        'system_prompt': systemPrompt,
        'max_tokens': maxTokens,
        'temperature': temperature,

        // ── VAD / endpointing ──
        'vad_threshold': vadThreshold,
        'vad_onset_ms': vadOnsetMs,
        'max_accumulation_ms': maxAccumulationMs,
        'silence_timeout_ms': silenceTimeoutMs,

        // ── Interruption / barge-in ──
        'allow_interruptions': allowInterruptions,
        'interrupt_mode': interruptMode,
        'interrupt_min_speech_ms': interruptMinSpeechMs,
        'interrupt_onset_ms': interruptOnsetMs,
        'interrupt_threshold': interruptThreshold,
        'interrupt_min_playback_ms': interruptMinPlaybackMs,
        'interrupt_initial_lockout_ms': interruptInitialLockoutMs,
        'interrupt_thinking_lockout_ms': interruptThinkingLockoutMs,

        // ── Audio / AEC ──
        'pre_roll_ms': preRollMs,
        'aec_enabled': aecEnabled,
        'aec_warmup_ms': aecWarmupMs,
        'aec_playback_gate_tail_ms': aecPlaybackGateTailMs,
        'speculative_whisper': speculativeWhisper,

        // ── Wake word ──
        'ww_threshold': wwThreshold,
        'conversation_timeout_sec': conversationTimeoutSec,

        // ── ASR language ──
        'stt_language': sttLanguage,

        // ── Turn detection ──
        // Android runs smart-turn on CPU (iOS: 'npu'); the turn_detector
        // engines path is injected at start() in voice_chat_screen.dart.
        'turn_detection_mode': useDnnTurn ? 'dnn' : 'vad',
        'turn_detector_device': 'cpu',
        'turn_eot_threshold': turnEotThreshold,
        'turn_eot_confirm_count': turnEotConfirmCount,
        'turn_eot_high_confidence': turnEotHighConfidence,
        'turn_pause_trigger_ms': turnPauseTriggerMs,
        'turn_reeval_interval_ms': turnReevalIntervalMs,
        'turn_max_silence_ms': turnMaxSilenceMs,
        'turn_window_ms': turnWindowMs,
        'turn_min_speech_ms': turnMinSpeechMs,
        'turn_asr_silence_hangover_ms': turnAsrSilenceHangoverMs,

        // ── Streaming ASR (live captions) ──
        'asr_streaming': asrStreaming,
        'asr_partial_interval_ms': asrPartialIntervalMs,

        // ── Diagnostics ──
        'debug_timeline': debugTimeline,
      };

  /// Resolve `BundledModels/<name>` paths and patch [config] so the agent loads
  /// VAD/STT/TTS/turn from the app bundle.
  ///
  /// INERT on Android: the on-device (local) LLM path is not available yet, so
  /// [useLocalBundles] stays false and this is a no-op. Kept for parity with
  /// the Apple app; do NOT rely on it to drive a working local run.
  Future<Map<String, dynamic>> resolveLocalConfig(
    Map<String, dynamic> config,
  ) async {
    if (!useLocalBundles) return config;

    Future<String> pathFor(String name) async {
      final p = await TheStageFlutterSDK.get_bundled_engine_path(name);
      if (p == null || p.isEmpty) {
        throw StateError('Bundled model missing: $name');
      }
      return p;
    }

    final sttPath = await pathFor(localSttBundle);
    final ttsPath = await pathFor(localTtsBundle);
    final vadPath = await pathFor(localVadBundle);
    final turnPath = await pathFor(localTurnBundle);

    config['vad'] = vadPath;
    config['stt'] = sttPath;
    config['tts'] = ttsPath;
    config['turn_detector'] = turnPath;
    config['llm_provider'] = 'local';
    config['llm_model'] = localLlmHandle;
    return config;
  }

  /// Start the on-device LLM after VAD/STT/TTS are loaded.
  ///
  /// INERT on Android: guarded on `llmProvider == 'local'`, which never holds
  /// because the Local provider is gated off ([localLlmAvailable] == false).
  Future<void> startLocalLlm() async {
    if (llmProvider != 'local') return;
    final String handle;
    final String enginesPath;
    if (useLocalBundles) {
      final p =
          await TheStageFlutterSDK.get_bundled_engine_path(localLlmBundle);
      if (p == null || p.isEmpty) {
        throw StateError('Bundled model missing: $localLlmBundle');
      }
      handle = localLlmHandle;
      enginesPath = p;
    } else {
      handle = llmModel;
      enginesPath = llmModel;
    }
    try {
      await TheStageFlutterSDK.stop_model(model_name: handle);
    } catch (_) {}
    await TheStageFlutterSDK.start_model(
      model_name: handle,
      engines_path: enginesPath,
      model_type: 'thestage_llm',
      device: 'npu',
    );
  }

  Future<void> stopLocalLlm() async {
    if (llmProvider != 'local') return;
    final handle = useLocalBundles ? localLlmHandle : llmModel;
    try {
      await TheStageFlutterSDK.stop_model(model_name: handle);
    } catch (_) {}
  }

  /// Mutate settings inside [fn] and notify listeners (the Settings screen).
  void update(void Function(VoiceAgentSettings s) fn) {
    fn(this);
    notifyListeners();
  }
}
