// Example: Light Account v1.1.0 (EntryPoint v0.6)
//
// USAGE:
//   dart run example/light_v110_example.dart
//   dart run example/light_v110_example.dart --self-fund

import 'light_runner.dart';

Future<void> main(List<String> args) async {
  final parsed = parseLightArgs(args);
  final result = await runLightVariant(
    variant: parseLightVariant('1.1.0')!,
    selfFunded: parsed.selfFunded,
  );
  if (!result.ok) throw StateError(result.toString());
}
