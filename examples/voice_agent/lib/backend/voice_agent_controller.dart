import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:thestage_android_sdk/thestage_android_sdk.dart';

import '../models/chat_message.dart';

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
//   tool_started           ◄LLM called a tool          [messages] (tool)
//   tool_ended             ◄the tool returned          [messages] (tool)
//   error                       something failed       [error]
//   metrics                     mic level / loader      [vadLevel] / loading*
//   voices                      the TTS bundle's voices [onVoices]
//
//   agent.tts_levels            speech level, 0..1     [ttsLevel]
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
  VoiceAgentController(this._agent, {this.onVoices}) {
    // (1) SUBSCRIBE. Three streams, cancelled in [dispose].
    //   • agent.events    — the live conversation/pipeline events.
    //   • on_progress     — per-model download/extract/compile progress.
    //   • agent.tts_levels — loudness of the reply as it plays.
    _eventSub = _agent.events.listen(_onEvent);
    _progressSub = TheStageFlutterSDK.on_progress.listen(_onProgress);
    _ttsLevelSub = _agent.tts_levels.listen((level) {
      ttsLevel = level;
      notifyListeners();
    });
  }

  final TSVoiceAgent _agent;

  /// Called with the loaded TTS bundle's voices and the one in use.
  final void Function(List<String> voices, String? current)? onVoices;

  StreamSubscription<Map<String, dynamic>>? _eventSub;
  StreamSubscription<Map<String, dynamic>>? _progressSub;
  StreamSubscription<double>? _ttsLevelSub;

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

  /// What the started agent can do (`listening` / `transcribing` /
  /// `responding` / `speaking` + `reasons`), from `start`.
  Map<String, dynamic> capabilities = const {};
  String? error;

  /// Live microphone activity while listening, 0..1 (drives the mic meter).
  double vadLevel = 0.0;

  /// Loudness of the reply as it plays, 0..1 (drives the speaking meter).
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
    notifyListeners();
    try {
      capabilities = await _agent.start(config: config);
    } catch (e) {
      error = 'Failed to start: ${_describe(e)}';
      // Tear down whatever came up before the failure; the agent may
      // already be gone, so a failure here changes nothing.
      try {
        await _agent.stop();
      } catch (_) {}
      _resetToIdle();
    } finally {
      busy = false;
      starting = false;
      notifyListeners();
    }
  }

  /// Stop the agent and reset the live (non-finalized) state. Committed
  /// [messages] are kept so the transcript stays on screen.
  Future<void> stop() async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      await _agent.stop();
    } catch (e) {
      error = 'Failed to stop: ${_describe(e)}';
    } finally {
      _resetToIdle();
      busy = false;
      notifyListeners();
    }
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

      // ─── Tools: what the agent looked up (shown, never spoken) ───
      case 'tool_started':
        final name = event['name']?.toString() ?? 'tool';
        final args = event['arguments']?.toString() ?? '{}';
        messages.add(ChatMessage(
          role: MessageRole.tool,
          text: '⚙ $name\n$args',
          meta: {'name': name, 'phase': 'started', 'content': args},
        ));

      case 'tool_ended':
        final name = event['name']?.toString() ?? 'tool';
        final content = event['content']?.toString() ?? '';
        messages.add(ChatMessage(
          role: MessageRole.tool,
          text: '✓ $name →\n$content',
          meta: {'name': name, 'phase': 'ended', 'content': content},
        ));

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

  void _resetToIdle() {
    state = TSAgentState.idle;
    partialTranscript = '';
    streamingResponse = '';
    vadLevel = 0.0;
    ttsLevel = 0.0;
    _resetLoading();
  }

  static String _describe(Object e) =>
      e is PlatformException ? (e.message ?? e.code) : '$e';

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
    _ttsLevelSub?.cancel();
    super.dispose();
  }
}
