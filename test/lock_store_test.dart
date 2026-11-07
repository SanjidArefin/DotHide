import 'package:flutter_test/flutter_test.dart';
import 'package:secure_file/services/lock_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('LockStore', () {
    test('no mandatory lock by default', () async {
      final store = LockStore();

      expect(await store.hasLock(), isFalse);
      expect(await store.type(), isNull);
    });

    test('stores the type and verifies the secret', () async {
      final store = LockStore();

      await store.setLock(LockType.pin, '1234', pinLength: 4);

      expect(await store.hasLock(), isTrue);
      expect(await store.type(), LockType.pin);
      expect(await store.pinLength(), 4);
      expect(await store.verify('1234'), isTrue);
      expect(await store.verify('4321'), isFalse);
    });

    test('never persists the plaintext secret', () async {
      final store = LockStore();
      await store.setLock(LockType.password, 'hunter2!');

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getKeys().map((key) => prefs.get(key).toString()).join('|');

      expect(stored.contains('hunter2!'), isFalse);
    });

    test('pattern is verified as a dash-joined dot sequence', () async {
      final store = LockStore();

      await store.setLock(LockType.pattern, '0-1-2-5');

      expect(await store.verify('0-1-2-5'), isTrue);
      expect(await store.verify('0-1-2'), isFalse);
    });

    test('changing the method invalidates the old secret', () async {
      final store = LockStore();
      await store.setLock(LockType.pin, '1234');

      await store.setLock(LockType.password, 'new secret');

      expect(await store.verify('1234'), isFalse);
      expect(await store.verify('new secret'), isTrue);
      expect(await store.type(), LockType.password);
      expect(await store.pinLength(), isNull);
    });

    test('fingerprint cannot be enabled without a mandatory method', () async {
      final store = LockStore();

      expect(await store.setBiometricEnabled(true), isFalse);
      expect(await store.biometricEnabled(), isFalse);
    });

    test('fingerprint can be enabled once a method exists', () async {
      final store = LockStore();
      await store.setLock(LockType.pin, '0000');

      expect(await store.setBiometricEnabled(true), isTrue);
      expect(await store.biometricEnabled(), isTrue);
    });

    test('clear removes the lock and the fingerprint shortcut', () async {
      final store = LockStore();
      await store.setLock(LockType.pin, '1234');
      await store.setBiometricEnabled(true);

      await store.clear();

      expect(await store.hasLock(), isFalse);
      expect(await store.biometricEnabled(), isFalse);
      expect(await store.verify('1234'), isFalse);
    });

    test('a new salt is generated for every save', () async {
      final store = LockStore();

      await store.setLock(LockType.pin, '1234');
      final prefs = await SharedPreferences.getInstance();
      final first = prefs.getString('lock.salt');

      await store.setLock(LockType.pin, '1234');
      final second = prefs.getString('lock.salt');

      expect(first, isNot(second));
    });
  });
}