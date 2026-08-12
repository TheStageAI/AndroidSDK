import 'package:flutter/material.dart';

import 'backend/sdk_host.dart';
import 'tabs/asr_tab.dart';
import 'tabs/tts_tab.dart';
import 'tabs/vlm_tab.dart';
// LLM bench (tabs/llm_tab.dart) is intentionally not wired in yet — there
// is no published on-device chat-LLM bundle for Android. The tab is greyed
// out below; re-enable it (and re-import LlmTab) once a bundle ships.

// ----------------------------------------------------------------------
// EngineBench — benchmark the on-device engines (LLM / TTS / ASR / VLM)
// with the TheStage Android SDK. Each tab loads its model from Hugging
// Face on first use and reports decode tok/s, TTFT, and latency; the
// Share action exports the whole session as a JSON file.
//
// Token: injected at build time via
//   --dart-define=TS_API_TOKEN=th_...
// ----------------------------------------------------------------------
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EngineBenchApp());
}

class EngineBenchApp extends StatelessWidget {
  const EngineBenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Engine Bench',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: SdkHost.instance.hasToken
          ? const _HomeShell()
          : const _MissingTokenScreen(),
    );
  }
}

// ----------------------------------------------------------------------
// _HomeShell — bottom-tab navigation over the four engine benches
// ----------------------------------------------------------------------
class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  // On-device LLM is not available on Android yet, so the LLM tab (index 0)
  // is disabled and we open on the first working bench (TTS).
  static const bool _llmEnabled = false;

  int _index = _llmEnabled ? 0 : 1;

  static const _tabs = [
    _LlmComingSoon(),
    TtsTab(),
    AsrTab(),
    VlmTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final disabled = Theme.of(context).disabledColor;
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          if (i == 0 && !_llmEnabled) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text(
                    'On-device LLM is coming soon to Android.',
                  ),
                ),
              );
            return;
          }
          setState(() => _index = i);
        },
        destinations: [
          NavigationDestination(
            // Greyed out: LLM bench is disabled until a bundle ships.
            icon: Icon(Icons.chat_bubble_outline, color: disabled),
            label: 'LLM',
          ),
          const NavigationDestination(
            icon: Icon(Icons.graphic_eq),
            label: 'TTS',
          ),
          const NavigationDestination(
            icon: Icon(Icons.mic_none),
            label: 'ASR',
          ),
          const NavigationDestination(
            icon: Icon(Icons.image_outlined),
            label: 'VLM',
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
// _LlmComingSoon — placeholder for the disabled LLM bench
// ----------------------------------------------------------------------
class _LlmComingSoon extends StatelessWidget {
  const _LlmComingSoon();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).disabledColor;
    return Scaffold(
      appBar: AppBar(title: const Text('LLM bench')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline, size: 48, color: muted),
              const SizedBox(height: 16),
              Text(
                'On-device LLM is coming soon to Android.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// _MissingTokenScreen — shown when TS_API_TOKEN wasn't provided
// ----------------------------------------------------------------------
class _MissingTokenScreen extends StatelessWidget {
  const _MissingTokenScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Engine Bench')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'TS_API_TOKEN not set.\n\n'
            'Run with:\n'
            '  --dart-define=TS_API_TOKEN=th_...',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.red),
          ),
        ),
      ),
    );
  }
}
