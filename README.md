# 涂想 Doodle

一个离线白板，用来把说不清楚的东西直接画出来。鼠标、触控板、手写笔、手指都能画，画完导出 PNG。

所有内容只存在你的设备上：没有账号，没有遥测，Android 版连网络权限都没申请。

> **意见建议请发邮件到 `lazyawen@163.com`**（软件里点工具栏的信封图标也能直接写邮件）。
> 这个软件完全离线，没法自动上报，所以你的邮件就是唯一的反馈渠道 —— 真的会看。

> **版权声明**：本仓库**不是**开源项目，没有授予任何人使用许可，代码公开只是为了自己查看和备份。
> 未经作者书面同意，请勿修改后重新发布，也请勿把代码或安装包用到别处。详见下文「[版权与使用限制](#版权与使用限制)」。

**下载地址**：<https://github.com/LazyAwen/tuxiang-doodle/releases>

- **Windows**：下载涂想 Doodle 安装包 exe，双击安装即可，可选安装路径和桌面快捷方式。
  也可以直接用便携版 zip：解压后运行 `doodle.exe`。免安装，不联网。
- **Android**：按机型选对应的 APK（**绝大多数手机选 `arm64-v8a`**），安装时允许「未知来源安装」。
  用的是自签名证书，所以无法覆盖安装 Play 商店版本。

## 功能

- **工具**：钢笔、荧光笔、橡皮、直线、箭头、矩形、椭圆、文字
- **颜色**：12 种预设 + HSV 自定义取色器，笔宽 1–48 可调
- **画布**：无限画布，平移缩放（滚轮 / Ctrl+滚轮 / 双指捏合 / 右下角 +− 按钮），
  点阵 / 网格 / 横线 / 空白四种纸张
- **编辑**：整笔橡皮（划到就删整条笔迹）、200 步撤销重做、清空画板、插入图片、
  Shift 画直线时吸附 15°、画矩形椭圆时吸附正方正圆
- **导出**：整幅画作导出为 2 倍分辨率的 PNG
  - Windows：默认保存到程序目录下的 `涂想图片`（装到 Program Files 则自动用「文档\涂想」），
    保存前会弹「另存为」，可以自己选位置和文件名，**取消就是真的不保存**
  - Android：默认存进相册的 **涂想** 文件夹（不需要任何存储权限）；也可以在工具栏
    用文件夹图标换一个自己指定的目录。存完底部会弹卡片，可直接分享到 QQ / 微信，或复制路径
- **操作说明**：右上角「?」按钮，展开的手势表会自动区分鼠标操作和触屏操作
- **工具栏**：可以整个收起，再点左下角「展开工具栏」回来
- **快捷键**：`Ctrl+Z` 撤销，`Ctrl+Shift+Z` / `Ctrl+Y` 重做，`Ctrl+S` 导出，
  `Ctrl+/-` 缩放，`Ctrl+0` 回到 100%，`F` 适应内容，`1`–`8` 切换工具

## 反馈

用起来不顺手、想要什么功能、或者撞见 bug，都欢迎写信到 **`lazyawen@163.com`**。

- **软件内**：工具栏右侧的信封图标 → 「写邮件给我」（自动填好主题和排查模板），
  或者一键「复制邮箱」。手机上没有配邮件应用的，复制地址用网页邮箱发也行。
- **GitHub**：也可以直接开 [issue](https://github.com/LazyAwen/tuxiang-doodle/issues)。

写信时如果能带上这些，会快很多：什么设备（Windows / 安卓机型）、版本号、
怎么操作才会出问题、期望的效果。可以的话附一张截图。

## 版权与使用限制

Copyright © 2026 LazyAwen. 保留所有权利（All rights reserved）。

**这个仓库没有采用开源许可证。** 代码放在 GitHub 上是为了备份和方便自己查看，
本身就构成公开发表，但**不构成**任何使用授权 —— 没有 LICENSE 文件时，默认就是
「保留所有权利」，这是著作权法的默认状态，不是作者在苛刻。

具体来说，**未经作者书面许可，请不要**：

- 复制、修改本项目的源码后重新发布（俗称「二改」）
- 把本项目的代码、图标、文档，整段或部分地用到你自己的项目里
- 重新打包分发安装包、APK 或任何衍生版本
- 用于商业用途

**可以**自由做的：

- 下载安装、自己使用，装在自己的多台设备上
- 为了自己使用而修改源码（改了不用发出来，就没人管你）
- 在文章或视频里介绍这个软件，附上本仓库链接
- 引用少量代码片段做技术讨论，注明出处

发现自己被二改、被盗用时，可以把情况发到 `lazyawen@163.com`。

> 一个诚实的补充：GitHub 的服务条款允许任何人对公开仓库点 Fork，这一点作者无法关闭，
> 也没有 LICENSE 能阻止。所以这份声明的作用是**明确态度、保留追究的权利**，
> 而不是技术上让人 fork 不了。真要完全杜绝，只能把仓库改成私有。

## 从源码构建

需要 Flutter 3.47+（Dart 3.13+）；打 APK 还需要 Android SDK（含 Android 11+ 即可）。

```bash
flutter pub get
flutter test          # 17 个单元测试
flutter build windows --release
flutter build apk --release --split-per-abi
```

打 Windows 安装包需要先装 Inno Setup 6（`winget install JRSoftware.InnoSetup`），然后：

```powershell
powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1
```

产物在 `installer/output/DoodleSetup-<版本号>.exe`。

### Windows：插件 symlink 的绕过方法

Flutter 会在 `windows/flutter/ephemeral/.plugin_symlinks` 下创建符号链接，这需要
开发者模式或管理员权限。如果你的账号两者都没有，就先跑这个脚本 —— 它把链接预先
创建成 **junction（目录联接）**，不需要任何特殊权限，而 Flutter 工具会跳过已存在的链接：

```powershell
powershell -File tool/fix_plugin_symlinks.ps1
```

每次 `flutter clean` 之后都要重新跑一遍。

### Android：导出为什么走 Kotlin 而不是直接写文件

Android 11+ 的分区存储禁止 App 直接往 `/storage/emulated/0` 写文件，直接 `File.writeAsBytes`
会抛异常。所以 `MainActivity.kt` 里加了一条 `doodle/save` MethodChannel：

- `savePng`：通过 **MediaStore** 写进 `Pictures/涂想`，相册和文件管理器里都能看到，不需要权限
- `pickFolder` / `saveToTree`：通过 **SAF**（系统文件夹选择器）写进用户自己选的目录，
  并调用 `takePersistableUriPermission` 把授权持久化，重启之后依然有效

分享时因为外部 App 拿不到 MediaStore 的读权限，会先把 PNG 复制一份到 cache 目录再分享。

### Android：签名

`android/key.properties`（已 git 忽略）指向 `android/keystore.jks`。没有它的情况下
release 构建会静默退回 debug 密钥，本地测试没问题，但不要拿去分发。自己生成一个：

```bash
keytool -genkeypair -v -keystore android/keystore.jks -keyalg RSA -keysize 2048 \
        -validity 10000 -alias doodle
```

### Android：为什么要设 `kotlin.incremental=false`

这是故意写在 `android/gradle.properties` 里的。Kotlin 增量缓存存的路径是相对模块根目录的，
当构建产物和 pub 缓存不在同一个盘符时，它会报 `this and base files have different roots`。
这几个插件编译只要几秒钟，关掉增量编译没有任何代价。

---

## English

涂想 Doodle is an offline whiteboard for sketching ideas instead of struggling to
describe them. Draw with a mouse, a trackpad, a stylus, or a finger — then export a PNG.

Everything stays on the device: no accounts, no telemetry, and the Android build
requests no network permission.

> **Feedback: email `lazyawen@163.com`** — or click the envelope button in the toolbar,
> which opens a pre-filled mail. The app is fully offline and cannot report anything
> automatically, so email is the only feedback channel — and it really is read.

**Download the release:** <https://github.com/LazyAwen/tuxiang-doodle/releases>

- Windows: run the Inno Setup installer (choose an install directory and optionally a
  desktop shortcut), or use the portable zip — unzip and run `doodle.exe`.
- Android: install the APK matching your device (most phones want `arm64-v8a`).
  It is signed with a self-signed certificate, so allow "install from unknown sources"
  and note it will not install over a Play Store build.

### Features

- **Tools:** pen, highlighter, eraser, line, arrow, rectangle, ellipse, text
- **Colors:** 12 presets plus an HSV color picker; stroke width 1–48
- **Canvas:** infinite pan and zoom (wheel, Ctrl+wheel, pinch, or on-screen buttons),
  with dotted / grid / lined / blank paper
- **Editing:** whole-stroke eraser, 200-step undo/redo, clear board, insert image,
  Shift to snap lines to 15° and shapes to squares/circles
- **Export:** PNG of the whole drawing at 2× resolution
  - Windows: defaults to a folder next to the program (or under Documents when installed
    in Program Files); a Save As dialog lets you choose the location, and cancelling
    really cancels
  - Android: lands in the gallery folder **涂想** with no storage permission needed,
    or in a folder you pick yourself; a sheet then offers share-to-QQ/WeChat or copy path
- **Help:** a "?" button shows a gesture cheat sheet that adapts to mouse vs. touch
- **Collapsible toolbar** via the arrow button
- **Shortcuts:** `Ctrl+Z` undo, `Ctrl+Shift+Z` / `Ctrl+Y` redo, `Ctrl+S` export,
  `Ctrl+/-` zoom, `Ctrl+0` reset zoom, `F` fit content, `1`–`8` pick a tool

### Feedback

Send mail to **`lazyawen@163.com`** — bug reports, feature requests, and complaints
all welcome. Inside the app, the envelope icon in the toolbar opens a pre-filled
`mailto:` or copies the address to the clipboard. GitHub
[issues](https://github.com/LazyAwen/tuxiang-doodle/issues) work too.

Helpful details: your device (Windows version / Android model), the app version,
what you did, what you expected. A screenshot is even better.

### Copyright and usage

Copyright © 2026 LazyAwen. All rights reserved.

**This repository is not open source.** There is no license grant. The code is public on
GitHub as a backup and for the author's own reference — being visible is not permission.
Without a LICENSE file, the default under copyright law is "all rights reserved", and
that is a statement of fact, not extra strictness.

**Please do not**, without written permission:

- republish this project's source after copying or modifying it
- take this project's code, icons, or docs — in whole or in part — into your own project
- redistribute repackaged installers, APKs, or any derived build
- use it commercially

**You are welcome to**:

- download, install, and use it, on as many of your own devices as you like
- modify the source for your own private use (nobody minds if you don't publish it)
- write about or make videos about it, linking back to this repository
- quote short excerpts for technical discussion, with attribution

Report repackaging or misuse to `lazyawen@163.com`.

> An honest caveat: GitHub's Terms of Service let anyone Fork a public repository. No
> license can switch that off. This notice states the author's position and preserves the
> right to act on violations; it does not technically prevent a fork. Making the
> repository private is the only way to stop that completely.

### Building from source

Requires Flutter 3.47+ (Dart 3.13+), and the Android SDK for the APK target.

```bash
flutter pub get
flutter test          # 17 unit tests
flutter build windows --release
flutter build apk --release --split-per-abi
```

For the Windows installer, install Inno Setup 6 (`winget install JRSoftware.InnoSetup`)
and run `installer\build_installer.ps1`; the output lands in `installer/output/`.

See the Chinese section above for the Windows plugin-symlink workaround, why Android
exports go through a Kotlin `doodle/save` MethodChannel (MediaStore + SAF, since scoped
storage blocks raw writes), Android signing, and why `kotlin.incremental=false` is set.
