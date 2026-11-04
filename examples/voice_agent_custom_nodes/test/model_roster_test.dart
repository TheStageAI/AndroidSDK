import 'package:flutter_test/flutter_test.dart';
import 'package:voice_agent_custom_nodes/backend/model_roster.dart';
import 'package:voice_agent_custom_nodes/backend/voice_agent_controller.dart';

class _FakeBackend implements ModelRosterBackend {
  final log = <String>[];
  String prefetchPath = '/cache/vlm';

  @override
  Future<String> prefetchEngines({
    required String repoId,
    String? modelType,
    String revision = '',
  }) async {
    log.add('prefetch $repoId');
    return prefetchPath;
  }

  @override
  Future<void> startModel({
    required String modelName,
    required String enginesPath,
    required String modelType,
    String device = '',
    String revision = '',
  }) async {
    log.add('start $modelName $enginesPath $modelType device=$device');
  }

  @override
  Future<void> stopModel({required String modelName}) async {
    log.add('stop $modelName');
  }
}

ModelSlot _slot(String name, [String type = 'lfm2-vl']) => ModelSlot(
      name: name,
      enginesPath: 'TheStageAI/$name',
      modelType: type,
      policy: ModelPolicy.ephemeral,
    );

void main() {
  test('slots default to the best bundle (no device)', () {
    expect(_slot('vlm').device, '');
  });

  test('ensureHot starts once, release stops once', () async {
    final b = _FakeBackend();
    final r = ModelRoster([_slot('vlm')], backend: b);
    await r.ensureHot(['vlm']);
    await r.ensureHot(['vlm']);
    expect(r.hot, {'vlm'});
    await r.release(['vlm']);
    await r.release(['vlm']);
    expect(r.hot, isEmpty);
    expect(b.log, [
      'start vlm TheStageAI/vlm lfm2-vl device=',
      'stop vlm',
    ]);
  });

  test('unknown names are ignored', () async {
    final b = _FakeBackend();
    final r = ModelRoster([_slot('vlm')], backend: b);
    await r.ensureHot(['nope']);
    await r.release(['nope']);
    expect(b.log, isEmpty);
  });

  test('prepare resolves the prefetched path for the later start', () async {
    final b = _FakeBackend();
    final r = ModelRoster([_slot('vlm')], backend: b);
    await r.prepare();
    await r.ensureHot(['vlm']);
    expect(r.resolvedPaths['vlm'], '/cache/vlm');
    expect(b.log.last, 'start vlm /cache/vlm lfm2-vl device=');
  });

  test('an empty prefetch path falls back to the repo id', () async {
    final b = _FakeBackend()..prefetchPath = '';
    final r = ModelRoster([_slot('vlm')], backend: b);
    await r.prepare();
    expect(r.resolvedPaths['vlm'], 'TheStageAI/vlm');
  });

  test('withEphemeral stops the model even when the body throws',
      () async {
    final b = _FakeBackend();
    final r = ModelRoster([_slot('vlm')], backend: b);
    await expectLater(
      r.withEphemeral<void>('vlm', () async => throw StateError('x')),
      throwsStateError,
    );
    expect(r.hot, isEmpty);
    expect(b.log.last, 'stop vlm');
  });

  test('withEphemeralSwap parks only hot models and restores them',
      () async {
    final b = _FakeBackend();
    final r = ModelRoster([_slot('llm', 'the-stage-llm'), _slot('vlm')],
        backend: b);
    await r.ensureHot(['llm']);
    b.log.clear();
    final out = await r.withEphemeralSwap(
      'vlm',
      park: const ['llm', 'tts'],
      body: () async {
        expect(r.hot, {'vlm'});
        return 42;
      },
    );
    expect(out, 42);
    expect(r.hot, {'llm'});
    expect(b.log, [
      'stop llm',
      'start vlm TheStageAI/vlm lfm2-vl device=',
      'stop vlm',
      'start llm TheStageAI/llm the-stage-llm device=',
    ]);
  });

  test('the VLM choices carry their own model type', () {
    final types = {
      for (final c in VoiceAgentController.vlmChoices)
        c.label: VoiceAgentController.vlmSlot(c).modelType,
    };
    expect(types['Gemma 4 E2B'], 'gemma4-vl');
    expect(types['LFM2.5-VL 450M'], 'lfm2-vl');
  });
}
