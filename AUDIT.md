# 代码审计报告（Code Audit）

> 对当前工作区的完整审计。结论分两句说：**架构是干净的，但实现里的 bug 一点也不少**，
> 而且有几个是会在真机上崩掉 / 卡死的硬伤。下文所有问题都已修复，并附回归测试。

---

## 一、结论：结构干准还是混乱？

**分层本身是干净的，而且比多数同规模项目规范。**

| 维度 | 评价 |
|---|---|
| 分层（ui → state → data/audio → api package） | ✅ 干净，方向单一，没有上层反渗 |
| `khinsider_api` 独立化、零 Flutter 依赖 | ✅ 很好，可用于 CLI / 嵌入式 |
| 接口抽象（`BaseAudioPlayer`） | ✅ 播放器可替换，UI 不知道具体实现 |
| 文件粒度（最大 429 行，按功能域分目录） | ✅ 正常 |
| 命名 / 注释 / `dart analyze` | ✅ 无 lint 告警 |
| 仓库卫生（`.gitignore` / 无垃圾文件被追踪） | ✅ 正常 |

但是 **“干净” 只是形状上的干净**，实现层有大量逻辑缺陷，而且有几处结构性的烂摊子：

### 结构上的真正问题

1. **`lib/ui/album/album_screen.dart` 曾经处于不能编译的状态**（括号不平衡，
   `flutter analyze` 报出多个 `expected_token` / `missing_identifier`）。同时它还把曲目列表
   的渲染逻辑复制了一份进来（私有 `_TrackListPane`），导致 `album_track_list.dart`
   和 `related_albums.dart` 变成死代码，且丢失了 “People who also viewed” 推荐功能 ——
   已恢复到引用共享组件的版本。
2. **同一份队列状态有三个互相不同步的镜像**：
   `PlayerState.entries/_albumIndexOfQueue`、`JustAudioPlayerImpl._items`、
   `KhinsiderAudioHandler._queueItems`。只要有一个地方在 `await` 之前就加写，
   索引就永远错位（已修）。
3. **`copyWith` 里 `error: error` / `currentIndex: currentIndex ?? this.x` 这种写法无法表达 “清空”**，
   是好几个 bug 的共同根源（已用 sentinel 统一修复）。
4. `ARCHITECTURE.md` 仍在描述已经被删掉的 `state/ui_state.dart` 和 `ui/shared/player_bar.dart`，
   文档与代码脱节。

---

## 二、已修复的 Bug（按严重性）

### 🔴 严重（崩溃 / 卡死 / 安娨）

| # | 位置 | 问题 | 修复 |
|---|---|---|---|
| 1 | `data/update_service.dart` `extractPendingUpdate` | **Zip Slip**：压缩包条目名未做任何净化就拼进路径，`../` 可以写到解压目录之外（已用单元编程验证：成功覆盖了 `pending` 上一级的文件）。更新包来自远端，这是真实的任意写文件漏洞 | 新增 `_safeEntryName()`，拒绝 `..`、绝对路径与空名；`extractPendingUpdate` 改为可注入 `root` 以便测试 |
| 2 | `data/update_service.dart` macOS 分支 | `while (!cur.path.endsWith('.app')) cur = cur.parent;` 在二进制不在 `.app` 里时 `Directory('/').parent` 是 `/` 自身 → **启动时死循环**（`applyPendingUpdate` 在 `runApp` 之前 `await`，表现为永远 黑屏）。另 `firstWhere` 无 `orElse` 会抛 `StateError` | 新增 `_macOSAppBundle()`，到根即返回 null；找不到 bundle 就放弃本次自更新 |
| 3 | `packages/.../parsers.dart` `parseSearchResults` | `row.querySelectorAll('td')[1]` 在行里只有一个 `<td>` 时抛 **RangeError** → 一行异常的搜索结果让整个搜索页崩掉（已用测试复现） | 取 cells 前判空，改为带索引保护的回退 |
| 4 | `data/storage/json_kv_store.dart` `_flush()` | **防抖与写盘并发竞争**：写入发生在某次 flush 进行中时，计时器重新启动第二个 flush，两个 flush 同时写同一个 `.tmp` → `rename` 抛 `PathNotFoundException`（已复现），且是 **未被 await 的异步异常**，还可能丢最新值 | flush 通过 `Future` 链接串行化，整个 `_flush()` 包在 `try/catch` 里 |
| 5 | `data/storage/json_kv_store.dart` `read<T>` | `as T?` 在存储类型不匹鍍时抛 `TypeError`（已复现），会把 `themeControllerProvider` 弄成永久 error 状态 | 改为 `value is T` 判断，不匹鍍视为缺失 |
| 6 | `audio/just_audio_player_impl.dart` `stop()` | `AudioPlayer.stop()` **只停止不清空队列**，但代码把 `_items` 清了 → `queueLength` 与 `_items` 分叉，之后每次 `append()` 都落在错的索引上，连带搞坏 `swapCurrentSource` 和 Now-Playing 元数据 | `stop()` 改为 `stop()` + `clearAudioSources()`，并推送一条 “空” 快照 |
| 7 | `lib/ui/album/album_screen.dart` | 文件本身语法错误，无法编译 | 恢复到引用共享组件的版本 |

### 🟠 功能性（功能不工作 / 行为错误）

| # | 位置 | 问题 | 修复 |
|---|---|---|---|
| 8 | `state/player_controller.dart` `playAlbum` | `state = const PlayerState(...)` 把用户在 OSD 菜单选的 **音质选择重置成 MP3** | 显式保留 `preferredFormat` |
| 9 | `state/player_controller.dart` `setPreferredFormat` | `urlFor(FLAC)` 有 `?? mp3Url` 回退，所以 **没有 FLAC 也能 “切换成功”**：UI 显示 FLAC、实际播 MP3（已用测试复现）。另外在 swap 前就改状态，失败时不回滚 | 新增 `urlForExact()` 供切换器使用；成功后再提交状态 |
| 10 | `state/player_controller.dart` snapshot 监听 | impl 报告 `currentIndex: null` 时，`copyWith` 的 `??` 会保留旧值 → **停止播放后旧曲目行仍被高亮**（已复现） | `copyWith` 改用 sentinel，显式 `null` 才清空 |
| 11 | `core/keyboard/global_media_keys.dart` | `MediaStop` 被绑到 `togglePlayPause()`，**整个应用没有任何地方可以真正 stop**（已用测试复现） | 绑到新增的 `PlayerController.stop()`；`ref.read` → `ref.watch` |
| 12 | `core/widgets/seek_bar.dart` | `_maxMs` 把时长 clamp 到最小 1ms，所以 **缓冲中（时长未知）时进度条直接显示为满格**，且点击会 seek 到 `0..1` 的毫秒 | 时长未知返回 null → 进度显示 0，拒络 seek；抽出 `_seekBy()` |
| 13 | `state/update_controller.dart` | `downloadedFile` **永远不被赋值** → `revealDownload()` 是死代码，“在文件管理器中显示” 永远无反应 | 把 `extractPendingUpdate` 的结果写进状态 |
| 14 | `state/update_controller.dart` | `retryDownload()` 传 `errorMessage: null` 想清掉错误，但 `copyWith` 的 `??` 保留了旧值 → **重试后屏幕上还挂着上一次的错误**（已复现） | `UpdateState.copyWith` 改用 sentinel |
| 15 | `state/search_controller.dart` | 无请求版本号，慢的旧请求会**覆盖较新的搜索结果**（已用可控时序的测试复现） | 新增 `_generation` 计数器，迟到的回复直接丢弃 |
| 16 | `state/player_controller.dart` `build()` | `ref.onDispose(p.dispose)` **会把 `main()` 里 override 进来的应用级播放器 dispose 掉**；此外 `listen()` 返回的订阅永远不取消 | 只取消自己的订阅，不动外部持有的播放器 |
| 17 | `lib/ui/album/album_screen.dart` | `BackButton(onPressed: () {})` → **返回键点了没反应** | `Navigator.maybePop(context)` |
| 18 | `lib/ui/album/album_screen.dart` `_ensureRowFocusNodes` | 在 `build()` 里 dispose 仍然被上一帧引用（可能还持有焦点）的 FocusNode → 曲目数变化时抛 “used after being disposed” | 改为复用旧节点 + post-frame 退役多余节点 |

### 🟡 次要（资源 / 健壮性）

| # | 位置 | 问题 | 修复 |
|---|---|---|---|
| 19 | `audio/audio_service_handler.dart` | 构造 函数里的 `listen()` 永远不取消 → 泄漏；`_queueItems` 在 `await` 前就写，inner 失败就分叉；`stop()` 后 `mediaItem` 不清 | 取消订阅、成功后写镜像、`stop()` 清 `mediaItem` |
| 20 | `audio/just_audio_player_impl.dart` | `playerStateStream` 与 `currentIndexStream` 两个监听器重复推冲突的快照；`_items` 在 `await _sourceFor` 之前就被覆盖 | 合并成单一 `_pushSnapshot()`；创建 source 成功后再改 `_items`，append 失败回滚 |
| 21 | `audio/just_audio_player_impl.dart` | 队列操作无 序列化；`dispose()` 可重复 | `_serialize()` 串行化；`_disposed` 哨兵 |
| 22 | `data/preferences_store.dart` | `albumSummaryFromJson` 直接 `as String`，文件中一条记录损坏就让 favorites/recents provider 永久 error | 新增 `tryAlbumSummaryFromJson`，坏记录跳过 |
| 23 | `state/update_controller.dart` | 自己拼 `${base}/updates`，与 `updatesDirectory()` 重复；`PackageInfo.fromPlatform()` 写法绕；提取中可重复 | 统一用 `updatesDirectory()`；加 `extracting` 防重复 |
| 24 | `data/update_service.dart` | `0.1.4-rc1` 的 `rc1` 经 `int.tryParse ?? 0` 静默变成 0，版本比较可能反转 | `_parseVersion()` 分离 core / `-pre` / `+build` |

---

## 三、验证方式

每一个严重 / 功能性问题都补写了可复现的断言，再修：

```sh
# pure-Dart 数据层（14 个测试）
cd packages/khinsider_api && dart test

# Flutter 应用（32 个测试，含新增回归测试）
cd app && flutter analyze && flutter test
```

新增回归测试：

| 文件 | 覆盖 |
|---|---|
| `app/test/data_layer_regression_test.dart` | KV store 类型容忍 / 写盘串行化 / close 语义；Zip Slip 三种攻击载荷均被拒绝 + 正常压缩包 不受影响 |
| `app/test/state_regression_test.dart` | `copyWith` 可清空；stop 清索引；换专辑不丢音质；无 FLAC 不假切换；MediaStop 真 stop；搜索乱序；SeekBar 未知时长 |
| `app/test/album_screen_regression_test.dart` | 返回键真的可以 pop；曲目数减少不再 dispose 活的 FocusNode |
| `packages/khinsider_api/test/parsers_test.dart` | 残缺表格 不再抛 RangeError，且正常行仍被解析 |

---

## 四、未修（记录在案，非本次范畴）

- `audio_cache_manager.dart` 没有上限与淘汰策略，磁盘占用 无限增长；`totalSize()` 不递归。
- `albumDetailProvider` 的 `(id, nonce)` family：每次刷新都产生新 provider，旧项永远不被回收。
- `HttpCache` / `KhinsiderClient` 在强制刷新网络失败时不会回退到过期缓存。
- `parseTrackPage` 全页扫描 `a[href]`，可能抓到无关的 `.mp3` 链接。
