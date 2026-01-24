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

/// Exception for invalid address format.
class InvalidAddressException extends PermissionlessException {
  InvalidAddressException(String address)
      : super('Invalid Ethereum address: $address');
}

/// Exception for unsupported Safe/EntryPoint version combination.
class UnsupportedVersionException extends PermissionlessException {
  UnsupportedVersionException(String safeVersion, String entryPointVersion)
      : super(
          'Safe version $safeVersion does not support EntryPoint version $entryPointVersion',
        );
}

/// Exception for RPC errors.
class RpcException extends PermissionlessException {
  RpcException(super.message, {this.code});

  final int? code;

  @override
  String toString() {
    if (code != null) {
      return 'RpcException [$code]: $message';
    }
    return 'RpcException: $message';
  }
}

/// Exception for signature errors.
class SignatureException extends PermissionlessException {
  SignatureException(super.message);
}
