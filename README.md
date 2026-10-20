# 涂想 Doodle

一个离线白板。把说不清楚的东西直接画出来，画完导出 PNG。

没有账号，不联网，Android 版连网络权限都没申请，所有内容只存在你自己的设备上。

## 下载

去 [Releases](https://github.com/LazyAwen/tuxiang-doodle/releases/latest) 下载。

**Windows**

- `DoodleSetup-2.1.0.exe` — 双击安装，可以选安装路径和桌面快捷方式
- `Doodle-2.1.0-windows-x64-portable.zip` — 解压后运行 `doodle.exe`，免安装

**Android**

按机型挑一个 APK，绝大多数手机是 `app-arm64-v8a-release.apk`，老一点的 32 位机器用
`app-armeabi-v7a-release.apk`。安装时需要允许「未知来源」。用的是自签名证书，所以装不上
应用商店的版本，两者不能互相覆盖。

## 能做什么

- 钢笔、荧光笔、橡皮，12 种预设色加一个自定义取色器，笔宽 1–48
- 直线、箭头、矩形、椭圆、文字标注、插入图片
- 无限画布，滚轮、Ctrl+滚轮、双指捏合、右下角按钮都能平移缩放
- 空白、点阵、网格、横线四种纸张
- 200 步撤销重做，工具栏可以整个收起来腾地方
- 导出 2 倍分辨率的 PNG

按住 Shift 会吸附：画线锁 15°，画矩形和椭圆锁正方形、正圆。

## 快捷键

| 按键 | 作用 |
| --- | --- |
| `Ctrl+Z` / `Ctrl+Shift+Z` | 撤销 / 重做 |
| `Ctrl+S` | 导出 PNG |
| `Ctrl++` / `Ctrl+-` / `Ctrl+0` | 放大 / 缩小 / 回到 100% |
| `F` | 缩放到适应整幅画 |
| `1`–`8` | 依次切换各个工具 |

用触屏的话看软件右上角的「?」，那里列的是手势，不列键盘。

## 图存到哪儿

**Windows**：默认放在程序目录下的 `涂想图片`，装进 Program Files 没有写权限时自动换成
「文档\涂想」。保存前会弹另存为对话框，位置和文件名都能改，点取消就是真的不存。

**Android**：默认存进相册的 `涂想` 文件夹，不需要任何存储权限。想换地方就点工具栏的文件夹
图标自己选，选完会记住。存好之后底部会弹一张卡片，可以直接分享到 QQ / 微信，或者复制路径。

## 反馈

用着不顺手、想要新功能、撞见 bug，都写信到 **lazyawen@163.com**。

软件里点工具栏右边的信封图标就能直接写，主题和排查模板会自动填好；也可以一键复制地址，
用网页邮箱发。不想发邮件的话，开 [issue](https://github.com/LazyAwen/tuxiang-doodle/issues)
也一样。

顺便带上这些会好查很多：设备（Windows 版本或安卓机型）、软件版本号、怎么操作会出问题、
期望的效果，有截图最好。

## 版权

Copyright © 2026 LazyAwen. 保留所有权利。

这个仓库没有开源许可证，代码放在 GitHub 上是为了备份、也让自己随时能看，公开可见不等于
授权使用。自己装来用、装在自己几台设备上、写文章截图分享，这些都欢迎；改完重新发布、
把代码搬进别的项目、重新打包分发，请先问我一声。

发现被二改或盗用，可以发邮件到 `lazyawen@163.com`。

## 从源码构建

需要 Flutter 3.47+（Dart 3.13+）。打 APK 还要 Android SDK，含 Android 11 以上即可。

```bash
flutter pub get
flutter test
flutter build windows --release
flutter build apk --release --split-per-abi
```

构建时踩过的坑、插件 symlink 的绕法、Android 的签名和分区存储处理，都记在
[docs/BUILDING.md](docs/BUILDING.md) 里。
