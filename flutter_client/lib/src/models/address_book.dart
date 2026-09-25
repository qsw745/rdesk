class AddressBookEntry {
  final String deviceId;
  final String alias;
  final String group;
  final String platform;
  final DateTime createdAt;
  final DateTime? lastConnectedAt;

  const AddressBookEntry({
    required this.deviceId,
    this.alias = '',
    this.group = '默认',
    this.platform = '',
    required this.createdAt,
    this.lastConnectedAt,
  });

  AddressBookEntry copyWith({
    String? alias,
    String? group,
    String? platform,
    DateTime? lastConnectedAt,
  }) {
    return AddressBookEntry(
      deviceId: deviceId,
      alias: alias ?? this.alias,
      group: group ?? this.group,
      platform: platform ?? this.platform,
      createdAt: createdAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }

  String get displayName => alias.isNotEmpty ? alias : deviceId;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'alias': alias,
        'group': group,
        'platform': platform,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'lastConnectedAt': lastConnectedAt?.millisecondsSinceEpoch,
      };

  factory AddressBookEntry.fromJson(Map<String, dynamic> json) {
    return AddressBookEntry(
      deviceId: json['deviceId'] as String,
      alias: json['alias'] as String? ?? '',
      group: json['group'] as String? ?? '默认',
      platform: json['platform'] as String? ?? '',
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      lastConnectedAt: json['lastConnectedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastConnectedAt'] as int)
          : null,
    );
  }
}
