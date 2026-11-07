import 'package:local_auth/local_auth.dart';

/// Thin wrapper around `local_auth`.
///
/// Fingerprint is a convenience shortcut only: [authenticate] always uses
/// `biometricOnly: true`, so the OS-level PIN/pattern/passcode fallback is
/// suppressed and the caller stays in charge of falling back to the app's own
/// mandatory method.
class BiometricService {
  BiometricService({LocalAuthentication? authentication})
      : _auth = authentication ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// True when the device has biometric hardware and at least one biometric
  /// is enrolled.
  Future<bool> isAvailable() async {
    try {
      if (!await _auth.canCheckBiometrics) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } on Exception {
      return false;
    }
  }

  /// True when the device has a fingerprint sensor with an enrolled print.
  Future<bool> hasFingerprint() async {
    try {
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.contains(BiometricType.fingerprint) ||
          enrolled.contains(BiometricType.strong) ||
          enrolled.contains(BiometricType.weak);
    } on Exception {
      return false;
    }
  }

  /// Returns `true` only on a successful fingerprint match. Any failure,
  /// cancellation, or missing enrolment returns `false` so the caller can fall
  /// back to the mandatory method.
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        sensitiveTransaction: false,
        persistAcrossBackgrounding: true,
      );
    } on Exception {
      return false;
    }
  }
}
