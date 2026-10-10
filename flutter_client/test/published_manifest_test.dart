import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rdesk/src/models/app_update.dart';

/// The manifest that ships to the website must be readable by the updater
/// built from this same source, for every platform it offers.
void main() {
  final manifest = jsonDecode(File('../deploy/releases.json').readAsStringSync())
      as Map<String, dynamic>;

  for (final target in const [
    UpdateTarget('windows'),
    UpdateTarget('macos', 'arm64'),
    UpdateTarget('macos', 'x64'),
    UpdateTarget('android'),
  ]) {
    test('发布清单中的 ${target.platform} ${target.arch} 可被应用内更新解析', () {
      final release = UpdateRelease.fromManifest(manifest, target);

      expect(release.uri.scheme, 'https');
      expect(release.uri.host, 'qisw.top');
      expect(release.uri.path, startsWith('/rdesk/dl/RDesk-'));
      expect(release.sha256, hasLength(64));
      expect(release.bytes, greaterThan(0));
    });
  }

  test('已发布的 Windows 版本高于上一个公开版本，旧版会收到更新', () {
    final release =
        UpdateRelease.fromManifest(manifest, const UpdateTarget('windows'));

    expect(release.version.compareTo(AppVersion.parse('2.3.2', 25)),
        greaterThan(0));
    expect(release.notes, isNotEmpty);
  });
}
