import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Outcome of a storage-access check or request.
enum StorageAccess { granted, denied, permanentlyDenied }

/// All-files access is what lets the app rename dot-prefixed folders anywhere
/// the user picks. On Android 11+ this is a special permission granted from a
/// dedicated system settings page rather than a normal runtime dialog.
class PermissionService {
  /// `MANAGE_EXTERNAL_STORAGE` only exists from Android 11 (API 30). On older
  /// releases `permission_handler` reports it as `restricted`, which is how we
  /// detect that the legacy `storage` permission group should be used instead.
  Future<Permission> _applicable() async {
    if (!Platform.isAndroid) return Permission.storage;
    final status = await Permission.manageExternalStorage.status;
    return status == PermissionStatus.restricted ? Permission.storage : Permission.manageExternalStorage;
  }

  /// Checks the permission without triggering any system UI.
  Future<StorageAccess> status() async {
    if (!Platform.isAndroid) return StorageAccess.granted;
    return _map(await (await _applicable()).status);
  }

  /// Requests the permission, opening the all-files settings page when needed.
  Future<StorageAccess> request() async {
    if (!Platform.isAndroid) return StorageAccess.granted;
    return _map(await (await _applicable()).request());
  }

  /// Deep-links into app settings so the user can grant access manually.
  Future<bool> openSettings() => openAppSettings();

  /// Root of shared external storage, used as the browser's starting point.
  static const String externalStorageRoot = '/storage/emulated/0';

  static StorageAccess _map(PermissionStatus status) {
    if (status.isGranted || status.isLimited || status.isProvisional) return StorageAccess.granted;
    if (status.isPermanentlyDenied || status.isRestricted) return StorageAccess.permanentlyDenied;
    return StorageAccess.denied;
  }
}
