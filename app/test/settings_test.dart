import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/audio/audio_cache_manager.dart';
import 'package:khinsider/core/platform/device.dart';
import 'package:khinsider/data/image_cache.dart';
import 'package:khinsider/data/khinsider_client.dart';
import 'package:khinsider/data/update_service.dart';
import 'package:khinsider/state/track_cache_controller.dart';
import 'package:khinsider/state/update_controller.dart';
import 'package:khinsider/ui/settings/cache_screen.dart';
import 'package:khinsider/ui/settings/settings_screen.dart';
import 'package:khinsider_api/khinsider_api.dart';

/// Never touches the network: fills the state the test wants and counts what
/// the UI asked for.
class FakeUpdateController extends UpdateController {
  FakeUpdateController(this.initial);

  final UpdateState initial;
  int checks = 0;
  int downloads = 0;
  int restarts = 0;
  int installs = 0;
  int installSettingsOpened = 0;

  @override
  UpdateState build() => initial;

  @override
  Future<void> check() async => checks++;

  @override
  Future<void> download() async => downloads++;

  @override
  Future<void> restartAndUpdate() async => restarts++;

  @override
  Future<void> revealDownload() async => installs++;

  @override
  Future<void> openInstallSettings() async => installSettingsOpened++;
}

/// One asset per platform, so the row under test exists whichever OS runs the
/// suite (the CI matrix runs it on Linux).
const _assets = [
  UpdateAsset(name: 'khinsider-9.9.9-universal.apk', url: 'https://x/a.apk'),
  UpdateAsset(name: 'khinsider-9.9.9-macos.zip', url: 'https://x/m.zip'),
  UpdateAsset(
    name: 'khinsider-9.9.9.steamdeck.flatpak',
    url: 'https://x/f.flatpak',
  ),
  UpdateAsset(name: 'khinsider-9.9.9-windows.zip', url: 'https://x/w.zip'),
];

void main() {
  setUp(() {
    // The cache screen asks path_provider where the thumbnail cache lives. An
    // unmocked platform channel never answers, which would hang the load.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  Future<FakeUpdateController> pump(
    WidgetTester tester, {
    required UpdateState state,
    Widget home = const SettingsScreen(),
    AudioCacheManager? cache,
    HttpCache? pageCache,
    ImageCacheStore? images,
    bool tv = false,
    Size size = const Size(460, 1700),
  }) async {
    tester.view.physicalSize = tv ? const Size(1920, 1080) : size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = FakeUpdateController(state);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateControllerProvider.overrideWith(() => fake),
          appVersionProvider.overrideWith((ref) async => '0.2.0'),
          isTelevisionProvider.overrideWithValue(tv),
          if (cache != null) audioCacheManagerProvider.overrideWithValue(cache),
          if (pageCache != null) httpCacheProvider.overrideWithValue(pageCache),
          if (images != null) imageCacheProvider.overrideWithValue(images),
        ],
        child: MaterialApp(home: home),
      ),
    );
    await tester.pump();
    return fake;
  }

  group('settings > update', () {
    testWidgets('offers the download and runs it in place', (tester) async {
      final fake = await pump(
        tester,
        state: const UpdateState(
          available: UpdateInfo(
            version: '9.9.9',
            url: 'https://example.com/release',
            notes: 'Fixes things\nmore text',
            assets: _assets,
          ),
        ),
      );

      expect(find.text('新版本 v9.9.9'), findsOneWidget);
      expect(find.text('Fixes things'), findsOneWidget);
      await tester.tap(find.text('下载并安装'));
      await tester.pump();

      expect(fake.downloads, 1, reason: 'no confirmation, no popup');
      expect(tester.takeException(), isNull);
    });

    testWidgets('reports an up-to-date result instead of staying silent', (
      tester,
    ) async {
      await pump(tester, state: const UpdateState(hasChecked: true));

      expect(find.text('已是最新版本'), findsOneWidget);
    });

    testWidgets('shows a failed check and can retry it', (tester) async {
      final fake = await pump(
        tester,
        state: const UpdateState(hasChecked: true, checkError: '检查更新失败：网络不可用'),
      );

      expect(find.text('检查更新失败：网络不可用'), findsOneWidget);
      await tester.tap(find.text('检查更新'));
      await tester.pump();

      expect(fake.checks, 1);
    });

    testWidgets('names the asset it is about to download', (tester) async {
      await pump(
        tester,
        state: const UpdateState(
          available: UpdateInfo(
            version: '9.9.9',
            url: 'https://x',
            assets: _assets,
          ),
        ),
      );

      // "Which package is it downloading?" is a fair question on a TV, and the
      // answer differs per platform, so ask the picker that decides.
      final expected = UpdateService(
        repoSlug: 'trdthg/khinsiderTV',
      ).assetForPlatform(_assets)!.name;
      expect(find.textContaining(expected), findsWidgets);
    });

    testWidgets('a refused install is offered again, not re-downloaded', (
      tester,
    ) async {
      final fake = await pump(
        tester,
        state: const UpdateState(
          available: UpdateInfo(
            version: '9.9.9',
            url: 'https://x',
            assets: _assets,
          ),
          downloadPhase: UpdateDownloadPhase.downloaded,
          downloadedFile: '/tmp/khinsider-9.9.9-universal.apk',
          installError: '系统还没有允许本应用安装应用，请先打开这个开关',
          installNeedsPermission: true,
        ),
      );

      expect(find.text('重试安装'), findsOneWidget);
      expect(find.textContaining('系统还没有允许'), findsOneWidget);
      await tester.tap(find.text('重试安装'));
      await tester.pump();
      expect(fake.installs, 1);
      expect(fake.downloads, 0, reason: 'the APK is already on disk');

      await tester.tap(find.text('去允许安装未知应用'));
      await tester.pump();
      expect(fake.installSettingsOpened, 1);
    });

    testWidgets('shows a restart for a downloaded desktop update', (
      tester,
    ) async {
      final fake = await pump(
        tester,
        state: const UpdateState(
          available: UpdateInfo(
            version: '9.9.9',
            url: 'https://x',
            assets: _assets,
          ),
          downloadPhase: UpdateDownloadPhase.ready,
        ),
      );

      expect(find.text('重启并更新'), findsOneWidget);
      await tester.tap(find.text('重启并更新'));
      await tester.pump();

      expect(fake.restarts, 1);
    });
  });

  group('settings > cache', () {
    testWidgets('lists cached albums with sizes, and deletes one of them', (
      tester,
    ) async {
      final cache = FakeCacheManager([
        const CachedAlbum(
          id: 'a1',
          title: 'Album One',
          path: '/cache/Album One',
          bytes: 4096,
          tracks: 2,
        ),
        const CachedAlbum(
          id: 'a2',
          title: 'Album Two',
          path: '/cache/Album Two',
          bytes: 8192,
          tracks: 3,
        ),
      ]);

      await pump(
        tester,
        state: const UpdateState(),
        home: const CacheScreen(),
        cache: cache,
        pageCache: FakePageCache(),
        images: FakeImageCache(),
        size: const Size(460, 2600),
      );

      expect(find.text('Album One'), findsOneWidget);
      expect(find.text('Album Two'), findsOneWidget);
      // The row joins the parts, so match inside the subtitle.
      expect(find.textContaining('4 KB'), findsOneWidget);
      expect(find.textContaining('8 KB'), findsOneWidget);

      await tester.tap(find.byTooltip('删除《Album One》的缓存'));
      await tester.pump();
      await tester.pump();

      expect(cache.deleted, ['/cache/Album One']);
      expect(find.text('Album One'), findsNothing);
      expect(find.text('Album Two'), findsOneWidget);
      expect(find.textContaining('已删除'), findsOneWidget);
    });

    testWidgets('clears everything in one tap', (tester) async {
      final cache = FakeCacheManager([
        const CachedAlbum(
          id: 'a1',
          title: 'Album One',
          path: '/cache/Album One',
          bytes: 4096,
          tracks: 2,
        ),
      ]);

      await pump(
        tester,
        state: const UpdateState(),
        home: const CacheScreen(),
        cache: cache,
        pageCache: FakePageCache(),
        images: FakeImageCache(),
        size: const Size(460, 2600),
      );

      await tester.tap(find.text('清除全部缓存'));
      await tester.pump();
      await tester.pump();

      expect(cache.cleared, 1);
      expect(find.text('还没有缓存任何专辑'), findsWidgets);
      expect(find.textContaining('已清除 4 KB'), findsOneWidget);
    });
  });
}

/// Cache manager with the disk replaced by a list: the real one is covered by
/// `cache_api_test.dart`, and real async IO cannot make progress inside a
/// widget test without `runAsync`.
/// Nothing on disk: the page cache's real `clear()` awaits `Directory.exists`,
/// which never finishes inside a widget test's fake async zone.
class FakePageCache extends HttpCache {
  FakePageCache() : super(() async => Directory('/tmp/kh-pages-unused'));

  int cleared = 0;

  @override
  Future<Directory> get directory async => Directory('/tmp/kh-pages-unused');

  @override
  Future<void> clear() async => cleared++;
}

/// A thumbnail cache with no disk behind it.
class FakeImageCache extends ImageCacheStore {
  FakeImageCache() : super();

  int cleared = 0;

  @override
  Future<Directory> directory() async => Directory('/tmp/kh-images-unused');

  @override
  Future<void> clear() async => cleared++;
}

class FakeCacheManager extends AudioCacheManager {
  FakeCacheManager(this._albums);

  List<CachedAlbum> _albums;
  final List<String> deleted = [];
  int cleared = 0;

  @override
  Future<List<CachedAlbum>> listCachedAlbums() async => _albums;

  @override
  Future<String> get displayRoot async => '/cache';

  @override
  Future<bool> get isUsingPublicMusicFolder async => false;

  @override
  Future<void> deleteCachedAlbum(String path) async {
    deleted.add(path);
    _albums = _albums.where((a) => a.path != path).toList();
  }

  @override
  Future<void> clear() async {
    cleared++;
    _albums = const [];
  }
}
