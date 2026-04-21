test:
	dart run melos exec -- dart test

.PHONY: changeset
changeset:
	dart run tool/changeset.dart

.PHONY: version
version:
	dart run tool/changeset_version.dart
	dart run tool/changeset_readme_sync.dart --write

.PHONY: changelog
changelog:
	dart run tool/changeset_changelog.dart

# Rewrite README dependency versions to match packages/*/pubspec.yaml.
.PHONY: sync-readme
sync-readme:
	dart run tool/changeset_readme_sync.dart --write

# Fail if any README dependency version is out of sync with pubspec.yaml.
# Intended for CI gating.
.PHONY: check-readme
check-readme:
	dart run tool/changeset_readme_sync.dart --check

# Prepare release by updating versions (+ syncing READMEs) and changelogs.
# Does not publish.
.PHONY: prepare-release
prepare-release:
	dart run tool/changeset_version.dart
	dart run tool/changeset_readme_sync.dart --write
	dart run tool/changeset_changelog.dart