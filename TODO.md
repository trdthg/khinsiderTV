# TODO

> 来源：AUDIT.md 的审计结论 + 用户的体验反馈。
> 每一项都「先写可复现的断言 → 再修 → 再跑全量测试」，做完一项勾一项。

---

## A. 审计发现的 Bug（AUDIT.md，已在本轮修复并带回归测试）

### 严重（崩溃 / 卡死 / 安全）

- [x] A1 `data/update_service.dart` `extractPendingUpdate` — **Zip Slip**：压缩包条目名未净化
      就拼路径，`../` 可以写出解压目录之外（已用恶意 zip 验证）。
      修复：新增 `_safeEntryName()`，拒绝 `..` / 绝对路径 / 空名；`root` 可注入以便测试。
- [x] A2 `data/update_service.dart` macOS 分支 — `while (!cur.path.endsWith('.app')) cur = cur.parent`
      在二进制不在 `.app` 里时 `Directory('/').parent` 是 `/` 自身 → 启动死循环（黑屏）。
      修复：`_macOSAppBundle()` 到根目录即返回 null；找不到 bundle 就放弃本次自更新。
- [x] A3 `packages/.../parsers.dart` `parseSearchResults` — `querySelectorAll('td')[1]` 在行内
      只有一个 `<td>` 时抛 `RangeError`，一行异常让整个搜索页崩掉。
      修复：取 cells 前判空 + 带索引保护的回退。
- [x] A4 `data/storage/json_kv_store.dart` `_flush()` — 两个 flush 并发写同一个 `.tmp`
      → `rename` 抛 `PathNotFoundException`（且是未被 await 的异步异常）。
      修复：flush 用 `Future` 链串行化，整段包进 `try/catch`。
- [x] A5 `data/storage/json_kv_store.dart` `read<T>` — 存储类型不匹配时 `as T?` 抛 `TypeError`，
      把 provider 永久变成 error。修复：`value is T` 判断，不匹配视为缺失。
- [x] A6 `audio/just_audio_player_impl.dart` `stop()` — `AudioPlayer.stop()` 不清空队列，
      `queueLength` 与 `_items` 分叉，之后每次 append 索引错位。
      修复：`stop()` + `clearAudioSources()`，并补一条「空」快照。
- [x] A7 `ui/album/album_screen.dart` — 文件本身语法错误无法编译。
      修复：恢复到引用共享组件（`AlbumTrackList` / `RelatedAlbumsRow`）的版本。

### 功能性

- [x] A8 `state/player_controller.dart` `playAlbum` — 把用户在 OSD 里选的音质重置成 MP3。
      修复：显式保留 `preferredFormat`。
- [x] A9 `state/player_controller.dart` `setPreferredFormat` — `urlFor(FLAC)` 有 `?? mp3Url`
      回退，导致没有 FLAC 也「切换成功」，UI 显示无损实际播 MP3。
      修复：新增 `urlForExact()`，切不上就不提交状态。
- [x] A10 impl 报 `currentIndex: null` 时 `copyWith` 的 `??` 保留旧值 → 停止播放后旧行仍高亮。
      修复：`copyWith` 改用 sentinel，显式 `null` 才清空。
- [x] A11 `core/keyboard/global_media_keys.dart` — `MediaStop` 被绑到 `togglePlayPause()`，
      整个应用没有任何地方能真正 stop。修复：绑到新增的 `PlayerController.stop()`。
- [x] A12 `core/widgets/seek_bar.dart` — 时长未知时 `_maxMs` clamp 到 1ms，进度条直接满格，
      点击会 seek 到 `0..1` 毫秒。修复：时长未知显示空 + 拒绝 seek。
- [x] A13 `state/update_controller.dart` — `downloadedFile` 永远不被赋值，`revealDownload()` 死代码。
- [x] A14 `state/update_controller.dart` — `retryDownload()` 想清错误但 `copyWith` 保留了旧值。
- [x] A15 `state/search_controller.dart` — 无请求版本号，慢的旧请求覆盖新结果。
      修复：`_generation` 计数器，迟到回复直接丢弃。
- [x] A16 `state/player_controller.dart` `build()` — `ref.onDispose(p.dispose)` 会把 `main()`
      override 进来的应用级播放器 dispose 掉。修复：只取消自己的订阅。
- [x] A17 `ui/album/album_screen.dart` — `BackButton(onPressed: () {})` 点了没反应。
      修复：`Navigator.maybePop(context)`（B3 里进一步加固）。
- [x] A18 `_ensureRowFocusNodes` 在 `build()` 里 dispose 仍被引用的 FocusNode
      →「used after being disposed」。修复：复用旧节点 + post-frame 退役多余节点。
- [x] A19 结构性：`album_screen.dart` 曾把曲目列表渲染复制了一份，`album_track_list.dart` /
      `related_albums.dart` 变死代码且丢失「People who also viewed」。已恢复共享组件版本。

---

## B. 体验问题（按用户反馈顺序，全部完成）

- [x] **B1 其他专辑的动画：向四周飞离，而不是直接消失/出现**
      `ui/album/related_albums.dart` 现在接收 `exitT`（zen 变形进度）：
      上排卡片往上飞、下排往下飞、列左右交替，整组像波浪一样散开并淡出，
      同时整行高度平滑收起（`OverflowBox` 保证卡片本身不被压扁，否则封面/标题会溢出）。
      返回时反向播放。关键修复：`album_screen.dart` 之前传 `showRelated: !zen`，
      变形一开始行就整体出树 —— 现在改为 `!zen || zenT.value < 1`，行在飞离期间保持挂载。
      回归测试：`album_ux_regression_test.dart`（中途不透明度 < 1、结束后行消失、Esc 返回后恢复）。
- [x] **B2 进入专辑页默认焦点落在第一首，且不自动播放**
      `_AlbumScreenState._focusFirstTrack()` 在专辑数据到达后的 post-frame 把焦点给 row-0，
      并在接下来几帧里重试（路由转场期间 navigator 的 focus scope 会把焦点抢回去）。
      焦点 ≠ 播放：测试断言 `loadQueue` 从未被调用、`entries` 为空。
- [x] **B3 没有默认焦点时返回按钮 / Esc 没反应 —— 原因与修复**
      原因有两层：
      1) Flutter 的按键事件从「当前焦点节点」开始**向上冒泡**。页面里什么都没聚焦时，
         焦点落在 route 的 focus scope 上，它是页面内任何 `onKeyEvent` 的**祖先**，
         所以页面内的 Esc 处理器根本收不到事件。
      2) 专辑页可能是入口路由（没有任何可 pop 的路由），`Navigator.maybePop` 是静默 no-op。
      修复：
      * 页面级 `Focus` 改为可聚焦 + `autofocus`（作为兜底焦点节点，Esc 总能到达它）；
      * `GlobalMediaKeys` 增加 Esc 兜底绑定（页面没人处理时 = 返回上一层）；
      * `_leave()`：能 pop 就 pop，否则 `pushReplacementNamed('/')` 回到搜索页；
      * 头部返回按钮在 zen 模式下不再禁用（返回 = 关菜单 → 退出 zen → 回专辑页）。
      测试：焦点回落到 route scope 时 Esc 仍能退出；入口路由下 Esc / 返回键都能落到搜索页。
- [x] **B4 鼠标 hover 列表行 = 高亮 + 聚焦**
      `core/widgets/dpad_tile.dart` 用 `onShowHoverHighlight`：hover 时请求焦点并显示淡色底，
      与「点击同时 requestFocus」的既有约定一致（否则 Enter 永远激活旧行）。
      注意：widget 测试里默认 highlightMode 是 touch，需要 `highlightStrategy = alwaysTraditional`。
- [x] **B5 每首曲子右对齐显示缓存状态**
      `ui/album/album_track_list.dart` 的 `_CacheBadge`：
      未缓存 = 半透明 cloud 图标；下载中（磁盘上有 `.part`）= 转圈；已缓存 = `download_done` +
      有无损时额外显示 `FLAC`；tooltip 里写明路径和大小。
      状态来自 `state/track_cache_controller.dart`（`albumCacheProvider`，autoDispose）：
      文件名由「曲目序号 + 标题」推出，所以**不需要**先解析直链就能知道每首是否已缓存，
      只是一两次 `stat` 调用，没有额外网络请求；下载期间用 1.2s 定时器轮询。
- [x] **B6 缓存直接保存到 Music 文件夹，按专辑分文件夹 + mp3/flac/image/other 分类**
      `audio/audio_cache_manager.dart` 重写：
      `<Music>/KHInsider/<专辑名>/mp3|flac|image|other`，文件名可读（`01 曲名.mp3`）。
      * macOS/Windows：`~/Music`、`%USERPROFILE%\Music`；Linux：`XDG_MUSIC_DIR`，回退 `~/Music`；
        Android/iOS：应用文档目录（公共 Music 目录需要 MediaStore 才能写）。
        权限不够时回退到 Application Support，绝不因此影响播放。
      * `other/album.json` 记录专辑信息 + 曲目表 + 原始页面链接（导出后仍知道来源）；
        封面进 `image/cover.jpg`；`.part` / `.mime` 由 just_audio 生成，都是隐藏后缀，不碍眼。
      * 同名专辑用 album id 短哈希区分（`album.json` 记录归属），互不覆盖。
      * `totalSize()/clear()/deleteAlbum()` 保留，供以后的设置页使用。

---

## C. 收尾

- [x] C1 `flutter analyze`（app）与 `dart analyze`（khinsider_api）零告警。
- [x] C2 `flutter test`（app，47 个）与 `dart test`（khinsider_api，14 个）全绿。
      新增回归测试：
      | 文件 | 覆盖 |
      |---|---|
      | `test/audio_cache_manager_test.dart` | Music 目录布局、文件名净化、同名专辑不互踩、absent→downloading→cached、album.json、封面进 image/、总量/删除/清空 |
      | `test/album_ux_regression_test.dart` | 默认焦点在第一首且不自动播放、无焦点时 Esc 可退出、入口路由下返回键/Esc 可用、hover 聚焦、缓存徽标三种状态 + FLAC 标记、related albums 飞离动画（中途淡出/位移，结束后消失，Esc 返回恢复）、RelatedAlbumsRow 散开方向 |
- [x] C3 `ARCHITECTURE.md` 已更新（缓存层级、Music 目录结构、焦点与快捷键）。
