/// Base exception for permissionless library errors.
class PermissionlessException implements Exception {
  const PermissionlessException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() {
    if (cause != null) {
      return 'PermissionlessException: $message (cause: $cause)';
    }
    return 'PermissionlessException: $message';
  }
}
