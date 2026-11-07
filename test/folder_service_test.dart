import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:secure_file/services/folder_service.dart';
import 'package:secure_file/services/media_scanner_service.dart';
import 'package:secure_file/services/rescan_service.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('dothide_test_');
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  group('FolderService', () {
    test('hide prepends a dot and keeps the folder name', () async {
      final folder = Directory(p.join(sandbox.path, 'Holiday'))..createSync();
      final service = FolderService(scanner: _NoopScanner());

      final hiddenPath = await service.hide(folder.path);

      expect(hiddenPath, p.join(sandbox.path, '.Holiday'));
      expect(Directory(hiddenPath).existsSync(), isTrue);
      expect(folder.existsSync(), isFalse);
    });

    test('unhide removes the dot', () async {
      final folder = Directory(p.join(sandbox.path, '.Holiday'))..createSync();
      final service = FolderService(scanner: _NoopScanner());

      final visiblePath = await service.unhide(folder.path);

      expect(visiblePath, p.join(sandbox.path, 'Holiday'));
      expect(Directory(visiblePath).existsSync(), isTrue);
    });

    test('files inside the folder are untouched by a rename', () async {
      final folder = Directory(p.join(sandbox.path, 'Holiday'))..createSync();
      final file = File(p.join(folder.path, 'photo.jpg'))..writeAsStringSync('bytes');
      final service = FolderService(scanner: _NoopScanner());

      await service.hide(folder.path);

      final moved = File(p.join(sandbox.path, '.Holiday', 'photo.jpg'));
      expect(moved.existsSync(), isTrue);
      expect(moved.readAsStringSync(), 'bytes');
      expect(file.existsSync(), isFalse);
    });

    test('hiding an already hidden folder throws', () async {
      final folder = Directory(p.join(sandbox.path, '.Holiday'))..createSync();
      final service = FolderService(scanner: _NoopScanner());

      expect(() => service.hide(folder.path), throwsA(isA<FolderOperationException>()));
    });

    test('unhiding a visible folder throws', () async {
      final folder = Directory(p.join(sandbox.path, 'Holiday'))..createSync();
      final service = FolderService(scanner: _NoopScanner());

      expect(() => service.unhide(folder.path), throwsA(isA<FolderOperationException>()));
    });

    test('hiding a missing folder throws', () async {
      final service = FolderService(scanner: _NoopScanner());

      expect(
        () => service.hide(p.join(sandbox.path, 'Nope')),
        throwsA(isA<FolderOperationException>()),
      );
    });

    test('refuses to overwrite an existing target folder', () async {
      Directory(p.join(sandbox.path, 'Holiday')).createSync();
      Directory(p.join(sandbox.path, '.Holiday')).createSync();
      final service = FolderService(scanner: _NoopScanner());

      expect(
        () => service.hide(p.join(sandbox.path, 'Holiday')),
        throwsA(isA<FolderOperationException>()),
      );
    });

    test('displayName and isHidden strip the dot', () {
      expect(FolderService.isHidden('/storage/emulated/0/.Holiday'), isTrue);
      expect(FolderService.isHidden('/storage/emulated/0/Holiday'), isFalse);
      expect(FolderService.displayName('/storage/emulated/0/.Holiday'), 'Holiday');
      expect(FolderService.displayName('/storage/emulated/0/Holiday'), 'Holiday');
    });

    test('trailing slashes are tolerated', () async {
      Directory(p.join(sandbox.path, 'Holiday')).createSync();
      final service = FolderService(scanner: _NoopScanner());

      final hiddenPath = await service.hide('${p.join(sandbox.path, 'Holiday')}/');

      expect(hiddenPath, p.join(sandbox.path, '.Holiday'));
    });
  });

  group('RescanService', () {
    test('finds user-hidden folders and skips folders already known', () async {
      Directory(p.join(sandbox.path, '.Trip 2026')).createSync();
      Directory(p.join(sandbox.path, '.Archive')).createSync();
      final service = RescanService();

      final found = await service.scan(
        [sandbox.path],
        known: {p.join(sandbox.path, '.Archive')},
      );

      expect(found.map((candidate) => candidate.name), ['.Trip 2026'.substring(1)]);
    });

    test('ignores Android system dot-folders', () async {
      Directory(p.join(sandbox.path, '.thumbnails')).createSync();
      Directory(p.join(sandbox.path, '.Trashed')).createSync();
      Directory(p.join(sandbox.path, '.nomedia')).createSync();
      final service = RescanService();

      final found = await service.scan([sandbox.path]);

      expect(found, isEmpty);
    });

    test('ignores visible folders', () async {
      Directory(p.join(sandbox.path, 'Visible')).createSync();
      final service = RescanService();

      final found = await service.scan([sandbox.path]);

      expect(found, isEmpty);
    });

    test('does not descend into hidden folders', () async {
      final hidden = Directory(p.join(sandbox.path, '.Outer'))..createSync();
      Directory(p.join(hidden.path, '.Inner')).createSync();
      final service = RescanService();

      final found = await service.scan([sandbox.path]);

      expect(found.map((candidate) => candidate.name), ['Outer']);
    });

    test('searches nested visible folders within maxDepth', () async {
      final nested = Directory(p.join(sandbox.path, 'Download', 'Media'))..createSync(recursive: true);
      Directory(p.join(nested.path, '.Secret')).createSync();
      final service = RescanService();

      final found = await service.scan([sandbox.path]);

      expect(found.map((candidate) => candidate.name), ['Secret']);
    });
  });
}

class _NoopScanner extends MediaScannerService {
  @override
  Future<void> refresh(String path, {String? alsoParent}) async {}
}