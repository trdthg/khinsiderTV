# Khinsider

[English](README.md) · 中文

一个简单的 khinsider 网站的客户端

下载：见 [Releases](https://github.com/trdthg/khinsiderTV/releases)（Android armv7 / arm64 / 通用 APK、macOS、Windows、Linux/Steam Deck flatpak）

## 状态

目前我已经在 安卓/IOS/Macos/Windows/Chromecast 设备上面都测试了可以运行

## 架构 / 设计

这个软件包含两个部分，一个是 gui, 一个是 khinsider 的 api, 通过解析 html 获取数据，里面基本上就两个部分，搜索，获取专辑信息，所以我想甚至可以提供多种数据源支持其他的网站

- 我尽量把所有的 音乐 以及 (搜索结果，图片) 缓存 等直接保存在 Music 文件夹，方便用户随意的拷贝清空，或者做任何事情
- 软件支持边下边播，并且在播放一首之后会预载下一首，以获得流畅的体验
- 没有提供一键下载的按钮，因为 khinsider 是一个类似公益网站的存在，为了不给服务器造成大量负载 (如果你实际上并不会好好对待你下载的所有东西) 我也希望您尊重原网站本身

## 为什么使用 Flutter

最初的目的是想为我的 chromecast 以及 steamdeck 编写，steamdeck 倒是无所谓，但是 chromecast 比较麻烦，它使用 armv7a 架构，是一个 32 位设备，
然后我又想为我的 安卓/Macos/Windows/IOS 设备都提供客户端，所以最后选择了跨平台的方案

我考虑了 wiliwili 的方案，他的 steamdeck 体验非常好，但是我调查了它使用的框架，似乎位安卓设备支持起来比较麻烦，而且我不是特别有意支持 switch, 因为我目前还没有一台 switch

我也考虑了 VacuumTube 的方案，使用 Electron 原始网页做一层封装，但是前几天我听说了最新的 Electron 已经放弃了 armv7a 架构，而且 Electron 太重量级了，为了 chromecast 的体验，还暂时不要使用为好，不过对网页做封装确实是我比较喜欢的一种方案
原汁原味的体验，再加上一段 js 脚本提供控制器支持，超棒的，我原本想让我的 ai 这样做，但是他好像没有领会它的意思，不过这样也行，毕竟这只是一个小的软件，但如果有时间，或者有需要，比如登陆，我会在考虑这个方案的

使用 react native ? 我不知道，我以前是 react 的忠实用户，特写是里面的 jsx/tsx 语法但是我厌倦了 useEffect, 虽然 Hermes 引擎性能较好，而且能带来热更新的能力，但是我觉得没必要，毕竟这只是一个小软件

使用 kotlin/swift? 这两个我都体验过一下，代码确实非常有趣，不过我不太熟悉他们的跨平台情况，所以暂时没有考虑，另外我其实也不太喜欢 dart 里面大量的嵌套结构... 不过算了，就先这样吧，这个软件使用 ai 编写，我也不会太看里面的代码，不过我会尽量让其变得简单可维护

使用 sdl ? 先别了吧...

总之我的榜样是 localsend, 他非常简洁优美，希望这个软件也能这样

## 构建与发版

```sh
# API 包测试（离线，用真实页面 fixture）
cd packages/khinsider_api && dart test

# App 单元测试
cd app && flutter pub get && flutter analyze && flutter test

# 本地跑 macOS
flutter run -d macos

# Android（armv7a/arm64，老电视盒子也能用）
flutter build apk --release --target-platform android-arm,android-arm64

# 发版：改 pubspec、commit、打 tag、推送（CI 负责构建并发布产物）
./scripts/release.sh patch          # 0.1.3 -> 0.1.4
./scripts/release.sh minor          # 0.1.3 -> 0.2.0
./scripts/release.sh major          # 0.1.3 -> 1.0.0
./scripts/release.sh repin          # 把最新 tag 重新指到当前 commit 并重建 GitHub Release（CI 失败修复后用）
./scripts/release.sh repin v0.1.3   # 重指指定 tag
./scripts/release.sh patch --dry-run
```
