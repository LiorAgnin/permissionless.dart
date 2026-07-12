// Example: Light Account v2.0.0 (EntryPoint v0.7)
//
// Same as light_example.dart — explicit version name for discoverability.
//
// USAGE:
//   dart run example/light_v200_example.dart
//   dart run example/light_v200_example.dart --self-fund

import 'light_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseLightArgs(args);
  final result = await runLightVariant(
    variant: parseLightVariant('2.0.0')!,
    selfFunded: parsed.selfFunded,
  );
  if (!result.ok) throw StateError(result.toString());
}
