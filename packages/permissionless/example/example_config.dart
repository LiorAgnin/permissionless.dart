// Shared configuration for example scripts.
//
// Loads values from process environment, then from a nearby `.env` file
// (packages/permissionless/.env or monorepo root .env).
//
// Expected variables:
//   PIMLICO_API_KEY       — required for bundler / paymaster
//   TEST_PRIVATE_KEY      — owner key (0x-prefixed or raw hex)
//   SEPOLIA_RPC_URL       — optional; falls back to publicnode
//   BASE_SEPOLIA_RPC_URL  — optional; falls back to sepolia.base.org

import 'dart:io';

/// Configuration for live example scripts.
class ExampleConfig {
  ExampleConfig._({
    required this.privateKey,
    required this.pimlicoApiKey,
    required this.sepoliaRpcUrl,
    required this.baseSepoliaRpcUrl,
  });

  /// Owner private key (always 0x-prefixed).
  final String privateKey;

  /// Pimlico API key.
  final String pimlicoApiKey;

  /// Ethereum Sepolia JSON-RPC URL.
  final String sepoliaRpcUrl;

  /// Base Sepolia JSON-RPC URL.
  final String baseSepoliaRpcUrl;

  static const _hardhatAccount0 =
      '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

  static const _defaultSepoliaRpc =
      'https://ethereum-sepolia-rpc.publicnode.com';

  static const _defaultBaseSepoliaRpc = 'https://sepolia.base.org';

  /// Load config from env / `.env`. Throws [StateError] if Pimlico key missing.
  static ExampleConfig load({bool requirePimlico = true}) {
    _ensureDotEnvLoaded();

    final rawKey = _env('TEST_PRIVATE_KEY') ?? _hardhatAccount0;
    final privateKey = rawKey.startsWith('0x') ? rawKey : '0x$rawKey';

    final pimlicoApiKey = _env('PIMLICO_API_KEY') ?? '';
    if (requirePimlico && pimlicoApiKey.isEmpty) {
      throw StateError(
        'PIMLICO_API_KEY is not set.\n'
        'Export it or put it in packages/permissionless/.env\n'
        '  PIMLICO_API_KEY=pim_...\n'
        'Then re-run, e.g.:\n'
        '  set -a && source .env && set +a && dart run example/safe_example.dart',
      );
    }

    return ExampleConfig._(
      privateKey: privateKey,
      pimlicoApiKey: pimlicoApiKey,
      sepoliaRpcUrl: _env('SEPOLIA_RPC_URL') ?? _defaultSepoliaRpc,
      baseSepoliaRpcUrl: _env('BASE_SEPOLIA_RPC_URL') ?? _defaultBaseSepoliaRpc,
    );
  }

  /// Pimlico bundler/paymaster URL for a network path segment.
  ///
  /// [network] examples: `sepolia`, `base-sepolia`.
  String pimlicoUrl(String network) =>
      'https://api.pimlico.io/v2/$network/rpc?apikey=$pimlicoApiKey';

  String get sepoliaPimlicoUrl => pimlicoUrl('sepolia');

  String get baseSepoliaPimlicoUrl => pimlicoUrl('base-sepolia');

  // ---------------------------------------------------------------------------
  // .env loading
  // ---------------------------------------------------------------------------

  static bool _dotEnvLoaded = false;

  static void _ensureDotEnvLoaded() {
    if (_dotEnvLoaded) return;
    _dotEnvLoaded = true;

    final candidates = <String>[
      // CWD when running from packages/permissionless
      '.env',
      // CWD when running from monorepo root
      'packages/permissionless/.env',
      'permissionless.dart/packages/permissionless/.env',
      'permissionless.dart/.env',
      // Absolute-ish relative to this script file
      '${File(Platform.script.toFilePath()).parent.parent.path}/.env',
      '${File(Platform.script.toFilePath()).parent.parent.parent.parent.path}/.env',
    ];

    for (final path in candidates) {
      final file = File(path);
      if (!file.existsSync()) continue;
      try {
        _applyDotEnv(file.readAsStringSync());
        stderr.writeln('Loaded env from $path');
        return;
      } catch (_) {
        // try next
      }
    }
  }

  static void _applyDotEnv(String contents) {
    for (final rawLine in contents.split('\n')) {
      var line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('export ')) {
        line = line.substring(7).trim();
      }
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      final key = line.substring(0, eq).trim();
      var value = line.substring(eq + 1).trim();
      // Strip matching quotes
      if (value.length >= 2) {
        final q = value[0];
        if ((q == '"' || q == "'") && value.endsWith(q)) {
          value = value.substring(1, value.length - 1);
        }
      }
      // Do not override already-exported process env
      if (Platform.environment.containsKey(key) &&
          Platform.environment[key]!.isNotEmpty) {
        continue;
      }
      // Platform.environment is unmodifiable; stash in our map
      _fileEnv[key] = value;
    }
  }

  static final Map<String, String> _fileEnv = {};

  static String? _env(String key) {
    final fromProcess = Platform.environment[key];
    if (fromProcess != null && fromProcess.isNotEmpty) return fromProcess;
    final fromFile = _fileEnv[key];
    if (fromFile != null && fromFile.isNotEmpty) return fromFile;
    return null;
  }
}
