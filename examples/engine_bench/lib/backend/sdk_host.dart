import 'package:thestage_android_sdk/thestage_android_sdk.dart';

// ----------------------------------------------------------------------
// SdkHost
// ----------------------------------------------------------------------
/// One-time SDK `initialize` guard shared by every tab. The token is
/// injected at build time via the unified Android convention:
///   --dart-define=TS_API_TOKEN=th_...
/// Online initialize is required — the token is validated before any
/// pipeline loads.
class SdkHost {
  SdkHost._();
  static final SdkHost instance = SdkHost._();

  /// API token from the build-time define. Empty → the app shows a
  /// clear "TS_API_TOKEN not set" message and never calls initialize.
  static const apiToken = String.fromEnvironment('TS_API_TOKEN');

  bool _initialized = false;
  bool get hasToken => apiToken.isNotEmpty;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    if (apiToken.isEmpty) {
      throw StateError(
        'TS_API_TOKEN not set. Run with '
        '--dart-define=TS_API_TOKEN=th_...',
      );
    }
    await TheStageFlutterSDK.initialize(api_token: apiToken);
    _initialized = true;
  }
}
