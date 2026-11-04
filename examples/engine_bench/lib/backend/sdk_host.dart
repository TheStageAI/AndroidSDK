import 'package:thestage_android_sdk/thestage_android_sdk.dart';

// ----------------------------------------------------------------------
// SdkHost
// ----------------------------------------------------------------------
/// One-time SDK `initialize` guard shared by every tab. The token is
/// TS_API_TOKEN in this app's secrets.json, injected at build time via
///   --dart-define-from-file=secrets.json
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
        'TS_API_TOKEN not set. Put it in secrets.json and run with '
        '--dart-define-from-file=secrets.json',
      );
    }
    await TheStageFlutterSDK.initialize(api_token: apiToken);
    _initialized = true;
  }
}
