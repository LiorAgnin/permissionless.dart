// tool/changeset_readme_sync.dart
//
// Syncs `<package>: ^X.Y.Z` references in README files with the current
// version declared in each package's pubspec.yaml.
//
// Modes:
//   --write   Mutate README files to match current pubspec versions (default).
//   --check   Do not mutate; exit 1 if any README is out of sync.
//
// Scope: rewrites only pubspec-style lines (e.g. `  permissionless: ^0.3.0`)
// anchored to the start of a line. Narrative prose and import statements are
// left alone because the package name must be the first non-whitespace token
// on the line and must be immediately followed by a colon.

import 'dart:io';

import 'changeset_lib.dart';

const _defaultReadmes = [
  'README.md',
  'packages/permissionless/README.md',
  'packages/permissionless_passkeys/README.md',
];

enum _Mode { write, check }

void main(List<String> args) {
  final mode = _parseMode(args);
  try {
    exitCode = _run(mode);
  } catch (e, st) {
    stderr
      ..writeln('error: $e')
      ..writeln(st);
    exitCode = 1;
  }
}

_Mode _parseMode(List<String> args) {
  final hasWrite = args.contains('--write');
  final hasCheck = args.contains('--check');
  if (hasWrite && hasCheck) {
    stderr.writeln('error: --write and --check are mutually exclusive');
    exit(2);
  }
  if (hasCheck) return _Mode.check;
  return _Mode.write;
}

int _run(_Mode mode) {
  final packages = discoverPackages();
  if (packages.isEmpty) {
    throw Exception('no packages discovered under $packagesRootDirName/');
  }

  final versions = <String, String>{
    for (final p in packages) p.name: readPubspecVersion(p.pubspecPath),
  };

  var anyDrift = false;

  for (final path in _defaultReadmes) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('warning: README not found: $path');
      continue;
    }
    final original = file.readAsStringSync();
    final updated = rewriteReadme(original, versions);
    if (updated == original) continue;

    anyDrift = true;
    if (mode == _Mode.check) {
      stderr.writeln('DRIFT: $path has stale version reference(s)');
    } else {
      file.writeAsStringSync(updated);
      stdout.writeln('updated: $path');
    }
  }

  if (mode == _Mode.check) {
    if (anyDrift) {
      stderr
        ..writeln('')
        ..writeln(
            'README version references are out of sync with pubspec.yaml.')
        ..writeln('Run: dart run tool/changeset_readme_sync.dart --write');
      return 1;
    }
    stdout.writeln('README versions match pubspec.yaml.');
    return 0;
  }

  if (!anyDrift) {
    stdout.writeln('No README updates needed.');
  }
  return 0;
}

/// Rewrites every pubspec-style `<name>: <version>` line in [input] whose name
/// matches a key in [versions], replacing the existing version with the
/// corresponding value. Anchors the match to the start of a line so narrative
/// prose is left alone. Exposed at library scope for unit testing.
String rewriteReadme(String input, Map<String, String> versions) {
  var out = input;
  for (final entry in versions.entries) {
    final escapedName = RegExp.escape(entry.key);
    final target = entry.value;
    final pattern = RegExp(
      '^(\\s*$escapedName\\s*:\\s*\\^?)(\\d+\\.\\d+\\.\\d+[\\w.-]*)(.*)\$',
      multiLine: true,
    );
    out = out.replaceAllMapped(pattern, (m) {
      final prefix = m.group(1)!;
      final trailing = m.group(3)!;
      return '$prefix$target$trailing';
    });
  }
  return out;
}
