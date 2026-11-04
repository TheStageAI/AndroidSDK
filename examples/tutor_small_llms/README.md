# tutor_small_llms

The example behind the tutorial *turn a receipt, chat, or SMS into
structured data on device*. Runs five guides on one small LLM and shows
what the model returned and what the app parsed from it:

1. **Expense record** — an OCR'd fiscal ticket → merchant, total and the
   printed date (copied verbatim, normalised by the app).
2. **Calendar event** — a chat thread → the meeting the people agreed
   on (the model copies what was said; the app resolves the date).
3. **Pickup code** — four carriers' parcel notices → the code only.
4. **Share-sheet router** — a pasted text → one label from an allow-list.
5. **Tool calling** — four questions with three tools described to the
   model (`get_weather`, `get_local_time`, `web_search`): the weather in
   Paris, the time in Tokyo, who invented the telephone, and a "thanks"
   that needs no tool. The app runs the Flutter tool loop: the stream
   ends at the call, the app answers it and asks again. It shows each
   call, the result and the final answer, and scores the tool choice
   and the arguments (2 points a question, out of 8), plus whether the
   answer uses the result.

The models decode greedily, so a run normally repeats the last one's
output (with MTP on, a near-tie between two tokens can rarely resolve
the other way; see [MTP](../../docs/llm.md#mtp-use_mtp)).
Guide 5's tools answer from fixed tables, with no network.
`lib/recipes.dart` holds the prompts, `lib/normalize.dart` the app-side
date / time normaliser, `lib/tools.dart` the tools, their canned
answers, the tool loop and the score, `lib/guides.dart` the checks.

## Prerequisites

- A TheStage API token — set as `TS_API_TOKEN` in `secrets.json`.
- A phone with Snapdragon 8 Gen 2, 8 Gen 3, 8 Elite or 8 Elite Gen 5,
  Android 9+ (minSdk 28).

## Run

```bash
# from the repo root
./scripts/setup.sh    # one-time, idempotent; creates examples/*/secrets.json

$EDITOR examples/tutor_small_llms/secrets.json    # the file setup.sh created

cd examples/tutor_small_llms
flutter pub get
flutter run --release \
    --dart-define-from-file=secrets.json \
    -d <YOUR_DEVICE_ID>
```

Pick a model (LFM2.5 230M / 350M / 1.2B, LFM3 1.7B, Qwen3.5 0.8B / 2B /
4B) and the guides,
then **Run guides**. `--dart-define=LLM_BUNDLE=<path or repo>` runs
another bundle; guide 5 is skipped for a model whose
`features.tools.supported` is false.

## Notes

- Guide 5's answers are canned, so it measures how the model picks a
  tool and fills its arguments, not the tools. The SDK's built-in tools
  (live weather, time and search) are Kotlin `DefaultTools`.
- See [LLM](../../docs/llm.md) for the API this app uses (`messages`,
  `enable_thinking`, `stop_reason`, and *Tool calling* for `tools`,
  the `tool_call` chunk and `tool` messages).
