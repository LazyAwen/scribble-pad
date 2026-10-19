# Scribble Pad

一个离线白板，用来把说不清楚的东西直接画出来。鼠标、触控板、手写笔、手指都能画，画完导出 PNG。

所有内容只存在你的设备上：没有账号，没有遥测，Android 版连网络权限都没申请。

**下载地址**：<https://github.com/LazyAwen/scribble-pad/releases>

- **Windows**：下载 `scribble-pad-windows-x64.zip`，解压后运行 `scribble_pad.exe`。免安装，不联网。
- **Android**：按机型选对应的 APK（**绝大多数手机选 `arm64-v8a`**），安装时允许「未知来源安装」。
  用的是自签名证书，所以无法覆盖安装 Play 商店版本。

## 功能

- **工具**：钢笔、荧光笔、橡皮、直线、箭头、矩形、椭圆、文字
- **画布**：无限平移与缩放，点阵 / 横线 / 空白三种纸张
- **编辑**：撤销、重做、清空画板、12 种颜色、笔宽可调
- **导出**：整幅画作导出为 2 倍分辨率的 PNG
- **快捷键**：`Ctrl+Z` 撤销，`Ctrl+Shift+Z` / `Ctrl+Y` 重做，`Ctrl+S` 导出 PNG

## 从源码构建

需要 Flutter 3.47+（Dart 3.13+）；打 APK 还需要 Android SDK。

```bash
flutter pub get
flutter test          # 15 个单元测试
flutter build windows --release
flutter build apk --release --split-per-abi
```

### Windows：插件 symlink 的绕过方法

Flutter 会在 `windows/flutter/ephemeral/.plugin_symlinks` 下创建符号链接，这需要
开发者模式或管理员权限。如果你的账号两者都没有，就先跑这个脚本 —— 它把链接预先
创建成 **junction（目录联接）**，不需要任何特殊权限，而 Flutter 工具会跳过已存在的链接：

```powershell
powershell -File tool/fix_plugin_symlinks.ps1
```

每次 `flutter clean` 之后都要重新跑一遍。

### Android：签名

`android/key.properties`（已 git 忽略）指向 `android/keystore.jks`。没有它的情况下
release 构建会静默退回 debug 密钥，本地测试没问题，但不要拿去分发。自己生成一个：

```bash
keytool -genkeypair -v -keystore android/keystore.jks -keyalg RSA -keysize 2048 \
        -validity 10000 -alias scribble
```

### Android：为什么要设 `kotlin.incremental=false`

这是故意写在 `android/gradle.properties` 里的。Kotlin 增量缓存存的路径是相对模块根目录的，
当构建产物和 pub 缓存不在同一个盘符时，它会报 `this and base files have different roots`。
这几个插件编译只要几秒钟，关掉增量编译没有任何代价。

---

## English

An offline whiteboard for sketching ideas instead of struggling to describe them.
Draw with a mouse, a trackpad, a stylus, or a finger — then export a PNG.

Everything stays on the device: no accounts, no telemetry, and the Android build
requests no network permission.

**Download the release:** <https://github.com/LazyAwen/scribble-pad/releases>

- Windows: unzip `scribble-pad-windows-x64.zip`, run `scribble_pad.exe`. Portable, no installer.
- Android: install the APK matching your device (most phones want `arm64-v8a`).
  It is signed with a self-signed certificate, so allow "install from unknown sources"
  and note it will not install over a Play Store build.

### Features

- **Tools:** pen, highlighter, eraser, line, arrow, rectangle, ellipse, text
- **Canvas:** infinite pan and zoom, plus dotted / lined / blank paper
- **Editing:** undo and redo, clear board, 12 colors, adjustable stroke width
- **Export:** PNG of the whole drawing at 2× resolution
- **Shortcuts:** `Ctrl+Z` undo, `Ctrl+Shift+Z` / `Ctrl+Y` redo, `Ctrl+S` export PNG

### Building from source

Requires Flutter 3.47+ (Dart 3.13+), and the Android SDK for the APK target.

```bash
flutter pub get
flutter test          # 15 unit tests
flutter build windows --release
flutter build apk --release --split-per-abi
```

See the Chinese section above for the Windows plugin-symlink workaround, Android
signing, and why `kotlin.incremental=false` is set.
