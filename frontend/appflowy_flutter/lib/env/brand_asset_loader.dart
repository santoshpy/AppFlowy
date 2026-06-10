import 'package:appflowy/env/env.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';

/// Wraps the default translation loader and overrides the `appName` key with the
/// `.env` brand name (APPFLOWY_BRAND_NAME) when set, so every `@:appName`
/// reference (e.g. "Welcome to @:appName") reflects the configured brand.
class BrandAssetLoader extends AssetLoader {
  const BrandAssetLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    final data = await const RootBundleAssetLoader().load(path, locale);
    if (data != null && Env.brandName.isNotEmpty) {
      return {...data, 'appName': Env.brandName};
    }
    return data;
  }
}
