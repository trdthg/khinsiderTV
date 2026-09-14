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

## G. 系统集成（用户反馈第五轮：通知栏 / macOS / 缓存目录）

- [x] **G1 安卓通知栏只剩封面+标题+进度条，一个按钮都没有**
      **真正的根因：release 构建的资源压缩把通知 action 的图标删掉了。**
      Flutter 的 Gradle 插件对 release 默认开 `isMinifyEnabled = true` +
      `isShrinkResources = true`（`FlutterPlugin.kt:217`），R8 的资源压缩会删掉
      **只按名字引用**的资源，而 `MediaControl.androidIcon` 正是运行时按名字解析的
      （`AudioService.getResourceId` → `Resources.getIdentifier`），静态分析看不到这次引用
      —— 于是 audio_service 自带的 `audio_service_*` drawable 全被删掉。
      实测（解析 APK 里 `resources.arsc` 的字符串池）：v0.1.21 的 APK 里有 app 自己的资源名
      （`launch_background`、`network_security_config`…）也有 androidx 的
      （`accessibility_custom_action_*`、`notification_background`…），
      但 **`audio_service_pause` / `play_arrow` / `skip_previous` / `skip_next` / `stop` 一个都没有**，
      `res/` 只剩 8 个文件；v0.1.20（pub 上的插件、尚未 vendored）完全一样 —— 所以这是从第一轮反馈
      「安卓没法从系统的弹窗上面控制播放的暂停下一首」起就一直存在的 bug。
      图标找不到 → `getResourceId` 返回 0 → action 的 icon 为 null → SystemUI 直接把 action 丢掉
      （AOSP `MediaDataManager.createActionsFromNotification`:
      `if (action.getIcon() == null) { actionsToShowCollapsed.remove(index); continue }`），
      于是卡片上封面/标题/进度条都在（进度条来自 metadata 的 duration，与 actions 无关），
      **按钮一个都没有**，折叠展开都一样。这也解释了为什么早先那版「补
      `EXTRA_COMPACT_ACTIONS`」的修法没用：actions 在进入 compact 逻辑之前就已经被丢掉了。
      修法（三层保险）：
      1. 5 个 action 图标作为**矢量图放进 app 模块**
         `app/android/app/src/main/res/drawable/khinsider_{play,pause,skip_previous,skip_next,stop}.xml`，
         `KhinsiderAudioHandler` 用自定义 `MediaControl(androidIcon: 'drawable/khinsider_*')`
         （app 自己的资源一定进包）；
      2. `res/values/media_action_icons.xml` 里一个 array 引用这 5 个 drawable，
         并在 `MainActivity` 里读 `R.array.media_action_icons` —— 让压缩器认为它们被使用；
      3. `res/raw/keep.xml` 的 `tools:keep` 兜底 + release 显式 `isShrinkResources = false`
         （实测：重新构建出的 APK 里 `khinsider_*` 五个图标内容都在，`res/` 从 8 个文件回到 104 个，
         arm64 APK 只大 0.15 MB / 19.03 → 19.18 MB）。
      回归测试：`media_session_test.dart`「every control icon exists in the app module」
      逐条断言 `controls` 里每个 `androidIcon` 都①在 app 模块有同名文件、
      ②出现在 keep 列表里、③不是 `audio_service_*`。
      另外保留（次要保险，针对 SystemUI 的「通知 actions」回落路径）那条 vendored 补丁：
      SystemUI 画媒体卡片有两条路 ——
      1. **语义 actions**：`MediaDataManager.createActionsFromState()` 从 `PlaybackState.actions`
         推导按钮，`MediaControlPanel.setSemanticButton` 判定
         `showInCompact = SEMANTIC_ACTIONS_COMPACT.contains(buttonId)`，与通知无关；
      2. **通知 actions**（回落）：折叠卡片是否显示按钮由 `setGenericButton(..., showInCompact)`
         决定，`showInCompact` 来自 `notif.extras.getIntArray(Notification.EXTRA_COMPACT_ACTIONS)`，
         而这个 extra 只有 `MediaStyle.setShowActionsInCompactView()` 会写，
         audio_service 0.18.19（pub 最新版）只在 `SDK_INT < 33` 时调用它。
      于是仓库内 vendored 一份 `packages/audio_service`（`app/pubspec.yaml` 用
      `dependency_overrides` 指过去），把那句改成**无条件调用**，并按实际 action 数量
      裁剪/过滤下标（框架对越界下标会抛 `IllegalArgumentException`）。
      语义路径上多一个 extra 完全无副作用，所以两条路径都安全。
- [x] **G2 macOS release 版一直转圈、不出声（有缓存也一样）**
      根因是签名权限：`app/macos/Runner/Release.entitlements` 里有 `network.client`、
      `assets.music.read-write`，但**没有 `com.apple.security.network.server`**。
      just_audio 的 `StreamAudioSource._onLoad()` 无条件
      `ensureRunning()` 起一个本地 HTTP 代理，而本应用播的 `LockCachingAudioSource`
      正是 `StreamAudioSource` —— 沙箱应用没有那个 entitlement 就不能监听 socket，
      于是一个字节都收不到：UI 永远停在 loading，缓存与否都一样。
      Flutter 模板的 `DebugProfile.entitlements` 里恰好有这个键，所以
      `flutter run`（debug）正常、从 GitHub 下载的 `.dmg/.zip`（release）不正常 —— 与反馈完全一致。
      修法：给 `Release.entitlements` 补上该键（附注释说明原因）。
- [x] **G3 安卓缓存目录改成公开的 `Music/`**
      以前安卓/iOS 都写 `getApplicationDocumentsDirectory()`（应用私有目录，文件管理器里很难找）。
      Android 11+ 分区存储下想写公开 `Music/` 只有一条实用路径：`MANAGE_EXTERNAL_STORAGE`
      （「所有文件访问」，一个系统设置页里的开关，不是运行时弹窗；本应用是 GitHub 侧载，
      不受 Play 政策限制），因此：
      * `MainActivity` 新增 `dev.khinsider/storage` channel：`canWritePublicMusic`（API 30+ 用
        `Environment.isExternalStorageManager()`；≤29 用 `WRITE_EXTERNAL_STORAGE` 运行时权限）、
        `publicMusicPath()`、`requestAllFilesAccess()`（跳 `ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`）；
      * Manifest 加 `MANAGE_EXTERNAL_STORAGE` + `WRITE_EXTERNAL_STORAGE(maxSdkVersion=29)`
        + `requestLegacyExternalStorage`（Android 10 及以下）；
      * `AudioCacheManager` 先问 `AndroidStorage`：授权了 root 就是 `Music/KHInsider`，
        没授权仍是私有目录（功能不受影响，只是文件不好找）；`forgetRoot()` 让授权后
        **不用重启**，下次写入自动切到新目录（已下载的文件留在旧目录）；
      * UI 只做「解释 + 跳转」：首次启动问一次（`PublicMusicPrompt`，持久化标记），
        专辑页缓存目录行再给一个按钮（**只在手机窄屏布局出现**，宽屏桌面/TV 布局不变）；
      * `main.dart` 把唯一的 `AudioCacheManager` 同时给 `JustAudioPlayerImpl` 和
        `audioCacheManagerProvider`（原来播放器和 UI 各有一个实例，`forgetRoot()` 只会影响一半）。
      回归测试：`audio_cache_manager_test.dart`「Android public Music folder」一组 4 条
      （授权后用 Music、未授权用私有目录、`forgetRoot()` 后重新解析、pin 住的 root 不被清掉）。

## H. 播放进度跳转（用户反馈第六轮）

- [x] **H1 手机：当前播放行变成可拖动进度条**
      手机窄屏布局此前**没有任何播放器 UI**（OSD 菜单只在 `width > 700` 的 zen 布局里出现），
      唯一能看进度的地方就是当前播放行的背景填充（`album_track_list.dart` 里的
      `FractionallySizedBox`），而它不可交互 —— 想去某个位置只能靠通知栏。
      做法：新增 `_ScrubLayer`（同一文件），只有「手机布局 + 当前行 + 时长已知」才挂手势：
      * 横向拖动时填充跟着手指走，右侧浮出 `1:23 / 3:45` 读数（拖动期间用本地 scrub 值渲染，
        不依赖 player 的 tick）；
      * **松手才提交一次 seek** —— 音频走 `LockCachingAudioSource`，它的本地代理对已下载区间
        直接读缓存文件（瞬时），对还没下到的位置要等顺序下载追上来；每次 update 都 seek 会让
        播放器卡在手指后面。这也是没做成 Material `Slider` 那种连续 seek 的原因；
      * 没移动的触摸不会被这个手势拿走（手势竞技场判给 `DpadTile` 的 tap），所以轻点仍然是
        播放/暂停；拖动时给一次 `HapticFeedback.selectionClick()`；
      * 其它行、以及宽屏 TV/桌面布局完全不挂手势（`seek_scrub_test.dart` 用「宽屏拖动不 seek」
        把这条约束 pin 住）；宽屏继续用 OSD 的 `SeekBar`（点击 + ←/→ ±10s）。
      `AlbumTrackList` 新增 `enableScrub`（默认 false），只有 `album_screen.dart` 的
      `_buildMobile` 传 true。
- [x] **H2 seek 之后系统进度条立刻跟手**
      `KhinsiderAudioHandler` 的位置发布本来有 1s 节流（防止播放中 60Hz 的 tick 刷爆 platform
      channel），于是跳转后通知栏/锁屏的进度条会慢半拍。现在：
      * 位置单次变化 > 2s 视为 seek，立即（force）发布；普通 tick 仍被节流；
      * `seek()` 先把目标写进 `_lastPosition` 并发布，再 `await` 播放器 —— 否则系统滑块会在
        播放器反应过来之前弹回旧位置。
      回归测试：`media_session_test.dart` 新增两条（跳转立即发布 / 普通 tick 仍被节流；
      seek 先发布目标）。

## I. Google TV 搜索 + 存储 API（用户反馈第七轮）

- [x] **I1 Google TV 上搜索用不了（焦点进不了系统键盘 / 第二次打开键盘不出来）**
      根因是「Flutter 的文本框永远没法把方向键交给系统 IME」：
      Android TV 的系统键盘是**另一个窗口**，遥控器的「下」本该把焦点交给它，
      但这个按键会先被 Flutter 框架消费掉 —— `WidgetsApp` 的默认快捷键把方向键绑成
      `DirectionalFocusIntent`（`app.dart:1281`），`DefaultTextEditingShortcuts` 又把它绑成
      移动光标，两者都在应用内消化，按键根本到不了 Android 的窗口管理器。
      所以「键盘弹出来了但按不下去」是必然的；第二次「键盘不出来」同源：
      系统 IME 只在字段**获得焦点的瞬间**请求一次，字段一直有焦点就不会再出现。
      修法：TV 上不再用系统 IME，改成应用自绘键盘：
      * `MainActivity` 新增 `dev.khinsider/platform` channel 的 `isTelevision`
        （`FEATURE_LEANBACK` / `FEATURE_TELEVISION`）；
      * `main.dart` 在**第一帧之前**解析它并覆盖 `isTelevisionProvider`
        （不能先 false 后 true，否则 TV 上会闪一下系统键盘）；
      * 新组件 `lib/ui/search/tv_keyboard.dart`：Leanback 风格键盘
        （数字行 + 三行字母 + Space/Delete/Clear/Search/Hide），每个键是 `DpadTile`，
        第一个键 autofocus（遥控器一进搜索页就能直接按）；面板外层 `Focus.onKeyEvent`
        让物理键盘照样能打字；
      * 搜索页在 TV 上把字段设成 `readOnly`（不请求 IME）、`autofocus: false`；
        Enter/Select 打开键盘；Back（`PopScope`）先收键盘再退出搜索；
        提交后自动收键盘、把焦点还给结果；
      * 手机/桌面完全不变（`isTelevision == false` 仍是原来的可编辑字段）。
      回归测试：`test/tv_search_test.dart` 6 条（进入即聚焦第一个键、增删清空、
      Search 提交、Hide/Escape 收起 + Enter 重开、物理键盘可打字、非 TV 不变）。
- [x] **I2 用 MediaStore 免权限导出到 `Music/`（用户选定方案 B：只加导出）**
      用户选了「加一个导出到 Music 文件夹」：**缓存与播放路径一行不动**，新增导出动作把已缓存的
      曲目**复制**一份进 `Music/KHInsider/<专辑>`。
      * Kotlin：`dev.khinsider/storage` 新增 `exportToMusic`：Android 10+ 用 `MediaStore.Audio`
        插入（`RELATIVE_PATH` 指向 `Music/KHInsider/<专辑>` + `IS_PENDING=1`，写完置 0），
        **不需要任何权限**；同名文件先查一次（按 `DISPLAY_NAME` 查、再比对路径，
        避开各版本 `RELATIVE_PATH` 尾斜杠不一致）→ 返回 `exists`，不重复复制；
        ≤Android 9 返回 `unsupported`（那时缓存本来就在公开目录，不需要导出）。
        顺带写入 `TITLE`/`ALBUM`/`IS_MUSIC`，别的播放器里能正常显示。
      * Dart：`AndroidStorage.exportToMusic` + `MusicExportStatus`；新增
        `MusicExporter`（`lib/audio/music_export.dart`）：每首取**最优的那份**
        （有 flac 用 flac，否则 mp3）、跳过仍在下载（只有 `.part`）的曲目、逐首上报进度、
        汇总 exported/alreadyThere/failed/unsupported；导出目录名沿用缓存目录名
        （同名专辑被加过 id 后缀时两边保持一致）。新增 `androidStorageProvider` 便于测试注入。
      * UI：手机在专辑头部（收藏按钮旁）有 `Export to Music` 按钮；宽屏在缓存行里有一个图标按钮
        （TV 与桌面不出现，手机也不在缓存行重复）；导出中是**不可取消**的进度对话框，
        结束用**对话框**报告结果与落点；缓存已经在公开目录时直接提示「无需导出」而不是造重复文件。
      * 测试：`test/music_export_test.dart` 10 条（最优副本、优先 flac、跳过下载中、各状态计数、
        进度、同名专辑目录、手机按钮导出、无缓存提示、TV/非 Android 不显示）。
      * 已知副作用（用户已接受）：导出是复制，占双份空间；删缓存不会删 Music 里的副本。
- [x] **I3 导出对话框把 macOS 的 AOT 编译器搞崩了（已规避）**
      `flutter build macos --release` 会死在 `gen_snapshot`：
      `Unexpected object (Class with illegal cid, full-aot):
       Library:'package:flutter/src/widgets/_window_macos.dart' Class: _Rect@262353218`
      （CI 的 build-macos 同样失败；本地可复现，两次运行的 hash 完全一样，所以不是偶发）。
      二分结果：
      * `album_screen.dart` 回退到 v0.1.24 → 构建成功；
      * 只保留导出器（`MusicExporter` 可达、不弹任何对话框）→ 成功；
      * 在 `album_screen.dart` 里加「进度对话框 + 结果对话框」→ 崩；
      * 只留一个结果 `AlertDialog`、把 `LinearProgressIndicator`/`OutlinedButton` 换成
        应用里已有的控件、加 `--no-tree-shake-icons` → 全都还是崩。
      结论：**别继续往 `album_screen.dart` 里堆这类 UI 代码**（那个文件已经很大，
      像是踩到了编译器的某个上限；同样的对话框放进新文件没问题）。
      规避：导出流程搬进独立页面 `lib/ui/album/export_album_screen.dart`
      （自带 `Scaffold`，所以进度条、结果、完成按钮都放得下），`album_screen.dart`
      只多了一个 `Navigator.push`，构建恢复正常。
      这个页面顺带解决了原来的 `SnackBar` 问题：专辑页没有 `Scaffold`，
      从那儿弹的 SnackBar 只会排队、等回到搜索页才出现；导出结果现在显示在自己页面上。
- [ ] **I4 全应用只有搜索页有 `Scaffold`，专辑页的 SnackBar 实际不显示**
      `ScaffoldMessenger.showSnackBar` 在专辑页会断言失败（debug）/ 排队（release），
      受影响的是老代码：「Copy cache folder path」按钮、首次启动的公开 Music 提示。
      修法要先决定 `Scaffold` 放哪（app shell 包一层 / 每个页面自带），尚未处理。
      注意别踩 I3：改 `album_screen.dart` 之后务必本地跑一次 `flutter build macos --release`。

<details><summary>原始分析（方案比较，留档）</summary>

      事实核对：Android 10+ 应用**不需要任何权限**就能往 `MediaStore.Audio` 插入自己的音频
      （`RELATIVE_PATH = Music/KHInsider` + `IS_PENDING`），Android 11+ 还能改/删自己的贡献；
      读回自己插入的文件同样不需要权限（**重装后**那些文件算「别人的」，那时才需要
      `READ_MEDIA_AUDIO`（13+）/`READ_EXTERNAL_STORAGE`（≤12））。
      但「把缓存本体搬进 MediaStore」不是换个 API 就行：
      * 下载是 just_audio 的 `LockCachingAudioSource` 干的，它要一个**文件路径**做
        `cacheFile`（`just_audio_player_impl.dart` 的 `_sourceFor`），MediaStore 只给
        `content://`，没有路径；
      * `AudioCacheManager` 整层是路径式 API（`root()` 返回 `Directory`、
        `fileFor/fileForSync/categoryDirSync`、`totalSize` 遍历、专辑清单与封面写文件），
        换成 URI 要重写这一层和所有调用点；
      * 播放侧可行：just_audio 用 ExoPlayer 的 `DefaultDataSource`（`AudioPlayer.java:749`）
        支持 `content://`，但没有设备可验证 seek / 缓存交互 / 重名改名 / 重装归属。
      当时的三个选项：
      * **A. 把 MediaStore 当仓库**：下载仍在私有目录暂存，下完「搬」进 `Music/`，重播走
        `content://`；单份空间，但要重做 `_sourceFor` 与缓存扫描，且只能在用户设备上验证。
        → 未选。
      * **B. 只加导出（用户选了这个）**：播放/缓存零改动，导出时复制一份进 MediaStore。
        占双份空间，但风险最低、可以立刻用上。
      * **C. 维持现状**（继续用「所有文件访问」）：零风险，但要用户在系统设置里开那个开关。
</details>

## J. Google TV 键盘走位（用户反馈第八轮）

- [x] **J1 Chromecast 上「一部分字母选不到」：`t` 右边的键完全走不过去**
      用户描述：`t` 右侧的字母选不到。根因是**方向键交给了 Flutter 的
      `DirectionalFocusTraversalPolicy`**，而它是按几何算的：在真实 TV 窗口
      （1920×1080 @ density 2 = **960×540 逻辑像素**）下，同一行内从 `t` 往右会失败，
      `y u i o p` 走不到。之前的测试用的是默认 800×600 窗口（更宽），所以没复现出来。
      修法：`TvKeyboard` 改成 `StatefulWidget`，**自己持有每个键的 `FocusNode`**
      （`debugLabel: tv-key-*`、`skipTraversal: true`），把四个方向键交给自己的
      `Focus.onKeyEvent`：行内左右 clamp、跨行保留列号并对该行长度 clamp。
      不再依赖屏幕尺寸，也不会跑到键盘外面去。
      回归测试：`test/tv_search_test.dart` 里新增一条，用**真实 TV 的物理分辨率 +
      dpr 2**（`physicalSize: 1920x1080, devicePixelRatio: 2`）复现：数字行右移 4 格 →
      下到 `t` → 再右移 1 格 → Select，期望得到 `y`。
- [x] **J2 收起键盘后焦点丢了：再按 Enter 回不到输入**
      用户描述：退出输入再重新进入输入「找不到东西」。原因有两个：
      (1) 收起键盘时被聚焦的键节点被 dispose，焦点掉到未知位置（旧测试里甚至写了
      「先点一下输入框再按 Enter」的错误假设，等于把 bug 写进了测试）；
      (2) 重开键盘时第一个键靠 `autofocus`，而 `autofocus` 只对**新建**节点生效，
      重开时焦点已经被字段/别处占着，不会触发。
      修法：`_setKeyboardOpen(false, focusField: true)`（Hide / Back 走这条）在 post-frame 里
      把焦点显式还给**搜索框**：字段本身已经处理 Enter/Select 重开键盘、可打印字符、
      退格，所以「隐藏 → 按 Enter 继续输入」直接成立。这里能放心把焦点给字段，是因为
      Android 上 `readOnly` 的 `EditableText` 根本不会创建 input connection
      （`_shouldCreateInputConnection => kIsWeb || macOS || !readOnly`，Android 走最后一项），
      所以不会把系统 IME 勾出来。提交（Search）那条**不**抢焦点，仍然让结果列表的
      autofocus 把焦点带到第一张专辑上。`TvKeyboard` 则在 `initState` 的 post-frame 里
      显式 `requestFocus()` 第一个键，不再依赖 `autofocus`（它只对新建节点生效）。
      回归测试：Hide 之后**不点输入框**直接按 Enter，键盘必须回来并且第一个键已聚焦
      （再按 Select 得到 `1`）。
- 教训：TV 相关的 UI 测试要用真实 TV 的**逻辑分辨率**跑，默认 800×600 会把这类
  几何相关的走位问题盖过去。

## K. 焦点系统：别让焦点跑到看不见的地方（用户反馈第九轮）

- [x] **K1 禅模式按右键 / 列表到底按向下，焦点「不知道跑哪去了」**
      实测（`test/tv_focus_test.dart`，1280×800）：从封面按右，焦点落在
      `album-page` 这个**页面级容器 Focus 节点**上 —— 它铺满整屏、什么都不画，
      所以焦点环消失、遥控器看起来像死了。同一个原因还有两处：
      * `IgnorePointer` 只挡指针，**不挡焦点**：禅模式里已经淡出的 header
        （返回键、刷新键）和往左飞走的 info panel 里的按钮，仍然是方向键的目标；
      * related albums 那一段在禅模式里正在飞出去，tile 还挂在树上，同样能被选中。
      修法：
      * 所有**容器** Focus 加 `skipTraversal: true`（`album-page`、背景 wrapper、
        OSD 菜单的容器）——显式 `requestFocus`/autofocus 照旧有效，但方向遍历
        再也不会落在它们身上；
      * 淡出的 header / info panel 用 `ExcludeFocus(excluding: zen)`；
      * 禅模式里飞走的 related 行用 `ExcludeFocus(excluding: isZen)`。
- [x] **K2 从封面按右，应该锁到第一个曲目（之前锁到了第一个相关专辑）**
      方向键此前完全交给 Flutter 的几何遍历，它按坐标挑「最近的那个」，
      于是挑到了下面的相关专辑。新增 `lib/core/widgets/dpad_nav.dart`：
      ```dart
      DpadNav(right: rowFocusNodes.first, child: DpadTile(...))
      ```
      明确指定某个方向的目标；**没有指定**的方向原样交还给默认遍历，
      所以区域内部的上/下行为不变。
- [x] **K3 从曲目行按左，锁不到专辑封面**
      `AlbumTrackList` 早就留了 `onLeftArrow` 钩子（原来只在别处用过），
      但专辑页从来没传给它，左键就一直走几何遍历（被 info panel 抢走）。
      现在传 `() => coverFocus.requestFocus()`。
- [x] **K4 ChromeOS 上选不中「自动更新」横幅**
      横幅里的按钮是 `TextButton`/`IconButton`：可聚焦，但没有一条明确的路径把焦点
      送进去（要从下面的内容几何遍历），而且 Material 的焦点提示在 banner 底色上
      几乎看不见。现在按钮全部换成 `DpadTile`（应用一贯的焦点环）+ 各自的
      `FocusNode`（`update-action` / `update-view` / `update-close`），并用
      `DpadNav` 左右互跳；关闭键用 `DpadIconButton`。按下/选择仍然走原来的逻辑。
- 回归测试：`test/tv_focus_test.dart` 5 条（封面→第一个曲目、禅模式行→左→封面、
  禅模式右/到底不丢焦点、普通模式 related 仍可用向下走到、更新横幅可被 D-pad 走到）。
- 教训：**不要指望几何方向遍历**。TV 上凡是「区域」级别的走位（封面↔列表↔相关专辑↔
  横幅），都要像 `TvKeyboard` 那样自己说了算；容器节点（什么都画不出来的那种）
  必须 `skipTraversal`，否则它一定会成为目标，然后把焦点环吃掉。

## L. 待办：把「所有缓存」都放进 Music 文件夹（用户提出，暂不实施）

- [ ] **L1 目标（README 里已写明）**：尽量把**音乐、搜索结果、图片**等缓存都直接保存在
      `Music/` 文件夹，方便用户随意拷贝、清空、做任何事情。
      用户在第九轮反馈末尾确认：**现在先不做**，只在 TODO 里记一笔。
- **现状（哪些已经在 Music 里，哪些还没有）**
  * 音频：`LockCachingAudioSource` 边下边播。缓存根目录默认在应用私有目录（Android）
    或应用支持目录（桌面）；Android 可以开「所有文件访问」把根目录改成
    `Music/KHInsider`（`AudioCacheManager` + `AndroidStorage.publicMusicPath`）。
  * 免权限通道：专辑页的 **Export to Music** 用 MediaStore 把**已缓存**的曲目复制进
    `Music/KHInsider/<专辑>`（Android 10+ 免权限），只复制、不搬运，不会替用户下载。
  * 专辑侧车文件：播放过的专辑会往缓存根目录下的专辑文件夹写
    `other/album.json` + `image/cover.jpg`（200×200 `thumbs_large`）。
  * **没有**进 Music 的：搜索历史 / 收藏 / 最近查看（`storage/json_kv_store.dart`，
    应用数据目录里的 JSON 文件）；以及「只在列表里出现过、没播放过」的封面
    （UI 走 `cached_network_image` 的私有缓存目录）。
- **为什么不是「换个 API」就完事**
  1. `LockCachingAudioSource` 需要**文件路径**做 `cacheFile`（just_audio 的要求），
     MediaStore 只给 `content://`。所以只能是：私有目录暂存 → 下完 insert 进
     MediaStore（`RELATIVE_PATH` + `IS_PENDING`）→ 删掉私有副本；重播改走
     `content://`（ExoPlayer 的 `DefaultDataSource` 支持，但 seek / 缓存交互没设备验证）。
  2. `AudioCacheManager` 整层是**路径式** API（`root()` 返回 `Directory`、
     `fileFor/fileForSync/categoryDirSync`、`totalSize` 遍历、专辑清单与封面写文件），
     换成 URI 要重写这一层和所有调用点（含 `_sourceFor` 与缓存扫描）。
  3. **重装后的归属**：自己贡献给 MediaStore 的文件，重装后算「别的应用」的，
     读回需要 `READ_MEDIA_AUDIO`（13+）/ `READ_EXTERNAL_STORAGE`（≤12）。
     「完全免权限」和「重装后还能接着用旧文件」不可兼得。
  4. 搜索历史 / 收藏属于**应用状态**而不是媒体：放进 `Music/` 需要
     `MANAGE_EXTERNAL_STORAGE`（11+ 写普通文件），或者塞进 `MediaStore.Files`
     （会被系统扫描器当成奇怪的媒体文件，不推荐）。建议要么留在应用目录，
     要么只提供「导出 / 导入」。
  5. 封面：要让**所有**封面（包括只看过列表、没播放的专辑）也进 `Music/`，
     得给 `cached_network_image` 换自定义 `CacheManager`（`FileSystem` 指向
     缓存根，缓存键按专辑分目录）。
  6. 桌面（macOS/Windows/Linux）本来就没有 MediaStore，写 `~/Music` 是普通文件，
     但 macOS 有沙箱、需要用户授权目录 —— 也要实测，不能想当然。
- **如果以后要做，建议的顺序**
  1. 先把缓存层改成「路径 + URI 双形态」（接口先行，导出/播放两侧都还能走老路）；
  2. Android 上做「下完搬进 MediaStore」并删私有副本，你在手机 + TV 上实测
     seek、缓存命中、重装后的表现，再决定是否要读权限；
  3. 封面缓存换成自定义 `CacheManager`（这一步和 Android 权限无关，风险最低）；
  4. 搜索历史/收藏保持现状，或另做导入导出。
- 相关存档：第七轮 I2 的 `<details>` 里有当时 A/B/C 三个方案的完整分析
  （A = 把 MediaStore 当仓库，B = 只加导出（已做），C = 维持「所有文件访问」）。

## M. 电视播放时不要休眠（用户反馈第十轮）

- [x] **M1「Chromecast 播放一段时间会自己休眠」**
      先说结论：**CPU 唤醒锁一直是有的** —— 播放时 `audio_service` 的
      `enterPlayingState()` 会拿一把 `PARTIAL_WAKE_LOCK`（`packages/audio_service/
      android/.../AudioService.java`），所以不是「进程睡着了导致播放卡住」，
      而是**电视自己睡了**：Chromecast / Google TV 在屏幕空闲到系统超时后进入
      ambient mode，再往下就是待机，待机一来音频输出就没了 —— 从用户角度就是
      「放着放着就停了」。
      修法：播放期间给窗口加 `FLAG_KEEP_SCREEN_ON`（Android 官方支持的做法），
      屏幕不超时 → 不进 ambient → 不进待机。
      * Dart：`lib/core/platform/device.dart` 的 `setScreenAwake(bool)`，
        复用已有的 `dev.khinsider/platform` 通道，方法名 `setKeepScreenOn`；
      * Kotlin：`MainActivity.setKeepScreenOn()`（`addFlags` / `clearFlags`）；
      * 接线：新增 `lib/core/widgets/keep_screen_awake.dart`，在 `app.dart` 根部
        监听 `playerControllerProvider.select((s) => s.playing)`，
        **开着播才常亮，暂停/播完就放开**（用 `listenManual(fireImmediately: true)`，
        否则热重启后已经在播的情况会漏掉第一次 `true`）。
      * 只对 Android 有效（其它平台没有这个 handler，调用落在 `MissingPluginException`
        的 catch 里，什么都不做）；`FLAG_KEEP_SCREEN_ON` 只在本应用可见时生效，
        所以退到后台不用手动清。
- **M2 管不了的部分（要跟用户说清）**：电视自己的「无操作 N 小时后自动关机 /
  睡眠定时器」是固件/用户设置，应用改不了。如果 TV 设置里开了 auto power off，
  再久一点还是会关 —— 那不是应用能拦的。
- **M3 还没做、但值得记一笔**：`AudioService.exitPlayingState()` 只在
  `androidStopForegroundOnPause = true` 时才释放唤醒锁；而这个应用为了修「暂停后
  通知栏按钮失灵」把它设成了 `false`，于是**暂停之后那把 `PARTIAL_WAKE_LOCK` 一直
  握着**（服务的 `onDestroy` 才放）。手机上这意味着暂停后 CPU 不能深睡、白耗电。
  要修的话：在 `exitPlayingState()` 里无条件 `releaseWakeLock()`（前台服务照旧
  不退），但这属于改动 vendored 插件 + 需要真机验证，先不动。
- 回归测试：`test/screen_awake_test.dart` 两条（播放=true、暂停=false、再播=true；
  平台没有 handler 时静默吞掉）。
- 顺带踩到的测试坑：**`flutter_test` 里没有被 mock 的 `MethodChannel` 调用不会抛
  `MissingPluginException`，而是永不返回**（把整个测试进程挂住）。要断言「没有
  handler 也能活」，得让 mock handler 主动 `throw MissingPluginException(...)`。

## N. 第十一轮：手机布局、循环、禅模式与 TV 键盘

- [x] **N1 收藏 + 导出挤成两排（安卓）**
      手机版专辑头部把它们放在「标题那一列」里（`Wrap`），而那列只剩
      `屏宽 - 104px 封面 - 12` 的宽度，两个带文字的按钮必然换行。现在这两个按钮
      挪到封面下面、**占满整行**并排（`Expanded` 一人一半），手机上也只有一排。
      Chromecast 那边这两个按钮分别在信息栏和缓存提示行里，位置本来就不一样，
      宽度由信息栏限制，没有跟着改（用户提到的「限制滚动宽度」按这个理解处理）。
- [x] **N2 安卓：最近搜索跟搜索框都在下面**
      手机布局的搜索框本来就贴底，但「最近搜索」在顶部空闲页里，离输入的地方隔了一屏。
      现在窄屏把历史改成 `_RecentSearchesStrip`：一行可横向滚动的 chip，紧贴搜索框上方，
      并且空闲页里不再重复显示（`_IdleHome(showHistory: narrow ? false : true)`）。
      宽屏（TV/桌面）保持原样。
- [x] **N3 默认循环播放**
      之前 `just_audio` 的队列播完就 `pause()` 并回到第 0 首（等于停住），
      `PlayerController.next()` 到专辑末尾也是直接 return。现在两者都循环：
      队列播完 → `_loopAlbum()` 重新 `playAlbum(album, startIndex: 0)`；
      在最后一首按下一首 → 同样回到第一首。`_looping` 防重入（completed 快照会重复推）。
      注意 `next()` 里是 `unawaited`：通知栏「下一首」要立刻响应，加载失败会走 state.error。
- [x] **N4 Chromecast：退出专辑要停止播放**
      宽屏没有迷你可视化播放条，专辑页**就是**播放器 UI，退出后音频还在放却没有任何入口去控制。
      现在 `_releaseAlbumPlayback()`：宽屏 `stop()`（清空队列、结束媒体会话），
      窄屏仍然只 `pause()`（手机有迷你可视化条，保持原行为）。
- [x] **N5 Chromecast：退出禅模式回专辑页（不是搜索页）**
      根因：遥控器的返回键在 Android 上是**系统 pop**，不是 key event，
      所以 `_onBack()` 根本收不到 —— 上一级路由直接被丢掉。现在专辑页外面套了
      `PopScope(canPop: !zen && !menuOpen)`：禅模式/OSD 打开时拦住 pop，
      按一次退一级（OSD → 禅模式 → 专辑页 → 搜索页）；真正退出专辑时也会触发
      `_releaseAlbumPlayback()`（补上系统返回这条路径的停止播放）。
- [x] **N6 进出禅模式焦点都落在「对应的曲目」上**
      `_requestRowFocus()` 里有一句 `if (_zen) return;` —— 禅模式里它拒绝做任何事，
      而进入禅模式时只做了一次 post-frame `requestFocus()`，跟重建抢时间，经常丢。
      现在 `_requestRowFocus(index, attempts: 12, allowZen: true)`，进入禅模式聚焦
      `currentIndex`（正在播放的那首），退出禅模式同样重试聚焦 `currentIndex`。
- [x] **N7 TV 键盘支持大写与特殊字符**
      `TvKeyboard` 现在有两层：字母层（数字 + qwerty + `⇧` 大写锁定键）和符号层
      （`!@#$%&*()?`、括号、标点，外加 `é è ü ö ä ñ ç` 这些专辑名里真有的大小写字母）。
      切换层的键固定在底行最后一格，来回切换时准星不会跑。大写是「锁定」而不是
      「一次」：遥控器按一次换一个字母太痛苦。方向键仍然是自己算网格（几何遍历在
      960×540 上会卡住），键位节点固定 10 列 × 5 行，切层时按当前层的行长重新 clamp。
      *为什么不用系统输入法*：Android TV 上从 Flutter 文本框无法把焦点交给 IME 窗口
      （方向键先被框架吃掉了），系统键盘会出现但按不动，所以 TV 走自绘键盘；
      手机/桌面依旧用系统输入法（`readOnly` 只在 TV 上为 true）。
- 回归测试：`test/tv_focus_test.dart` 新增「系统返回键在禅模式只退出禅模式、不离开专辑」；
  `test/tv_search_test.dart` 新增「TV 键盘能打大写和符号」；`media_session_test.dart`
  里「最后一首按下一首」的用例改名并注明现在是循环。
- 没写测试的两条：N4（宽屏退出专辑的 `stop()`）和 N3 的「播完自动循环」需要真实
  构造 completed 快照 / 有下级路由的 Navigator，测试里搭建成本高，先在真机上验。

## O. 第十二轮：TV 改回系统输入法

- [x] **O1 用户反馈**：`我希望键盘还是用原生键盘吧?`（第十一轮刚把自绘键盘补上大写/符号）。
      结论：TV 默认走**系统 IME**，自绘键盘降级为后备，两种模式可切换、可持久化。
- 改动：
  - `TvKeyboardMode { system, builtin }` + `tvKeyboardModeProvider`（存在 `khinsider_store.json`
    的 `tv_keyboard_mode`，默认 `system`，老用户没有这个键 ⇒ 也是 `system`）。
  - 搜索框：`readOnly: builtinKeyboard`、`autofocus: !builtinKeyboard` —— 系统 IME 模式下就是普通
    可编辑输入框，进入页面聚焦即弹出 Android TV 自带键盘（方向键可用）。
  - 搜索框**左侧**新增键盘按钮（仅 TV，`DpadIconButton`，`filled` 表示当前用的是自绘键盘）：
    一键切换两种输入法。从输入框按「左」（光标已在开头）聚焦它，按「右」回到输入框 ——
    遥控器永远够得着后备键盘。
  - 系统 IME 模式下按「确定/Select」会让 `TextInput.show` 重新弹出键盘：`TextField` 只在获得焦点时
    请求 IME，Back 关掉之后字段从没失去焦点，就再也不会请求了（`EditableText` 没有公开 API，
    这里发的是框架内部同一条消息）。
  - `PopScope(canPop: ...)` 只在**自绘键盘打开**时拦返回键；系统 IME 模式下 Android 自己会用第一次
    Back 关掉 IME，所以不能再拦 pop。
- 回归测试（`test/tv_search_test.dart`，pump 多了一个 `mode` 参数，默认 `builtin` 给老用例）：
  默认 TV 不渲染 `TvKeyboard`、字段可编辑、`testTextInput.isVisible`；按钮来回切换两种模式；
  Select 能把 IME 叫回来；「左」聚焦到键盘按钮、「右」回到输入框。
- 待真机确认：某些 TV box 可能压根没装 IME —— 那时按「左」→ 键盘按钮 → 切回自绘键盘即可。

## P. 第十三轮：Chromecast 上选不中「更新」按钮

- [x] **P1 用户反馈**：`我现在还是无法在 chromecast 上面选中更新按钮..........`
- 根因（不是按钮没接线，而是**焦点进不去**）：`UpdateBanner` 内部三个按钮用 `DpadNav` 左右串好了，但
  App 的页面都是**按区域导航**（`skipTraversal` 容器 + 显式 `DpadNav`），Flutter 的几何遍历从搜索框/曲目
  列表走不到屏幕顶部这一行 —— 提示条在 `Navigator` 之外（`MaterialApp.builder` 的 Column 里），
  它的焦点节点跟页面不在同一棵子树里，靠箭头「走上去」是靠运气的。旧测试只在一个玩具页面
  （单个 `DpadTile`）里验证过「Up 能到提示条」，所以一直没暴露。
- 改动（`lib/ui/shared/update_banner.dart`）：
  - TV 上提示条**出现时自己接管焦点**：post-frame `_actionFocus.requestFocus()`，并把当时的
    `primaryFocus` 记到 `_returnFocus`。`_tookFocus` 保证只在出现时抢一次（下载进度刷新不会再把焦点拽回来）。
  - **按「下」把焦点还回去**（`_restoreFocus()`：优先还给记住的那个节点；节点没了就几何向下；都没有就
    放行默认遍历）。关闭按钮同理，并且提示条消失时也会还回去 —— 否则遥控器会「死」掉。
  - 下载中阶段原来把动作位换成纯 `Text`，`_actionFocus` 节点被摘掉 ⇒ 圆环消失、够不到 View/关闭。
    现在进度用 `DpadTile` 占住同一个位置（`onSelect: () {}`）。
  - 提示条外层 `Focus(canRequestFocus: false, skipTraversal: true)`：加「下」键处理时引入的容器节点
    会让几何遍历停在它身上（`focusedLabel()` 变成 `Focus`），旧的「Up 能到提示条」测试立刻抓到了这一点。
- 测试：`test/tv_focus_test.dart` 新增「TV 上提示条接管焦点 → Select 触发下载（进度变 50%）→ 圆环不消失 →
  按「下」回到内容」；`FakeUpdateController` 增加 `download()`。旧的「Up 能到提示条」用例保持通过。
- 注意：这个修复**只能通过手动安装** `v0.1.31` 生效 —— 坏掉的那个按钮本身没法把新版本装上去。
- Android 更新链路本来就有：Download（下载对应 ABI 的 APK）→ Show file → `installApk` → 系统安装器
  （需要「未知来源」权限）。

## Q. 第十四轮：Chromecast 系统键盘无法聚焦（上网查证 + 平台视图方案）

- [x] **Q1 用户反馈**：`呼出的系统键盘还是无法聚焦` + `我想用系统键盘 ... 解决后就可以把咱们自己的实现删除掉了`
- **查证**（本机 web_search/web_fetch 都被代理拦掉了：搜索接口 402、域名解析到非公网 IP；改用 `gh api` 直接查 GitHub ✅）
  - flutter/flutter **#177360**（open，Chromecast 上「Unable to use software keyboard with TextField」）
  - flutter/flutter **#154924**（closed as WAI：官方在模拟器/真机上发现「YouTube 和设置也一样」，认为 Android TV 正在放弃用 D-pad 操作软键盘，
    且 Android TV 不是官方支持目标）
  - flutter/flutter **#125541**（同样的现象：`Flutter activity still have focus and d-pad is navigating through elements behind keyboard`）
  - flutter/flutter **#147772**（open，Android TV 上 TextField 的 D-pad 导航坏掉）
  - ⭐ 关键：**#177360 里 2026-07 的评论**在真机 Google TV 上做了对照实验 —— 同一个页面、同一个 Gboard TV：
    用 Flutter `TextField` 时方向键进不了键盘；把输入换成**平台视图里的原生 `EditText`** 后，Gboard TV 完全可以方向键选字母、
    `IME_ACTION_DONE` 正常、密码框也正常。结论：**IME 仍然支持 D-pad，只是只对「平台文本输入」生效**，问题在 Flutter 提供的
    `InputConnection`/`EditorInfo`。官方给的 workaround 就是「用平台视图嵌一个最小 `EditText`」。
    注意评论里的坑：**不要重复设置 `inputType`**（每次都会 `restartInput()`，Gboard TV 会在每个按键后丢掉高亮）。
- [x] **Q2 实现**：
  - `android/.../TvTextFieldView.kt`（新）：`PlatformViewFactory` + `TvTextFieldView`，内部一个 `EditText`
    （`TYPE_CLASS_TEXT`、`IME_ACTION_SEARCH | IME_FLAG_NO_FULLSCREEN`、单行、透明背景、颜色/字号/hint 由 Dart 传参），
    文字变化 → `onChanged`、回车/搜索键 → `onSubmitted`、D-pad 下/上/左 → `onMoveDown`/`onMoveUp`/`onMoveLeft`（并 `clearFocus()`，
    否则 Android 焦点还留在 EditText 上、Flutter 侧的键盘操作永远收不到键）；Dart → 原生支持 `setText`/`focus`/`blur`。
  - `MainActivity.configureFlutterEngine` 注册工厂；`TvSystemTextField`（Dart，`AndroidView`）负责通道、文本同步
    （只回写 selection，避免每敲一个字光标跳到末尾）、`requestFocus()`/`blur()`。
  - 搜索页：TV + 系统键盘模式 → `TvSystemTextField`（外面套 `Focus(_nativeFieldAnchor, autofocus: true)`，
    让「从结果往上」和「更新提示条还焦点」能回到输入框）；手机/桌面与自绘键盘模式仍用普通 `TextField`。
  - `_leaveSystemField()`：平台视图握着 Android 焦点，Flutter 焦点树里没有「当前节点」，所以先锚定到 Search 按钮再按方向移动。
  - `_showSystemKeyboard()`（v0.1.30 加的 `TextInput.show` 兜底）已删除：系统模式下已经不再有 Flutter 输入连接。
- [x] **Q3 测试**：`test/tv_search_test.dart` 改成「TV 默认渲染 `TvSystemTextField`、没有 `TextField`、没有 `TvKeyboard`」「键盘按钮两种模式来回切」
  「（自绘模式下）左→键盘按钮、右→输入框」。全套 123 个测试通过。
- [ ] **Q4 待用户真机确认**：确认系统键盘能打字后，**删掉整个自绘键盘**（`TvKeyboard` + `TvKeyboardMode` 的 builtin 分支 + 测试 + 搜索框左侧按钮）。

## R. 第十五轮：删掉自绘键盘（系统键盘已在真机确认可用）

- [x] **R1 用户确认**：`能用了` —— v0.1.33 在 Chromecast 上系统键盘（Gboard TV）方向键正常，可以打字、可以搜索。
- [x] **R2 删除范围**：
  - 删掉 `lib/ui/search/tv_keyboard.dart`（整个 Leanback 风格 D-pad 键盘，含 `⇧` 大写锁定与符号层）。
  - 删掉 `preferences_store.dart` 里的 `TvKeyboardMode` / `TvKeyboardModeController` / `tvKeyboardModeProvider` /
    `tv_keyboard_mode` 键（老用户的这个键留在 JSON 里没人读，无害）。
  - 删掉搜索页的：`_keyboardOpen`、`_setKeyboardOpen`、`_builtinKeyboard`、`_keyboardModeFocus` + `_onKeyboardModeKey`
    + `_toggleKeyboardMode`（键盘按钮）、`_append`/`_backspace`/`_caretAtStart`（只为只读字段服务）、
    以及为了收键盘而加的 `PopScope`（现在返回键交给平台：第一次收键盘、第二次退页面）。
  - 平台视图侧删掉 `onMoveLeft`（左边已经没有键盘按钮了；文字里左右键仍然移动光标）。
- [x] **R3 测试**：`test/tv_search_test.dart` 重写为 5 条 —— TV 渲染平台视图输入框（没有 `TextField`）、
  手机/桌面仍是普通可编辑 `TextField`、平台视图的焦点锚点、创建参数带 hint/viewType、手机端 Search 按钮提交查询。
- 历史记录保留在上面（O/P/Q 三节），不再需要的实现细节只在这里标记删除。

## S. 第十六轮：设置页 + 局域网跨设备同步（收藏）

用户需求：① 局域网跨设备（同步收藏 / 同步播放组环绕声）；② 加设置按钮（清除缓存：一键 + 指定专辑；检测更新、更新、**不要弹窗**；关于 + GitHub 链接）。

- [x] **S0 设置按钮放哪**（用户直接问的）：放**搜索页搜索栏最右边**（Search 按钮右边）。理由：应用没有 AppBar/抽屉，
  搜索页是根页面、专辑页是全屏详情，搜索栏是唯一常驻 chrome；齿轮是那一行的最后一站，遥控器一直按右就到。
  有更新时齿轮上出现小红点（不再有横幅）。
- [x] **S1 更新搬进设置、彻底去弹窗**：删掉 `lib/ui/shared/update_banner.dart` 与 `app.dart` 里的挂载点
  （连带 `tv_focus_test.dart` 的两条横幅用例和它的 fake）。启动仍静默检查一次；`UpdateController.check()` 现在会
  记录 `hasChecked`/`checkError`（以前失败是静默吞掉的），设置页里原地显示：正在检查 / 已是最新 / 新版本 + 下载百分比进度条
  / 安装 / 重启并更新（终于用上了原本没有调用者的 `restartAndUpdate()`）/ 失败 + 重试。
  Android 的系统安装界面去不掉（那是系统 UI），其余全无对话框。
- [x] **S2 缓存管理**：`AudioCacheManager` 新增 `listCachedAlbums()`（列目录、读 manifest、算体积与文件数）、
  `deleteCachedAlbum(path)`（按目录删，且拒绝 root 之外的路径）、`readManifestSync`；`CachedAlbum` 模型。
  新增设置页 `缓存` 子页：位置（公开 Music 还是私有）、总占用、**一键清除全部**（含 HTML 页缓存）、
  每张专辑单独删除。`HttpCache` 提成 `httpCacheProvider` 以便清理。
- [x] **S3 关于**：版本号（`appVersionProvider`）+ GitHub 仓库链接（`url_launcher`）。
- [x] **S4 局域网发现**：`lib/data/lan/lan_device.dart` + `lan_service.dart`（纯 `dart:io`，零新依赖）——
  UDP 广播 probe/pong/bye、20 秒过期、手填 IP 单播、每视图 `MethodChannel` 无关的 HTTP 接口 `GET/POST /kh/favorites`、
  `x-khinsider` 头校验、设备 id 随机持久化、设备名默认取主机名或「安卓设备 xxxx」。
- [x] **S5 收藏双向同步**：`FavoritesController.mergeAll()`（并集、只增不删、新在前；state 未加载时从磁盘读，避免覆盖）；
  `LanController` 持有服务与状态（开关、设备列表、忙碌、状态行），`LanScreen`：本机信息、设备列表（展开后
  发送/拉取/移除手动地址）、手动添加、合并安全的说明文字。全部原地显示，无对话框。
- [x] **S6 平台配置**：Android `network_security_config` 打开 `base-config` cleartext（LAN 对端 IP 无法枚举）；
  iOS 加 `NSLocalNetworkUsageDescription`。macOS 的 `network.client/server` 权限本来就有。
- [x] **S7 测试**：`settings_test.dart`（6 条：更新四种状态 + 缓存列表/单删/清除）、`cache_api_test.dart`（7 条，真实临时目录）、
  `lan_test.dart`（8 条：双向同步端到端、回调、403、连不上、包解析、id 格式、并集合并两种情形）、
  `tv_search_test.dart` 增加「搜索栏有设置入口」。全套 **136 个测试通过**。
  坑：widget test 里真实异步 IO 不会推进（FakeAsync），缓存/页缓存的 widget 测试要用 fake 管理器，
  纯行为测试放到 `test(...)` 里用真实临时目录。
- [ ] **S8 同步播放 / 组环绕声**（用户需求 ② 的后半）——下一轮做：主机把播放状态（曲目、位置、播放/暂停、跳转）
  通过 WebSocket 推给跟随设备，跟随端按 RTT 补偿起播，并提供每设备延迟微调（毫秒）用于多音箱对齐。

## T. v0.2.1：反馈修复（用户报的 5 件事）

- [x] **T1 设备列表里的收藏数一直是 0**（bug）：`probe`/`pong` 信标压根没带收藏数量，而 `LanDevice`
  的默认值就是 0，所以「从没说过」和「真的是 0」长得一样。现在两种信标都带 `fav`，`pong` 里的数字是现读的
  （不是缓存值）；`_upsert` 也不会用「没带数字」的 0 覆盖已知数量。顺手修了一个隐藏问题：**没人持续探测时，
  20 秒后设备会全部过期消失** —— 现在设备列表页打开时每 15 秒重新探测一次（`setWatching`），离开就停。
- [x] **T2 刷新按钮消失 + 布局抖动**：`trailing: busy ? null : TextButton(...)` 改成始终存在的
  `TextButton(onPressed: busy ? null : ...)`（变灰禁用），顶部进度条改成固定占位 4px（`SizedBox`），
  缓存页同样处理。
- [x] **T3 缓存页新增「搜索与网页缓存」和「图片缓存」**：总占用现在把两者也算进去（并分行显示明细），
  都可以单独清除；「清除全部」也包含它们。图片缓存走 `flutter_cache_manager`（原本就是传递依赖，现在提到
  直接依赖），清完还会清 Flutter 的解码位图缓存，否则缩略图会继续显示。为此把 `HttpCache` 暴露了
  `directory`，并新增 `imageCacheProvider`（顺带让 widget 测试可以替换掉它 —— path_provider 在测试里不会应答）。
- [x] **T4 Chromecast 更新失败**：原因是 Android 8+ 除了清单里的 `REQUEST_INSTALL_PACKAGES`，还要用户为
  「本应用」打开**安装未知应用**，否则系统安装界面一闪而过、Dart 侧完全看不到原因。新增
  `canInstallPackages` / `openInstallSettings` 两个 channel 方法：设置页会明确说「系统还没有允许本应用安装应用」
  并给出跳转按钮；安装失败不再被当成下载失败（保留安装包、阶段仍是「已下载」，只显示 `installError`），
  重试安装不会重新下载；`ACTION_VIEW` 没有处理器时退回 `ACTION_INSTALL_PACKAGE`；下载前清掉旧的同类型安装包。
  另外设置页现在会显示**要下载的包名**（armv7 的 Chromecast 拿到的是 `-universal.apk` 通用包，包含 armv7 + arm64）。
- [x] **T5 进度条手势**：Android/iOS 上拖动改为**相对位移**（手指按在哪里不重要，按移动的距离调整），
  桌面/遥控仍是绝对定位，点一下仍是绝对跳转；拖动时条自己渲染目标位置，松手才 seek 一次。
- [x] **T6 测试**：`settings_test.dart` 8 条（含「拒绝安装后重试不重新下载」「显示要下载的包名」）、
  `seek_bar_test.dart` 4 条（新增）、`lan_test.dart` 9 条（含信标必须带 `fav`）；全套 **143 个测试通过**。

## U. v0.2.2：Chromecast 装不上（「软件包似乎无效」）

用户反馈：TV 上提示**软件包似乎无效**，问 armv7a 能不能直接装（universal 包）。

先做的排查（结论：**发布出来的 APK 没问题**）：
- 用 App 完全相同的方式（同一个 `browser_download_url` + 同样的 `Accept` 头）下载 universal 包，得到 37,094,963 字节，
  与普通下载 **sha256 完全一致**，`unzip -t` 通过 —— 下载链路本身没问题；
- 包里有 `lib/arm64-v8a`、**`lib/armeabi-v7a`**、`lib/x86_64`，v2/v3 签名块存在（v1 签名文件没有是正常的），
  `AndroidManifest.xml`、`classes.dex` 都在 —— 所以 armv7a **可以**安装（universal 包就是给这种设备用的）；
- `path_provider` 的 `getApplicationSupportDirectory()` 在 Android 上就是 `filesDir`，
  和 `file_paths.xml` 里的 `<files-path path="updates/">` 对得上 —— FileProvider 路径也没有错；
- 结论：问题在设备上那条「把文件交给安装器」的链路上，而那条链路当时**没有任何反馈**。

所以这一版做的是「换掉那条链路 + 让它会说话」：
- [x] **U1 改用 PackageInstaller session**：`MainActivity.startInstallSession()` 把 APK 流写进 session 再 `commit`，
      不经过 content URI；`ACTION_VIEW`/`ACTION_INSTALL_PACKAGE` 保留为兜底（session 抛异常时）。
      注意 `STATUS_PENDING_USER_ACTION` 必须自己 `startActivity(EXTRA_INTENT)`，否则会静默等待。
- [x] **U2 把系统判定报回来**：`BroadcastReceiver` 收 `PackageInstaller.EXTRA_STATUS`，
      经 channel `installResult` 回传，Dart 侧 `InstallResult.explanation` 翻译成中文：
      「签名冲突，需要先卸载旧版本」「存储空间不足」「系统阻止了安装（安装未知应用没允许）」「安装包无效」等。
      这条信息是之前完全拿不到的，下次再失败就能直接看到原因。
- [x] **U3 按 ABI 下更小的包**：新增 `androidAbi` channel 方法读 `applicationInfo.nativeLibraryDir`；
      armv7 设备下 17MB 的 `-armv7.apk`，而不再一律下 37MB 的 universal 包（设置页会显示要下的包名）。
- [x] **U4 下载后先校验**：比对 GitHub API 的 `size` + 检查 ZIP 头（`PK\x03\x04`）；
      不合格就删文件并明确报「下载不完整（x / y MB）」，绝不把坏文件交给安装器。
      下载前清掉同扩展名的旧安装包（`pending` 目录等不碰）。
- [x] **U5 测试**：新增 `update_download_test.dart` 6 条（起本地 HttpServer：完整包通过、短包被拒且删除、
      非压缩包被拒、旧包清理、ABI 选择、安装结果翻译）；全套 **149 个测试通过**。
- [x] **U6 CI 加固**：v0.2.2 的 build-android 因为我加的 `private companion object` 与类里已有的重复而编译失败
  （已合并）；同一轮的 build-linux 是 `media_kit_libs_linux` 的「Integrity check failed, please try to rebuild」
  抖动 —— 给 linux 那步加了一次 `flutter clean` 重试，避免第三方下载抖动把整个 release 卡掉。修复后以 **v0.2.3** 发布
  （v0.2.2 的 tag 没有对应的 release）。

## V. v0.2.4：同步连不上 + 两个强制覆盖选项

用户反馈：① 设备列表里的收藏数量已经对了，但点同步提示「连不上安卓设备」；② 要两个「强制覆盖」版本的同步。

### V1 同步连不上

手头只有「连不上 <设备名>」这一句，看不出原因，所以先把这条链路做成可自证、能自愈的：
- [x] **错误分支不关响应（真 bug）**：`_handleRequest` 只在成功路径写了 body，403/400/404/500
      只设了状态码就 `return` —— 响应永远不 close，客户端只能等到超时，而超时会被报成「连不上」。
      现在每个分支都 `await _writeJson(...)`（它会 `await response.close()`），错误也带 body。
- [x] **失败后单播重探 + 重试一次**：广播能收到但 TCP 连不上，最可能是端口来自更早的 beacon，
      或者电视的无线网卡睡了。`_request()` 先正常请求，失败后向同一地址单播 probe（刷新端口 + 唤醒对方），
      再用新地址重试一次；两次都失败才报错。
- [x] **报错必须带地址和端口**：`连不上 客厅电视（192.168.1.20:41827）：<原因>`，并提示「两台设备要在同一个网络、
      对方应用不能被系统休眠」。设备行里 `port == 0` 时显示「（地址待确认）」。
- [x] **顺手修掉一个真 bug**：`LanScreen.dispose()` 里用了 `ref.read(...)` —— Riverpod 3 在 dispose 时
      直接抛 `StateError`，于是 `setWatching(false)` 和后面的 `_host.dispose()` 全被跳过（离开页面后还在探测）。
      改成在 `initState` 里把 notifier 存到字段。这个是新加的 widget 测试抓到的。

### V2 两个强制覆盖选项

- [x] `mode` 字段：`POST /kh/favorites` 带 `"mode": "replace"` 就**覆盖**接收方的收藏，缺省/未知值一律 merge
      （安全默认：客户端忘了带字段不会把对方清空）；响应多回一个 `replaced`。
- [x] 拉取方向：`pullFavorites(peer, replace: true)` 本地走新的 `FavoritesController.replaceAll`（真删除，按对方的列表覆盖）。
- [x] UI：每个设备展开后从 2 行变 4 行 —— 普通两行加「只增不减」副标题，强制两行用 `danger` 样式，
      **点第一次只是变成确认行**（「再点一次：覆盖 …」，5 秒后自动取消），第二次才真的执行。
- [x] 说明文字改成同时讲清「合并」和「强制覆盖」的区别。
- [x] 测试：**154 个通过**（新增 2 条强制同步端到端 + 3 条 LAN 界面 widget 测试：
      两段确认、普通行仍然只合并、确认会过期）。

## W. 已发布（v0.3.1）：Chromecast 上的聚焦 + 缺下载按钮

用户反馈：① Chromecast 上从专辑曲目列表按左键会聚焦到封面而不是左边的专辑操作区；专辑封面上按向下键
不一定会到 favorite，而是跑到「其他专辑」；② Chromecast 上只有 favorite，没有下载按钮。
（另外用户问为什么跳到 0.3 —— 因为上一轮的强制覆盖是用户可见的新功能就用了 minor；以后一律 patch。）

### W1 专辑页的 D-Pad 走向（`album_screen.dart`）

问题出在「默认几何遍历」上：封面只有 `DpadNav(right: 第一首)`，向下没指定，于是 Flutter 自己找最近的
可聚焦控件，会跳过封面正下方的操作区、落到曲目列表尾部的**相关专辑**上；而曲目列表的 Left 是硬编码到
`coverFocus` 的，普通模式下封面按 Enter 什么都不做（只有 zen 模式才开 OSD 菜单），所以那个方向键等于白按。

- [x] 封面：`DpadNav(right: 第一首, down: 收藏/下载区)`（zen 模式下 down 保持默认 —— 那时信息面板是 `ExcludeFocus` 的）。
- [x] 曲目列表：Left 改成「普通模式到收藏/下载区，zen 模式到封面」（zen 没有信息面板）。
- [x] 操作区：`DpadNav(up: 封面, right: 第一首)`，所以封面仍然按上键可达、不会变成孤岛。
- [x] 新增测试：封面向下 → Favorite（`anyOf('Favorite','In favorites')`）；曲目列表向左 → Favorite，再按上 → 封面。

### W2 TV 上没有下载按钮

不是漏了，是**故意藏起来的**：`_ExportToMusicButton` 第一行就是 `if (isTelevision) return SizedBox.shrink()`，
而宽屏（TV/桌面）布局用的是 `_InfoPanel`，它根本没有第二个按钮 —— 所以电视上永远只有一个 Favorite。
现在：宽屏面板里「收藏」下面加同一个导出/下载按钮，并且 `_ExportToMusicButton` 只按
`supportsPublicMusicFolder`（= 是否 Android）判断，不再看是不是电视。`_CacheFolderHint` 里那个小图标
保持原样（TV 上仍然隐藏），避免同一个动作在一屏出现两次。

- [x] 新增测试：1280×800 + `isTelevision: true` + `isAndroid: true` 时 `Export to Music` 按钮存在。

### TV 上那个「下载」按钮到底是什么

把**已缓存（播放过）**的曲目导出到 `Music/KHInsider`，应用本身只在播放时边播边下（一首预取）。
这里**没有**、也**永远不会有**「一键下载整张专辑」：

> There is no "download this album" button on purpose: khinsider is effectively a public-service
> site, and I do not want to hammer its servers... Please respect the site itself too. — README

用户原话：**「我在 readme 里面也说过永远不要做这个功能」**。这是硬性约束，不是「待用户确认」的候选功能：
以后任何人（包括 AI）都不许再把批量下载当成一个"要不要做"的问题提出来。真正的修复只是把已有的
导出按钮在 TV 布局里显示出来，不涉及任何新的下载行为。

## X. 已发布（v0.3.1）：安装 session 的确认框 + 横向行两端越界

用户反馈：① 安卓更新又坏了，下载完显示「安装取消」；② 收藏行走到最后一张卡再按右键会跳到 recently viewed。

### X1 「安装取消」= STATUS_FAILURE_ABORTED

`STATUS_PENDING_USER_ACTION` 的意思是「会话在等我们弹出系统确认框」，而 `PackageInstaller.EXTRA_INTENT`
这个 extra 的类型变过：**Android 12（API 31）起它是 `PendingIntent`，之前才是 `Intent`**。我们只写了
`getParcelableExtra(EXTRA_INTENT) as? Intent` —— 在电视上（Android 12+）永远取到 null，于是确认框从来不弹，
会话干等到被系统判成 aborted，应用能报的只有「安装被取消」。

- [x] `launchInstallConfirmation()` 同时接受 `PendingIntent`（`send()`）和 `Intent`（`startActivity`）。
- [x] 如果两者都打不开（或抛异常），就 `abandonSession()` 并退回 `installViaIntent()`（content:// + ACTION_VIEW）
      —— 宁可退回老路，也不把用户丢在一个注定 aborted 的会话上。
- [x] 记录进行中的 `pendingSessionId` / `pendingApk`，任何终结状态都清掉。
- [x] status 3 的文案改成「系统的安装确认界面没有完成」并附上系统给的 message，下次再出问题能直接看到原因。
- [x] 把那段 content:// 兜底抽成 `installViaIntent(file): Boolean`，`installApk` 和 receiver 共用。
- 注意：这个修复只有**装上新版本之后**才生效 —— 旧版本（v0.3.0）里的安装逻辑是坏的，所以它没法用应用内更新
  把自己升上来，仍然需要手动装一次。

### X2 横向行两端不该把焦点漏出去

`_AlbumRow`（收藏 / 最近浏览）和相关专辑那一行都是横向 `ListView`/`GridView`，每张卡是一个 `DpadTile`，
没有任何显式的方向邻居，于是默认几何遍历在最后一张卡按右键时「就近」把焦点交给了下一行的卡片。

- [x] `DpadNav` 新增 `stopUp/stopDown/stopLeft/stopRight`：该方向没有显式目标且标了 stop 时，直接
      `KeyEventResult.handled` 把键吃掉（有目标仍然是「跳过去」优先）。
- [x] 收藏/最近浏览行的每张卡包一层 `DpadNav(stopLeft: i == 0, stopRight: i == 最后一页)`；相关专辑同理。
- [x] 新增 `test/dpad_nav_test.dart`：行尾按右键焦点不动；对照组（不带 stop 参数）确认「会漏到下一行」，
      所以这个回归测试抓的确实是那个行为。

## Y. 已发布（v0.3.1）：打开应用/进设置页时键盘自己弹出来

用户反馈：① 默认不要聚焦到输入框，不然默认键盘会弹出来；② 在设置页面键盘也会弹出来，不知道为什么。

### Y1 两个地方都在「创建时主动弹键盘」

- 手机/桌面路径：搜索页的 `TextField` 带着 `autofocus: true` —— 一进应用系统键盘就顶上来。
- TV 路径：`TvTextFieldView.kt` 在创建原生 `EditText` 时自己 `requestFocus()` + `showIme()`，
  注释还写着「就像原生 TV 应用打开搜索框那样」—— 而设置页 → 局域网设备页里那个「手动填地址」的输入框
  用的是同一个原生 view，所以**一进设置页键盘就会弹**，那一页本身根本没有任何 TextField，难怪「不知道为什么」。

- [x] 手机/桌面的搜索框不再 `autofocus`（点一下才输入）。
- [x] 原生 view 创建时**不再**自己聚焦、也不再弹键盘；改成由 Dart 侧显式要求。
- [x] `TvSystemTextField` 新增 `autoFocus`（只聚焦、**不弹键盘**）：平台 view 不是 Flutter 的焦点目标，
      不自己拿焦点遥控器就永远够不到它。搜索页和局域网地址框都用它。
- [x] 键盘只在「用户真的要输入」时出现：遥控器在框里按 **OK**（新增的原生按键分支）、手指点一下、
      或者从结果列表再导航回输入框（第一次自动聚焦是静默的，之后再回来才带键盘）。
- [x] 进设置页之前先 `blur()` 原生框 + `unfocus()` 当前焦点，免得搜索页留下的键盘跟过去。
- [x] 新增测试：手机布局下搜索框 `autofocus` 为 false、且当前焦点不是 `EditableText`。

## Z. 已发布（v0.3.2）：pong 从未被处理 + 安装会话失败后的第二条路

用户反馈：① 安卓上还是「安装被取消」；② 同步时提示「连不上对方的服务端口」。

### Z1 同步：`pong` 包被解析、被回答，然后被丢掉

协议里 `probe` 是「谁在线」，`pong` 是「这是我要约的地址和端口」。发送侧一直是对的
（`beaconPayload('pong')` 有测试覆盖它的字段），但**接收侧只处理 `bye` 和 `probe`** —— `pong`
落到 `if (message['kh'] != 'probe') continue;` 直接被丢掉了。后果：

- `_probeHost()` 等的就是 `deviceStream` 里出现那个 host，而它只在收到 `probe` 时才触发 ——
  所以「手动填地址」基本永远超时（`没有回应`），除非对方恰好在那一刻广播。
- `_request()` 失败后的自愈重试（`_refreshPeer` → `_probeHost`）**从来没有成功过**，于是那条
  「对方在广播里能被看到，但连不上它的服务端口」的文案**无论真实原因是什么都会出现** ——
  用户看到的正是这句。

- [x] `_handleDatagram` 处理 `pong`（当成一次 sighting upsert，且**不回 pong**，否则两端会互刷）。
- [x] 失败文案按异常类型给方向：`refused`（端口上没有服务，对方可能刚重启，端口是每次启动重分配的）
      与 `timed out`（对方防火墙 / 路由器客户端隔离 —— UDP 广播能通、TCP 不通就是这个特征）。
- [x] 新增测试：伪造的 peer 只发一个 `pong` 就能被服务学到（修复前这条测试必失败）。

### Z2 安装：会话路线之外留一条老路

上一轮修的是「确认框不弹」（`EXTRA_INTENT` 在 Android 12+ 是 `PendingIntent`），但用户设备上仍然是
「安装被取消」。协议侧只能再补两件事：

- [x] `launchInstallConfirmation` 也接受 `IntentSender`（个别 ROM 给的是裸 sender）。
- [x] `installApk` 新增 `forceIntent`：跳过 PackageInstaller 会话，直接走 content:// + ACTION_VIEW
      那条独立的老路；设置页在**安装真的失败之后**才多出一行「改用系统安装器」（`installFailed` 标志，
      正常流程/等待确认时不出现）。
- [x] 顺带说明：从 v0.3.0 及更早版本点「更新」必然还是「安装被取消」—— 装的是旧逻辑，
      修不了自己，必须先手动装一次。

## AA. 未发布（v0.3.3）：让应用自己说清「连不上」到底是哪一半

用户第二次反馈「同步还是说连不上」，但没给完整文案 —— 与其再问第三遍，不如把诊断做进应用里。

- [x] 新增 `LanService.diagnose()` + 设备展开后的一行 **「测试连接」**：先做一次 UDP 地址探测，再请求
      `GET /kh/info`，然后明确说是哪一半坏了（探测没回应 / 探测有回应但 API 连不上 / 都正常），
      文案里直接给出对应的排查方向（防火墙、路由器客户端隔离、对方应用被挂起）。
- [x] **端口未知就先解析再同步**：`_request` 在 `peer.port == 0` 时先探测拿新端口 —— 以前会直接去连
      `http://host:0`，秒失败，然后被当成网络问题报出来（手动填的地址、以及不广播端口的旧版本都会命中）。
- [x] 同步页底部显示 **本机地址：ip:端口**，两台设备对上即可确认在同一网段。
- [x] 「对方没有回应 TCP」的文案补上最可能的原因：**对方的应用已经不在前台**（被系统挂起），
      其次才是防火墙/AP 隔离。
- [x] 新增测试：`describe()` 三种结论的措辞；伪造 peer 只发 pong 时 `diagnose` 应报告
      `udp=true, tcp=false`（修复前后都成立，但这是新 API 的契约）。

### 仍然无法从代码里解释的部分

客户端和服务端两边都读过：服务端 `HttpServer.bind(anyIPv4, 0)` + 端口随 beacon/pong 广播，客户端请求带
鉴权头、5 秒超时、失败后重探再试一次。剩下的可能只有环境（AP 隔离/防火墙）或者设备上跑的不是带修复的
版本 —— 后者最可能，因为安卓的安装一直是坏的，用户很可能根本没装上 v0.3.2。所以这一轮的重点是让
**应用自己给出结论**，而不是继续猜。

