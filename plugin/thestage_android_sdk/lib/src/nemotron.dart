// ----------------------------------------------------------------------
// Nemotron speaker types
// ----------------------------------------------------------------------
// Shared value types for `nemotron-diarization` (who spoke when) and
// `nemotron-multispeaker` (who said what). Kept in their own file
// rather than on the SDK class: an app that only renders a transcript
// imports these without pulling in the method surface.

// -- shared speaker types --------------------------------------------------

/// A voice the app already knows: one or more `speaker-id` embeddings of
/// one person. Vectors must come from the SAME embedder the pipeline runs.
class EnrolledSpeaker {
  const EnrolledSpeaker({required this.id, required this.vectors});

  /// Single-sample convenience.
  EnrolledSpeaker.single({required this.id, required List<double> vector})
      : vectors = [vector];

  /// Your own identifier, returned verbatim as `identity`. A display name
  /// works.
  final String id;

  /// One or more embeddings of this person.
  final List<List<double>> vectors;

  Map<String, dynamic> toJson() => {'id': id, 'vectors': vectors};
}

/// One stretch of one speaker's speech.
class SpeakerSegment {
  const SpeakerSegment({
    required this.start,
    required this.end,
    required this.speaker,
    this.identity,
  });

  /// Seconds from the start of the recording / stream.
  final double start;
  final double end;

  /// `SPEAKER_00`, `SPEAKER_01`, ... — carried on the segment so a
  /// flattened timeline stays self-describing.
  final String speaker;

  /// The [EnrolledSpeaker.id] this speaker turned out to be, or null.
  final String? identity;

  /// What to show a human: the name when there is one, else the label.
  String get displayName => identity ?? speaker;

  double get duration => end - start;

  /// The trailing number, for colour tables. -1 if not `SPEAKER_NN`.
  int get index => int.tryParse(speaker.split('_').last) ?? -1;

  static SpeakerSegment _fromMap(Map<String, dynamic> map, String speaker,
          [String? identity]) =>
      SpeakerSegment(
        start: (map['start'] as num).toDouble(),
        end: (map['end'] as num).toDouble(),
        speaker: speaker,
        identity: identity,
      );
}

// -- nemotron-multispeaker ------------------------------------------------

/// Knobs of the `nemotron-multispeaker` pipeline (Nemotron-3-Diarization +
/// speaker-id + VAD + ASR). Every field is nullable: null keeps the SDK's
/// measured default, so an app only sends what it changes.
class NemotronMultiSpeakerSettings {
  const NemotronMultiSpeakerSettings({
    this.enrolled = const [],
    this.identityThreshold,
    this.minIdentitySpeech,
    this.language = 'auto',
    this.transcribe = true,
    this.threshold,
    this.minOn,
    this.minSandwich,
    this.maxInterruption,
    this.maxTurnSeconds,
    this.minTurnAsr,
    this.cutPad,
    this.embedHop,
    this.commitPause,
    this.maxUtterance,
    this.vadThreshold,
    this.feedSilence,
    this.maxSilenceFeed,
    this.lookaheadFrames,
    this.speakerMemorySeconds,
    this.neverResetSpeakers = false,
    this.rejoinThreshold,
    this.slotDriftThreshold,
    this.partials = false,
    this.partialInterval,
    this.partialAsr,
    this.partialAsrInterval,
    this.partialMinTurn,
    this.partialActiveWindow,
  });

  /// Voices the app already knows (same `speaker-id` embedder).
  final List<EnrolledSpeaker> enrolled;

  /// Cosine a speaker needs to take an enrolled id (SDK default 0.40).
  final double? identityThreshold;

  /// Clean speech a speaker needs before it may take an enrolled id or
  /// re-join a known speaker after a cache reset (default 2 s).
  final double? minIdentitySpeech;

  /// `auto` detects the language on Apple; Android whisper has no
  /// language detection yet and decodes `auto` as English.
  final String language;
  final bool transcribe;

  /// Nemotron speaker probability above which a 10 ms frame is active.
  final double? threshold;

  /// Intervals shorter than this join a neighbour (default 0.25 s).
  final double? minOn;

  /// A short interval between two of the same other speaker is folded in.
  final double? minSandwich;

  /// A turn splits only when ANOTHER speaker talks longer than this
  /// (default 1.0 s). One ASR call per turn.
  final double? maxInterruption;

  /// ASR window; a longer turn is split at its widest gap (default 28 s).
  final double? maxTurnSeconds;

  /// Turns with less speech are reported but not transcribed (0.5 s).
  final double? minTurnAsr;
  final double? cutPad;
  final double? embedHop;

  // -- streaming --------------------------------------------------------

  /// VAD silence that closes an utterance and triggers a Nemotron step
  /// and its transcription (default 0.8 s).
  final double? commitPause;

  /// Longest utterance before a forced commit at its quietest point
  /// (default 27 s = one Nemotron step).
  final double? maxUtterance;

  /// Silero probability at/above which a frame is speech (0.5).
  final double? vadThreshold;

  /// Feed the pauses to Nemotron (default true — measured better).
  final bool? feedSilence;

  /// Only the last this-many seconds of a longer pause are fed (60 s).
  final double? maxSilenceFeed;

  /// Look-ahead frames (80 ms each) a step takes after its chunk (8).
  final int? lookaheadFrames;

  /// Continuous non-speech after which Nemotron's speaker cache is reset
  /// (default 600 s). Returning voices re-join by embedding.
  final double? speakerMemorySeconds;

  /// True = never reset the speaker cache on silence (overrides
  /// [speakerMemorySeconds]).
  final bool neverResetSpeakers;

  /// Cosine a new epoch's speaker needs to re-join a known one (0.45).
  final double? rejoinThreshold;

  /// Drift guard: an utterance embedding below this against its
  /// speaker's centroid does not update it (0.25).
  final double? slotDriftThreshold;

  // -- live previews (streaming only; off = on-pause results only) ------

  /// Emit `partial` events between pauses: who is speaking now and a live
  /// transcript of the current turn. The commit at the pause is unchanged
  /// and replaces them.
  final bool partials;

  /// Seconds between two diarization previews (SDK default 0.5).
  final double? partialInterval;

  /// Transcribe the current turn live (default true; false = who-speaks
  /// previews only).
  final bool? partialAsr;

  /// Seconds between two live transcriptions (default max(1 s,
  /// [partialInterval])).
  final double? partialAsrInterval;

  /// Speech the current turn needs before it is transcribed live (1.0 s).
  final double? partialMinTurn;

  /// A speaker active within this many seconds of the newest audio is
  /// "speaking now" (0.5 s). With several, the longer turn is transcribed.
  final double? partialActiveWindow;

  Map<String, dynamic> toInputs() => {
        'language': language,
        'transcribe': transcribe,
        if (enrolled.isNotEmpty)
          'enrolled': [for (final e in enrolled) e.toJson()],
        if (identityThreshold != null) 'identity_threshold': identityThreshold,
        if (minIdentitySpeech != null) 'min_identity_speech': minIdentitySpeech,
        if (threshold != null) 'threshold': threshold,
        if (minOn != null) 'min_on': minOn,
        if (minSandwich != null) 'min_sandwich': minSandwich,
        if (maxInterruption != null) 'max_interruption': maxInterruption,
        if (maxTurnSeconds != null) 'max_turn_seconds': maxTurnSeconds,
        if (minTurnAsr != null) 'min_turn_asr': minTurnAsr,
        if (cutPad != null) 'cut_pad': cutPad,
        if (embedHop != null) 'embed_hop': embedHop,
        if (commitPause != null) 'commit_pause': commitPause,
        if (maxUtterance != null) 'max_utterance': maxUtterance,
        if (vadThreshold != null) 'vad_threshold': vadThreshold,
        if (feedSilence != null) 'feed_silence': feedSilence,
        if (maxSilenceFeed != null) 'max_silence_feed': maxSilenceFeed,
        if (lookaheadFrames != null) 'lookahead_frames': lookaheadFrames,
        // 0 = never (the SDK maps a non-positive value to "no reset").
        if (neverResetSpeakers)
          'speaker_memory_seconds': 0
        else if (speakerMemorySeconds != null)
          'speaker_memory_seconds': speakerMemorySeconds,
        if (rejoinThreshold != null) 'rejoin_threshold': rejoinThreshold,
        if (slotDriftThreshold != null)
          'slot_drift_threshold': slotDriftThreshold,
        if (partials) 'partials': true,
        if (partialInterval != null) 'partial_interval': partialInterval,
        if (partialAsr != null) 'partial_asr': partialAsr,
        if (partialAsrInterval != null)
          'partial_asr_interval': partialAsrInterval,
        if (partialMinTurn != null) 'partial_min_turn': partialMinTurn,
        if (partialActiveWindow != null)
          'partial_active_window': partialActiveWindow,
      };
}

/// One turn: a run of one speaker's speech, split only by another speaker
/// talking longer than `max_interruption`. One ASR call.
class SpeakerTurn {
  const SpeakerTurn({
    required this.speaker,
    required this.start,
    required this.end,
    required this.segments,
    required this.text,
    required this.transcribed,
    required this.audioSeconds,
    this.identity,
  });

  final String speaker;
  final String? identity;
  String get displayName => identity ?? speaker;
  final double start;
  final double end;
  final List<SpeakerSegment> segments;
  final String text;

  /// False for turns under `min_turn_asr` (reported, not transcribed).
  final bool transcribed;
  final double audioSeconds;

  int get index => int.tryParse(speaker.split('_').last) ?? -1;

  SpeakerTurn relabel(String speaker, String? identity) => SpeakerTurn(
        speaker: speaker,
        identity: identity,
        start: start,
        end: end,
        text: text,
        transcribed: transcribed,
        audioSeconds: audioSeconds,
        segments: [
          for (final s in segments)
            SpeakerSegment(
                start: s.start, end: s.end, speaker: speaker, identity: identity)
        ],
      );

  static SpeakerTurn fromMap(Map<String, dynamic> m) {
    final speaker = m['speaker'] as String? ?? '';
    final identity = m['identity'] as String?;
    return SpeakerTurn(
      speaker: speaker,
      identity: identity,
      start: (m['start'] as num?)?.toDouble() ?? 0,
      end: (m['end'] as num?)?.toDouble() ?? 0,
      text: m['text'] as String? ?? '',
      transcribed: m['transcribed'] as bool? ?? false,
      audioSeconds: (m['audio_seconds'] as num?)?.toDouble() ?? 0,
      segments: ((m['segments'] as List?) ?? const [])
          .map((e) => SpeakerSegment._fromMap(
              Map<String, dynamic>.from(e as Map), speaker, identity))
          .toList(),
    );
  }
}

/// One speaker's voice: its embedding and who it turned out to be.
class SpeakerVoice {
  const SpeakerVoice({
    required this.speaker,
    required this.embedding,
    required this.embeddingSeconds,
    required this.speechSeconds,
    required this.provisional,
    this.identity,
    this.identityScore,
  });

  final String speaker;
  final String? identity;
  String get displayName => identity ?? speaker;
  final double? identityScore;

  /// L2-normalised `speaker-id` embedding (same model as enrollment).
  final List<double> embedding;

  /// Clean speech the embedding was built from — its averaging weight.
  final double embeddingSeconds;
  final double speechSeconds;

  /// Streaming: the label may still change.
  final bool provisional;

  int get index => int.tryParse(speaker.split('_').last) ?? -1;

  static SpeakerVoice fromMap(Map<String, dynamic> m) => SpeakerVoice(
        speaker: m['speaker'] as String? ?? '',
        identity: m['identity'] as String?,
        identityScore: (m['identity_score'] as num?)?.toDouble(),
        embedding: ((m['embedding'] as List?) ?? const [])
            .map((e) => (e as num).toDouble())
            .toList(),
        embeddingSeconds: (m['embedding_seconds'] as num?)?.toDouble() ?? 0,
        speechSeconds: (m['speech_seconds'] as num?)?.toDouble() ?? 0,
        provisional: m['provisional'] as bool? ?? false,
      );
}

/// Offline `nemotron-multispeaker` result: turns in time order, one voice
/// per speaker, and per-stage diagnostics.
class NemotronMultiSpeakerResult {
  const NemotronMultiSpeakerResult({
    required this.turns,
    required this.voices,
    required this.profile,
  });

  final List<SpeakerTurn> turns;
  final List<SpeakerVoice> voices;
  final Map<String, double> profile;

  List<SpeakerSegment> get timeline {
    final all = [for (final t in turns) ...t.segments];
    all.sort((a, b) => a.start.compareTo(b.start));
    return all;
  }
}

/// One event of a live `nemotron-multispeaker` stream.
///
/// `kind`: `utterance` (turns + voices of one committed utterance),
/// `identity_update` (voices whose label or identity changed; [merges] maps
/// old label -> surviving label), `reset` (new speaker-cache epoch),
/// `final` (every speaker of the stream + profile), `cancelled`, and with
/// [NemotronMultiSpeakerSettings.partials] `partial`: tentative [turns] /
/// [segments] of the utterance still open, [activeSpeaker] = who speaks
/// now. A `partial` replaces the previous one; the next `utterance`
/// replaces every partial of its window.
class NemotronStreamEvent {
  const NemotronStreamEvent({
    required this.kind,
    required this.turns,
    required this.voices,
    required this.merges,
    required this.profile,
    this.segments = const [],
    this.reason,
    this.activeSpeaker,
  });

  final String kind;
  final List<SpeakerTurn> turns;
  final List<SpeakerVoice> voices;
  final Map<String, String> merges;
  final Map<String, double> profile;

  /// `reset` only: why the cache was reset.
  final String? reason;

  /// Speaker intervals of this event (`partial`, `utterance`).
  final List<SpeakerSegment> segments;

  /// `partial` only: the speaker speaking now (null when nobody is).
  final String? activeSpeaker;

  bool get isPartial => kind == 'partial';
  bool get isFinal => kind == 'final' || kind == 'cancelled';

  static NemotronStreamEvent fromChunk(Map<String, dynamic> c) {
    final kind = c['kind'] as String? ?? '';
    final delta = c['delta'] as String?;
    final merges = <String, String>{};
    if (kind == 'identity_update' && delta != null && delta.isNotEmpty) {
      for (final pair in delta.split(',')) {
        final parts = pair.split('->');
        if (parts.length == 2) merges[parts[0]] = parts[1];
      }
    }
    List<Map<String, dynamic>> maps(Object? v) => ((v as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return NemotronStreamEvent(
      kind: kind,
      turns: maps(c['turns']).map(SpeakerTurn.fromMap).toList(),
      voices: maps(c['voices']).map(SpeakerVoice.fromMap).toList(),
      merges: merges,
      reason: kind == 'reset' ? delta : null,
      activeSpeaker: kind == 'partial' ? delta : null,
      segments: maps(c['segments'])
          .map((m) => SpeakerSegment._fromMap(
              m, m['speaker'] as String? ?? '', m['identity'] as String?))
          .toList(),
      profile: Map<String, dynamic>.from((c['stage_profile'] as Map?) ?? {})
          .map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }
}

  // -- nemotron-multispeaker -------------------------------------------

  /// Wire the `nemotron-multispeaker` pipeline over models that are
  /// ALREADY started: a `nemotron-diarization` model, a `speaker-id`
  /// embedder, and optionally `silero-vad` (needed for streaming) and an
  /// ASR (`whisper`).
