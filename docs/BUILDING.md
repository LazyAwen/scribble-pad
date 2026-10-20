# 构建笔记

给未来的自己看的。README 里只写怎么用，这里写怎么把东西构建出来、以及踩过的坑。

## 环境

- Flutter 3.47+（Dart 3.13+）
- 打 Windows 版：Visual Studio 2022 生成工具 + Windows 10 SDK
- 打 APK：Android SDK（Android 11 / API 30 以上即可）
- 打安装包：Inno Setup 6（`winget install JRSoftware.InnoSetup`）

## 常用命令

```bash
flutter pub get
flutter analyze
flutter test                                   # 17 个单元测试
flutter build windows --release
flutter build apk --release --split-per-abi
```

安装包：

```powershell
powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1
```

产物在 `installer/output/DoodleSetup-<版本号>.exe`。版本号从 `pubspec.yaml` 读，不写死在脚本里。

## Windows：插件 symlink 过不去

Flutter 会在 `windows/flutter/ephemeral/.plugin_symlinks` 下建符号链接，这需要开发者模式
或者管理员权限。两样都没有的话先跑这个脚本，它把链接预先建成 **junction（目录联接）**，
不需要任何特殊权限，而 Flutter 工具会跳过已经存在的链接：

```powershell
powershell -ExecutionPolicy Bypass -File tool/fix_plugin_symlinks.ps1
```

每次 `flutter clean` 之后都要重新跑一遍。

## Windows：换目录后 CMake 报错

`build\windows\x64\CMakeCache.txt` 里存着构建时所在的绝对路径。把仓库挪到别的位置后
CMake 会拒绝构建，报 `The current CMakeCache.txt directory ... is different than the directory
... where it was created`。删掉 `build\windows` 让它重新生成就行。

Android 同理：`android\.gradle` 里也缓存着旧路径，挪过目录之后要删掉，否则构建时会在原
路径下重新长出一堆空目录。

## Android：导出为什么绕到 Kotlin

Android 11+ 的分区存储不允许 App 直接往 `/storage/emulated/0` 写文件，`File.writeAsBytes`
会直接抛异常。所以 `MainActivity.kt` 里有一条 `doodle/save` MethodChannel：

- `savePng` — 通过 **MediaStore** 写进 `Pictures/涂想`，相册和文件管理器里都能看到，不需要权限
- `pickFolder` / `saveToTree` — 通过 **SAF**（系统文件夹选择器）写进用户自己挑的目录，
  并用 `takePersistableUriPermission` 把授权持久化，重启之后依然有效

分享时因为外部 App 拿不到 MediaStore 的读权限，会先把 PNG 复制一份到 cache 再分享。

## Android：签名

`android/key.properties`（已 git 忽略）指向 `android/keystore.jks`。没有这两个文件时
release 构建会静默退回 debug 密钥，自己测试没问题，但不要拿去分发。自己生成一个：

```bash
keytool -genkeypair -v -keystore android/keystore.jks -keyalg RSA -keysize 2048 \
        -validity 10000 -alias doodle
```

## Android：为什么关掉 Kotlin 增量编译

`android/gradle.properties` 里的 `kotlin.incremental=false` 是故意的。Kotlin 增量缓存存的
路径是相对模块根目录的，一旦构建产物和 pub 缓存不在同一个盘符，就报
`this and base files have different roots`。这几个插件编译只要几秒钟，关掉没有代价。
