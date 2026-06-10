// lib/env/env.dart
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/plugins/shared/share/constants.dart';
import 'package:envied/envied.dart';

part 'env.g.dart';

@Envied(path: '.env')
abstract class Env {
  // This flag is used to decide if users can dynamically configure cloud settings. It turns true when a .env file exists containing the APPFLOWY_CLOUD_URL variable. By default, this is set to false.
  static bool get enableCustomCloud {
    return Env.authenticatorType ==
            AuthenticatorType.appflowyCloudSelfHost.value ||
        Env.authenticatorType == AuthenticatorType.appflowyCloud.value ||
        Env.authenticatorType == AuthenticatorType.appflowyCloudDevelop.value &&
            _Env.afCloudUrl.isEmpty;
  }

  @EnviedField(
    obfuscate: false,
    varName: 'AUTHENTICATOR_TYPE',
    defaultValue: 2,
  )
  static const int authenticatorType = _Env.authenticatorType;

  /// AppFlowy Cloud Configuration
  @EnviedField(
    obfuscate: false,
    varName: 'APPFLOWY_CLOUD_URL',
    defaultValue: '',
  )
  static const String afCloudUrl = _Env.afCloudUrl;

  /// True when the cloud URL is pinned at build time via .env (APPFLOWY_CLOUD_URL).
  /// The in-app cloud-URL controls are shown read-only in that case, because the
  /// pin is authoritative and any in-app override is ignored (see cloud_env.dart).
  static bool get isCloudUrlPinned => afCloudUrl.isNotEmpty;

  @EnviedField(
    obfuscate: false,
    varName: 'INTERNAL_BUILD',
    defaultValue: '',
  )
  static const String internalBuild = _Env.internalBuild;

  @EnviedField(
    obfuscate: false,
    varName: 'SENTRY_DSN',
    defaultValue: '',
  )
  static const String sentryDsn = _Env.sentryDsn;

  @EnviedField(
    obfuscate: false,
    varName: 'BASE_WEB_DOMAIN',
    defaultValue: ShareConstants.defaultBaseWebDomain,
  )
  static const String baseWebDomain = _Env.baseWebDomain;

  // Config-driven brand name. When set in .env, overrides the in-app `appName`
  // (e.g. "Welcome to <brand>"). Empty -> keeps the default ("AppFlowy").
  @EnviedField(
    obfuscate: false,
    varName: 'APPFLOWY_BRAND_NAME',
    defaultValue: '',
  )
  static const String brandName = _Env.brandName;
}
