# tutor_tts

Mixed-language **streaming TTS** demo: a language tutor that switches
language mid-sentence. Pick a stock tagged phrase (or edit it), and the
app streams it on-device with **NeuTTS nano multilingual**
(`TheStageAI/neutts-nano-multilingual`), giving each span its own
`language` and voice:

```
<en>In French, start the morning with a full greeting:</en>
<fr>Bonjour, comment allez-vous ce matin?</fr>
```

## What it exercises

- `infer_stream` per span with `language` and `voice_id` in the request
  (`lib/tutor_model.dart`).
- Language-tagged scripts parsed into ordered spans
  (`lib/lang_parser.dart`): English, Spanish, French, German,
  Portuguese, Japanese, Korean, Chinese, Urdu.
- One `TSAudioPlayer` for gapless 24 kHz playback across spans,
  with a short pause between them.
- A voice picker per language, from the bundle's `voices`.

## Prerequisites

- A TheStage API token — set as `TS_API_TOKEN` in `secrets.json`.
- A phone with Snapdragon 8 Gen 2, 8 Gen 3, 8 Elite or 8 Elite Gen 5,
  Android 9+ (minSdk 28).

## Run

```bash
# from the repo root
./scripts/setup.sh    # one-time, idempotent; creates examples/*/secrets.json

$EDITOR examples/tutor_tts/secrets.json    # the file setup.sh created

cd examples/tutor_tts
flutter pub get
flutter run --release \
    --dart-define-from-file=secrets.json \
    -d <YOUR_DEVICE_ID>
```

Tap **Load model** (the first load downloads
`neutts-nano-multilingual`), pick a phrase, then **Play**.

## Notes

- The voices are the bundle's own. Add your own per language as
  [custom voices](../../docs/tts.md#custom-voices).
- See [TTS](../../docs/tts.md) for the API this app uses.
