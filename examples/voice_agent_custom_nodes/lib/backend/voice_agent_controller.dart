import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

import '../models/chat_message.dart';
import '../nodes/event_log_node.dart';
import '../nodes/vlm_caption_node.dart';
import 'model_roster.dart';

// ============================================================================
// BACKEND layer — the ONE bridge between the native voice agent and the UI
// ============================================================================
// The native `TSVoiceAgent` runs the whole pipeline (mic → VAD →
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
//   voices                      the TTS bundle's voices [onVoices]
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
/// A VLM the caption node can use.
class VlmChoice {
  const VlmChoice(this.label, this.enginesPath, this.modelType);
  final String label;
  final String enginesPath;
  final String modelType;
}

class VoiceAgentController extends ChangeNotifier {
  VoiceAgentController(this._agent, {this.onVoices}) {
    // (1) SUBSCRIBE. Two streams, cancelled in [dispose].
    //   • agent.events    — the live conversation/pipeline events.
    //   • on_progress     — per-model download/extract/compile progress.
    _eventSub = _agent.events.listen(_onEvent);
    // Loudness of the reply as it plays, for the speaking meter.
    _ttsLevelSub = _agent.tts_levels.listen((level) {
      ttsLevel = level;
      notifyListeners();
    });
    _progressSub = TheStageFlutterSDK.on_progress.listen(_onProgress);
  }

  final TSVoiceAgent _agent;

  /// Called with the loaded TTS bundle's voices and the one in use.
  final void Function(List<String> voices, String? current)? onVoices;

  StreamSubscription<Map<String, dynamic>>? _eventSub;
  StreamSubscription<Map<String, dynamic>>? _progressSub;
  StreamSubscription<String>? _captionSub;
  StreamSubscription<double>? _ttsLevelSub;

  // ── Custom-nodes demo state ──────────────────────────────────────────────
  // Fully-on-device VLM captioner. The LFM2.5-VL repo is overridable at
  // build time (an HF repo id or a local bundle path).
  static const vlmEnginesPath = String.fromEnvironment(
    'LFM2VL_ENGINES_PATH',
    defaultValue: 'TheStageAI/LFM2.5-VL-450M',
  );
  // Empty resolves each repo's SDK-pinned commit.
  static const vlmRevision = String.fromEnvironment(
    'LFM2VL_REVISION',
    defaultValue: '',
  );

  static const vlmChoices = [
    VlmChoice('LFM2.5-VL 450M', vlmEnginesPath, 'lfm2-vl'),
    VlmChoice('Gemma 4 E2B', 'TheStageAI/gemma-4-E2B-it', 'gemma4-vl'),
  ];

  /// The VLM the next caption uses.
  VlmChoice selectedVlm = vlmChoices.first;

  /// Whether a caption is in flight (the VLM picker stays locked).
  bool get captioning => _captionInFlight != null;
  Future<void>? _captionInFlight;

  /// Completed by [stop], so a caption waiting for a quiet agent state
  /// gives up instead of waiting on an agent that is gone.
  Completer<void>? _stopSignal;

  /// Attached to the native graph via `extra_nodes` on [start]. [eventLog]
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

  // True from a reply's response_done until the next turn starts.
  bool _replyDone = false;

  /// Live (streaming-ASR) partial of what you're saying *right now*, before
  /// the turn ends and the final `user_request` line lands. Empty otherwise.
  String partialTranscript = '';

  // ── Agent status ─────────────────────────────────────────────────────────

  TSAgentState state = TSAgentState.idle;
  String? error;

  /// Live microphone activity while listening, 0..1 (drives the mic meter).
  double vadLevel = 0.0;

  /// Speech level of the reply while it plays, 0..1 (`tts_levels`).
  double ttsLevel = 0.0;

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

  /// A [start] or [stop] call is in flight: Start/Stop stay disabled.
  bool busy = false;

  /// [start] is in flight (models loading).
  bool starting = false;

  bool get isRunning => state != TSAgentState.idle;
  bool get canInterrupt =>
      state == TSAgentState.thinking ||
      state == TSAgentState.tool_calling ||
      state == TSAgentState.speaking;

  // ── Commands (called by the UI) ──────────────────────────────────────────

  /// The roster slot for [choice]: the VLM as an ephemeral handle,
  /// started only for a caption burst. Agent-owned VAD/STT/TTS are not
  /// roster handles.
  static ModelSlot vlmSlot(VlmChoice choice) => ModelSlot(
        name: 'vlm',
        enginesPath: choice.enginesPath,
        modelType: choice.modelType,
        policy: ModelPolicy.ephemeral,
        revision: vlmRevision,
      );

  /// Pick the VLM for the next caption.
  void selectVlm(VlmChoice choice) {
    if (captioning || choice == selectedVlm) return;
    selectedVlm = choice;
    if (roster != null) roster = ModelRoster([vlmSlot(choice)]);
    notifyListeners();
  }

  /// Start the agent with a fully-built config map (see
  /// `VoiceAgentSettings.toConfig`). The native side loads models, then
  /// begins listening; progress arrives via the subscriptions above. A
  /// failed start leaves the controller idle with [error] set, so Start
  /// works again.
  Future<void> start(Map<String, dynamic> config) async {
    if (busy || isRunning) return;
    busy = true;
    starting = true;
    error = null;
    _stopSignal = Completer<void>();

    roster = ModelRoster([vlmSlot(selectedVlm)]);

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
      enginesPath: selectedVlm.enginesPath,
      modelType: selectedVlm.modelType,
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
        extra_nodes: [v, eventLog!],
      );
    } catch (e) {
      error = 'Failed to start: ${_describe(e)}';
      // Tear down whatever came up before the failure; the agent may
      // already be gone, so a failure here changes nothing.
      try {
        await _agent.stop();
      } catch (_) {}
      await _teardown();
    } finally {
      busy = false;
      starting = false;
      notifyListeners();
    }
  }

  /// Caption an image with the ephemeral VLM. Waits until the agent is
  /// in a quiet state (never captions mid-turn), starts the VLM handle,
  /// runs one inference, then stops it. Result lands in [captions].
  Future<void> captionImage(String path) {
    final running = _captionInFlight;
    if (running != null) return running;
    final f = _caption(path);
    _captionInFlight = f;
    notifyListeners();
    return f.whenComplete(() {
      _captionInFlight = null;
      notifyListeners();
    });
  }

  Future<void> _caption(String path) async {
    final node = vlm;
    final r = roster;
    if (node == null || r == null) return;
    try {
      await _waitUntilQuiet();
      await r.withEphemeralSwap(
        'vlm',
        // The agent owns STT/TTS, so there is nothing for the roster to
        // park here; a host that also runs other roster models lists
        // them.
        park: const [],
        body: () async {
          node.markReady(ready: true);
          await node.submitImage(path: path);
        },
      );
    } catch (e) {
      error = 'VLM caption failed: ${_describe(e)}';
    } finally {
      node.markReady(ready: false);
    }
  }

  /// Inject a typed user turn (bypasses mic + ASR), driving LLM → TTS.
  /// Throws when the agent rejects it; the caller shows the error.
  Future<void> sendText(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await _agent.send_request(t);
  }

  /// Wait until the agent leaves an active turn (thinking / speaking).
  /// Throws when [stop] runs first or the wait times out.
  Future<void> _waitUntilQuiet({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    bool quiet(TSAgentState s) =>
        s == TSAgentState.idle ||
        s == TSAgentState.sleeping ||
        s == TSAgentState.listening;
    if (quiet(state)) return;
    final done = Completer<void>();
    final stopped = _stopSignal?.future;
    late StreamSubscription sub;
    sub = _agent.events.listen((e) {
      if (e['kind'] != 'state_changed') return;
      final s = TSAgentState.fromString(
        e['state']?.toString() ?? 'idle',
      );
      if (quiet(s) && !done.isCompleted) done.complete();
    });
    try {
      await Future.any([
        done.future,
        if (stopped != null)
          stopped.then<void>((_) => throw StateError('agent stopped')),
      ]).timeout(timeout);
    } finally {
      await sub.cancel();
    }
  }

  /// Stop the agent and reset the live (non-finalized) state. Committed
  /// [messages] are kept so the transcript stays on screen. A caption in
  /// flight finishes (or gives up) before the VLM node is disposed.
  Future<void> stop() async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      await _agent.stop();
    } catch (e) {
      error = 'Failed to stop: ${_describe(e)}';
    } finally {
      await _teardown();
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _teardown() async {
    final signal = _stopSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
    _stopSignal = null;
    final inFlight = _captionInFlight;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {}
    }
    try {
      await roster?.release(['vlm']);
    } catch (_) {}
    await _captionSub?.cancel();
    _captionSub = null;
    vlm?.dispose();
    vlm = null;
    eventLog = null;
    state = TSAgentState.idle;
    partialTranscript = '';
    streamingResponse = '';
    vadLevel = 0.0;
    ttsLevel = 0.0;
    _resetLoading();
  }

  /// Barge-in: stop the agent mid-thought/mid-speech (only valid while
  /// [canInterrupt]).
  Future<void> interrupt() async {
    try {
      await _agent.interrupt();
    } catch (e) {
      error = 'Interrupt failed: ${_describe(e)}';
      notifyListeners();
    }
  }

  static String _describe(Object e) =>
      e is PlatformException ? (e.message ?? e.code) : '$e';

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
        state = TSAgentState.fromString(
          event['state']?.toString() ?? 'idle',
        );
        // Leaving `loading` means startup finished — clear the loader state.
        if (state != TSAgentState.loading) _resetLoading();

      // ─── ASR path: what YOU said ───
      case 'user_request_partial':
        // Streaming ASR caption: grows as you speak. Feeds the live USER
        // bubble. Replaced wholesale each event (it's the full partial so far).
        partialTranscript = event['text']?.toString() ?? '';

      case 'user_request':
        // A new turn: its reply's deltas are welcome again.
        _replyDone = false;
        // Turn ended: the authoritative transcript. Drop the live partial and
        // commit a permanent USER line.
        partialTranscript = '';
        messages.add(ChatMessage(
          role: MessageRole.user,
          text: event['text']?.toString() ?? '',
        ));

      // ─── LLM path: what the AGENT said ───
      case 'response_started':
        _replyDone = false;

      case 'response_delta':
        // A delta that arrives after its reply's response_done must
        // not reopen a live bubble: the committed line already has it.
        if (_replyDone) break;
        // One streamed LLM token/chunk. Append to the live ASSISTANT bubble.
        streamingResponse += event['delta']?.toString() ?? '';

      case 'response_done':
        _replyDone = true;
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

      case 'voices':
        // The loaded TTS bundle's voices, and the one the agent uses.
        final vs = event['voices'];
        if (vs is List) {
          onVoices?.call(
            [for (final v in vs) '$v'],
            event['current']?.toString(),
          );
        }

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
    _ttsLevelSub?.cancel();
    _progressSub?.cancel();
    _captionSub?.cancel();
    vlm?.dispose();
    super.dispose();
  }
}
