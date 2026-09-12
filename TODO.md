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

---

## D. Android 体验修复（用户反馈第二轮）

- [x] **D1 安卓通知栏/锁屏的播放·暂停·下一首点不动**
      两个原因，都修了：
      1) `AudioServiceConfig` 里 `androidStopForegroundOnPause: true`：暂停后服务退出前台，
         之后在后台按通知栏按钮要重新 `startForegroundService`，Android 12+ 抛
         `ForegroundServiceStartNotAllowedException`（按钮停在播放图标、下一首无反应）。
         改为 `false`（服务暂停时保持前台；`androidNotificationOngoing` 与它互斥，一并
         改为 `false`），并订阅 `AudioService.asyncError` 打日志。
      2) 队列只有「当前 + 预取的下一首」。预取还没完成时按下一首，透传给 impl 是
         静默 no-op。新增 `BaseAudioPlayer.setSystemCommandHandler` /
         `SystemMediaCommandHandler`，`KhinsiderAudioHandler` 的 `play/pause/
         skipToNext/skipToPrevious` 改为转发给 `PlayerController`；`next()` 会
         **按需解析**缺失的下一首（并 `await` 正在进行的预取）再切歌。
      顺带：`PlaybackState` 补 `queueIndex` / `androidCompactActionIndices`，
      `MediaItem` 补 `duration`（通知栏进度条/锁屏进度需要），位置上报按 1s 节流；
      因为服务暂停时不再退出前台、老版本 Android 上通知不可划掉，补一个
      `MediaControl.stop`（展开视图才显示，紧凑视图仍是 上一首/播放暂停/下一首），
      `stop()` 同样经 `SystemMediaCommandHandler` 回到 controller，顺带清空应用内队列状态；
      `_prefetchNextImpl` 缓存分支补 `finally`（append 抛错曾让 `_prefetchInFlight`
      永久为 true，之后再也不会预取）。
      回归测试：`test/media_session_test.dart`（7 条）。
      注：这里的接线方式（把会话当成播放器用）本身是错的，第四轮直接踩中，见 F1。
- [x] **D2 安卓点不到「喜欢」；专辑信息要在列表上面**
      窄屏专辑页原本只有一条标题栏，没有封面/信息/收藏按钮。现在
      `AlbumTrackList.header` 接受一个「表头」，手机布局把
      封面 + 标题 + 曲目数 + 平台/年份/开发商 + 收藏按钮 + 折叠的
      「Album details」（内含缓存目录提示）放在**曲目列表上方**，与曲目共用同一个
      `ListView`（不嵌套滚动）。收藏按钮抽成 `_FavoriteButton`：`DpadTile` 包裹
      `IgnorePointer` 的 `FilledButton`，触摸与遥控器 OK 走同一条路径、不会触发两次。
      400×900 / 360×640 / 320×568 三种尺寸都无溢出（拉通铺开 details 也一样）。
      回归测试：`test/mobile_ux_test.dart`。
- [x] **D3 安卓搜索栏移到下面、结果从下往上排**
      窄屏（≤700）时搜索栏放到 `Column` 的**底部**（键盘弹起跟随上移），
      结果网格 `reverse: true`：第一条紧贴搜索框、往上排；搜索框的「↓ 进结果」
      在窄屏改成向上找焦点。宽屏（TV/桌面）布局完全不变。
      回归测试：`test/mobile_ux_test.dart`。
- [x] **D4 封面别再用缩略图**
      站点把每张封面预渲染成多档，**只有目录段不同**：
      `<file>` 原图（最大见过 10.8MB / 3000×3000）、`thumbs_large/` 200×200、
      `thumbs/` 117×117、`thumbs_small/` 60×60。页面只给最小的两档
      （搜索结果 60×60、专辑页 117×117），画到 140–200px 卡片和 252px 封面上发虚。
      新增 `KhinsiderImage.large()`（khinsider_api）：改写目录段取 200×200，
      幂等、保留 host/专辑目录/百分号编码，非专辑图片原样返回；
      模型加 `AlbumSummary.imageUrl` / `Album.imageUrl`（由 `thumbUrl`/`coverUrl`
      现算，收藏/最近浏览里持久化的老数据不用迁移）。
      全app 改用 `imageUrl`：搜索网格、收藏/最近浏览行、相关专辑、
      专辑页封面、正在播放、通知栏/锁屏封面（`artUri`）、
      以及写到 `Music/KHInsider/<专辑>/image/cover.jpg` 的那张。
      解析器顺手把专辑页封面从 117×117 升到 200×200。
      回归测试：`image_urls_test.dart`（api，6 条）、
      `app/test/image_loading_test.dart`（6 条，逐个调用点都用变异测试验证过确实会红）。

---

## E. 触摸/鼠标交互分流（用户反馈第三轮）

- [x] **E1 安卓触摸屏：去掉 hover/选中高亮，改成点击水波纹**
      鼠标/键盘需要「我现在在哪」的提示，手指不需要：手指不会 hover，而点击后留在方块上的
      焦点环会被当成「选中」，而且点下一个才换、清不掉。所以在 `touch` 模式下不画焦点环与
      悬停底色，改用水波纹；`traditional`（键盘/遥控/鼠标）行为一点没变。跟 Flutter 自己的
      Material 组件同一条规则：`FocusManager.highlightMode`（最后用的是手指还是按键/鼠标），
      并用 `addHighlightModeListener` 跟模式变化一起重绘，所以接上键盘后焦点环会自己回来。
      实现要点（`core/widgets/dpad_tile.dart`）：
      * 水波纹不能直接套 `InkWell`：Material 的 ink 画在它包裹的 child **下面**
        （`_RenderInkFeatures.paint`：先画 ink，再 `super.paint` 画 child），
        卡片/封面是不透明的，套在外面根本看不见。所以墨层是 `Stack` 的最后一个孩子
        （内容之上）的透明 `Material`，ink feature 由 `onTapDown/Up/Cancel` 手动驱动
        （`splashFactory.create` + `confirm/cancel`，和 `InkResponse` 一样）。
      * 墨层套 `IgnorePointer`：它只是画，不能把方块内部控件的手势/Tooltip 挡掉
        （曲目行的缓存徽标 tooltip、主题色块的 tooltip 都在 tile 内部）。
      * 波纹在 `deactivate()` 里 dispose，不是 `dispose()`：tile 是墨层的**祖先**，
        卸载时后代先走完，等到 `dispose()` 时 `Material` 已经没了（ticker 泄漏断言）。
      * 点击仍然 `requestFocus()`（只是不画环）：之后接上键盘/手柄就从最后点的那一行继续。
      回归测试：`test/touch_feedback_test.dart`（6 条，四条变异——去掉模式判断、把 ink 建到
      外层 Material、墨层抢手势、只在 dispose 里清理——都能让对应的用例变红）。
      注意：widget 测试里 `InkSparkle` 的 fragment shader 不会编译（真机上首帧也可能还没好），
      所以水波纹那条用例把 `splashFactory` 固定成 `InkRipple` 再比像素。

---

## F. 播放控制全挂（用户反馈第四轮）

- [x] **F1 播了一首歌之后：点别的歌没反应、暂停点不动、通知栏按钮全部失灵（偶发卡死）**
      根因是 D1 的接线：`main.dart` 把 `audioPlayerProvider` 覆盖成了
      `KhinsiderAudioHandler`（媒体会话），而它的 `play/pause/stop` 正是**系统**入口，
      内部会转交回 `PlayerController` —— 于是
      `controller.pause()` → `handler.pause()` → `controller.pause()` → … 无限同步递归，
      把 isolate 挂死。通知栏进度条还在走是**假象**：那是系统按
      `updatePosition + updateTime + speed` 自己推算的，不代表应用还活着。
      三条症状因此完全一致：第一首能播（`loadQueue` 不走这条路），之后所有经过
      `play/pause/stop` 的操作全死 —— 点队列里已有的歌（`skipToIndex + play()`）、
      应用内暂停、通知栏暂停/停止；深递归/栈溢出还会让进程偶发卡死。
      修法：把「会话」与「播放器」拆成两个对象，**类型上**就不可能再互相调用：
      * 新增 `MediaSession` 接口（`setSystemCommandHandler` + `endSession()`）；
        `KhinsiderAudioHandler` 只实现它，不再是 `BaseAudioPlayer`（删掉全部转发方法，
        `MediaItem` 改为读 `BaseAudioPlayer.items` 这个单一事实来源）。
      * `PlayerController` 只用 `audioPlayerProvider`（impl）播放；系统命令通过
        `mediaSessionProvider` 装到会话上；`stop()` 额外 `endSession()`，
        应用内停止也会收掉通知栏（老 Android 上通知划不掉，只能靠它）。
      * `main.dart`：先建 `transport = JustAudioPlayerImpl()`，同一个实例既给
        `audioPlayerProvider`，也给 `KhinsiderAudioHandler(player: transport)` 去镜像。
      回归测试：`media_session_test.dart` 新增 `production wiring (main.dart)` 一组
      （每条命令只到 impl 一次、系统路径 session → controller → impl、
      应用内 `stop()` 会清掉 `mediaItem`），并给 `BaseAudioPlayer` 加 `items`。
- [x] **F2 播放中通知栏没有暂停按钮（F1 之外的第二条独立原因）**
      AOSP 里 SystemUI 的播放/暂停图标只看一个条件：`state == STATE_PLAYING`
      （`MediaControlPanel.isPlaying`）。而 audio_service 把
      `AudioProcessingState.buffering` 映射成 `STATE_BUFFERING`（`AudioService.java`
      的 `getPlaybackState()`），于是**只要上报 buffering，图标就变回「播放三角」**——
      正在响的时候通知栏反而没有暂停按钮；进度条还在走是因为 `PlaybackState` 的
      `speed` 仍是 1.0（系统按 `updatePosition + speed` 自行外推）。
      首次加载（`playing: false`）之后的重新缓冲、以及切歌/预取造成的 `loading`，
      都会把我们带进这个状态，所以「看不到暂停按钮」很容易复现。
      修法：`processing` 只在 `playing == false` 时才映射为 `buffering`，
      播放中一律 `ready` —— 宁可少一个转圈，也不能让「暂停」这个最需要的按钮消失。
      回归测试：`media_session_test.dart`「never advertises buffering while the track
      is playing」（变异验证：把条件改回 `snap.processing` 立刻变红）。
