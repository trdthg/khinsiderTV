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
- [ ] **I2 用 MediaStore 免权限写 `Music/`（替代「所有文件访问」）—— 待定方案**
      事实核对：Android 10+ 应用**不需要任何权限**就能往 `MediaStore.Audio` 插入自己的音频
      （`RELATIVE_PATH = Music/KHInsider` + `IS_PENDING`），Android 11+ 还能改/删自己的贡献；
      读回自己插入的文件同样不需要权限（**重装后**那些文件算「别人的」，那时才需要
      `READ_MEDIA_AUDIO`（13+）/`READ_EXTERNAL_STORAGE`（≤12））。
      但当前实现不是换个 API 就行：
      * 下载是 just_audio 的 `LockCachingAudioSource` 干的，它要一个**文件路径**做
        `cacheFile`（`just_audio_player_impl.dart` 的 `_sourceFor`），MediaStore 只给
        `content://`，没有路径；
      * `AudioCacheManager` 整层是路径式 API（`root()` 返回 `Directory`、
        `fileFor/fileForSync/categoryDirSync`、`totalSize` 遍历、专辑清单与封面写文件），
        要换成 URI 得重写这一层和所有调用点；
      * 播放侧可行：just_audio 用 ExoPlayer 的 `DefaultDataSource`（`AudioPlayer.java:749`），
        支持 `content://` —— 但没有设备可验证 seek / 缓存交互 / 重名改名 / 重装归属。
      可选方案（按工作量与风险）：
      * **A. 导出**：缓存仍在私有目录，用户对一个专辑点「导出到 Music」时写进 MediaStore
        （复制 → 双份空间；或播放结束后移动 → 单份但要处理「正在播的文件被搬走」）；
        播放路径零改动，风险最低。
      * **B. 重写缓存层**：自己下载直接落 MediaStore，播放改用 `content://`，
        缓存徽标/清单/FLAC/迁移全跟着改；最"正确"、单份空间，但没有设备可验证，风险最高。
      * **C. 保持现状**（「所有文件访问」+ 路径式缓存）：能用、零风险，但要用户在系统设置里
        开一个比较吓人的开关。
      待用户选 A / B / C 后再实现。
