import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/data/storage/json_kv_store.dart';
import 'package:khinsider/data/update_service.dart';

void main() {
  group('JsonKvStore', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('kvtest'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('read<T> returns null for an incompatible stored type', () async {
      File(
        '${dir.path}${Platform.pathSeparator}khinsider_store.json',
      ).writeAsStringSync(jsonEncode({'k': '2'}));
      final store = await JsonKvStore.open(dir);
      // A legacy/mismatched type must read as "absent", not throw.
      expect(store.read<int>('k'), isNull);
      expect(store.read<String>('k'), '2');
      expect(store.read<int>('missing'), isNull);
    });

    test('write then read round-trips', () async {
      final store = await JsonKvStore.open(dir);
      store.write('theme_seed', 3);
      expect(store.read<int>('theme_seed'), 3);
      await store.close();
    });

    test('close() persists pending debounced writes', () async {
      final store = await JsonKvStore.open(dir);
      store.write('a', 1);
      store.write('b', 2); // still inside the 400ms debounce window
      await store.close();
      final reopened = await JsonKvStore.open(dir);
      expect(reopened.read<int>('a'), 1);
      expect(reopened.read<int>('b'), 2);
    });

    test('writes after close() are ignored (no resurrection)', () async {
      final store = await JsonKvStore.open(dir);
      await store.close();
      store.write('late', 'value');
      await Future<void>.delayed(const Duration(milliseconds: 450));
      final reopened = await JsonKvStore.open(dir);
      expect(reopened.read<String>('late'), isNull);
    });

    test(
      'a write during an in-flight flush does not throw or lose data',
      () async {
        final store = await JsonKvStore.open(dir);
        store.write('first', 'one');
        // Let the debounce fire, then write again while the flush is running so
        // two flushes would overlap on the same .tmp file if unserialised.
        await Future<void>.delayed(const Duration(milliseconds: 420));
        store.write('second', 'two');
        await store.close();
        final reopened = await JsonKvStore.open(dir);
        expect(reopened.read<String>('first'), 'one');
        expect(reopened.read<String>('second'), 'two');
      },
    );
  });

  group('extractPendingUpdate (Zip Slip guard)', () {
    late Directory root;
    late File marker;

    setUp(() {
      root = Directory.systemTemp.createTempSync('updatetest');
      marker = File('${root.path}${Platform.pathSeparator}marker.txt');
    });
    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    /// Builds a zip whose single entry escapes the extraction directory.
    List<int> evilZip(String entryName, List<int> content) {
      final archive = Archive();
      archive.add(ArchiveFile(entryName, content.length, content));
      return ZipEncoder().encode(archive);
    }

    test('a ../ entry cannot write outside the extraction directory', () async {
      marker.writeAsStringSync('original');
      File(
        '${root.path}${Platform.pathSeparator}evil.zip',
      ).writeAsBytesSync(evilZip('../marker.txt', utf8.encode('PWNED')));

      await extractPendingUpdate(root: root);

      // The marker (one level above pending/) must be untouched.
      expect(marker.readAsStringSync(), 'original');
      // Nothing but the (now consumed) archive location may exist next to
      // the extraction directory - the escaped payload was dropped.
      expect(
        File(
          '${root.path}${Platform.pathSeparator}pending'
          '${Platform.pathSeparator}marker.txt',
        ).existsSync(),
        isFalse,
      );
    });

    test('a deeply nested ../ traversal is rejected', () async {
      File(
        '${root.path}${Platform.pathSeparator}evil.zip',
      ).writeAsBytesSync(evilZip('a/../../evil.txt', utf8.encode('x')));
      await extractPendingUpdate(root: root);
      expect(
        root
            .listSync(recursive: true)
            .whereType<File>()
            .any((f) => f.path.endsWith('evil.txt')),
        isFalse,
      );
    });

    test('an absolute entry path is rejected', () async {
      File(
        '${root.path}${Platform.pathSeparator}evil.zip',
      ).writeAsBytesSync(evilZip('/etc/evil.txt', utf8.encode('x')));
      await extractPendingUpdate(root: root);
      expect(
        File('${Directory.systemTemp.path}/etc/evil.txt').existsSync(),
        isFalse,
      );
    });

    test(
      'benign entries (including nested dirs) are extracted normally',
      () async {
        final archive = Archive();
        archive.add(ArchiveFile('bundle.app/Contents/app.bin', 3, [1, 2, 3]));
        archive.add(ArchiveFile('bundle.app/Info.plist', 3, [4, 5, 6]));
        File(
          '${root.path}${Platform.pathSeparator}ok.zip',
        ).writeAsBytesSync(ZipEncoder().encode(archive));

        final pending = await extractPendingUpdate(root: root);

        final extracted = pending;
        expect(extracted, isNotNull);
        expect(
          extracted!.listSync(recursive: true).whereType<File>().length,
          2,
        );
        expect(
          File(
            '${extracted.path}${Platform.pathSeparator}bundle.app'
            '${Platform.pathSeparator}Info.plist',
          ).existsSync(),
          isTrue,
        );
        // The consumed archive is cleaned up.
        expect(
          root.listSync().whereType<File>().where(
            (f) => f.path.endsWith('.zip'),
          ),
          isEmpty,
        );
      },
    );

    test('returns null when there is no archive to extract', () async {
      expect(await extractPendingUpdate(root: root), isNull);
    });
  });
}
