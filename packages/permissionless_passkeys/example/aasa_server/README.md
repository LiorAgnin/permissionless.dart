# AASA Server for WebAuthn Testing

This small Dart server hosts the two files passkeys need on the relying-party
domain:

- `/.well-known/apple-app-site-association` for iOS
- `/.well-known/assetlinks.json` for Android

## Prerequisites

1. **Dart SDK**
2. **An HTTPS tunnel** to your machine. The checked-in config uses
   `28fc478be30e2f.lhr.life`, a [localhost.run](https://localhost.run)
   address. Free tunnel hosts usually change between sessions, so expect to
   set your own host (see [Using a Different Domain](#using-a-different-domain)).
   ngrok or any other HTTPS tunnel works too.

## Quick Start

### 1. Configure the server

Edit `bin/server.dart`:

- `domain`: your tunnel host. It must equal `passkeyRpId` in `../lib/config.dart`.
- `teamId`: your Apple Developer Team ID (Xcode → Signing & Capabilities).
- `androidSha256`: your signing certificate's SHA-256 fingerprint. For the
  debug keystore:
  ```bash
  keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android
  ```

`bundleId` (`com.example.permissionlessPasskeysExample`) and `androidPackage`
(`com.example.permissionless_passkeys_example`) already match the example app.

### 2. Start the server

```bash
cd packages/permissionless_passkeys/example/aasa_server
dart pub get
dart run bin/server.dart        # port 8080; pass another port as an argument
```

### 3. Expose it over HTTPS

In a separate terminal:

```bash
# localhost.run
ssh -R 80:localhost:8080 nokey@localhost.run

# or ngrok
ngrok http 8080
```

### 4. Verify the files

Visit `https://<your host>/.well-known/apple-app-site-association`. With the
default `teamId` you should see:

```json
{
  "webcredentials": {
    "apps": ["YOUR_TEAM_ID.com.example.permissionlessPasskeysExample"]
  }
}
```

and `https://<your host>/.well-known/assetlinks.json` for Android.

### 5. Run the Flutter example app

```bash
cd packages/permissionless_passkeys/example
flutter run
```

## Using a Different Domain

When your tunnel host changes, update it in every place that names it:

1. `domain` in `bin/server.dart`
2. `passkeyRpId` in `example/lib/config.dart`
3. Android: `android:host` in `example/android/app/src/main/AndroidManifest.xml`
4. iOS: add `webcredentials:<your host>` to Associated Domains in
   `example/ios/Runner/Runner.entitlements` (Xcode → Signing & Capabilities →
   Associated Domains). The checked-in entitlements file is empty, so iOS
   needs this step even with the default host.

## How It Works

WebAuthn passkeys on iOS require the Relying Party ID (rpId) to be validated:

1. Your iOS app declares `webcredentials:yourdomain.com` in Associated Domains
2. iOS fetches `https://yourdomain.com/.well-known/apple-app-site-association`
3. The AASA file must list your app's Team ID + Bundle ID
4. If validation passes, passkey registration/authentication works

Android does the same with `assetlinks.json` and the
`delegate_permission/common.get_login_creds` relation.

Without this validation, you'll get a `SecurityError` when trying to register passkeys.

## Troubleshooting

### "SecurityError" on passkey registration
- Ensure the AASA server is running and reachable through the tunnel
- Verify the AASA file returns valid JSON
- Check that Team ID and Bundle ID match your iOS app exactly
- Check that the tunnel host matches `passkeyRpId` and the platform config
- Clear iOS cache: Settings > Developer > WebKit Feature Flags > Clear Website Data

### Associated Domains not working
- Rebuild the iOS app after changing entitlements
- Check Xcode: Signing & Capabilities > Associated Domains
