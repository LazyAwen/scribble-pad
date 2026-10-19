# Scribble Pad

An offline whiteboard for sketching ideas instead of struggling to describe them.
Draw with a mouse, a trackpad, a stylus, or a finger — then export a PNG.

Everything stays on the device: no accounts, no telemetry, and the Android build
requests no network permission.

**Download the release:** <https://github.com/LazyAwen/scribble-pad/releases>

- Windows: unzip `scribble-pad-windows-x64.zip`, run `scribble_pad.exe`. Portable, no installer.
- Android: install the APK matching your device (most phones want `arm64-v8a`).
  It is signed with a self-signed certificate, so allow "install from unknown sources"
  and note it will not install over a Play Store build.

## Features

- **Tools:** pen, highlighter, eraser, line, arrow, rectangle, ellipse, text
- **Canvas:** infinite pan and zoom, plus dotted / lined / blank paper
- **Editing:** undo and redo, clear board, 12 colors, adjustable stroke width
- **Export:** PNG of the whole drawing at 2× resolution
- **Shortcuts:** `Ctrl+Z` undo, `Ctrl+Shift+Z` / `Ctrl+Y` redo, `Ctrl+S` export PNG

## Building from source

Requires Flutter 3.47+ (Dart 3.13+), and the Android SDK for the APK target.

```bash
flutter pub get
flutter test          # 15 unit tests
flutter build windows --release
flutter build apk --release --split-per-abi
```

### Windows: the plugin symlink workaround

Flutter creates plugin symlinks under `windows/flutter/ephemeral/.plugin_symlinks`,
which needs Developer Mode or an elevated shell. If your account has neither, run
the helper script instead — it pre-creates the links as **junctions**, which need no
special privilege, and the Flutter tool skips links that already exist:

```powershell
powershell -File tool/fix_plugin_symlinks.ps1
```

Re-run it after every `flutter clean`.

### Android: signing

`android/key.properties` (git-ignored) points at `android/keystore.jks`. Without it
the release build silently falls back to the debug key, which is fine for local
testing but not for distribution. Generate your own:

```bash
keytool -genkeypair -v -keystore android/keystore.jks -keyalg RSA -keysize 2048 \
        -validity 10000 -alias scribble
```

### Android: `kotlin.incremental=false`

Set in `android/gradle.properties` on purpose. Kotlin's incremental cache stores
paths relative to the module root, so it throws `this and base files have different
roots` when the build output and the pub cache sit on different drives. These
plugins compile in seconds, so disabling incremental compilation costs nothing.
