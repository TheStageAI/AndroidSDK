import 'package:flutter/foundation.dart';

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
// Models are Hugging Face repo ids. The app passes no `*_revision` and no
// `*_device` key, so the SDK takes each repo's pinned revision and the best
// bundle this phone supports.
//
// It's a [ChangeNotifier] so the Settings screen rebuilds live as sliders move.
// ============================================================================
class VoiceAgentSettings extends ChangeNotifier {
  // Default on-device LLM (the `local` provider).
  static const hfLlmRepo = 'TheStageAI/LFM2.5-350M';
  static const hfSttRepo = 'TheStageAI/thewhisper-large-v3-turbo';
  static const hfTtsRepo = 'TheStageAI/neutts-nano-multilingual';

  /// The model the `openai_compatible` provider starts with.
  static const cloudDefaultModel = 'gpt-4o-mini';

  /// Shipping on-device LLMs (see docs/llm.md).
  static const availableHfLlms = [
    'TheStageAI/LFM2.5-350M',
    'TheStageAI/LFM2.5-230M',
    'TheStageAI/LFM2.5-1.2B',
    'TheStageAI/LFM3-1.7B',
    'TheStageAI/Qwen3.5-0.8B',
    'TheStageAI/Qwen3.5-2B',
    'TheStageAI/Qwen3.5-4B',
    'TheStageAI/Qwen3.5-9B', // 8 Elite and 8 Elite Gen 5 only
  ];

  /// Shipping ASR repos (Whisper large-v3 turbo).
  static const availableHfAsr = [
    'TheStageAI/thewhisper-large-v3-turbo',
  ];

  /// Shipping TTS repos (the NeuTTS families).
  static const availableHfTts = [
    'TheStageAI/neutts-multilingual',
    'TheStageAI/neutts-nano-multilingual',
  ];

  String sttRepo = hfSttRepo;
  // NeuTTS engines: an HF repo id, or a local bundle path via
  // --dart-define=NEUTTS_ENGINES_PATH.
  String ttsRepo = const String.fromEnvironment(
    'NEUTTS_ENGINES_PATH',
    defaultValue: hfTtsRepo,
  );
  // Smart-turn engines (used when [useDnnTurn]): an HF repo id, or a
  // local bundle via --dart-define=TURN_DETECTOR_ENGINES_PATH.
  String turnDetectorRepo = const String.fromEnvironment(
    'TURN_DETECTOR_ENGINES_PATH',
    defaultValue: 'TheStageAI/smart-turn-v3',
  );

  // ── Voice & language ─────────────────────────────────────────────────────
  /// Offered before the TTS has loaded. Once it has, [voices] holds the
  /// loaded bundle's own list (the agent's `voices` event).
  static const fallbackVoices = ['paul', 'bril', 'dave', 'jo'];
  static const availableLanguages = ['en', 'auto', 'fr', 'de', 'es'];

  List<String> voices = fallbackVoices;
  String ttsVoice = 'paul';
  String sttLanguage = 'en';
  // Short strict persona. No few-shot cities — small packs copy them.
  // The call markup comes from the SDK's tools section, not from here.
  // Keep "Tool pattern (always):" so the SDK does not append a second
  // spoken-hint block.
  String systemPrompt = '''
You are a short on-device voice assistant. Answer in complete sentences. Use the user's language.

Use a tool only when the user asks for it or for a fact you must look up: live facts (weather, time, search), an encyclopedia summary, arithmetic, or a phone action the user asked for (call, map, message, e-mail). Greetings, chit-chat, and opinions: answer yourself — no tool, no filler, no city, no weather.

Tool pattern (always):
1) Need a tool? One short filler, then the exact markup from the tools section (do not speak the markup).
2) After the tool result: 1–2 sentences using only that result.
3) No tool needed? Answer the question directly.

Never invent facts. Never name a place, time, or number the user did not ask and the tool did not return. Never read JSON aloud. Never stop after one word.
'''.trim();

  /// Built-in tool preset for the on-device LLM: voice | web | phone |
  /// live | none. Default `voice`, the SDK's own default: weather, time,
  /// web search, Wikipedia, the calculator and the phone actions
  /// (dialer, maps, SMS, e-mail, clipboard, battery — each opens system
  /// UI for the user to confirm). `web` / `live` keep only weather, time
  /// and search. Weather and search send the city / query to Open-Meteo,
  /// DuckDuckGo and Wikipedia. An OpenAI-compatible endpoint gets no
  /// tools.
  String llmTools = 'voice';
  static const availableLlmTools = ['voice', 'web', 'phone', 'live', 'none'];

  // ── LLM provider ─────────────────────────────────────────────────────────
  // local: llm_model is the on-device LLM's HF repo id (see [hfLlmRepo]); the
  // agent runs it with thinking off.
  // openai_compatible: llm_model is the cloud model name, sent with
  // [llmEndpoint] and the OPENAI_API_KEY.
  String llmProvider = 'local';
  String llmModel = hfLlmRepo;
  String llmEndpoint = 'https://api.openai.com/v1/chat/completions';
  // The reply's token cap, for both providers.
  int maxTokens = 256;
  // Cloud only: the on-device models decode greedily and ignore it.
  double temperature = 0.7;

  /// Switch the LLM provider and give [llmModel] a value that makes
  /// sense for it: an on-device repo for `local`, a cloud model name for
  /// `openai_compatible`.
  void selectProvider(String provider) {
    llmProvider = provider;
    final onDevice = availableHfLlms.contains(llmModel);
    if (provider == 'local' && !onDevice) {
      llmModel = hfLlmRepo;
    } else if (provider != 'local' && onDevice) {
      llmModel = cloudDefaultModel;
    }
  }

  void selectTtsRepo(String repo) {
    if (repo == ttsRepo) return;
    ttsRepo = repo;
    // A different bundle has its own voices; they arrive on next Start.
    voices = fallbackVoices;
    if (!voices.contains(ttsVoice)) ttsVoice = voices.first;
  }

  /// Take the loaded TTS bundle's voices (the agent's `voices` event)
  /// and the voice it actually uses.
  void applyBundleVoices(List<String> bundleVoices, {String? current}) {
    if (bundleVoices.isEmpty) return;
    voices = List.unmodifiable(bundleVoices);
    if (current != null && voices.contains(current)) {
      ttsVoice = current;
    } else if (!voices.contains(ttsVoice)) {
      ttsVoice = voices.first;
    }
    notifyListeners();
  }

  // ── Endpointing (VAD) ────────────────────────────────────────────────────
  int silenceTimeoutMs = 600;
  double vadThreshold = 0.8;
  int vadOnsetMs = 96;
  int maxAccumulationMs = 30000;

  // ── Turn detection (end-of-turn). DNN = pipecat smart-turn. ──────────────
  // On by default. Force VAD-silence endpointing with
  // --dart-define=USE_DNN_TURN=false.
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
  // Log a single monotonic cross-node event timeline under the `Timeline`
  // logcat tag. Read it with:
  //   adb logcat -s Timeline:I
  bool debugTimeline = false;

  // ── Wake word ────────────────────────────────────────────────────────────
  // The SDK supports a wake word (the `wake_word` key below), but a
  // wake-word model recognises one specific phrase, so this example ships
  // without one: the agent always listens continuously. The threshold and
  // timeout stay here to show the config surface a wake word would use.
  final bool wakeWordEnabled = false;
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
  // longer window on the FIRST reply that covers the echo canceller's cold
  // start; it's set generously here because on a warm restart (models
  // cached) the first reply arrives before AEC has fully converged, which
  // otherwise self-interrupts.
  int interruptMinPlaybackMs = 250;
  int interruptInitialLockoutMs = 1500;
  int interruptThinkingLockoutMs = 600;

  // ── Audio ────────────────────────────────────────────────────────────────
  int preRollMs = 200;
  bool aecEnabled = true;
  // Silence played at start so the echo canceller has reference samples
  // before the first real TTS. 400 ms here, above the SDK's 250 ms default,
  // for margin on a warm restart.
  int aecWarmupMs = 400;
  // Grace after each TTS turn drains before the mic is trusted again.
  int aecPlaybackGateTailMs = 80;

  // ── ASR ──────────────────────────────────────────────────────────────────
  bool speculativeWhisper = true;

  /// Flatten the settings into the `config` map `agent.start(config:)` reads.
  /// Grouped by subsystem so the LLM / ASR / TTS / turn-detection wiring is
  /// obvious at a glance.
  Map<String, dynamic> toConfig(String apiKey) => {
        // ── Models the agent loads ──
        'vad': 'TheStageAI/silero-vad',
        'stt': sttRepo,
        'tts': ttsRepo,
        // No `*_revision` keys on purpose: an explicit revision overrides
        // the SDK's pinned one, which is the revision we test and ship.
        // Pass one only to try a bundle that is not pinned yet.
        'tts_voice': ttsVoice,
        // No wake-word bundle ships with this example, so the agent never
        // rests in `sleeping`. Set this to a bundle to enable a wake word.
        'wake_word': null,

        // ── LLM wiring (what produces the assistant's words) ──
        'llm_provider': llmProvider,
        'llm_model': llmModel,
        // Local: the on-device LLM's engines (HF repo id).
        if (llmProvider == 'local') 'llm': llmModel,
        if (llmProvider != 'local') ...{
          'llm_endpoint': llmEndpoint,
          'llm_api_key': apiKey,
          'temperature': temperature,
        },
        'system_prompt': systemPrompt,
        'llm_tools': llmTools,
        'max_tokens': maxTokens,

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
        'turn_detection_mode': useDnnTurn ? 'dnn' : 'vad',
        'turn_detector': turnDetectorRepo,
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

  /// Mutate settings inside [fn] and notify listeners (the Settings screen).
  void update(void Function(VoiceAgentSettings s) fn) {
    fn(this);
    notifyListeners();
  }
}
