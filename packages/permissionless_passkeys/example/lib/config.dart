/// Relying Party ID the example registers and signs passkeys with.
///
/// A localhost.run tunnel for testing. It must match the domain served by
/// aasa_server/, the `android:host` in android/app/src/main/AndroidManifest.xml
/// and, on iOS, the `webcredentials:` Associated Domain in
/// ios/Runner/Runner.entitlements.
const passkeyRpId = '28fc478be30e2f.lhr.life';

/// Sepolia JSON-RPC URL. Replace `YOUR_KEY`, or use any Sepolia endpoint.
///
/// The Kernel account resolves its address through this RPC, and sending a
/// transaction reads the nonce and deployment state from it.
const sepoliaRpcUrl = 'https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY';
