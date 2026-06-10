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
SENTRY_DSN=                                     # optional: crash telemetry (empty = off)
UPDATE_FEED_URL=                                # optional: desktop appcast (empty = updater off)
```

- `APPFLOWY_CLOUD_URL` is **authoritative**: when set it always wins over any saved
  / in-app value and never falls back to the public cloud (see `lib/env/cloud_env.dart`).
  The in-app cloud-URL controls are shown **read-only** while it is pinned
  (`Env.isCloudUrlPinned`).
- `APPFLOWY_BRAND_NAME` overrides the `appName` i18n key via `BrandAssetLoader`.
- `SENTRY_DSN` (empty by default) enables crash/error reporting via `sentry_flutter`;
  no-op when unset. `UPDATE_FEED_URL` (empty) keeps the desktop auto-updater **off** so
  the fork never checks upstream AppFlowy releases.
- After editing `.env`, re-run `cargo make code_generation` to regenerate `env.g.dart`.

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

### One step (recommended)

`cargo make` convenience tasks build the Rust core for the target **and** launch the
Flutter app, handling the env quirks for you (Flutter pinned to 3.27.4 via fvm,
`~/.pub-cache/bin` on `PATH`, protoc-gen-dart snapshot health, and the right
simulator-vs-device build profile). Run from `frontend/`:

```bash
cargo make run-ios-sim             # iOS Simulator (auto-boots one if none is running)
cargo make run-ios-device          # physical iOS device (debug, stays attached)
cargo make run-ios-device-release  # physical iOS device (release, standalone)
cargo make run-android             # Android device/emulator (debug)
```

These wrap `scripts/run_mobile.sh` (callable directly too, e.g. `scripts/run_mobile.sh sim`).
Overrides: `DEVICE_ID=<id>` to target a specific device, `FLUTTER_BIN=<path>` to use a
specific Flutter. For the underlying steps, see below.

### Manual steps

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

**Android:** `flutter run -d <android-device>` (build needs the Android rust core via
`cargo make --profile development-android <...>`). The app reaches the LAN cloud over
cleartext only because of the scoped network config in §5 — see below.

## 5. Network & transport (cleartext now, TLS later)

The self-host is reached over **cleartext http on a trusted LAN**, scoped narrowly so
neither platform's blanket protection is disabled:
- **Android** — `android/app/src/main/res/xml/network_security_config.xml` permits
  cleartext **only** for the configured host. Its `<domain>` **must match the host in
  `.env APPFLOWY_CLOUD_URL`** — update it when your LAN IP/host changes.
- **iOS** — `NSAllowsLocalNetworking` (Info.plist) permits private-range LAN hosts while
  ATS stays enforced for all real-domain traffic.

> ⚠️ Until TLS, session tokens traverse the LAN in plaintext. Use only on a trusted,
> isolated network.

### Switch to HTTPS (recommended for production)

1. **Server** — terminate TLS at the self-host (nginx reverse-proxy + a cert; an
   internal-CA cert is fine for a private deployment). This is a change in the
   `AppFlowy-Cloud` repo's nginx/compose config.
2. **gotrue** — ensure `GOTRUE_URI_ALLOW_LIST` includes
   `appflowy-flutter://login-callback` and `GOTRUE_SITE_URL` is set, or mobile
   magic-link/OAuth login hangs on the callback.
3. **Client** — set `APPFLOWY_CLOUD_URL=https://<host>` in `.env`, trust the internal CA
   on devices if used, then **remove the cleartext exemptions**: delete the
   `<domain-config>` from `network_security_config.xml` and the `NSAllowsLocalNetworking`
   key from `Info.plist`. Rebuild.

## 6. Entitlements

`ios/Runner/Runner.entitlements` is stripped to empty for free-team signing. The
real functional impact is small:
- `aps-environment` (push) — **unused** (no push runtime in the app).
- `applesignin` (Sign in with Apple) — **unused**; the "Apple" login button goes
  through the OAuth custom URL scheme `appflowy-flutter://login-callback`, not the
  native entitlement, so OAuth login is unaffected.
- `associated-domains` (`applinks:appflowy.com/.io`) — the **only** real loss:
  universal-link sharing for the upstream domains (N/A for a different brand domain).

Re-add `applinks:<your-domain>` under a paid team if you want universal-link sharing.
