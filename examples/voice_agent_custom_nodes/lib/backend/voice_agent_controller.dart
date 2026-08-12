import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

import '../models/chat_message.dart';
import '../nodes/event_log_node.dart';
import '../nodes/vlm_caption_node.dart';
import 'model_roster.dart';

// ============================================================================
// BACKEND layer — the ONE bridge between the native voice agent and the UI
// ============================================================================
// The native `TheStageVoiceAgentFlutter` runs the whole pipeline (mic → VAD →
// ASR → LLM → TTS → speaker) and emits a single stream of events. This class
// is the *only* place that:
//
//   1. SUBSCRIBES to those events (see constructor), and
//   2. TRANSLATES each event into plain, typed UI state (see [_onEvent]).
//
// The frontend never touches the SDK. It reads the fields below and calls
// [start] / [stop] / [interrupt]. Because this class is a [ChangeNotifier],
// any widget wrapped in an `AnimatedBuilder`/`ListenableBuilder` rebuilds when
// state changes.
//
// ───────────────────────── Event → state map ──────────────────────────────
//
//   agent.events['kind']        what it means          field(s) updated
//   ─────────────────────       ──────────────         ───────────────────
//   state_changed               agent FSM moved        [state]
//   user_request_partial   ◄ASR live caption           [partialTranscript]
//   user_request           ◄ASR finalized your turn    [messages] (user)
//   response_delta         ◄LLM streamed token         [streamingResponse]
//   response_done          ◄LLM final reply            [messages] (assistant)
//   error                       something failed       [error]
//   metrics                     mic level / loader      [vadLevel] / loading*
//
//   TheStageFlutterSDK.on_progress  model download/extract/compile progress
//                                   → [downloadProgress], [loadPhase]
//
// ASR (what you say)  → user_request_partial → user_request   (▲ two events)
// LLM (what it says)  → response_delta…      → response_done   (▲ two events)
//
// In both flows the FIRST event feeds a *live* (streaming) bubble and the
// SECOND finalizes it into a permanent [messages] line. The frontend draws the
// live bubbles from [partialTranscript] / [streamingResponse] and the final
// ones from [messages]; see `ui/widgets/transcript_area.dart`.
// ============================================================================
class VoiceAgentController extends ChangeNotifier {
  VoiceAgentController(this._agent) {
    // (1) SUBSCRIBE. Two streams, two handlers, cancelled in [dispose].
    //   • agent.events    — the live conversation/pipeline events.
    //   • on_progress     — per-model download/extract/compile progress.
    _eventSub = _agent.events.listen(_onEvent);
    _progressSub = TheStageFlutterSDK.on_progress.listen(_onProgress);
  }

  final TheStageVoiceAgentFlutter _agent;
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  StreamSubscription<Map<String, dynamic>>? _progressSub;
  StreamSubscription<String>? _captionSub;

  // ── Custom-nodes demo state ──────────────────────────────────────────────
  // Fully-on-device LFM2.5-VL captioner. HF repo id (Android engines on the
  // `android` branch), overridable at build time.
  static const vlmEnginesPath = String.fromEnvironment(
    'LFM2VL_ENGINES_PATH',
    defaultValue: 'TheStageAI/LFM2.5-VL-450M',
  );
  static const vlmRevision = String.fromEnvironment(
    'LFM2VL_REVISION',
    defaultValue: 'android',
  );

  /// Attached to the native graph via `extraNodes` on [start]. [eventLog]
  /// mirrors the internal bus into [busEvents]; [vlm] captions images.
  EventLogNode? eventLog;
  VLMCaptionNode? vlm;
  ModelRoster? roster;

  /// Newest-first internal-bus events observed by [EventLogNode.onEvent].
  final List<String> busEvents = [];

  /// Newest-first VLM captions produced by [VLMCaptionNode].
  final List<String> captions = [];

  // ── Conversation state (rendered by the transcript) ──────────────────────

  /// Finalized transcript lines (user + assistant), oldest first.
  final List<ChatMessage> messages = [];

  /// The assistant reply currently being streamed token-by-token, before it's
  /// finalized into [messages]. Empty when the assistant isn't mid-sentence.
  String streamingResponse = '';

  /// Live (streaming-ASR) partial of what you're saying *right now*, before
  /// the turn ends and the final `user_request` line lands. Empty otherwise.
  String partialTranscript = '';

  // ── Agent status ─────────────────────────────────────────────────────────

  TheStageAgentState state = TheStageAgentState.idle;
  String? error;

  /// Live microphone activity while listening, 0..1 (drives the mic meter).
  double vadLevel = 0.0;

  // ── Startup model loading ────────────────────────────────────────────────

  /// Models in the order the SDK loads them (VAD, Whisper, NeuTTS, ...). Each
  /// is announced by a `metrics` event before its progress starts streaming.
  final List<String> loadingModels = [];

  /// The model currently loading (everything earlier in [loadingModels] is
  /// done). `null` once loading completes.
  String? currentLoadingModel;

  /// Download fraction (0..1) for [currentLoadingModel] while downloading.
  double downloadProgress = 0.0;

  /// Phase for [currentLoadingModel]: downloading / extracting / loading.
  String loadPhase = '';

  // ── Derived helpers the UI asks about ────────────────────────────────────

  bool get isRunning => state != TheStageAgentState.idle;
  bool get canInterrupt =>
      state == TheStageAgentState.thinking ||
      state == TheStageAgentState.speaking;

  // ── Commands (called by the UI) ──────────────────────────────────────────

  /// Start the agent with a fully-built config map (see `AgentConfig`/
  /// `VoiceAgentSettings.toConfig`). The native side loads models, then begins
  /// listening; progress arrives via the subscriptions above.
  Future<void> start(Map<String, dynamic> config) async {
    error = null;

    // Roster with the VLM as an ephemeral slot (started only for a caption
    // burst). Agent-owned VAD/STT/TTS are not roster handles on Android.
    roster = ModelRoster([
      ModelSlot(
        name: 'vlm',
        enginesPath: vlmEnginesPath,
        modelType: 'lfm2-vl',
        policy: ModelPolicy.ephemeral,
        revision: vlmRevision,
      ),
    ]);

    // (a) EventLogNode — mirror the internal bus into [busEvents].
    eventLog = EventLogNode(
      onBusEvent: (e) {
        busEvents.insert(0, '${e['kind'] ?? '?'}: $e');
        if (busEvents.length > 80) {
          busEvents.removeRange(80, busEvents.length);
        }
        notifyListeners();
      },
    );

    // (b) VLMCaptionNode — host-owned residency (roster starts/stops it).
    final v = VLMCaptionNode(
      enginesPath: vlmEnginesPath,
      revision: vlmRevision,
      lifecycle: VlmLifecycle.external,
    );
    vlm = v;
    await _captionSub?.cancel();
    _captionSub = v.captions.listen((c) {
      captions.insert(0, c);
      if (captions.length > 20) captions.removeRange(20, captions.length);
      notifyListeners();
    });

    notifyListeners();
    try {
      await _agent.start(
        config: config,
        extraNodes: [v, eventLog!],
      );
    } catch (e) {
      error = 'Failed to start: $e';
      notifyListeners();
    }
  }

  /// Caption an image with the ephemeral VLM. Blocks until the agent is in
  /// a quiet state (never captions mid-turn), starts the `lfm2-vl` handle,
  /// runs one inference, then stops it. Result lands in [captions].
  Future<void> captionImage(String path) async {
    final node = vlm;
    final r = roster;
    if (node == null || r == null) return;
    try {
      await _waitUntilQuiet();
      await r.withEphemeralSwap(
        'vlm',
        // Agent owns STT/TTS and the LLM is remote, so there is nothing
        // for the roster to park here — kept for API parity.
        park: const [],
        body: () async {
          node.markReady(ready: true);
          await node.submitImage(path: path);
        },
      );
    } catch (e) {
      error = 'VLM caption failed: $e';
    } finally {
      node.markReady(ready: false);
      notifyListeners();
    }
  }

  /// Inject a typed user turn (bypasses mic + ASR), driving LLM → TTS.
  Future<void> sendText(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await _agent.sendRequest(t);
  }

  /// Block until the agent leaves an active turn (thinking / speaking).
  Future<void> _waitUntilQuiet({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    bool quiet(TheStageAgentState s) =>
        s == TheStageAgentState.idle ||
        s == TheStageAgentState.sleeping ||
        s == TheStageAgentState.listening;
    if (quiet(state)) return;
    final done = Completer<void>();
    late StreamSubscription sub;
    sub = _agent.events.listen((e) {
      if (e['kind'] != 'state_changed') return;
      final s = TheStageAgentState.fromString(
        e['state']?.toString() ?? 'idle',
      );
      if (quiet(s) && !done.isCompleted) done.complete();
    });
    try {
      await done.future.timeout(timeout);
    } finally {
      await sub.cancel();
    }
  }

  /// Stop the agent and reset the live (non-finalized) state. Committed
  /// [messages] are kept so the transcript stays on screen.
  Future<void> stop() async {
    await _agent.stop();
    await roster?.release(['vlm']);
    await _captionSub?.cancel();
    _captionSub = null;
    vlm?.dispose();
    vlm = null;
    eventLog = null;
    state = TheStageAgentState.idle;
    partialTranscript = '';
    streamingResponse = '';
    notifyListeners();
  }

  /// Barge-in: stop the agent mid-thought/mid-speech (only valid while
  /// [canInterrupt]).
  Future<void> interrupt() => _agent.interrupt();

  void clearError() {
    error = null;
    notifyListeners();
  }

  // ── (2) TRANSLATE: event → typed state ───────────────────────────────────
  // This is the heart of the bridge. Every case maps one SDK event onto the
  // fields above, then notifies listeners so the UI repaints.
  void _onEvent(Map<String, dynamic> event) {
    switch (event['kind']?.toString()) {
      case 'state_changed':
        state = TheStageAgentState.fromString(
          event['state']?.toString() ?? 'idle',
        );
        // Leaving `loading` means startup finished — clear the loader state.
        if (state != TheStageAgentState.loading) _resetLoading();

      // ─── ASR path: what YOU said ───
      case 'user_request_partial':
        // Streaming ASR caption: grows as you speak. Feeds the live USER
        // bubble. Replaced wholesale each event (it's the full partial so far).
        partialTranscript = event['text']?.toString() ?? '';

      case 'user_request':
        // Turn ended: the authoritative transcript. Drop the live partial and
        // commit a permanent USER line.
        partialTranscript = '';
        messages.add(ChatMessage(
          role: MessageRole.user,
          text: event['text']?.toString() ?? '',
        ));

      // ─── LLM path: what the AGENT said ───
      case 'response_delta':
        // One streamed LLM token/chunk. Append to the live ASSISTANT bubble.
        streamingResponse += event['delta']?.toString() ?? '';

      case 'response_done':
        // LLM reply finished (or was interrupted). Commit a permanent
        // ASSISTANT line and clear the live stream.
        final raw = event['text']?.toString() ?? '';
        final interrupted = event['reason']?.toString() == 'interrupted' ||
            event['interrupted'] == true;
        // Prefer the SDK's authoritative final text; fall back to what we
        // streamed (e.g. interrupted before a final string was emitted).
        final text = raw.isNotEmpty ? raw : streamingResponse;
        if (text.isNotEmpty) {
          messages.add(ChatMessage(
            role: MessageRole.assistant,
            text: interrupted ? '$text …' : text,
          ));
        }
        streamingResponse = '';

      case 'error':
        error = event['message']?.toString();

      case 'metrics':
        // Two unrelated diagnostics ride on `metrics`:
        //   • vad_prob      — live mic level while listening.
        //   • loading_model — name of the model about to load (startup only).
        final prob = (event['vad_prob'] as num?)?.toDouble();
        if (prob != null) vadLevel = prob;
        final model = event['loading_model']?.toString();
        if (model != null && model != currentLoadingModel) {
          currentLoadingModel = model;
          if (!loadingModels.contains(model)) loadingModels.add(model);
          downloadProgress = 0.0;
          loadPhase = '';
        }
    }
    notifyListeners();
  }

  /// Progress always belongs to the model currently loading (loads are
  /// sequential), so we apply it to [currentLoadingModel].
  void _onProgress(Map<String, dynamic> event) {
    downloadProgress = (event['progress'] as num?)?.toDouble() ?? 0.0;
    loadPhase = event['phase']?.toString() ?? '';
    notifyListeners();
  }

  void _resetLoading() {
    loadingModels.clear();
    currentLoadingModel = null;
    downloadProgress = 0.0;
    loadPhase = '';
  }

  @override
  void dispose() {
    // Mirror of the constructor: always release the subscriptions.
    _eventSub?.cancel();
    _progressSub?.cancel();
    _captionSub?.cancel();
    vlm?.dispose();
    super.dispose();
  }
}
