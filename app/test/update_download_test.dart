import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/data/update_service.dart';

/// The download path, against a local HTTP server: this is where a truncated
/// response used to reach the system installer, which then only said "this
/// package appears to be invalid".
void main() {
  late HttpServer server;
  late String base;
  late Directory saveDir;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    saveDir = Directory.systemTemp.createTempSync('kh-update-dl');
    // One canned response per path.
    final bodies = <String, List<int>>{
      '/apk': [0x50, 0x4b, 0x03, 0x04, ...List<int>.filled(2048, 7)],
      '/truncated': [0x50, 0x4b, 0x03, 0x04, ...List<int>.filled(16, 7)],
      '/html': utf8.encode('<html>rate limited</html>'),
    };
    server.listen((request) async {
      final body = bodies[request.uri.path];
      if (body == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.headers.contentLength = body.length;
        request.response.add(body);
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (saveDir.existsSync()) saveDir.deleteSync(recursive: true);
  });

  UpdateService service() => UpdateService(repoSlug: 'trdthg/khinsiderTV');

  test('accepts a complete package and reports its size', () async {
    final asset = UpdateAsset(
      name: 'khinsider-9.9.9-armv7.apk',
      url: '$base/apk',
      size: 2052,
    );

    final file = await service().downloadAsset(asset, saveDir: saveDir);

    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), 2052);
  });

  test('rejects a short download instead of installing it', () async {
    final asset = UpdateAsset(
      name: 'khinsider-9.9.9-armv7.apk',
      url: '$base/truncated',
      size: 37094963,
    );

    await expectLater(
      service().downloadAsset(asset, saveDir: saveDir),
      throwsA(
        isA<LanFreeUpdateException>().having(
          (e) => e.message,
          'message',
          contains('下载不完整'),
        ),
      ),
    );
    // The bad file must not be left behind for the next attempt to pick up.
    expect(
      File(
        '${saveDir.path}${Platform.pathSeparator}khinsider-9.9.9-armv7.apk',
      ).existsSync(),
      isFalse,
    );
  });

  test('rejects a response that is not an archive at all', () async {
    const html = '<html>rate limited</html>';
    final asset = UpdateAsset(
      name: 'khinsider-9.9.9-armv7.apk',
      url: '$base/html',
      // The size matches, so this exercises the "not an archive" branch
      // rather than the truncation one.
      size: utf8.encode(html).length,
    );

    await expectLater(
      service().downloadAsset(asset, saveDir: saveDir),
      throwsA(
        isA<LanFreeUpdateException>().having(
          (e) => e.message,
          'message',
          contains('不是安装包'),
        ),
      ),
    );
  });

  test(
    'an older installer of the same kind is replaced, not accumulated',
    () async {
      for (final name in [
        'khinsider-1.0.0-armv7.apk',
        'khinsider-1.1.0-armv7.apk',
      ]) {
        File(
          '${saveDir.path}${Platform.pathSeparator}$name',
        ).writeAsBytesSync(List<int>.filled(8, 1));
      }
      // Unrelated files (the unpacked desktop update, other formats) stay.
      Directory('${saveDir.path}${Platform.pathSeparator}pending').createSync();
      File(
        '${saveDir.path}${Platform.pathSeparator}khinsider-1.1.0-macos.zip',
      ).writeAsBytesSync(List<int>.filled(8, 1));

      await service().downloadAsset(
        UpdateAsset(
          name: 'khinsider-2.0.0-armv7.apk',
          url: '$base/apk',
          size: 2052,
        ),
        saveDir: saveDir,
      );

      final left =
          saveDir
              .listSync()
              .map((e) => e.path.split(Platform.pathSeparator).last)
              .toList()
            ..sort();
      expect(left, [
        'khinsider-1.1.0-macos.zip',
        'khinsider-2.0.0-armv7.apk',
        'pending',
      ]);
    },
  );

  group('asset picking', () {
    const assets = [
      UpdateAsset(name: 'khinsider-9.9.9-armv7.apk', url: 'u'),
      UpdateAsset(name: 'khinsider-9.9.9-arm64.apk', url: 'u'),
      UpdateAsset(name: 'khinsider-9.9.9-universal.apk', url: 'u'),
      UpdateAsset(name: 'khinsider-9.9.9-macos.zip', url: 'u'),
      UpdateAsset(name: 'khinsider-9.9.9-steamdeck.flatpak', url: 'u'),
    ];

    test('Android takes the build for its own ABI, not the fat one', () {
      // The platform gate cannot be faked on a desktop test host, so the
      // Android pick is a static helper the test can call directly.
      expect(
        UpdateService.pickAndroidAsset(assets, 'armv7')!.name,
        'khinsider-9.9.9-armv7.apk',
      );
      expect(
        UpdateService.pickAndroidAsset(assets, 'arm64')!.name,
        'khinsider-9.9.9-arm64.apk',
      );
      expect(
        UpdateService.pickAndroidAsset(assets, 'x86_64'),
        isNull,
        reason: 'no x86 build in the release: fall back to universal',
      );
    });

    test('the installer verdict explains itself', () {
      String explain(int status, [String? message]) =>
          InstallResult(status, message).explanation;

      expect(explain(-1), contains('确认'));
      expect(explain(0), '安装完成');
      expect(explain(1, 'boom'), contains('boom'));
      expect(explain(2), contains('安装未知应用'));
      expect(explain(3), contains('取消'));
      expect(explain(4), contains('不完整'));
      expect(explain(5), contains('签名'));
      expect(explain(6), contains('存储空间'));
      expect(explain(7), contains('不兼容'));
      expect(explain(99), contains('99'));
      expect(InstallResult(0, null).succeeded, isTrue);
      expect(InstallResult(2, null).blocked, isTrue);
    });
  });
}
