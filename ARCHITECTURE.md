# 架构总览

> 本文档描述 KHInsider 客户端的整体设计。分层规则：**上层可以依赖下层，下层永不依赖上层**。

## 目录结构

```
lib/
├── main.dart                  # 启动：媒体会话初始化 + provider overrides
├── app.dart                   # 根 Widget：主题、路由表、GlobalMediaKeys
│
├── core/                      # 与业务无关的基建（可独立复用）
│   ├── theme.dart             #   主题：种子色列表 + 暗色主题
│   ├── widgets/
│   │   ├── dpad_tile.dart     #   D-Pad 可聚焦瓦片（高亮/辉光，hover 聚焦）
│   │   └── seek_bar.dart      #   进度条（点击跳转 + 焦点态左右键 ±10s）
│   └── keyboard/
│       └── global_media_keys.dart  # 全局媒体键（最低优先级监听）
│
├── data/                      # 数据层（纯逻辑，无 UI 依赖）
│   ├── khinsider_client.dart  #   API client provider（dio+缓存）
│   └── storage/
│   │   └── json_kv_store.dart #   JSON 文件 KV 存储（原子写/防抖落盘）
│   └── preferences_store.dart #   KV 存储 provider + 收藏/历史/最近浏览
│
│   （khinsider_api 包里另有 `image_urls.dart`：封面多档尺寸的 URL 改写，
│     页面只给 60×60/117×117，`KhinsiderImage.large` 取 200×200）
│
├── audio/                     # 播放抽象与实现
│   ├── base_audio_player.dart #   播放器接口（Switch 移植预留通道）+ 系统命令回调 / 媒体会话接口
│   ├── just_audio_player_impl.dart  # just_audio 实现（LockCaching 边播边缓存）
│   ├── audio_service_handler.dart   # audio_service 媒体会话桥接（只发布+收命令，不播放）
│   └── audio_cache_manager.dart     # 音频文件缓存管理
│
├── state/                     # Riverpod 控制器（唯一的 UI ↔ 数据桥梁）
│   ├── search_controller.dart #   搜索（含 forceRefresh）
│   ├── album_controller.dart  #   专辑详情（(id, refreshNonce) family）
│   ├── player_controller.dart #   播放队列/两阶段惰性加载/取消/音质/映射
│   ├── track_cache_controller.dart # 每首曲目的缓存状态（磁盘扫描）
│   ├── theme_controller.dart  #   主题种子色（持久化）
│   └── update_controller.dart #   更新检查 / 下载→提取→就绪
│
└── ui/                        # 视图，按功能域分文件夹
    ├── search/search_screen.dart
    ├── album/                 #   专辑页 + 曲目列表（含缓存徽标）+ 相关专辑（飞离动画）
    ├── now_playing/           #   全屏播放：屏幕 / 封面动画 / 曲目列表 / OSD 菜单
    └── shared/update_banner.dart #   顶部更新提示吧（挂在 MaterialApp.builder）
```

## 数据流（两阶段惰性加载）

```
UI (曲目行 / 卡片)
   │  playAlbum(album, i) / search(q) / getAlbum(id)
   ▼
Riverpod Controller ──── Phase 1: 1 次 HTML（搜索页 / 专辑页，磁盘缓存优先）
   │                      Phase 2: 仅点击/预取时解析直链（dio CancelToken 可取消）
   ▼
BaseAudioPlayer ◄──── 仅实现替换即可移植（Switch 预留）
   ▼
just_audio (LockCachingAudioSource: 边下边播, 断点续传)
```

## 关键设计决策

| 决策 | 原因 |
|---|---|
| `khinsider_api` 独立包、零 Flutter 依赖 | 数据层可在 CLI / 测试 / 嵌入式复用 |
| 专辑页缓存优先 + 显式刷新按钮 | 页面秒开；站点数据基本静态 |
| 曲目直链永不缓存 | CDN token 会轮换 |
| 队列索引 → 专辑序号映射表 | 惰性队列只有已解析曲目，impl 索引 ≠ 专辑索引 |
| PlayerBar 挂 `Scaffold.bottomNavigationBar` | 与路由同 FocusScope，D-Pad 方向键可达 |
| 全屏播放时 `descendantsAreFocusable: false` | OSD 菜单模态化，焦点无法逃逸到背景列表 |
| 点击/悬停同时 `requestFocus()` | 鼠标/键盘行为一致（否则 Enter 永远激活 autofocus 行） |
| 页面级 `Focus(autofocus: true)` 兜底 | 什么都不聚焦时按键从 route 的 focus scope 冒泡，页面内的 `onKeyEvent` 收不到；本节点持有焦点才能接住 Esc |
| 缓存状态同步扫描（stat） | 每行 1–2 次 stat，不等 event loop，UI 不会卡；下载期间才用 1.2s 定时器轮询 |
| 媒体键挂在 root 最低优先级 | 任意页面全局生效，且不与深层快捷键冲突 |
| 系统媒体命令（通知栏/锁屏/耳机键）经 `SystemMediaCommandHandler` 回到 `PlayerController` | 队列只有「当前 + 预取的下一首」，系统按下一首时若预取还没完成，直接透传给 impl 就是静默 no-op；走 controller 才能按需解析下一首 |
| 媒体会话（`KhinsiderAudioHandler`）**不是** `BaseAudioPlayer`，播放一律走 `audioPlayerProvider` | 会话的 `play/pause/stop` 是**系统**入口，内部会转交回 `PlayerController`；若 controller 又拿同一个对象播放，`pause()` → `handler.pause()` → `controller.pause()` 会无限同步递归（实测把 isolate 卡死，而通知栏进度条因为系统自行推算仍在走，看起来「还在播」）。所以两件事拆成两个真实对象：`BaseAudioPlayer`（播放，`audioPlayerProvider`）与 `MediaSession`（接收系统命令 + `endSession()`，`mediaSessionProvider`） |
| Android `androidStopForegroundOnPause: false` | 设为 `true` 时暂停会退出前台服务，之后在后台按通知栏的播放/暂停/下一首需要重新 `startForegroundService`，Android 12+ 会抛 `ForegroundServiceStartNotAllowedException` → 系统控件看起来「点不动」。保持前台可完全绕开（`androidNotificationOngoing` 因此必须为 `false`，两者互斥）；代价是老版本 Android 上通知不可划掉，所以 controls 里补了一个 `MediaControl.stop`（只在展开视图显示）作为结束会话的出口 |
| `PlaybackState` 带 `queueIndex` / `androidCompactActionIndices` / `MediaItem.duration` | 通知栏紧凑视图顺序稳定；有 duration 才有进度条（锁屏进度也依赖它） |
| **播放中绝不上报 `buffering`** | SystemUI 的播放/暂停图标只看 `state == STATE_PLAYING`（AOSP `MediaControlPanel.isPlaying`），而 `buffering` 会映射成 `STATE_BUFFERING` → 图标变回「播放三角」：明明在响，通知栏却没有暂停按钮（曲目刚起播、或播放中重新缓冲时最容易撞上）。所以 `processing` 只在 `playing == false`（首次加载、或用户已暂停的卡顿）时才报 `buffering`，播放中一律 `ready` |
| 手机的进度跳转做在「当前播放行」上，而且**松手才 seek** | 手机窄屏布局没有播放器 UI（OSD 菜单只在 zen/宽屏出现），能显示进度的只有当前行的背景填充，所以在它上面挂横向拖动是最小改动：只有「手机 + 当前行 + 时长已知」才挂手势，轻点仍由 `DpadTile` 的 tap 处理（手势竞技场按移动距离分流），宽屏 TV/桌面一行代码都没变。松手才提交一次 seek 是关键：音频经 `LockCachingAudioSource` 播放，其本地代理对已缓存区间直接读文件（瞬时），对未下载到的位置必须等顺序下载追上，逐帧 seek 会让播放器卡在手指后面；拖动期间界面用本地 scrub 值渲染，不理会 player 的 tick |
| seek 后立刻 force-publish 媒体会话（并识别位置跳变） | 位置发布有 1s 节流（防止 60Hz tick 刷爆 platform channel），可跳转是一次性大跳，节流会让通知栏/锁屏的进度条慢半拍。所以：位置单次变化 > 2s 视为 seek 立即发布；`seek()` 先写 `_lastPosition` 再发布、然后才 `await` 播放器，否则系统滑块会在播放器反应过来之前弹回旧位置 |
| 通知栏按钮图标必须放在 **app 模块**（`res/drawable/khinsider_*.xml`），且 release 关掉资源压缩 | 这是「通知栏一个按钮都没有」的真正根因。Flutter 的 Gradle 插件对 release 默认开 `isMinifyEnabled = true` + `isShrinkResources = true`（`FlutterPlugin.kt:217`），于是 R8 的资源压缩把**只按名字引用**的 drawable 当无用资源删掉 —— `MediaControl.androidIcon` 正是运行时按名字解析的（`AudioService.getResourceId` → `Resources.getIdentifier`），静态分析看不到。实测：v0.1.21 的 APK 里 `resources.arsc` 有 app 自己的资源名（`launch_background` 等）也有 androidx 的（`accessibility_custom_action_*`、`notification_background`），但**没有任何 `audio_service_*`**，`res/` 只剩 8 个文件；v0.1.20（还是 pub 上的插件）完全一样 —— 所以从第一轮反馈起就存在。`getResourceId` 于是返回 0，通知 action 的 icon 为 null，而 SystemUI 会把这种 action 直接丢掉（`MediaDataManager.createActionsFromNotification`: `if (action.getIcon() == null) { …; continue }`）→ 卡片上封面/标题/进度条都在（进度条来自 metadata 的 duration），**按钮一个都没有**。修法：5 个图标做成 app 模块里的矢量图（app 自己的资源一定进包），`KhinsiderAudioHandler` 用 `MediaControl(androidIcon: 'drawable/khinsider_*')`，再从 `values/media_action_icons.xml` 的 array + `MainActivity` 的 `R.array` 引用一次、`res/raw/keep.xml` 的 `tools:keep` 兜底，并把 release 的 `isShrinkResources` 显式设为 `false`（实测 `res/` 从 8 个文件回到 104 个，arm64 APK 只大 0.15 MB）。回归测试逐条断言每个 `androidIcon` 都能在 app 模块找到对应文件且出现在 keep 列表里 |
| 折叠展开态的通知栏按钮靠 `EXTRA_COMPACT_ACTIONS`（因此 vendored 了 audio_service） | 次要保险（真正根因见上一行）。SystemUI 画按钮有两条路径：**语义 actions**（`MediaDataManager.createActionsFromState()` 从 `PlaybackState.actions` 推导）与**通知 actions**（回落路径，折叠卡片是否显示由 `setGenericButton(..., showInCompact)` 决定，而 `showInCompact` 来自 `notif.extras.getIntArray(EXTRA_COMPACT_ACTIONS)`）。这个 extra 只有 `MediaStyle.setShowActionsInCompactView()` 会写，而 audio_service 0.18.19（pub 上最新版）只在 `SDK_INT < 33` 时调用它。修法：仓库内 vendored 一份 0.18.19（`packages/audio_service`，`dependency_overrides` 指过去），无条件调用它并按实际 action 数量裁剪下标（框架对越界下标会抛 `IllegalArgumentException`）。语义路径上多写一个 extra 无副作用，所以两条路径都安全 |
| Android 缓存目录：公开 `Music/` 需要「所有文件访问」，没授权就退回私有目录 | Android 11+ 的分区存储下，未授权写入 `Music/` 要么失败、要么被重定向到看不到的地方，所以`AudioCacheManager` 先问 `AndroidStorage`（`MainActivity` 的 `dev.khinsider/storage` channel）：`Environment.isExternalStorageManager()` 为真才把 root 定为 `Music/KHInsider`，否则仍是应用 documents 目录（功能不受影响，只是文件不好找）。授权是**系统设置页里的开关**而不是运行时弹窗，所以 UI 只做「解释 + 跳转」（首次启动问一次 + 专辑页缓存行里的按钮），并用 `forgetRoot()` 让下次写入重新解析 root —— 不需要重启，已下载的文件留在旧目录。桌面/TV 宽屏布局不出现这个入口 |
| 位置更新按 1s 节流后再 publish | 系统用 `updatePosition + updateTime` 自行推算进度，逐 tick 上报只会刷爆 method channel |
| 封面统一用 `thumbs_large`（200×200） | 页面只会给最小的那档：搜索结果 `thumbs_small` 60×60、专辑页 `/thumbs/` 117×117，画到 140–200px 卡片和 252px 封面上明显发虚。站点把同一张图预渲染了多档，**只有目录段不同**，改一下路径就能取 200×200（~15–80KB），不用额外请求；原图则可能到 10MB（3000×3000 PNG），绝不能进列表。见 `KhinsiderImage`，模型上统一暴露 `imageUrl` |
| 触摸/鼠标/键盘的反馈按 `FocusManager.highlightMode` 分流 | 手指不会 hover，而点击后留在方块上的焦点环会被当成「选中」，还清不掉。`touch` 模式（手机/平板，或桌面没接鼠标）不画焦点环与悬停底色，改用水波纹；`traditional`（键盘/遥控/鼠标）行为完全不变。跟 Flutter 自己的 Material 组件同一条规则 |
| 水波纹手绘在内容**之上**的透明 `Material` 里 | Material 的 ink 画在它包裹的 child **下面**（`_RenderInkFeatures.paint`），直接套 `InkWell` 会被不透明的卡片/封面盖住。所以墨层是 `Stack` 的最后一个孩子并套 `IgnorePointer`（不能抢走方块内部控件的手势），ink feature 由 `_handleTapDown/Up/Cancel` 手动驱动；离开屏幕时在 `deactivate` 里 dispose（`dispose` 时机太晚，Material 已经先被卸载 → ticker 泄漏） |
| 播放走完一张专辑时**默认循环**（回到第一首）| `just_audio` 的队列播完只会 `pause()`，`PlayerController.next()` 到末尾也是直接 return，所以「默认循环播放」要自己实现：`completed` 快照 → `_loopAlbum()` 重新 `playAlbum(album, startIndex: 0)`；在最后一首按下一首走同一条路。`_looping` 防重入，`next()` 里是 `unawaited`（通知栏要立刻响应）。没有单独的循环开关：目前是「永远循环」 |
| 遥控器的返回键 = 系统 pop，不是 key event | `_onBack()` 只能收到 Esc / 手柄 B；Android TV 的返回键走 `Navigator.maybePop`，会把专辑路由直接丢回搜索页。所以专辑页套了 `PopScope(canPop: !zen && !menuOpen)`：OSD → 禅模式 → 专辑页 → 搜索页，一次退一级；真的离开专辑时（含系统返回）调用 `_releaseAlbumPlayback()` —— 宽屏 `stop()`（专辑页就是播放器 UI），窄屏 `pause()`（手机有迷你可视化条） |
| 更新提示条：TV 上**自己接管焦点** | 提示条的按钮彼此用 `DpadNav` 串好了，但**没有任何路径能把焦点移进来** —— App 里的页面都是按区域导航（`skipTraversal` 容器 + 显式 `DpadNav`），Flutter 的几何遍历从搜索框/曲目根本走不到顶部这一行，所以用户在 Chromecast 上「看得到更新按钮却选不中」。现在 TV 上提示条一出现就自己 `requestFocus()`（记住原来焦点的 `FocusNode`），按「下」或关掉提示条会把焦点还回去；下载开始后进度也用 `DpadTile` 占住同一个位置，不然圆环会随着阶段切换消失、遥控器就再也够不到 View/关闭了。包外层是 `Focus(canRequestFocus: false, skipTraversal: true)`，否则几何遍历会停在这个容器节点上（正是最初那个「选不中」的bug） |
| TV 输入法：**平台 EditText（平台视图）** | Google TV / Chromecast 上，Flutter 的 `TextField` 唤起系统键盘后 **D-pad 永远进不了键盘**：方向键继续在输入框里移动光标，一个字都打不出来。这是 Flutter 引擎 `InputConnectionAdaptor` 的问题（flutter/flutter#177360、#154924、#125541 —— 官方在 #154924 里曾以 WAI 关掉，但 2026-07 有人在真机 Google TV 上复现出关键结论：**同一个 Gboard TV，只要焦点编辑器是原生 `EditText`（平台视图）就完全可以用方向键选字母**，所以问题在 Flutter 提供的 `InputConnection`/`EditorInfo`，不在平台）。因此 TV 的搜索框是 `TvSystemTextField`（`AndroidView` + `android/.../TvTextFieldView.kt` 里的原生 `EditText`，工厂在 `MainActivity.configureFlutterEngine` 注册）：Flutter 画框和布局，`EditText` 拥有 IME。文字/事件走每个视图一条 `MethodChannel`；离开输入框的方向（下→结果、左→键盘切换按钮、上→更新提示条）由原生回调送回 Dart，因为平台视图自己握着焦点。`TvKeyboard`（自绘键盘）降级为后备开关。**坑**：`inputType` 只能设置一次 —— 重新赋值会触发 `restartInput()`，Gboard TV 每敲一个字就丢掉高亮 |
| 播放时不让电视休眠：`FLAG_KEEP_SCREEN_ON`（只在播放中）| Android TV / Google TV 屏幕空闲到系统超时会进 ambient mode，再往下是待机，待机直接掐掉音频输出 —— 表现就是「Chromecast 放着放着自己停了」。播放本身不会因为 CPU 睡眠而卡住：`audio_service` 在 `enterPlayingState()` 里已经拿了 `PARTIAL_WAKE_LOCK`。所以补的是屏幕这一层：`KeepScreenAwake`（`lib/core/widgets/keep_screen_awake.dart`）在 `app.dart` 根部跟随 `playerControllerProvider.playing`，通过 `dev.khinsider/platform` 的 `setKeepScreenOn` 让 `MainActivity` 加/清 `FLAG_KEEP_SCREEN_ON`；暂停和播完就放开，退到后台时该 flag 自动失效 |
| 焦点走位：**区域之间显式指定，区域内部交给默认遍历**；容器节点永不参与遍历 | 方向键默认走 Flutter 的 `DirectionalFocusIntent`，它是按几何坐标找邻居的，在真实 TV 上会把焦点送到**淡出/飞到屏幕外/铺满整屏但不画东西**的容器节点上 —— 表现就是「焦点环消失、遥控器像坏了」（实测从封面按右会落在 `album-page` 容器上）。所以：① 容器 `Focus` 一律 `skipTraversal: true`（显式 `requestFocus`/autofocus 仍有效）；② 淡出的区域（禅模式的 header、飞走的 info panel、飞走的 related 行）用 `ExcludeFocus` —— `IgnorePointer` 只挡指针不挡焦点；③ 区域之间的走位用 `DpadNav` 写明（`lib/core/widgets/dpad_nav.dart`：`DpadNav(right: firstRowFocus)`），没写的方向才交还默认遍历。TV 键盘更进一步，自己持有每个键的 `FocusNode` 并按网格算走位（`TvKeyboard`） |
| TV 布局用**自绘键盘**，绝不碰系统 IME；方向键由键盘自己算，不交给 Flutter 的焦点遍历 | Android TV 的系统键盘是**另一个窗口**，遥控器的「下」本该把焦点交给它，但这个按键会先被 Flutter 消费：`WidgetsApp` 的默认快捷键把方向键绑成 `DirectionalFocusIntent`（`app.dart:1281`）、`DefaultTextEditingShortcuts` 又绑成移动光标，两者都在应用内消化，按键到不了 Android 的窗口管理器 —— 于是「键盘弹出来但按不下去」是必然的；而「第二次进搜索页键盘不出来」同源：系统 IME 只在字段**获得焦点的瞬间**请求一次，字段一直有焦点就不会重现。所以 TV 上搜索框是 `readOnly`（不请求 IME、`autofocus: false`），输入交给 `TvKeyboard`（`lib/ui/search/tv_keyboard.dart`：`DpadTile` 网格，外层 `Focus.onKeyEvent` 让物理键盘照样能打字），Enter/Select 打开、Back(`PopScope`) 先收键盘、提交后自动收起。键盘**自己持有每个键的 `FocusNode`（`skipTraversal: true`）并在 `onKeyEvent` 里处理四个方向键**（行内左右 clamp、跨行保留列号），因为 Flutter 的 `DirectionalFocusTraversalPolicy` 是按几何走的：在真实 TV 窗口尺寸（1920×1080 @ density 2 = 960×540 逻辑像素）下字母行内往右会失效，`t` 右边的键完全选不到（Chromecast 实测）。键盘收起时焦点显式还给搜索框（Hide/Back 走这条；字段本身处理 Enter 重开、可打印字符与退格），而 Android 上 `readOnly` 的 `EditableText` 不会创建 input connection（`_shouldCreateInputConnection` 对 Android + readOnly 为 false），所以把焦点给字段不会勾出系统 IME；提交那条不抢焦点，仍由结果列表 autofocus；键盘 `initState` 的 post-frame 显式 `requestFocus` 第一个键（`autofocus` 只对新建节点生效，重开键盘时不触发）。`isTelevision` 由 `dev.khinsider/platform` 提供，并在**第一帧之前**于 `main.dart` 解析后覆盖 `isTelevisionProvider`（否则 TV 上会先闪一次系统键盘）。手机/桌面完全不变 |

| 「导出到 Music」走 MediaStore 贡献，不申请权限；导出流程放在**独立页面**里 | Android 10+ 应用可以**免权限**往 `MediaStore.Audio` 插入自己的音频（`RELATIVE_PATH = Music/KHInsider/<专辑>` + `IS_PENDING=1`，写完置 0），Android 11+ 还能改/删自己的贡献；只有写普通文件才需要「所有文件访问」。所以导出是**复制**（播放/缓存路径一行不动），命中同名文件就跳过（按 `DISPLAY_NAME` 查再比路径，避开各版本 `RELATIVE_PATH` 尾斜杠差异），≤Android 9 报 `unsupported`（那时缓存本来就在公开目录）。进度与结果放在 `ExportAlbumScreen`（自带 `Scaffold`）而不是专辑页的对话框里：往 `album_screen.dart` 加对话框代码会让 arm64 macOS 的 `gen_snapshot` 崩掉（`Class with illegal cid, full-aot`，详见 TODO I3），而且专辑页没有 `Scaffold`、SnackBar 在那里本来也不会显示 |

## 焦点与快捷键

| 场景 | 按键 | 行为 |
|---|---|---|
| 任意页面 | MediaPlayPause / MediaTrackNext / MediaTrackPrevious / MediaStop | 全局播放控制（stop 真正清空队列） |
| 任意页面 | Esc（页面没处理时） | 返回上一层（`GlobalMediaKeys` 兜底） |
| 进入专辑页 | — | 默认焦点落在第一首，**不会自动播放** |
| 专辑页曲目行 | 鼠标 hover | 高亮 + 把键盘焦点移到该行 |
| 专辑页曲目行 | 手指点击 | 水波纹反馈 + 播放；**不画焦点环**（焦点仍然跟随，之后接上键盘就从这一行继续） |
| 专辑页曲目行 | ↑↓ 移动焦点 / Enter·Space 激活 | 播放该曲目并进入全屏 |
| 全屏播放 | OK(Enter/点击封面) | 开关 OSD 菜单（焦点困在菜单内） |
| 全屏播放 | Esc / 手柄 B | 菜单开→关菜单；菜单关→退回专辑页 |
| OSD 菜单 | ↑↓←→ 导航 / Enter 激活 | 进度、播放、音质 MP3/FLAC、主题 6 色 |
| 进度条聚焦 | ←→ | ±10s 快进快退（不移动焦点） |
| 未播放行 | 数字序号 → 点击 | 播放；转圈时点击 = 取消加载 |

## 响应式布局（窄屏 = 手机 / 宽屏 = TV·桌面，断点 700）

| 页面 | 窄屏（≤700） | 宽屏（>700） |
|---|---|---|
| 搜索 | 搜索栏固定在**底部**（键盘弹起时跟随上移），结果网格 `reverse: true` 从下往上排，第一条结果紧贴搜索框 | 搜索栏在顶部，结果从上往下 |
| 专辑 | 封面 + 标题 + 曲目数 + 收藏按钮 + 「Album details」（折叠）作为**列表的表头**，与曲目在同一个 `ListView` 里滚动（不做嵌套滚动）；不进入 zen 全屏形态，点当前行=暂停/继续 | 左侧信息面板 + 封面，右侧曲目列表，可 morph 进 zen |

* 收藏按钮 = `DpadTile` 包裹一个 `IgnorePointer` 的 `FilledButton`：触摸点按与遥控器 OK
  走同一条路径（`DpadTile.onSelect`），按钮本身不吃事件，因此不会触发两次。
* 专辑信息用 `AlbumTrackList.header` 塞进曲目列表，而不是外面再套一层滚动视图 ——
  否则两个 `ListView` 会互相抢滚动，且 `shrinkWrap` 列表本来就会构建全部子项。

## 状态一览

| Provider | 类型 | 持久化 |
|---|---|---|
| `searchControllerProvider` | Notifier → SearchState | —（搜索词缓存到页面缓存） |
| `albumDetailProvider` | FutureProvider.family<(id, nonce)> | 页面磁盘缓存 |
| `playerControllerProvider` | Notifier → PlayerState | — |
| `favoritesProvider` / `recentAlbumsProvider` / `searchHistoryProvider` | AsyncNotifier | JSON KV |
| `themeControllerProvider` | AsyncNotifier<int> | JSON KV |
| `fullscreenProvider` | Notifier<bool> | — |
| `albumCacheProvider` | Notifier.autoDispose → AlbumCacheState | —（随专辑页销毁） |
| `audioCacheManagerProvider` | Provider<AudioCacheManager> | —（写 Music 目录） |
| `jsonKvStoreProvider` | FutureProvider<JsonKvStore> | — |

## 缓存层次

| 层 | 内容 | 策略 | 位置 |
|---|---|---|---|
| 页面缓存 | 搜索/专辑页 HTML | 永久 + 显式刷新按钮绕过 | `api_cache/` |
| 曲目页缓存 | 单曲页 HTML（直链解析） | TTL 30 分钟（CDN token 会轮换） | `api_cache/` |
| 音频缓存 | 播放中的曲目 | LockCaching 边下边播，断点续传 | `Music/KHInsider/<专辑>/mp3\|flac` |
| 封面/清单 | 封面图（200×200 `thumbs_large`）+ album.json | 开始播放时写入 | `Music/KHInsider/<专辑>/image\|other` |
| 预加载 | 下一首（仅一首） | 播放稳定后解析直链 + 后台下载 | 同音频缓存 |

### 音频缓存：直接落在系统 Music 文件夹，用户可以自己用

```text
<Music>/KHInsider/<专辑名>/
   mp3/    01 曲目名.mp3
   flac/   01 曲目名.flac
   image/  cover.jpg
   other/  album.json + 非 mp3/flac 的媒体
```

* 目标是**缓存 = 用户能找到的文件**：文件名是曲目序号 + 标题（不是哈希），
  用户可以自己删除、复制、或用别的播放器直接播放。
* 文件名由 `曲目序号 + 标题` 推出（`AudioCacheManager.trackFileName`），所以
  专辑页**不用解析直链**就能判断每首曲目的缓存状态（同步 stat，无网络请求）。
* `.part` = 下载中，完成后 just_audio rename 成正式文件；`.mime` 是它的副产品。
* 位置：macOS `~/Music`、Windows `%USERPROFILE%\Music`、Linux `XDG_MUSIC_DIR`
  （回退 `~/Music`）；Android/iOS 不能直接写设备 Music，用应用文档目录。
  目录不可写时回退 `Application Support/KHInsider`，绝不影响播放。
* 页面缓存仍在 `Application Support/api_cache/`（HTML 不适合给用户看）。
* `HttpCache.clear()` 与 `AudioCacheManager.clear()/totalSize()/deleteAlbum()` 预留设置页入口。
* 首次播放一张新专辑的速度下限 = 网络 RTT（曲目页 + CDN 起播缓冲），之后同专辑内所有操作都是即时的
