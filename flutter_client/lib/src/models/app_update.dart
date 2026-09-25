import 'dart:ffi';
import 'dart:io';

class AppVersion implements Comparable<AppVersion> {
  final List<int> parts;
  final int? build;
  AppVersion._(this.parts, this.build);
  factory AppVersion.parse(String value, [int? build]) {
    if (!RegExp(r'^\d{1,6}\.\d{1,6}\.\d{1,6}$').hasMatch(value) ||
        (build != null && build < 0)) {
      throw const FormatException('版本信息无效');
    }
    return AppVersion._(value.split('.').map(int.parse).toList(), build);
  }
  @override
  int compareTo(AppVersion other) {
    for (var i = 0; i < 3; i++) {
      final result = parts[i].compareTo(other.parts[i]);
      if (result != 0) return result;
    }
    return build != null && other.build != null
        ? build!.compareTo(other.build!)
        : 0;
  }

  @override
  String toString() => parts.join('.');
}

class UpdateTarget {
  final String platform;
  final String arch;
  const UpdateTarget(this.platform, [this.arch = 'x64']);
  static UpdateTarget current() => UpdateTarget(Platform.operatingSystem,
      Abi.current() == Abi.macosArm64 ? 'arm64' : 'x64');
}

class UpdateRelease {
  static const maxBytes = 512 * 1024 * 1024;
  static final storeUri =
      Uri.parse('https://apps.apple.com/cn/app/id6796165712');
  final AppVersion version;
  final String platform;
  final Uri uri;
  final String? sha256;
  final int? bytes;
  final List<String> notes;
  const UpdateRelease(
      {required this.version,
      required this.platform,
      required this.uri,
      this.sha256,
      this.bytes,
      this.notes = const []});
  bool get isStore => platform == 'ios';
  String get filename => uri.pathSegments.last;
  String get key => '$platform:$version:${version.build}:$sha256';

  Map<String, dynamic> toManifest() => {
        'platforms': [
          {
            'id': platform,
            'version': version.toString(),
            if (version.build != null) 'build_number': version.build,
            'url': uri.toString(),
            'alternate': {'url': uri.toString()},
            'release_notes': notes,
          }
        ],
        if (!isStore)
          'files': {
            filename: {'sha256': sha256, 'bytes': bytes}
          },
      };

  static UpdateRelease fromManifest(
      Map<String, dynamic> json, UpdateTarget target) {
    final list = json['platforms'];
    if (list is! List) throw const FormatException('更新清单格式无效');
    final entries =
        list.whereType<Map>().where((e) => e['id'] == target.platform).toList();
    if (entries.length != 1) throw const FormatException('此平台暂无更新信息');
    final entry = entries.single;
    final version = AppVersion.parse(
        entry['version'] as String, entry['build_number'] as int?);
    final rawNotes = entry['release_notes'];
    final notes = rawNotes is List
        ? rawNotes
            .whereType<String>()
            .take(12)
            .map((s) => s.length > 500 ? s.substring(0, 500) : s)
            .toList()
        : <String>[];
    if (target.platform == 'ios') {
      if (entry['url'] != storeUri.toString())
        throw const FormatException('商店地址无效');
      return UpdateRelease(
          version: version, platform: 'ios', uri: storeUri, notes: notes);
    }
    final suffix = switch (target.platform) {
      'windows' => 'windows-x64-setup.exe',
      'android' => 'android.apk',
      'macos' when target.arch == 'arm64' => 'macos-arm64.dmg',
      'macos' when target.arch == 'x64' => 'macos-x64.zip',
      _ => throw const FormatException('此平台暂不支持应用内更新'),
    };
    final filename = 'RDesk-$version-$suffix';
    final expected = 'https://qisw.top/rdesk/dl/$filename';
    final alternate = entry['alternate'];
    final url = target.platform == 'macos' && target.arch == 'x64'
        ? (alternate is Map ? alternate['url'] : null)
        : entry['url'];
    if (url != expected) throw const FormatException('安装包来源无效');
    final file = (json['files'] as Map?)?[filename];
    if (file is! Map ||
        file['sha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(file['sha256'] as String) ||
        file['bytes'] is! int ||
        file['bytes'] < 1 ||
        file['bytes'] > maxBytes) {
      throw const FormatException('安装包校验信息无效');
    }
    return UpdateRelease(
        version: version,
        platform: target.platform,
        uri: Uri.parse(expected),
        sha256: file['sha256'] as String,
        bytes: file['bytes'] as int,
        notes: notes);
  }
}
