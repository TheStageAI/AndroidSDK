import 'dart:convert';

import 'package:thestage_android_sdk/thestage_android_sdk.dart';

import 'normalize.dart';
import 'recipes.dart';
import 'tools.dart';

// ---------------------------------------------------------------------------
// The guides: call the model, parse, check against the input.
// ---------------------------------------------------------------------------
/// One chat turn of a few-shot conversation.
typedef Turn = ({String role, String content});

Turn user(String content) => (role: 'user', content: content);
Turn assistant(String content) => (role: 'assistant', content: content);

/// Runs guides 1–5 on the model loaded as [modelName], writing what the
/// model returned and what the app parsed to [log].
class Guides {
  final String modelName;
  final void Function(String line) log;

  /// The loaded model calls tools (`features.tools.supported`).
  final bool supportsTools;

  /// Starts a stream for guide 5; null: the SDK's `infer_stream`.
  final StreamFn? stream;

  Guides(
    this.modelName,
    this.log, {
    this.supportsTools = true,
    this.stream,
  });

  static const titles = {
    1: 'Expense record',
    2: 'Calendar event',
    3: 'Pickup code',
    4: 'Share-sheet router',
    5: 'Tool calling',
  };

  /// Guide 5's questions: one per tool, and one that needs none.
  static const toolCases = [
    ToolCase(
      "What's the weather in Paris right now?",
      tool: 'get_weather',
      arg: 'city',
      argContains: 'paris',
      answerUses: ['18'],
    ),
    ToolCase(
      'What time is it in Tokyo?',
      tool: 'get_local_time',
      arg: 'city',
      argContains: 'tokyo',
      answerUses: ['15:30', '3:30'],
    ),
    ToolCase(
      'Who invented the telephone?',
      tool: 'web_search',
      arg: 'query',
      argContains: 'telephone',
      answerUses: ['Bell'],
    ),
    ToolCase("Thanks, that's all for now."),
  ];

  /// "Today" for guide 2 (the threads were written on this day).
  static final today = DateTime(2026, 8, 13);

  Future<void> run(int guide) async {
    log('\n======== Guide $guide / ${titles[guide]} ========');
    switch (guide) {
      case 1:
        await _guide1();
      case 2:
        await _guide2();
      case 3:
        await _guide3();
      case 4:
        await _guide4();
      case 5:
        await _guide5();
    }
  }

  // -------------------------------------------------------------------------
  // Model call
  // -------------------------------------------------------------------------
  /// One greedy, non-thinking reply to the conversation [turns].
  Future<({String text, String stopReason})> _infer(
    List<Turn> turns, {
    required String system,
    required int maxNewTokens,
  }) async {
    final out = await TheStageFlutterSDK.infer(
      model_name: modelName,
      input_json: {
        'system_prompt': system,
        'messages': [
          for (final t in turns) {'role': t.role, 'content': t.content},
        ],
        // The last turn doubles as the prompt.
        'prompt': turns.last.content,
        'max_new_tokens': maxNewTokens,
        'enable_thinking': false,
      },
    );
    final r = out.first;
    return (
      text: (r['text'] as String? ?? '').trim(),
      stopReason: r['stop_reason'] as String? ?? '',
    );
  }

  static Map<String, dynamic>? _json(String text) {
    try {
      final v = jsonDecode(text);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Guide 1 — expense record
  // -------------------------------------------------------------------------
  Future<void> _guide1() async {
    await _expense('ticket 1 — want 8.80 / 14/O8/2026', Recipes.starbucksOcr);
    await _expense('ticket 2 — want 7.70 / 02-09-2026', Recipes.tabaccheriaOcr);
  }

  Future<void> _expense(String label, String ocr) async {
    log('-- $label');
    final r = await _infer(
      [
        user(Recipes.expenseShotUser),
        assistant(Recipes.expenseShotAssistant),
        user(ocr),
      ],
      system: Recipes.expenseSystem,
      maxNewTokens: 128,
    );
    log(r.text);
    if (r.stopReason == 'max_new_tokens') {
      log('  truncated — raise max_new_tokens');
      return;
    }
    // The fields an expense record needs (extra keys are ignored).
    final e = _json(r.text);
    if (e == null ||
        e['merchant'] is! String ||
        e['total'] is! num ||
        e['currency'] is! String ||
        e['date_printed'] is! String) {
      log('  (could not decode — extra keys or truncated JSON)');
      return;
    }
    final printed = '${e['date_printed']}';
    if (!ocr.contains(printed)) {
      log('  date_printed is not a verbatim copy of the ticket: $printed');
      return;
    }
    final day = normalizePrintedDate(printed);
    if (day == null) {
      log('  could not normalise: $printed');
      return;
    }
    log('  parsed: ${e['merchant']} ${e['total']} ${isoDay(day)}');
  }

  // -------------------------------------------------------------------------
  // Guide 2 — calendar event
  // -------------------------------------------------------------------------
  Future<void> _guide2() async {
    await _calendar(
      'thread 1 — want 14/08 13:00 14:30',
      system: Recipes.calendarSystem,
      shots: [
        (Recipes.calendarShotUser, Recipes.calendarShotAssistant),
      ],
      live: stripExportPrefixes(Recipes.marcoExport),
    );
    await _calendar(
      'thread 2 — when: tomorrow 18:30',
      system: Recipes.calendarWhenSystem,
      shots: Recipes.calendarWhenShots,
      live: Recipes.lenaRevised,
    );
  }

  Future<void> _calendar(
    String label, {
    required String system,
    required List<(String, String)> shots,
    required String live,
  }) async {
    log('-- $label');
    final r = await _infer(
      [
        for (final (u, a) in shots) ...[user(u), assistant(a)],
        user(live),
      ],
      system: system,
      maxNewTokens: 128,
    );
    log(r.text);
    final m = _json(r.text);
    if (m == null) return;
    final when = m['when'];
    if (when is String) {
      final start = parseWhen(when, today: today);
      if (start != null) {
        log('  parsed when: $when');
        log('  resolved start: ${isoStamp(start)}');
        return;
      }
    }
    final daySaid = m['day_said'];
    final startSaid = m['start_said'];
    if (daySaid is! String || startSaid is! String) return;
    final start = resolveSaidDatetime(
      daySaid: daySaid,
      startSaid: startSaid,
      today: today,
    );
    if (start != null) log('  resolved start: ${isoStamp(start)}');
  }

  // -------------------------------------------------------------------------
  // Guide 3 — pickup code
  // -------------------------------------------------------------------------
  Future<void> _guide3() async {
    const cases = [
      ('Amazon — want 482917', Recipes.smsAmazon, '482917'),
      ('InPost — want 730114', Recipes.smsInpost, '730114'),
      ('Royal Mail — want 61529', Recipes.smsRoyalmail, '61529'),
      ('Bring — want 4471-88', Recipes.smsBring, '4471-88'),
    ];
    for (final (label, sms, want) in cases) {
      log('-- $label');
      final r = await _infer(
        [
          user(Recipes.lockerShotUser),
          assistant(Recipes.lockerShotAssistant),
          user(sms),
        ],
        system: Recipes.lockerSystem,
        maxNewTokens: 16,
      );
      final code = r.text;
      log(code);
      if (sms.contains(code) && code == want) {
        log('  ok');
      } else if (sms.contains(code)) {
        log('  in input, but not the expected token');
      } else {
        log('  not in input (few-shot parrot or sentence)');
      }
    }
  }

  // -------------------------------------------------------------------------
  // Guide 4 — share-sheet router
  // -------------------------------------------------------------------------
  Future<void> _guide4() async {
    final r = await _infer(
      [
        user(Recipes.routerShotReceipt),
        assistant('receipt'),
        user(Recipes.routerShotEvent),
        assistant('event'),
        user(Recipes.smsRoyalmail),
      ],
      system: Recipes.routerSystem,
      maxNewTokens: 16,
    );
    final label = r.text;
    log(label);
    const allowed = {'receipt', 'event', 'locker', 'other'};
    if (!allowed.contains(label)) {
      log('  not in allow-list');
    } else if (label == 'locker') {
      log('  ok');
    }
  }

  // -------------------------------------------------------------------------
  // Guide 5 — tool calling (the app runs the tools)
  // -------------------------------------------------------------------------
  Future<void> _guide5() async {
    if (!supportsTools) {
      log('this model cannot call tools. skip.');
      return;
    }
    final stream = this.stream ??
        (input) => TheStageFlutterSDK.infer_stream(
              model_name: modelName,
              input_json: input,
            );
    var choice = 0;
    var args = 0;
    var grounded = 0;
    for (final c in toolCases) {
      log('-- ${c.ask}   want ${c.want}');
      final turn = await runToolTurn(
        c.ask,
        stream: stream,
        tools: ToolRecipes.tools,
        system: ToolRecipes.system,
        log: log,
      );
      log('  answer: ${turn.answer}');
      if (turn.stopReason == 'max_tool_rounds') {
        log('  the model kept calling tools; it answered at the cap');
      }
      final s = scoreToolTurn(
        c,
        turn,
        toolNames: [for (final t in ToolRecipes.tools) '${t['name']}'],
      );
      log('  ${s.note}');
      if (s.choice) choice += 1;
      if (s.arguments) args += 1;
      if (s.grounded) grounded += 1;
    }
    final n = toolCases.length;
    log('  score: ${choice + args}/${2 * n} '
        '(tool choice $choice/$n, arguments $args/$n; '
        'answer from the result $grounded/$n)');
  }
}
