# AASA Server for WebAuthn Testing

This simple Dart server hosts the Apple App Site Association file required for iOS WebAuthn passkey functionality.

## Prerequisites

1. **ngrok account** with a reserved subdomain (requires paid plan for custom subdomains)
   - Sign up at https://ngrok.com
   - The example uses subdomain `9feab7e13674`

2. **Dart SDK** installed

## Quick Start

### 1. Start the AASA server

```bash
cd packages/permissionless_passkeys/example/aasa_server
dart pub get
dart run bin/server.dart
```

The server runs on `http://localhost:8080`.

### 2. Expose via ngrok

In a separate terminal:

```bash
# If you have a reserved subdomain:
ngrok http 8080 --subdomain=9feab7e13674

# Or with a static domain (ngrok v3):
ngrok http 8080 --domain=9feab7e13674.ngrok.app
```

### 3. Verify the AASA file

Visit: https://9feab7e13674.ngrok.app/.well-known/apple-app-site-association

You should see:
```json
{
  "webcredentials": {
    "apps": ["QC9255BHMY.com.example.permissionlessPasskeysExample"]
  }
}
```

### 4. Run the Flutter example app

The iOS app is pre-configured to use `9feab7e13674.ngrok.app` as the rpId.

```bash
cd packages/permissionless_passkeys/example
flutter run -d iphone
```

## Using a Different Domain

If you use a different ngrok subdomain or your own domain:

1. Update `bin/server.dart` with your Team ID and Bundle ID
2. Update iOS entitlements in `example/ios/Runner/Runner.entitlements`
3. Update the rpId in:
   - `example/lib/providers/credential_provider.dart`
   - `example/lib/screens/account_screen.dart`
   - `example/lib/screens/send_transaction_screen.dart`

## How It Works

WebAuthn passkeys on iOS require the Relying Party ID (rpId) to be validated:

1. Your iOS app declares `webcredentials:yourdomain.com` in Associated Domains
2. iOS fetches `https://yourdomain.com/.well-known/apple-app-site-association`
3. The AASA file must list your app's Team ID + Bundle ID
4. If validation passes, passkey registration/authentication works

Without this validation, you'll get a `SecurityError` when trying to register passkeys.

## Troubleshooting

### "SecurityError" on passkey registration
- Ensure the AASA server is running and accessible via ngrok
- Verify the AASA file returns valid JSON
- Check that Team ID and Bundle ID match your iOS app exactly
- Clear iOS cache: Settings > Developer > WebKit Feature Flags > Clear Website Data

### ngrok subdomain not available
- Reserved subdomains require an ngrok paid plan
- Use a free ngrok URL (updates the subdomain each restart) and update the iOS entitlements accordingly

### Associated Domains not working
- Rebuild the iOS app after changing entitlements
- Check Xcode: Signing & Capabilities > Associated Domains
