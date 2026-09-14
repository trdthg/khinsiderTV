import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/data/lan/lan_device.dart';
import 'package:khinsider/state/lan_controller.dart';
import 'package:khinsider/ui/settings/lan_screen.dart';

/// The forced (overwrite) sync is the only destructive thing this app can do to
/// a favorites list, so the two-tap confirmation is worth a test of its own.
class _FakeLanController extends LanController {
  final calls = <String>[];

  static const device = LanDevice(
    id: 'peer-1',
    name: '客厅电视',
    host: '192.168.1.20',
    port: 41827,
    version: '0.2.3',
    favorites: 12,
  );

  @override
  Future<LanState> build() async => const LanState(
    deviceId: 'me',
    name: '手机',
    devices: [device],
    status: '发现 1 台设备',
  );

  @override
  Future<void> setWatching(bool watching) async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> pushFavorites(LanDevice device, {bool replace = false}) async {
    calls.add(replace ? 'push-replace' : 'push');
  }

  @override
  Future<void> pullFavorites(LanDevice device, {bool replace = false}) async {
    calls.add(replace ? 'pull-replace' : 'pull');
  }
}

void main() {
  late _FakeLanController controller;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lanControllerProvider.overrideWith(() {
            controller = _FakeLanController();
            return controller;
          }),
        ],
        child: const MaterialApp(home: LanScreen()),
      ),
    );
    await tester.pump();
    // Open the device row.
    await tester.tap(find.text('客厅电视'));
    await tester.pumpAndSettle();
  }

  testWidgets('a forced overwrite needs a second tap', (tester) async {
    await pump(tester);

    expect(find.text('强制：用本机收藏覆盖 客厅电视'), findsOneWidget);
    expect(find.text('强制：用 客厅电视 的收藏覆盖本机'), findsOneWidget);

    await tester.tap(find.text('强制：用本机收藏覆盖 客厅电视'));
    await tester.pumpAndSettle();

    // First tap only arms it.
    expect(controller.calls, isEmpty);
    expect(find.text('再点一次：覆盖 客厅电视 的收藏'), findsOneWidget);
    expect(find.text('强制：用 客厅电视 的收藏覆盖本机'), findsOneWidget);

    await tester.tap(find.text('再点一次：覆盖 客厅电视 的收藏'));
    await tester.pumpAndSettle();

    expect(controller.calls, ['push-replace']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the ordinary rows still merge', (tester) async {
    await pump(tester);

    await tester.tap(find.text('把本机收藏发送到 客厅电视'));
    await tester.pumpAndSettle();
    expect(controller.calls, ['push']);
  });

  testWidgets('an armed confirmation expires on its own', (tester) async {
    await pump(tester);

    await tester.tap(find.text('强制：用 客厅电视 的收藏覆盖本机'));
    await tester.pump();
    expect(find.text('再点一次：覆盖本机的收藏'), findsOneWidget);

    // Five seconds is the whole window; after that a stray tap cannot delete
    // anything.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('强制：用 客厅电视 的收藏覆盖本机'), findsOneWidget);
    expect(controller.calls, isEmpty);
  });
}
