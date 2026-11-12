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

  group('FolderService.hideAll', () {
    test('hides every folder and reports the new paths', () async {
      Directory(p.join(sandbox.path, 'Alpha')).createSync();
      Directory(p.join(sandbox.path, 'Beta')).createSync();
      Directory(p.join(sandbox.path, 'Gamma')).createSync();
      final service = FolderService(scanner: _NoopScanner());

      final result = await service.hideAll([
        p.join(sandbox.path, 'Alpha'),
        p.join(sandbox.path, 'Beta'),
        p.join(sandbox.path, 'Gamma'),
      ]);

      expect(result.hidden, [
        p.join(sandbox.path, '.Alpha'),
        p.join(sandbox.path, '.Beta'),
        p.join(sandbox.path, '.Gamma'),
      ]);
      expect(result.failed, isEmpty);
      expect(result.hasFailures, isFalse);
      for (final name in ['.Alpha', '.Beta', '.Gamma']) {
        expect(Directory(p.join(sandbox.path, name)).existsSync(), isTrue);
      }
    });

    test('one bad folder does not stop the rest', () async {
      Directory(p.join(sandbox.path, 'Alpha')).createSync();
      Directory(p.join(sandbox.path, '.Already')).createSync();
      Directory(p.join(sandbox.path, 'Gamma')).createSync();
      final service = FolderService(scanner: _NoopScanner());

      final result = await service.hideAll([
        p.join(sandbox.path, 'Alpha'),
        p.join(sandbox.path, 'Nope'),
        p.join(sandbox.path, '.Already'),
        p.join(sandbox.path, 'Gamma'),
      ]);

      expect(result.hidden, [
        p.join(sandbox.path, '.Alpha'),
        p.join(sandbox.path, '.Gamma'),
      ]);
      expect(
        result.failed.map((failure) => failure.path),
        [p.join(sandbox.path, 'Nope'), p.join(sandbox.path, '.Already')],
      );
      expect(result.hasFailures, isTrue);
      expect(result.failed.first.message, contains('no longer exists'));
      expect(result.failed.last.message, 'Folder is already hidden.');
    });

    test('reports a name collision without renaming anything', () async {
      Directory(p.join(sandbox.path, 'Alpha')).createSync();
      Directory(p.join(sandbox.path, '.Alpha')).createSync();
      final service = FolderService(scanner: _NoopScanner());

      final result = await service.hideAll([p.join(sandbox.path, 'Alpha')]);

      expect(result.hidden, isEmpty);
      expect(result.failed.single.message, contains('already exists'));
      expect(Directory(p.join(sandbox.path, 'Alpha')).existsSync(), isTrue);
    });

    test('files inside batch-hidden folders are untouched', () async {
      final alpha = Directory(p.join(sandbox.path, 'Alpha'))..createSync();
      final beta = Directory(p.join(sandbox.path, 'Beta'))..createSync();
      File(p.join(alpha.path, 'a.txt')).writeAsStringSync('aaa');
      File(p.join(beta.path, 'b.txt')).writeAsStringSync('bbb');
      final service = FolderService(scanner: _NoopScanner());

      await service.hideAll([alpha.path, beta.path]);

      expect(File(p.join(sandbox.path, '.Alpha', 'a.txt')).readAsStringSync(), 'aaa');
      expect(File(p.join(sandbox.path, '.Beta', 'b.txt')).readAsStringSync(), 'bbb');
    });

    test('an empty selection is a no-op', () async {
      final service = FolderService(scanner: _NoopScanner());

      final result = await service.hideAll(const []);

      expect(result.hidden, isEmpty);
      expect(result.failed, isEmpty);
    });

    test('rescans each affected folder once', () async {
      Directory(p.join(sandbox.path, 'Alpha')).createSync();
      Directory(p.join(sandbox.path, 'Beta')).createSync();
      final scanner = _RecordingScanner();
      final service = FolderService(scanner: scanner);

      await service.hideAll([p.join(sandbox.path, 'Alpha'), p.join(sandbox.path, 'Beta')]);

      // Hidden folders plus their parent, deduplicated.
      expect(scanner.scanned, {
        p.join(sandbox.path, '.Alpha'),
        p.join(sandbox.path, '.Beta'),
        sandbox.path,
      });
    });

    test('a failing folder is not rescanned', () async {
      Directory(p.join(sandbox.path, '.Already')).createSync();
      final scanner = _RecordingScanner();
      final service = FolderService(scanner: scanner);

      await service.hideAll([p.join(sandbox.path, '.Already')]);

      expect(scanner.scanned, isEmpty);
    });
  });

  group('RescanService', () {    test('finds user-hidden folders and skips folders already known', () async {
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

/// Records every path handed to the scanner so batch refreshes can be asserted.
class _RecordingScanner extends MediaScannerService {
  final Set<String> scanned = <String>{};

  @override
  Future<void> refresh(String path, {String? alsoParent}) async {
    scanned.add(path);
    if (alsoParent != null) scanned.add(alsoParent);
  }
}