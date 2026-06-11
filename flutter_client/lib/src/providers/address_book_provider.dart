import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/address_book.dart';

class AddressBookProvider extends ChangeNotifier {
  static const _storageKey = 'address_book_entries';
  List<AddressBookEntry> _entries = [];
  List<String> _groups = ['默认'];
  String _filterGroup = '';
  String _searchQuery = '';

  List<AddressBookEntry> get entries {
    var list = List<AddressBookEntry>.from(_entries);
    if (_filterGroup.isNotEmpty) {
      list = list.where((e) => e.group == _filterGroup).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((e) =>
              e.deviceId.toLowerCase().contains(q) ||
              e.alias.toLowerCase().contains(q))
          .toList();
    }
    list.sort((a, b) {
      final aTime = a.lastConnectedAt ?? a.createdAt;
      final bTime = b.lastConnectedAt ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
    return list;
  }

  List<String> get groups => List.unmodifiable(_groups);
  String get filterGroup => _filterGroup;
  String get searchQuery => _searchQuery;

  bool containsDevice(String deviceId) =>
      _entries.any((e) => e.deviceId == deviceId);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      _entries = list
          .map((e) =>
              AddressBookEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      _rebuildGroups();
    }
    notifyListeners();
  }

  Future<void> addEntry({
    required String deviceId,
    String alias = '',
    String group = '默认',
    String platform = '',
  }) async {
    if (containsDevice(deviceId)) return;
    _entries.add(AddressBookEntry(
      deviceId: deviceId,
      alias: alias,
      group: group,
      platform: platform,
      createdAt: DateTime.now(),
    ));
    _rebuildGroups();
    await _save();
    notifyListeners();
  }

  Future<void> updateEntry(String deviceId, {
    String? alias,
    String? group,
    String? platform,
    DateTime? lastConnectedAt,
  }) async {
    final idx = _entries.indexWhere((e) => e.deviceId == deviceId);
    if (idx < 0) return;
    _entries[idx] = _entries[idx].copyWith(
      alias: alias,
      group: group,
      platform: platform,
      lastConnectedAt: lastConnectedAt,
    );
    _rebuildGroups();
    await _save();
    notifyListeners();
  }

  Future<void> removeEntry(String deviceId) async {
    _entries.removeWhere((e) => e.deviceId == deviceId);
    _rebuildGroups();
    await _save();
    notifyListeners();
  }

  Future<void> addGroup(String name) async {
    if (!_groups.contains(name)) {
      _groups.add(name);
      notifyListeners();
    }
  }

  void setFilterGroup(String group) {
    _filterGroup = group;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> markConnected(String deviceId) async {
    await updateEntry(deviceId, lastConnectedAt: DateTime.now());
  }

  void _rebuildGroups() {
    final groupSet = <String>{'默认'};
    for (final entry in _entries) {
      if (entry.group.isNotEmpty) {
        groupSet.add(entry.group);
      }
    }
    _groups = groupSet.toList()..sort();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, data);
  }
}
