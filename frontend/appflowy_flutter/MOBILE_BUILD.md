# Mobile build (team fork)

How to build the branded **Teamflowy** iOS app from source against a self-hosted
AppFlowy Cloud. This fork adds config-driven cloud URL + brand name and an
xcconfig-based signing setup so the tracked project stays contributor-portable.

## 1. Configure `.env`

`frontend/appflowy_flutter/.env` (gitignored — create it):

```
APPFLOWY_CLOUD_URL=http://<your-cloud-host>   # e.g. http://192.168.1.18 on a LAN
AUTHENTICATOR_TYPE=2                            # MUST be 0 or 2 (rust rejects 3/4)
APPFLOWY_BRAND_NAME=Teamflowy                   # overrides "AppFlowy" in the UI
```

- `APPFLOWY_CLOUD_URL` is **authoritative**: when set it always wins over any saved
  / in-app value and never falls back to the public cloud (see `lib/env/cloud_env.dart`).
  The in-app cloud-URL controls are shown **read-only** while it is pinned
  (`Env.isCloudUrlPinned`).
- `APPFLOWY_BRAND_NAME` overrides the `appName` i18n key via `BrandAssetLoader`.

## 2. Code generation

```bash
cd frontend/appflowy_flutter
cargo make appflowy-flutter-deps-tools     # once: installs protoc-gen-dart etc.
cargo make code_generation                 # regenerates env.g.dart from .env + protobuf/freezed
```

## 3. iOS signing (xcconfig — no personal identity in the tracked project)

The Runner target reads its signing identity from xcconfig variables, so you set
your Apple Team **without** editing the tracked `project.pbxproj`:

```bash
cp ios/Flutter/Signing.local.example.xcconfig ios/Flutter/Signing.local.xcconfig
# edit ios/Flutter/Signing.local.xcconfig:
#   TEAMFLOWY_DEVELOPMENT_TEAM = <your 10-char Apple Team ID>
#   TEAMFLOWY_BUNDLE_ID        = com.<you>.appflowy   (must be unique to your team)
#   TEAMFLOWY_DISPLAY_NAME     = Teamflowy
```

`Signing.local.xcconfig` is gitignored. A free/personal Apple team works but the
build expires after ~7 days and can't sign the stripped paid-only entitlements
(see below).

## 4. Build & run

```bash
# Rust core (dart-ffi). On Xcode 26 the device/sim link needs the clang runtime
# for zstd's stack-probe builtins (___chkstk_darwin):
export RUSTFLAGS="-Clink-arg=-L$(xcrun --show-sdk-platform-path)/../../Toolchains/XcodeDefault.xctoolchain/usr/lib/clang/*/lib/darwin -Clink-arg=-lclang_rt.ios"

cargo make --profile development-ios-arm64-sim appflowy-core-dev-ios   # simulator
cargo make --profile development-ios-arm64     appflowy-core-dev-ios   # device (debug)
cargo make --profile production-ios-arm64      appflowy-core-dev-ios   # device (release, standalone)

flutter run -d <device-id>            # debug (must stay attached)
flutter run -d <device-id> --release  # release (runs standalone; ptrace warning is harmless)
```

iOS debug builds are JIT and only run while `flutter run` is attached; use
`--release` for a build that launches from the home screen untethered.

## 5. Entitlements

`ios/Runner/Runner.entitlements` is stripped to empty for free-team signing. The
real functional impact is small:
- `aps-environment` (push) — **unused** (no push runtime in the app).
- `applesignin` (Sign in with Apple) — **unused**; the "Apple" login button goes
  through the OAuth custom URL scheme `appflowy-flutter://login-callback`, not the
  native entitlement, so OAuth login is unaffected.
- `associated-domains` (`applinks:appflowy.com/.io`) — the **only** real loss:
  universal-link sharing for the upstream domains (N/A for a different brand domain).

Re-add `applinks:<your-domain>` under a paid team if you want universal-link sharing.
