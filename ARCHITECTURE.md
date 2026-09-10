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
│   │   ├── dpad_tile.dart     #   D-Pad 可聚焦瓦片（高亮边框/辉光，无缩放）
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
├── audio/                     # 播放抽象与实现
│   ├── base_audio_player.dart #   播放器接口（Switch 移植预留通道）
│   ├── just_audio_player_impl.dart  # just_audio 实现（LockCaching 边播边缓存）
│   ├── audio_service_handler.dart   # audio_service 媒体会话桥接
│   └── audio_cache_manager.dart     # 音频文件缓存管理
│
├── state/                     # Riverpod 控制器（唯一的 UI ↔ 数据桥梁）
│   ├── search_controller.dart #   搜索（含 forceRefresh）
│   ├── album_controller.dart  #   专辑详情（(id, refreshNonce) family）
│   ├── player_controller.dart #   播放队列/两阶段惰性加载/取消/音质/映射
│   ├── theme_controller.dart  #   主题种子色（持久化）
│   └── ui_state.dart          #   全屏模式标志
│
└── ui/                        # 视图，按功能域分文件夹
    ├── search/search_screen.dart
    ├── album/                 #   专辑页 + 元数据面板 + 相关专辑（双行）
    ├── now_playing/           #   全屏播放：屏幕 / 封面动画 / 曲目列表 / OSD 菜单
    └── shared/player_bar.dart #   底部播放条（Scaffold.bottomNavigationBar）
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
| 点击同时 `requestFocus()` | 鼠标/键盘行为一致（否则 Enter 永远激活 autofocus 行） |
| 媒体键挂在 root 最低优先级 | 任意页面全局生效，且不与深层快捷键冲突 |

## 焦点与快捷键

| 场景 | 按键 | 行为 |
|---|---|---|
| 任意页面 | MediaPlayPause / MediaTrackNext / MediaTrackPrevious | 全局播放控制 |
| 专辑页曲目行 | ↑↓ 移动焦点 / Enter·Space 激活 | 播放该曲目并进入全屏 |
| 全屏播放 | OK(Enter/点击封面) | 开关 OSD 菜单（焦点困在菜单内） |
| 全屏播放 | Esc / 手柄 B | 菜单开→关菜单；菜单关→退回专辑页 |
| OSD 菜单 | ↑↓←→ 导航 / Enter 激活 | 进度、播放、音质 MP3/FLAC、主题 6 色 |
| 进度条聚焦 | ←→ | ±10s 快进快退（不移动焦点） |
| 未播放行 | 数字序号 → 点击 | 播放；转圈时点击 = 取消加载 |

## 状态一览

| Provider | 类型 | 持久化 |
|---|---|---|
| `searchControllerProvider` | Notifier → SearchState | —（搜索词缓存到页面缓存） |
| `albumDetailProvider` | FutureProvider.family<(id, nonce)> | 页面磁盘缓存 |
| `playerControllerProvider` | Notifier → PlayerState | — |
| `favoritesProvider` / `recentAlbumsProvider` / `searchHistoryProvider` | AsyncNotifier | JSON KV |
| `themeControllerProvider` | AsyncNotifier<int> | JSON KV |
| `fullscreenProvider` | Notifier<bool> | — |
| `jsonKvStoreProvider` | FutureProvider<JsonKvStore> | — |

## 缓存层次

| 层 | 内容 | 策略 | 位置 |
|---|---|---|---|
| 页面缓存 | 搜索/专辑页 HTML | 永久 + 显式刷新按钮绕过 | `api_cache/` |
| 曲目页缓存 | 单曲页 HTML（直链解析） | TTL 30 分钟（CDN token 会轮换） | `api_cache/` |
| 音频缓存 | 播放中的曲目 | LockCaching 边下边播，断点续传 | `audio_cache/` |
| 预加载 | 下一首（仅一首） | 播放稳定后解析直链 + 后台下载 | `audio_cache/` |

* 位置：`Application Support/`
* `HttpCache.clear()` 与 `AudioCacheManager.clear()/totalSize()` 预留设置页入口
* 首次播放一张新专辑的速度下限 = 网络 RTT（曲目页 + CDN 起播缓冲），之后同专辑内所有操作都是即时的
