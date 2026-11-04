import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'method_channels.dart';

// ---------------------------------------------------------------------------
// ModelAvailability
// ---------------------------------------------------------------------------
/// Whether a model bundle is available for THIS device, as reported by
/// [TheStageFlutterSDK.check_model_availability] — resolvable before
/// [TheStageFlutterSDK.initialize], with no token and no download.
enum ModelAvailability {
  /// A published remote bundle exists for this device (HF).
  remote,

  /// The given path is a local bundle present on disk.
  local,

  /// Nothing available — see [ModelAvailabilityResult.reason].
  none,

  /// Availability could not be determined (SDK not initialized, or a
  /// transport failure during the probe).
  unknown,
}

ModelAvailability _availabilityFromRaw(String? raw) {
  switch (raw) {
    case 'remote':
      return ModelAvailability.remote;
    case 'local':
      return ModelAvailability.local;
    case 'none':
      return ModelAvailability.none;
    default:
      return ModelAvailability.unknown;
  }
}

/// Detail behind a [ModelAvailability].
enum AvailabilityReason {
  repoNotFound,
  variantUnavailable,

  /// `aipack_pack` — Play AI pack delivered or fetchable
  /// (install-time and on-demand alike).
  aipackPack,
  localMissing,
  networkUnreachable,
  notInitialized,
}

AvailabilityReason? _reasonFromRaw(String? raw) {
  switch (raw) {
    case 'repo_not_found':
      return AvailabilityReason.repoNotFound;
    case 'variant_unavailable':
      return AvailabilityReason.variantUnavailable;
    case 'aipack_pack':
      return AvailabilityReason.aipackPack;
    case 'local_missing':
      return AvailabilityReason.localMissing;
    case 'network_unreachable':
      return AvailabilityReason.networkUnreachable;
    case 'not_initialized':
      return AvailabilityReason.notInitialized;
    default:
      return null;
  }
}

/// Compute backend a remote bundle targets.
enum Compute { npu, cpu, gpu }

Compute? _computeFromRaw(String? raw) {
  switch (raw) {
    case 'npu':
      return Compute.npu;
    case 'cpu':
      return Compute.cpu;
    case 'gpu':
      return Compute.gpu;
    default:
      return null;
  }
}

/// Result of [TheStageFlutterSDK.check_model_availability].
class ModelAvailabilityResult {
  /// The headline answer (remote / local / none / unknown).
  final ModelAvailability availability;

  /// Detail behind [availability], when one applies.
  final AvailabilityReason? reason;

  /// Detected device variant (SoC). Set only on a `remote` result.
  final String? variant;

  /// Backend the matched remote bundle runs on. Set only on `remote`.
  final Compute? compute;

  /// The matched URL (remote) or path (local), when one was found.
  final String? source;

  /// Compressed bundle size (remote) or on-disk size (local), bytes.
  final int? bundleSizeBytes;

  const ModelAvailabilityResult({
    required this.availability,
    this.reason,
    this.variant,
    this.compute,
    this.source,
    this.bundleSizeBytes,
  });

  factory ModelAvailabilityResult.fromMap(
    Map<String, dynamic> map,
  ) {
    return ModelAvailabilityResult(
      availability: _availabilityFromRaw(map['availability'] as String?),
      reason: _reasonFromRaw(map['reason'] as String?),
      variant: map['variant'] as String?,
      compute: _computeFromRaw(map['compute'] as String?),
      source: map['source'] as String?,
      bundleSizeBytes: (map['bundle_size_bytes'] as num?)?.toInt(),
    );
  }
}

// ---------------------------------------------------------------------------
// Typed exceptions (Android-only error surfaces)
// ---------------------------------------------------------------------------

/// Thrown when the input exceeds the LLM bundle's compiled capacity
/// (Genie's static-cache constraint). Apps surface this with a
/// "shorten your input" UI.
class InputTooLongException implements Exception {
  InputTooLongException({required this.message});
  final String message;

  @override
  String toString() => 'InputTooLongException: $message';
}

/// Thrown when one sentence in streamed input exceeds the bundle's
/// compiled capacity. Apps typically surface a transient "sentence too
/// long" banner and continue.
class SentenceTooLongException implements Exception {
  SentenceTooLongException({required this.message});
  final String message;

  @override
  String toString() => 'SentenceTooLongException: $message';
}

/// Thrown by [TheStageFlutterSDK.start_model] when a bundle-backed
/// model can't be loaded because its on-disk files are missing,
/// incomplete or malformed — e.g. an OS cache-wipe removed the
/// extracted engines, a partial download left the bundle without its
/// `llm/` dir / `encoder_spec.json` / `metadata.json`, or a
/// Keystore/DEK reset left the sealed ctx-bins unrecoverable. Apps
/// surface this with a "reconnect and reload" UI; reloading re-fetches
/// the bundle.
class ModelUnavailableException implements Exception {
  ModelUnavailableException({required this.message});
  final String message;

  @override
  String toString() => 'ModelUnavailableException: $message';
}

/// Rethrows known PlatformExceptions as typed Dart exceptions; passes
/// everything else through. The plugin forwards the SDK's symbolic
/// error code (`INPUT_TOO_LONG` / `SENTENCE_TOO_LONG` /
/// `MODEL_UNAVAILABLE`) as `PlatformException.code`.
Never _rethrowTyped(PlatformException e) {
  if (e.code == 'INPUT_TOO_LONG') {
    throw InputTooLongException(message: e.message ?? 'Input too long');
  }
  if (e.code == 'SENTENCE_TOO_LONG') {
    throw SentenceTooLongException(
      message: e.message ?? 'One of the sentences is too long',
    );
  }
  if (e.code == 'MODEL_UNAVAILABLE') {
    throw ModelUnavailableException(
      message: e.message ?? 'Model unavailable',
    );
  }
  throw e;
}

// ---------------------------------------------------------------------------
// TheStageFlutterSDK
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Model lifecycle
// ---------------------------------------------------------------------------

/// How a staged bundle reached the device.
enum InstalledSource {
  /// Downloaded from Hugging Face.
  hf,

  /// Delivered by Google Play as an AI pack.
  aipack,

  /// A local directory or archive the app supplied.
  local,
}

InstalledSource? _installedSourceFromRaw(String? raw) {
  switch (raw) {
    case 'hf':
      return InstalledSource.hf;
    case 'aipack':
      return InstalledSource.aipack;
    case 'local':
      return InstalledSource.local;
  }
  return null;
}

/// Which comparison produced a [ModelUpdate].
///
/// [ModelUpdate.installed] and [ModelUpdate.available] live in this
/// kind's identity space and are never comparable across kinds.
enum UpdateKind {
  /// The pinned commit moved, or the staged bundle predates pinning
  /// and cannot be shown to be the pinned one. Both are commits.
  revision,

  /// The app ships an AI pack at a different release tag than the
  /// one staged. Both are release tags.
  tag,

  /// The app has named a different delivery route than the staged
  /// bundle came from. Both are route names.
  route,
}

UpdateKind _updateKindFromRaw(String? raw) {
  switch (raw) {
    case 'tag':
      return UpdateKind.tag;
    case 'route':
      return UpdateKind.route;
  }
  return UpdateKind.revision;
}

/// One model staged on this device.
class InstalledModel {
  final String modelType;
  final String variant;

  /// How it got here.
  final InstalledSource? source;

  /// A commit, a release tag or a source stamp depending on
  /// [source]. Compare it for equality; never parse it.
  final String identity;

  /// The repo it was downloaded from, when it was.
  final String? repository;

  /// The repo it was BUILT from, as the bundle itself declares.
  final String? sourceRepo;

  final String? slot;
  final int bytes;
  final String? archive;
  final int archiveBytes;

  /// Why a retained archive was kept, when one was.
  final String? retainedReason;

  final String? contentSha256;

  /// When the bundle was built, as it declares.
  final String? builtAt;

  /// What the app last asked for. Diverges from [identity] when a
  /// new pack tag is declared and the staged bundle keeps serving.
  final String? declaredIdentity;

  /// The route the app last named. Differs from [source] exactly
  /// when a route change is pending.
  final InstalledSource? declaredSource;

  /// The commit, when one is known. Null is a real answer.
  final String? hfRevision;

  /// True when Play also holds this pack's copy, so removing the
  /// model frees [bytes] and no more.
  final bool playCopyRetained;

  final int? installedAt;

  /// Tree plus any retained archive. Computed on the native side so
  /// the two halves cannot disagree about what a model occupies.
  final int totalBytes;

  const InstalledModel({
    required this.modelType,
    required this.variant,
    required this.identity,
    required this.bytes,
    required this.archiveBytes,
    required this.totalBytes,
    required this.playCopyRetained,
    this.source,
    this.repository,
    this.sourceRepo,
    this.slot,
    this.archive,
    this.retainedReason,
    this.contentSha256,
    this.builtAt,
    this.declaredIdentity,
    this.declaredSource,
    this.hfRevision,
    this.installedAt,
  });

  factory InstalledModel.fromMap(Map<String, dynamic> map) {
    return InstalledModel(
      modelType: map['model_type'] as String? ?? '',
      variant: map['variant'] as String? ?? '',
      source: _installedSourceFromRaw(map['source'] as String?),
      identity: map['identity'] as String? ?? '',
      repository: map['repository'] as String?,
      sourceRepo: map['source_repo'] as String?,
      slot: map['slot'] as String?,
      bytes: (map['bytes'] as num?)?.toInt() ?? 0,
      archive: map['archive'] as String?,
      archiveBytes: (map['archive_bytes'] as num?)?.toInt() ?? 0,
      retainedReason: map['retained_reason'] as String?,
      contentSha256: map['content_sha256'] as String?,
      builtAt: map['built_at'] as String?,
      declaredIdentity: map['declared_identity'] as String?,
      declaredSource:
          _installedSourceFromRaw(map['declared_source'] as String?),
      hfRevision: map['hf_revision'] as String?,
      playCopyRetained:
          map['play_copy_retained'] as bool? ?? false,
      installedAt: (map['installed_at'] as num?)?.toInt(),
      totalBytes: (map['total_bytes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A newer bundle exists for a staged model.
class ModelUpdate {
  final String modelType;
  final String variant;

  /// The repo this update is about, or null for a bundle with no
  /// repo (an AI pack, a local tree). Every text LLM shares one
  /// [modelType], so this is what tells two installed LLMs apart.
  final String? repository;

  /// What is on the device, in [kind]'s identity space.
  final String installed;

  /// What this build names, in the same space.
  final String available;

  final UpdateKind kind;

  const ModelUpdate({
    required this.modelType,
    required this.variant,
    this.repository,
    required this.installed,
    required this.available,
    required this.kind,
  });

  factory ModelUpdate.fromMap(Map<String, dynamic> map) {
    return ModelUpdate(
      modelType: map['model_type'] as String? ?? '',
      variant: map['variant'] as String? ?? '',
      repository: map['repository'] as String?,
      installed: map['installed'] as String? ?? '',
      available: map['available'] as String? ?? '',
      kind: _updateKindFromRaw(map['kind'] as String?),
    );
  }
}

/// The answer to "is this staged bundle intact?".
class SlotIntegrity {
  /// True when the bundle's contents matched what was published.
  final bool verified;

  /// False means the bundle carries no integrity data, so there is
  /// nothing to check it against — **not** corruption, and not a
  /// reason to repair. Re-downloading it would prove nothing.
  final bool verifiable;

  /// Why not, when [verified] is false; null when it is true.
  ///
  /// A stable code, not prose: `not_staged` (nothing installed),
  /// `not_verifiable` (no integrity data to check against),
  /// `check_failed` (checked and did not match), `check_error` (the
  /// check itself could not run). Safe to branch on.
  final String? reason;

  const SlotIntegrity({
    required this.verified,
    required this.verifiable,
    this.reason,
  });

  factory SlotIntegrity.fromMap(Map<String, dynamic> map) {
    return SlotIntegrity(
      verified: map['verified'] as bool? ?? false,
      verifiable: map['verifiable'] as bool? ?? false,
      reason: map['reason'] as String?,
    );
  }
}

/// What [TheStageFlutterSDK.maintain] reclaimed.
class SweepResult {
  /// Bytes freed.
  final int freed_bytes;

  /// Files and directories removed.
  final int removed_paths;

  const SweepResult({
    required this.freed_bytes,
    required this.removed_paths,
  });

  factory SweepResult.fromMap(Map<String, dynamic> map) {
    return SweepResult(
      freed_bytes: (map['freed_bytes'] as num?)?.toInt() ?? 0,
      removed_paths: (map['removed_paths'] as num?)?.toInt() ?? 0,
    );
  }
}

class TheStageFlutterSDK {
  static const MethodChannel _channel = MethodChannel(MethodChannels.main);
  static const EventChannel _progressChannel = EventChannel(
    MethodChannels.progress,
  );
  static const EventChannel _streamChannel = EventChannel(
    MethodChannels.ttsStream,
  );
  static const EventChannel _logsChannel = EventChannel(
    MethodChannels.logs,
  );
  static StreamSubscription<dynamic>? _logsSub;

  static StreamController<Map<String, dynamic>>? _streamEvents;
  static int _nextStreamOrdinal = 0;

  static void _ensureStreamChannel() {
    if (_streamEvents != null) return;
    _streamEvents = StreamController<Map<String, dynamic>>.broadcast();
    _streamChannel.receiveBroadcastStream().listen((event) {
      final map = event as Map<Object?, Object?>;
      _streamEvents!.add(
        map.map((key, value) => MapEntry(key.toString(), value)),
      );
    }, onError: (e) => _streamEvents!.addError(e));
  }

  /// Model download / preparation progress. Each event is a map
  /// always carrying `model_name` + `phase`, and at most one of
  /// `progress` or `status`.
  ///
  /// `phase` is the signal to drive your UI from. It is one of
  /// `downloading`, `waiting_for_wifi`,
  /// `waiting_for_confirmation`, `extracting`, `loading`, `ready`.
  ///
  ///  - `progress` (0..1) — present only while a transfer is
  ///    measurable, i.e. `downloading` (and `1.0` on `ready`).
  ///    **`extracting` and `loading` omit it**: unpacking,
  ///    and NPU compilation report nothing
  ///    intermediate, so there is no honest number to send. Bind a
  ///    determinate bar when the key is present and an
  ///    indeterminate one when it is absent.
  ///  - `status` (no `progress`) — an AI-pack fetch is parked
  ///    waiting on the network or the user:
  ///      * `waiting_for_confirmation` — the download needs the
  ///        user's OK to use cellular (>200 MB off Wi-Fi). Show
  ///        Play's confirmation dialog from your Activity
  ///        (`AiPackManager.showConfirmationDialog(launcher)`); the
  ///        fetch resumes automatically once approved.
  ///      * `waiting_for_wifi` — parked until an unmetered network
  ///        is available; prompt the user to connect to Wi-Fi.
  ///    HF-repo and local sources never emit `status`.
  static Stream<Map<String, dynamic>> get on_progress {
    return _progressChannel.receiveBroadcastStream().map((event) {
      final map = event as Map<Object?, Object?>;
      return map.map((key, value) => MapEntry(key.toString(), value));
    });
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// [hf_token] is optional: a Hugging Face access token for private or
  /// gated model repos. It is sent to huggingface.co only (stripped on CDN
  /// redirects) and never logged. Public models download without one.
  static Future<void> initialize({
    required String api_token,
    String? hf_token,
  }) async {
    ensureDeveloperLogs();
    // Open the inference-stream channel now, long before any model
    // runs. `receiveBroadcastStream().listen` registers the native
    // sink asynchronously; doing it lazily inside infer_stream means
    // a fast model can emit its first chunks before the sink exists,
    // and those are dropped with no error. Warming it here makes the
    // first generation behave like every later one.
    _ensureStreamChannel();
    await _channel.invokeMethod(
      MethodRoute.initialize,
      {
        'api_token': api_token,
        if (hf_token != null && hf_token.isNotEmpty) 'hf_token': hf_token,
      },
    );
  }

  /// Mirror the SDK's developer log stream into `flutter run`.
  ///
  /// The native SDK logs its lifecycle (model load/unload, download,
  /// cache, recovery, coarse timings) to `adb logcat`, which
  /// `flutter run` does not surface. This subscribes to the plugin's
  /// `logs` EventChannel and [debugPrint]s each line so it shows up in
  /// the Flutter console. Idempotent, and a no-op in release builds.
  /// Called automatically by [initialize]; call it earlier if you want
  /// the pre-initialize lines too. Lines are path-sanitized and carry
  /// no user content. Mirrors the Apple SDK's `ensureDeveloperLogs`.
  static void ensureDeveloperLogs() {
    if (!kDebugMode) return;
    if (_logsSub != null) return;
    _logsSub = _logsChannel.receiveBroadcastStream().listen(
      (event) => debugPrint('[TheStage] $event'),
      onError: (Object e) =>
          debugPrint('[TheStage] log stream error: $e'),
    );
  }

  static Future<Map<String, dynamic>> start_model({
    required String model_name,
    required String engines_path,
    String? model_type,
    /// Which class of bundle to deliver, and the default placement
    /// for engines whose own metadata names none.
    ///
    /// Empty -- the default -- takes the best available bundle for
    /// this model on this device. `'npu'` or `'cpu'` CONSTRAIN it
    /// and fail loudly when the model publishes no such bundle.
    ///
    /// It defaulted to `'gpu'`, which was never a real selection:
    /// GPU is not supported, so the native side fell through to
    /// the CPU execution provider. Every Flutter caller that
    /// omitted this argument therefore never selected the NPU for
    /// an engine whose metadata declared no device.
    String device = '',
    String revision = '',
    Map<String, String>? devices,
    Map<String, dynamic>? config,
  }) async {
    try {
      final result = await _channel
          .invokeMethod<Map<Object?, Object?>>(MethodRoute.startModel, {
            'model_name': model_name,
            'engines_path': engines_path,
            'device': device,
            'revision': revision,
            if (model_type != null) 'model_type': model_type,
            if (devices != null) 'devices': devices,
            if (config != null) 'config': config,
          });
      return _asMap(result);
    } on PlatformException catch (e) {
      _rethrowTyped(e);
    }
  }

  static Future<Map<String, dynamic>> stop_model({
    required String model_name,
  }) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      MethodRoute.stopModel,
      {'model_name': model_name},
    );
    return _asMap(result);
  }

  // -------------------------------------------------------------------------
  // Batch Inference
  // -------------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> infer({
    required String model_name,
    required Map<String, dynamic> input_json,
  }) async {
    try {
      final result = await _channel.invokeMethod<List<Object?>>(
        MethodRoute.infer,
        {
          'model_name': model_name,
          'input_json': input_json,
        },
      );
      if (result == null) return [];
      return result
          .map((item) => _asMap(item as Map<Object?, Object?>))
          .toList();
    } on PlatformException catch (e) {
      _rethrowTyped(e);
    }
  }

  // -------------------------------------------------------------------------
  // Streaming Inference
  // -------------------------------------------------------------------------

  /// Stream inference results (TTS audio chunks or LLM text tokens).
  ///
  /// Audio chunks: `{kind: 'audio', audio: Float32List, sample_rate, is_final}`
  /// Text chunks: `{kind: 'text', delta: String, is_final}`
  ///
  /// LLM with `tools` in `input_json` (`[{name, description, parameters}]`,
  /// optional `max_tool_rounds`): `{kind: 'text_delta', delta}` (the only
  /// text to show or speak), `{kind: 'thinking_delta', delta}`,
  /// `{kind: 'tool_call', name, arguments: Map}` and a `final` that also
  /// carries `raw_text` (also in its `delta`: the raw reply, markup
  /// included — never shown), `final_text`, `tool_calls`
  /// (`[{name, arguments}]`) and `thinking`. The app runs the tool: the stream ends after the call
  /// (`stop_reason: 'tool_calls'`); append `{'role': 'tool', 'content':
  /// result}` to `messages` and call [infer_stream] again with the same
  /// `tools` (an assistant call turn is synthesized when you omit it).
  /// `tool_result` chunks (`name`, `content`) come only from tools the SDK
  /// runs itself. Without `tools`, chunks are exactly as above.
  ///
  /// `input_json` accepts model-specific keys. For TTS pipelines the
  /// codec-side chunking knobs (`first_frames_per_chunk` and the rest)
  /// go at the top level of `input_json`, not in a nested map.
  ///
  /// Pass `text: ''` to start a push-mode stream driven by [send] /
  /// [finish_stream]. Unknown keys are ignored.
  static Stream<Map<String, dynamic>> infer_stream({
    required String model_name,
    required Map<String, dynamic> input_json,
    String? stream_id,
  }) async* {
    _ensureStreamChannel();
    final id = stream_id ?? _makeStreamId(model_name);

    // Subscribe BEFORE starting the stream. The event stream is a
    // broadcast controller, which does not buffer: anything emitted
    // between `start_stream` returning and an `await for` attaching
    // is dropped on the floor. A slow first chunk (TTS, ASR) hides
    // that, but a fast LLM can prefill and emit its first tokens
    // inside the platform-channel round trip and lose the whole
    // reply. Buffering into a local controller closes the window.
    final buffered = StreamController<Map<String, dynamic>>();
    final sub = _streamEvents!.stream
        .where((chunk) => chunk['stream_id'] == id)
        .listen(
          buffered.add,
          onError: buffered.addError,
          onDone: buffered.close,
        );
    try {
      await _channel.invokeMethod(MethodRoute.startStream, {
        'model_name': model_name,
        'input_json': input_json,
        'stream_id': id,
      });
      await for (final chunk in buffered.stream) {
        yield chunk;
        if (chunk['is_final'] == true) return;
      }
    } finally {
      await sub.cancel();
      unawaited(buffered.close());
    }
  }

  /// Push input into a live [infer_stream] session.
  ///
  /// Only models whose streaming path accepts input after the
  /// stream opens support this — ASR today. For speech, pass
  /// `{'audio': <List<double> 16 kHz mono in [-1, 1]>}`.
  ///
  /// Models that take their whole input up front (NeuTTS,
  /// LFM2-VL) reject it.
  static Future<void> stream_append({
    required String model_name,
    required Map<String, dynamic> input_json,
  }) async {
    await _channel.invokeMethod(MethodRoute.streamAppend, {
      'model_name': model_name,
      'input_json': input_json,
    });
  }

  /// End a streaming session: flush what is still open so the
  /// final chunk is emitted on the stream opened by
  /// [infer_stream]. Idempotent.
  static Future<void> stream_finish({
    required String model_name,
    Map<String, dynamic> input_json = const {},
  }) async {
    await _channel.invokeMethod(MethodRoute.streamFinish, {
      'model_name': model_name,
      'input_json': input_json,
    });
  }

  /// Abandon a streaming session with no final result.
  static Future<void> stream_cancel({
    required String model_name,
    Map<String, dynamic> input_json = const {},
  }) async {
    await _channel.invokeMethod(MethodRoute.streamCancel, {
      'model_name': model_name,
      'input_json': input_json,
    });
  }

  /// Start `nemotron-multispeaker`: a composite that owns no engines
  /// and is wired from models already running.
  ///
  /// [diarization_model] and [embedding_model] are required — who
  /// spoke when, and the voice embedding that gives speakers an
  /// identity. [vad_model] is needed for the streaming path;
  /// [asr_model] adds transcription, without which you get turns and
  /// no text.
  ///
  /// Start each component first with [start_model]; this call only
  /// wires them, so they keep their own lifetimes.
  static Future<Map<String, dynamic>> start_nemotron_multispeaker({
    required String model_name,
    required String diarization_model,
    required String embedding_model,
    String? vad_model,
    String? asr_model,
  }) {
    return start_model(
      model_name: model_name,
      model_type: 'nemotron-multispeaker',
      engines_path: '',
      config: {
        'diarization': diarization_model,
        'embedding': embedding_model,
        if (vad_model != null) 'vad': vad_model,
        if (asr_model != null) 'asr': asr_model,
      },
    );
  }

  static Future<void> send({
    required String stream_id,
    required String text,
  }) async {
    await _channel.invokeMethod(MethodRoute.send, {
      'stream_id': stream_id,
      'text': text,
    });
  }

  static Future<void> finish_stream({required String stream_id}) async {
    await _channel.invokeMethod(MethodRoute.finishStream, {
      'stream_id': stream_id,
    });
  }

  static Future<void> stop_stream({required String stream_id}) async {
    await _channel.invokeMethod(MethodRoute.stopStream, {
      'stream_id': stream_id,
    });
  }

  // -------------------------------------------------------------------------
  // Components
  // -------------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> list_components({
    required String model_name,
  }) async {
    final result = await _channel.invokeMethod<List<Object?>>(
      MethodRoute.listComponents,
      {'model_name': model_name},
    );
    if (result == null) return [];
    return result
        .map((item) => _asMap(item as Map<Object?, Object?>))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> load_components({
    required String model_name,
    required List<String> component_ids,
  }) async {
    final result = await _channel.invokeMethod<List<Object?>>(
      MethodRoute.loadComponents,
      {'model_name': model_name, 'component_ids': component_ids},
    );
    if (result == null) return [];
    return result
        .map((item) => _asMap(item as Map<Object?, Object?>))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> unload_components({
    required String model_name,
    required List<String> component_ids,
  }) async {
    final result = await _channel.invokeMethod<List<Object?>>(
      MethodRoute.unloadComponents,
      {'model_name': model_name, 'component_ids': component_ids},
    );
    if (result == null) return [];
    return result
        .map((item) => _asMap(item as Map<Object?, Object?>))
        .toList();
  }

  // -------------------------------------------------------------------------
  // Utilities
  // -------------------------------------------------------------------------

  static Future<String?> get_bundled_engine_path(String filename) async {
    return await _channel.invokeMethod<String?>(
      MethodRoute.bundledEnginePath,
      {'filename': filename},
    );
  }

  // -------------------------------------------------------------------------
  // Android-only API
  // -------------------------------------------------------------------------

  /// Download + extract engines for `repo_id@revision` without loading
  /// the model into memory. Returns the local engines directory path —
  /// pass it as `engines_path` to [start_model] later to skip the
  /// download phase. Progress events are emitted on [on_progress] with
  /// the `repo_id` as the `model_name` field. Android-only.
  /// Every model staged on this device, largest first.
  ///
  /// Local and cheap: it reads the on-disk index, with no network
  /// and no model load.
  static Future<List<InstalledModel>> installed_models() async {
    try {
      final res = await _channel.invokeMethod<List<Object?>>(
        MethodRoute.installedModels,
      );
      return (res ?? const [])
          .whereType<Map>()
          .map((m) => InstalledModel.fromMap(
                m.map((k, v) => MapEntry(k.toString(), v)),
              ))
          .toList();
    } on PlatformException catch (e) {
      _rethrowTyped(e);
    }
  }

  /// Every staged model for which a newer bundle exists.
  ///
  /// This **reports only**. Nothing downloads, and the call is
  /// local — it compares what is staged against what this build
  /// names. Take an update with
  /// [prefetch_model] and `replace_existing: true`.
  static Future<List<ModelUpdate>> available_updates() async {
    try {
      final res = await _channel.invokeMethod<List<Object?>>(
        MethodRoute.availableUpdates,
      );
      return (res ?? const [])
          .whereType<Map>()
          .map((m) => ModelUpdate.fromMap(
                m.map((k, v) => MapEntry(k.toString(), v)),
              ))
          .toList();
    } on PlatformException catch (e) {
      _rethrowTyped(e);
    }
  }

  /// The update available for one model, or null when it is
  /// current, not installed, or its wanted identity cannot be
  /// determined.
  ///
  /// Null is an answer, not a failure: a real problem throws.
  /// [variant] defaults to this device's detected SoC variant,
  /// which is what an app normally wants.
  static Future<ModelUpdate?> update_available({
    required String model_type,
    String? variant,
    /// Which repo to ask about, when several publish this model
    /// type; see [remove_model].
    String? repository,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        MethodRoute.updateAvailable,
        {
          'model_type': model_type,
          if (variant != null) 'variant': variant,
          if (repository != null) 'repository': repository,
        },
      );
      if (res == null) return null;
      return ModelUpdate.fromMap(
        res.map((k, v) => MapEntry(k.toString(), v)),
      );
    } on PlatformException catch (e) {
      _rethrowTyped(e);
    }
  }

  /// Remove a staged model and report the bytes freed.
  ///
  /// For an AI pack Play still holds, this frees the extracted tree
  /// and says so rather than claiming a footprint Play owns.
  /// Throws if the model is currently loaded — stop it first.
  static Future<int> remove_model({
    required String model_type,
    String? variant,
    /// Which repo's bundle to remove, when several publish this
    /// model type (every text LLM is `the-stage-llm`). A device can
    /// hold more than one of them, each staged on its own; without
    /// this an arbitrary one is removed.
    String? repository,
  }) async {
    try {
      final res = await _channel.invokeMethod<Object?>(
        MethodRoute.removeModel,
        {
          'model_type': model_type,
          if (variant != null) 'variant': variant,
          if (repository != null) 'repository': repository,
        },
      );
      return (res as num?)?.toInt() ?? 0;
    } on PlatformException catch (e) {
      _rethrowTyped(e);
    }
  }

  /// Re-check a staged bundle against its published contents.
  ///
  /// Reports; never deletes. Staging already verifies and wipes a
  /// bad extract on the spot, so this is for the other case: a
  /// slot that passed then rotted — a truncated restore, a partial
  /// backup — where you want to know before a load fails.
  static Future<SlotIntegrity> verify_model({
    required String model_type,
    String? variant,
    /// Which repo's bundle to check, when several publish this
    /// model type; see [remove_model].
    String? repository,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        MethodRoute.verifyModel,
        {
          'model_type': model_type,
          if (variant != null) 'variant': variant,
          if (repository != null) 'repository': repository,
        },
      );
      return SlotIntegrity.fromMap(
        (res ?? const {}).map((k, v) => MapEntry(k.toString(), v)),
      );
    } on PlatformException catch (e) {
      _rethrowTyped(e);
    }
  }

  /// Re-stage a bundle that no longer verifies, and report whether
  /// it verifies afterwards.
  ///
  /// Acts only when it should: an intact slot is left alone, and a
  /// bundle with no integrity data has nothing to verify against.
  /// Needs
  /// the repo the slot came from, so a local path or an AI pack is
  /// not repairable here — Play owns a pack's bytes.
  ///
  /// May download.
  static Future<bool> repair_model({
    required String model_type,
    String? variant,
    /// Which repo's bundle to repair, when several publish this
    /// model type; see [remove_model].
    String? repository,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        MethodRoute.repairModel,
        {
          'model_type': model_type,
          if (variant != null) 'variant': variant,
          if (repository != null) 'repository': repository,
        },
      );
      return res ?? false;
    } on PlatformException catch (e) {
      _rethrowTyped(e);
    }
  }

  /// Reclaim model bytes nothing claims, and report what was freed.
  ///
  /// Models live in app storage, which Android never evicts, so
  /// anything stranded there stays until this runs: revisions an
  /// update superseded, models the app no longer loads, and
  /// transfers abandoned more than a day ago. The SDK already
  /// reclaims the superseded revision right after each update, so
  /// this is the whole-cache pass — put it behind a "free up space"
  /// action, or call it after dropping a model from the app.
  ///
  /// Safe at any time and cheap when there is nothing to do; models
  /// that are loaded are never touched.
  static Future<SweepResult> maintain() async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        MethodRoute.maintainModels,
      );
      return SweepResult.fromMap(
        (res ?? const {}).map((k, v) => MapEntry(k.toString(), v)),
      );
    } on PlatformException catch (e) {
      _rethrowTyped(e);
    }
  }

  /// Delete every model the SDK has staged, and its download
  /// caches, returning the bytes freed.
  ///
  /// For starting over. Everything comes back on the next load, at
  /// the cost of the downloads. A Play-delivered AI pack's own
  /// archive is released through Play, not deleted.
  ///
  /// Throws while any model is loaded: call [stop_model] on each
  /// first. It does **not** wait for a [prefetch_model] in flight —
  /// that transfer is aborted, and the next load downloads again.
  static Future<int> reset_models() async {
    try {
      final res = await _channel.invokeMethod<Object?>(
        MethodRoute.resetModels,
      );
      return (res as num?)?.toInt() ?? 0;
    } on PlatformException catch (e) {
      _rethrowTyped(e);
    }
  }


  static Future<String> prefetch_model({
    required String repo_id,
    String? model_type,
    String revision = '',
    /// Which class of bundle to fetch: empty takes the best
    /// available, `'npu'` or `'cpu'` constrain it and fail when
    /// the model publishes no such bundle.
    ///
    /// Same semantics as [start_model]'s, so a prefetch installs
    /// what a later load will find staged instead of the two
    /// resolving differently and downloading twice.
    String device = '',
    Map<String, dynamic>? config,
    /// Replace a bundle that is already staged.
    ///
    /// Default false, so this installs what is missing and leaves
    /// what is there — a load never replaces anything, so neither
    /// does a prefetch. Pass true to take an update
    /// [available_updates] has reported, at a moment you choose.
    bool replace_existing = false,
  }) async {
    try {
      final res = await _channel.invokeMethod<String>(
        MethodRoute.androidPrefetchModel,
        {
          'repo_id': repo_id,
          if (model_type != null) 'model_type': model_type,
          'revision': revision,
          'device': device,
          if (config != null) 'config': config,
          'replace_existing': replace_existing,
        },
      );
      return res ?? '';
    } on PlatformException catch (e) {
      _rethrowTyped(e);
    }
  }

  /// Check whether a model bundle is available for THIS device BEFORE
  /// loading it — no [initialize], no token, no download (HEAD-only for
  /// HF repos, a file stat for local paths).
  ///
  /// [model_path] is an HF repo id (e.g.
  /// `TheStageAI/thewhisper-large-v3-turbo`) or a local bundle path. Use
  /// the result to pick a model / show UI before the heavier
  /// [start_model] call. Android-only.
  static Future<ModelAvailabilityResult> check_model_availability({
    required String model_path,
    String revision = '',
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        MethodRoute.androidCheckModelAvailability,
        {
          'model_path': model_path,
          'revision': revision,
        },
      );
      return ModelAvailabilityResult.fromMap(_asMap(result));
    } on PlatformException {
      // Native never throws here; guard defensively anyway.
      return const ModelAvailabilityResult(
        availability: ModelAvailability.unknown,
        reason: AvailabilityReason.networkUnreachable,
      );
    }
  }

  /// Report this process's memory as the OS accounts it.
  ///
  /// `footprint_mb` is total PSS in MB (the Android analogue of iOS
  /// `phys_footprint` — what the low-memory killer tracks); `resident_mb`
  /// is RSS in MB (the smaller, secondary diagnostic). Returns `null` if
  /// the platform couldn't read the footprint.
  static Future<Map<String, double>?> memory_footprint() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      MethodRoute.memoryFootprint,
    );
    if (result == null) return null;
    final map = _asMap(result);
    final footprint = (map['footprint_mb'] as num?)?.toDouble();
    final resident = (map['resident_mb'] as num?)?.toDouble();
    if (footprint == null || footprint < 0) return null;
    return {
      'footprint_mb': footprint,
      if (resident != null && resident >= 0) 'resident_mb': resident,
    };
  }

  // -------------------------------------------------------------------------
  // Private Helpers
  // -------------------------------------------------------------------------

  static String _makeStreamId(String model_name) {
    _nextStreamOrdinal++;
    return '${model_name}_${DateTime.now().microsecondsSinceEpoch}_'
        '$_nextStreamOrdinal';
  }

  static Map<String, dynamic> _asMap(Map<Object?, Object?>? value) {
    if (value == null) return <String, dynamic>{};
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
}
