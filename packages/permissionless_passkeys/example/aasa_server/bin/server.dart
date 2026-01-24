// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

/// Simple HTTP server that serves the Apple App Site Association file
/// and Android Asset Links for WebAuthn passkey testing.
///
/// Usage:
///   1. Run this server: `dart run bin/server.dart`
///   2. Expose via Tailscale Funnel: `tailscale funnel 8080`
///   3. The AASA file will be available at:
///      https://28fc478be30e2f.lhr.life/.well-known/apple-app-site-association
void main(List<String> args) async {
  // Configuration - update these values to match your iOS/Android app
  // TODO: Update teamId to your Apple Developer Team ID
  const teamId = 'YOUR_TEAM_ID'; // Get from Xcode: Signing & Capabilities
  const bundleId = 'com.example.permissionlessPasskeysExample';
  const androidPackage = 'com.example.permissionless_passkeys_example';

  // Port can be overridden via command line: dart run bin/server.dart 8081
  final port = args.isNotEmpty ? int.parse(args[0]) : 8080;

  // Get Android SHA-256 fingerprint with:
  // keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android
  // TODO: Update this with your debug/release signing certificate fingerprint
  const androidSha256 = 'YOUR_SHA256_FINGERPRINT';

  // Apple App Site Association content
  final aasaContent = {
    'webcredentials': {
      'apps': ['$teamId.$bundleId'],
    },
  };

  // Android Asset Links content (for Android passkey support)
  // Both relations are needed: handle_all_urls for App Links, get_login_creds for passkeys
  final assetLinksContent = [
    {
      'relation': [
        'delegate_permission/common.handle_all_urls',
        'delegate_permission/common.get_login_creds',
      ],
      'target': {
        'namespace': 'android_app',
        'package_name': androidPackage,
        'sha256_cert_fingerprints': [
          if (androidSha256 != 'YOUR_SHA256_FINGERPRINT') androidSha256,
        ],
      },
    }
  ];

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('AASA Server running on http://localhost:$port');
  print('');
  print('Exposed via Tailscale Funnel at:');
  print('  https://28fc478be30e2f.lhr.life/');
  print('');
  print('Verify the files are accessible at:');
  print('  iOS:     https://28fc478be30e2f.lhr.life/.well-known/apple-app-site-association');
  print('  Android: https://28fc478be30e2f.lhr.life/.well-known/assetlinks.json');
  print('');
  if (teamId == 'YOUR_TEAM_ID') {
    print('WARNING: Update teamId in server.dart with your Apple Team ID!');
  }
  if (androidSha256 == 'YOUR_SHA256_FINGERPRINT') {
    print('WARNING: Update androidSha256 in server.dart for Android support!');
    print('  Run: keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android');
  }
  print('');
  print('Press Ctrl+C to stop the server.');

  await for (final request in server) {
    final path = request.uri.path;
    print('${request.method} $path');

    // Set CORS headers for all responses
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET');

    if (path == '/.well-known/apple-app-site-association') {
      // Apple App Site Association file
      request.response.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      request.response
          .write(const JsonEncoder.withIndent('  ').convert(aasaContent));
    } else if (path == '/.well-known/assetlinks.json') {
      // Android Asset Links file
      request.response.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      request.response
          .write(const JsonEncoder.withIndent('  ').convert(assetLinksContent));
    } else if (path == '/') {
      // Health check / info page
      request.response.headers.contentType = ContentType.html;
      request.response.write('''
<!DOCTYPE html>
<html>
<head><title>AASA Server</title></head>
<body>
  <h1>WebAuthn Association Server</h1>
  <p>This server hosts the required files for WebAuthn passkey testing via Tailscale Funnel.</p>
  <h2>Available Endpoints:</h2>
  <ul>
    <li><a href="/.well-known/apple-app-site-association">/.well-known/apple-app-site-association</a> (iOS)</li>
    <li><a href="/.well-known/assetlinks.json">/.well-known/assetlinks.json</a> (Android)</li>
  </ul>
  <h2>Configuration:</h2>
  <pre>
iOS Team ID: $teamId
iOS Bundle ID: $bundleId
Android Package: $androidPackage
  </pre>
</body>
</html>
''');
    } else {
      // 404 for other paths
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Not Found');
    }

    await request.response.close();
  }
}
