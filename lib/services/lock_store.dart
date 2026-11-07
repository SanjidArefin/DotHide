import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The three mandatory unlock methods. Exactly one is always configured.
enum LockType { pin, password, pattern }

extension LockTypeLabel on LockType {
  String get storageKey => name;

  String get label => switch (this) {
        LockType.pin => 'PIN',
        LockType.password => 'Password',
        LockType.pattern => 'Pattern',
      };

  static LockType? fromStorage(String? value) {
    for (final type in LockType.values) {
      if (type.storageKey == value) return type;
    }
    return null;
  }
}

/// Stores the mandatory lock (PIN / password / pattern) and the optional
/// fingerprint shortcut. Only a salted SHA-256 digest is persisted — the
/// plaintext secret never touches disk.
class LockStore {
  static const String _kType = 'lock.type';
  static const String _kHash = 'lock.hash';
  static const String _kSalt = 'lock.salt';
  static const String _kPinLength = 'lock.pinLength';
  static const String _kBiometric = 'lock.biometricEnabled';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// True when a mandatory method has been configured.
  Future<bool> hasLock() async => (await type()) != null;

  Future<LockType?> type() async {
    final prefs = await _prefs;
    return LockTypeLabel.fromStorage(prefs.getString(_kType));
  }

  /// Digit count of the configured PIN, or `null` for other methods.
  Future<int?> pinLength() async {
    final prefs = await _prefs;
    final length = prefs.getInt(_kPinLength);
    return length == null || length < 4 ? null : length;
  }

  Future<bool> biometricEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_kBiometric) ?? false;
  }

  /// Fingerprint is a shortcut only, so it can never be enabled without a
  /// mandatory method in place.
  Future<bool> setBiometricEnabled(bool enabled) async {
    if (enabled && !await hasLock()) return false;
    final prefs = await _prefs;
    await prefs.setBool(_kBiometric, enabled);
    return true;
  }

  /// Replaces the mandatory method. [secret] is the raw PIN digits, password
  /// text, or the pattern encoded as dot indices joined by `-`.
  Future<void> setLock(LockType type, String secret, {int? pinLength}) async {
    final prefs = await _prefs;
    final salt = _newSalt();
    await prefs.setString(_kSalt, salt);
    await prefs.setString(_kHash, _digest(salt, secret));
    await prefs.setString(_kType, type.storageKey);
    if (type == LockType.pin && pinLength != null) {
      await prefs.setInt(_kPinLength, pinLength);
    } else {
      await prefs.remove(_kPinLength);
    }
  }

  Future<bool> verify(String secret) async {
    final prefs = await _prefs;
    final salt = prefs.getString(_kSalt);
    final hash = prefs.getString(_kHash);
    if (salt == null || hash == null) return false;
    return hash == _digest(salt, secret);
  }

  /// Removes the mandatory method and therefore also the fingerprint shortcut.
  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(_kType);
    await prefs.remove(_kHash);
    await prefs.remove(_kSalt);
    await prefs.remove(_kPinLength);
    await prefs.remove(_kBiometric);
  }

  static String _newSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  static String _digest(String salt, String secret) =>
      sha256.convert(utf8.encode('$salt::$secret')).toString();
}
