# Passkeys Smart Account Example

A Flutter example app demonstrating WebAuthn passkey authentication for ERC-4337 smart accounts.

## Features

- Register passkeys using device biometrics (Face ID, Touch ID, Windows Hello)
- Create Kernel v0.3.x smart accounts with WebAuthn validator
- Create Safe v1.4.1 smart accounts with WebAuthn shared signer
- View account info and encoded transactions
- Export credentials as JSON
- **Riverpod** state management for clean architecture

## Platform Setup

WebAuthn requires platform-specific configuration. Follow the instructions below for your target platform.

### iOS Setup

1. **Enable Associated Domains capability** in Xcode:
   - Open your project in Xcode
   - Select your target → Signing & Capabilities
   - Click "+ Capability" and add "Associated Domains"
   - Add `webcredentials:yourdomain.com`

2. **Host the Apple App Site Association file** at:
   ```
   https://yourdomain.com/.well-known/apple-app-site-association
   ```

   Content:
   ```json
   {
     "webcredentials": {
       "apps": ["TEAMID.com.yourcompany.yourapp"]
     }
   }
   ```

3. **Update Info.plist** if needed for attestation.

### Android Setup

1. **Add App Links intent filter** in `android/app/src/main/AndroidManifest.xml`:
   ```xml
   <intent-filter android:autoVerify="true">
       <action android:name="android.intent.action.VIEW" />
       <category android:name="android.intent.category.DEFAULT" />
       <category android:name="android.intent.category.BROWSABLE" />
       <data android:scheme="https" android:host="yourdomain.com" />
   </intent-filter>
   ```

2. **Host the Asset Links file** at:
   ```
   https://yourdomain.com/.well-known/assetlinks.json
   ```

   Content:
   ```json
   [{
     "relation": ["delegate_permission/common.get_login_creds"],
     "target": {
       "namespace": "android_app",
       "package_name": "com.yourcompany.yourapp",
       "sha256_cert_fingerprints": ["YOUR_APP_SIGNING_CERT_FINGERPRINT"]
     }
   }]
   ```

### Web Setup

1. **Serve over HTTPS** (required for WebAuthn)

2. **Set proper CORS headers** if using cross-origin requests

3. The rpId must match your domain exactly

### macOS Setup

1. **Enable WebAuthn entitlement** in your app's entitlements file:
   ```xml
   <key>com.apple.developer.web-browser.public-key-credential</key>
   <true/>
   ```

2. **Configure Associated Domains** similar to iOS

## Configuration

Update the following values in the example code:

### `lib/providers/credential_provider.dart`
```dart
final config = PassKeyConfig(
  rpId: 'yourdomain.com',     // Your relying party ID (domain)
  rpName: 'Your App Name',    // Display name for passkey prompt
);
```

### `lib/screens/account_screen.dart`
```dart
_webAuthnAccount = createWebAuthnAccount(
  credential: widget.credential,
  rpId: 'yourdomain.com',  // Must match registration config
);
```

## Running the Example

```bash
cd example
flutter pub get
flutter run
```

## Testing Without a Domain

For local development, you can:

1. **Use the included AASA server** (recommended) - See `aasa_server/README.md`
2. **Use a simulator/emulator** - Some platforms allow `localhost` during development
3. **Deploy to a test domain** - Set up a simple domain for testing

### Using the AASA Server with ngrok

The example app is pre-configured to use `9feab7e13674.ngrok.app`. To set this up:

```bash
# Terminal 1: Start the AASA server
cd aasa_server
dart pub get
dart run bin/server.dart

# Terminal 2: Expose via ngrok (requires reserved subdomain)
ngrok http 8080 --subdomain=9feab7e13674

# Terminal 3: Run the Flutter app
cd ..
flutter run -d iphone
```

See `aasa_server/README.md` for detailed instructions and troubleshooting.

## Troubleshooting

### "SecurityError" on registration
- Verify HTTPS is being used
- Check that Associated Domains (iOS) or App Links (Android) are configured
- Ensure the rpId matches your domain

### "NotAllowedError" on registration
- User cancelled the passkey prompt
- No authenticator available on device
- Check that biometrics are enabled on device

### "InvalidStateError" on registration
- A passkey already exists for this user on this device
- Use a different username or clear existing passkeys

### Account address not computed
- The example doesn't connect to an RPC endpoint
- In production, provide a `publicClient` to compute the counterfactual address
- Or deploy the account first and provide the `address` directly

## Architecture

This app uses **Riverpod** for state management with a clean separation of concerns:

```
lib/
├── main.dart                # App entry with ProviderScope
├── providers/
│   └── credential_provider.dart  # Credential state management
├── screens/
│   ├── home_screen.dart     # Main navigation (ConsumerWidget)
│   ├── register_screen.dart # Passkey registration (ConsumerStatefulWidget)
│   └── account_screen.dart  # Account info & demo encoding
└── widgets/
    └── credential_card.dart # Reusable credential display
```

### State Management

The `credentialProvider` manages the passkey credential state:

```dart
// Read the current state
final state = ref.watch(credentialProvider);

// Access the notifier for mutations
ref.read(credentialProvider.notifier).registerPasskey(...);
ref.read(credentialProvider.notifier).clearCredential();
```

## Security Notes

- Passkeys are bound to the device and domain (rpId)
- Private keys never leave the secure enclave
- The example stores credentials in memory only
- For production, consider secure storage for credential metadata
