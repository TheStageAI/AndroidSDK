import 'package:engine_bench/backend/bench_session.dart';
import 'package:engine_bench/backend/load_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stats', () {
    test('empty series have no value', () {
      expect(median([]), isNull);
      expect(mean([]), isNull);
      expect(maxOf([]), isNull);
    });

    test('median of odd and even series', () {
      expect(median([3, 1, 2]), 2);
      expect(median([4, 1, 3, 2]), 2.5);
    });

    test('median leaves its input unsorted', () {
      final xs = [3.0, 1.0, 2.0];
      median(xs);
      expect(xs, [3.0, 1.0, 2.0]);
    });

    test('mean and max', () {
      expect(mean([1, 2, 3, 6]), 3);
      expect(maxOf([1, 7, 3]), 7);
    });
  });

  group('loadKey', () {
    test('changes with every load-time option', () {
      final a = loadKey('TheStageAI/LFM2.5-350M', mtp: true);
      expect(loadKey('TheStageAI/LFM2.5-350M', mtp: true), a);
      expect(loadKey('TheStageAI/LFM2.5-350M', mtp: false), isNot(a));
      expect(loadKey('TheStageAI/LFM2.5-1.2B', mtp: true), isNot(a));
    });

    test('model type is part of the key', () {
      expect(
        loadKey('x', modelType: 'lfm2-vl'),
        isNot(loadKey('x', modelType: 'gemma4-vl')),
      );
    });

    test('starts with the engines path', () {
      expect(
        loadKey('TheStageAI/Qwen3.5-2B', mtp: true)
            .startsWith('TheStageAI/Qwen3.5-2B|'),
        isTrue,
      );
    });
  });

  test('isProgressFor keeps only its own handle', () {
    expect(
      isProgressFor({'model_name': 'bench_llm', 'phase': 'loading'},
          'bench_llm'),
      isTrue,
    );
    expect(isProgressFor({'model_name': 'bench_vlm'}, 'bench_llm'), isFalse);
    expect(isProgressFor({'phase': 'loading'}, 'bench_llm'), isFalse);
  });

  group('voicesFromStatus', () {
    test('reads the bundle voices', () {
      expect(
        voicesFromStatus({
          'voices': ['jo', 'paul'],
        }, fallback: const ['dave']),
        ['jo', 'paul'],
      );
    });

    test('falls back when the status names none', () {
      expect(voicesFromStatus({}, fallback: const ['dave']), ['dave']);
      expect(
        voicesFromStatus({'voices': []}, fallback: const ['dave']),
        ['dave'],
      );
    });
  });

  test('BenchRecord JSON keeps only the set keys', () {
    final r = BenchRecord(
      kind: 'llm',
      model: 'LFM2.5 350M',
      runs: 2,
      metrics: {'best_tok_s': 10},
      perRun: {
        'tok_s': [9, 10],
      },
    ).toJson();
    expect(r['kind'], 'llm');
    expect(r['best_tok_s'], 10);
    expect(r['per_run_tok_s'], [9, 10]);
    expect(r.containsKey('voice'), isFalse);
    expect(r.containsKey('prompt'), isFalse);
  });
}
