import 'package:flutter_test/flutter_test.dart';
import 'package:thestage_android_sdk/src/asr_engine.dart';
import 'package:thestage_android_sdk/src/asr_stream.dart';

void main() {
  test('empty streaming config stays optional on the wire', () {
    expect(const ASRStreamingConfig().to_json(), isEmpty);
    expect(
      ASRStreamingAlgorithm.values,
      contains(ASRStreamingAlgorithm.NAIVE),
    );
    expect(
      ASRStreamingAlgorithm.values,
      contains(ASRStreamingAlgorithm.THESTAGE_V5),
    );
  });

  test('prefix control is explicit on the wire', () {
    expect(
      const ASRStreamingConfig(
        algorithm: ASRStreamingAlgorithm.NAIVE,
        use_prefix: true,
      ).to_json(),
      {
        'algorithm': 'NAIVE',
        'use_prefix': true,
      },
    );
  });

  test('V6 cut settings reach native JSON without changing empty defaults', () {
    expect(
      const ASRStreamingConfig(
        algorithm: ASRStreamingAlgorithm.THESTAGE_V6,
        cut_search_s: 6,
        cut_force_s: 9.5,
        cut_age_s: 1,
        cut_confirm_ratio: 0.8,
        cut_veto_cer: 0.2,
        cut_pick: 'last',
        clock_release_s: 8,
      ).to_json(),
      {
        'algorithm': 'THESTAGE_V6',
        'cut_search_s': 6,
        'cut_force_s': 9.5,
        'cut_age_s': 1,
        'cut_confirm_ratio': 0.8,
        'cut_veto_cer': 0.2,
        'cut_pick': 'last',
        'clock_release_s': 8,
      },
    );
  });

  test('consecutive local agreement is explicit on the wire', () {
    expect(
      const ASRStreamingConfig(
        n_confirmations: 3,
        agreement_mode: ASRLocalAgreementMode.CONSECUTIVE,
      ).to_json(),
      {
        'n_confirmations': 3,
        'agreement_mode': 'CONSECUTIVE',
      },
    );
  });

  test('ASREngine holds optional vad handle', () {
    expect(ASREngine(stt: 'stt', vad: 'vad').vad, 'vad');
    expect(ASREngine(stt: 'stt').vad, isNull);
  });

  test('ASRStreamEvent parses begin / turn / termination', () {
    expect(ASRStreamEvent.from_json({'kind': 'BEGIN'}).is_begin, isTrue);
    expect(
      ASRStreamEvent.from_json({'kind': 'turn', 'transcript': 'hi'}).is_turn,
      isTrue,
    );
    expect(
      ASRStreamEvent.from_json({'kind': 'termination'}).is_termination,
      isTrue,
    );
  });

  test('ASRStreamEvent parses partial / cancelled', () {
    expect(
      ASRStreamEvent.from_json({'kind': 'partial', 'text': 'hi'}).is_partial,
      isTrue,
    );
    expect(
      ASRStreamEvent.from_json({'kind': 'cancelled'}).is_cancelled,
      isTrue,
    );
  });

  test('generation config defaults on the wire', () {
    expect(const ASRGenerationConfig().to_json(), {
      'language': 'en',
      'timestamps': 'WORD',
      'return_tokens': false,
      'text_context': 'NONE',
      'context_text': '',
      'language_detection': false,
      'overlap': 0.2,
    });
    expect(
      const ASRGenerationConfig(max_new_tokens: 64).to_json()['max_new_tokens'],
      64,
    );
  });

  test('ASRResult parses the native result row', () {
    final result = ASRResult.from_json({
      'transcription': 'hello there',
      'text': 'hello there',
      'token_count': 3,
      'generated_tokens': 3,
      'decode_seconds': 0.25,
      'timestamp_mode': 'WORD',
      'language': 'en',
      'words': [
        {'text': 'hello', 't0': 0.1, 't1': 0.4},
        {'text': 'there', 't0': 0.5, 't1': 0.9, 'speaker_id': 'S1'},
      ],
      'metrics': {
        'preprocess_seconds': 0.01,
        'encode_seconds': 0.1,
        'decode_seconds': 0.25,
        'last_prefill_seconds': 0.02,
        'total_seconds': 0.36,
        'audio_seconds': 1.0,
        'rtf': 2.7,
        'tokens_per_second': 12.0,
        'chunk_count': 1,
        'generated_tokens': 3,
      },
    });
    expect(result.text, 'hello there');
    expect(result.timestamp_mode, ASRTimestampMode.WORD);
    expect(result.language, 'en');
    expect(result.generated_tokens, 3);
    expect(result.words!.length, 2);
    expect(result.words![0].speaker_id, isNull);
    expect(result.words![1].speaker_id, 'S1');
    expect(result.words![1].t1, 0.9);
    expect(result.metrics.rtf, 2.7);
    expect(result.metrics.chunk_count, 1);
    expect(result.metrics.generated_tokens, 3);
    expect(result.metrics.prefill_seconds, 0.02);
  });

  test('ASRResult falls back to transcription and empty rows', () {
    expect(ASRResult.from_json({'transcription': 'x'}).text, 'x');
    final empty = ASRResult.from_json(const {});
    expect(empty.text, '');
    expect(empty.words, isNull);
    expect(empty.timestamp_mode, ASRTimestampMode.NONE);
  });
}
