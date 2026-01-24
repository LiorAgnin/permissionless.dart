import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permissionless_passkeys/permissionless_passkeys.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web3_signers/web3_signers.dart';

const _credentialKey = 'saved_passkey_credential';

/// State for the credential registration process
class CredentialState {
  final WebAuthnCredential? credential;
  final PassKeyPublicKey? publicKey;
  final bool isLoading;
  final String? errorMessage;

  const CredentialState({
    this.credential,
    this.publicKey,
    this.isLoading = false,
    this.errorMessage,
  });

  CredentialState copyWith({
    WebAuthnCredential? credential,
    PassKeyPublicKey? publicKey,
    bool? isLoading,
    String? errorMessage,
    bool clearCredential = false,
    bool clearError = false,
  }) {
    return CredentialState(
      credential: clearCredential ? null : (credential ?? this.credential),
      publicKey: clearCredential ? null : (publicKey ?? this.publicKey),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  bool get hasCredential => credential != null;
}

/// Notifier for managing credential state
class CredentialNotifier extends Notifier<CredentialState> {
  @override
  CredentialState build() {
    // Try to load saved credential on startup
    _loadSavedCredential();
    return const CredentialState();
  }

  /// Load a previously saved credential from local storage
  Future<void> _loadSavedCredential() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedJson = prefs.getString(_credentialKey);

      if (savedJson != null) {
        final credential = WebAuthnCredential.fromJson(savedJson);

        state = CredentialState(
          credential: credential,
          publicKey: credential.raw,
        );
      }
    } catch (e) {
      // Ignore errors loading saved credential - user can register a new one
    }
  }

  /// Save the current credential to local storage
  Future<void> _saveCredential(WebAuthnCredential credential) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_credentialKey, credential.toJson());
    } catch (e) {
      // Ignore save errors - credential is still usable this session
    }
  }

  /// Register a new passkey with the given username and display name
  Future<bool> registerPasskey({
    required String username,
    required String displayName,
    String rpId = '28fc478be30e2f.lhr.life',
    String appName = 'Passkeys Example',
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final config = PassKeyConfig(
        rpId: rpId,
        rpName: appName,
        authenticatorAttachment: 'platform',
      );

      // Use generatePassKey from web3_signers to register a new passkey
      final publicKey = await generatePassKey(
        config: config,
        username: username,
        displayname: displayName,
      );
      final credential = WebAuthnCredential.fromPublicKey(publicKey);

      // Save credential for future sessions
      await _saveCredential(credential);

      state = state.copyWith(
        credential: credential,
        publicKey: publicKey,
        isLoading: false,
      );

      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _formatError(e),
      );
      return false;
    }
  }

  /// Clear the current credential (also removes from storage)
  Future<void> clearCredential() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_credentialKey);
    } catch (_) {}
    state = const CredentialState();
  }

  /// Clear any error message
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Set credential from an existing PassKeyPublicKey (e.g., from import)
  void setCredential(PassKeyPublicKey publicKey) {
    state = CredentialState(
      credential: WebAuthnCredential.fromPublicKey(publicKey),
      publicKey: publicKey,
    );
  }

  String _formatError(Object error) {
    final message = error.toString();

    if (message.contains('NotAllowedError')) {
      return 'Passkey registration was cancelled or denied.';
    }
    if (message.contains('InvalidStateError')) {
      return 'A passkey already exists for this user on this device.';
    }
    if (message.contains('SecurityError')) {
      return 'Security error. Make sure you\'re using HTTPS and '
          'have configured Associated Domains (iOS) or App Links (Android).';
    }
    if (message.contains('NotSupportedError')) {
      return 'WebAuthn is not supported on this device.';
    }

    return 'Failed to register passkey: $message';
  }
}

/// Provider for credential state management
final credentialProvider =
    NotifierProvider<CredentialNotifier, CredentialState>(
  CredentialNotifier.new,
);
