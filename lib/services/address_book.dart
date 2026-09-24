import 'dart:convert';

/// One saved address. Field names and rules mirror the Android wallet
/// (wallet/lib/models/addressbook_entry.dart) so `.btcs` files move freely
/// between the two apps.
class AddressBookEntry {
  final String label;
  final String address;
  final DateTime createdAt;

  const AddressBookEntry({
    required this.label,
    required this.address,
    required this.createdAt,
  });

  // Accepts both our storage shape (`label`) and the .btcs shape (`username`).
  factory AddressBookEntry.fromJson(Map<String, dynamic> json) {
    final rawLabel = (json['label'] ?? json['username'] ?? '').toString().trim();
    final rawAddress = (json['address'] ?? '').toString().trim();
    final rawAddedAt = json['addedAt']?.toString();

    return AddressBookEntry(
      label: rawLabel,
      address: rawAddress,
      createdAt: DateTime.tryParse(rawAddedAt ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'address': address,
        'addedAt': createdAt.toIso8601String(),
      };

  AddressBookEntry copyWith({String? label, String? address}) => AddressBookEntry(
        label: label ?? this.label,
        address: address ?? this.address,
        createdAt: createdAt,
      );
}

/// Result of a `.btcs` import, shown to the user as-is.
class AddressBookImportResult {
  final bool success;
  final int imported;
  final int skipped;
  final String message;

  const AddressBookImportResult({
    required this.success,
    required this.message,
    this.imported = 0,
    this.skipped = 0,
  });
}

/// In-memory address book with the Android wallet's validation, matching and
/// `.btcs` import/export rules. Persistence is left to the caller.
class AddressBook {
  static const int maxImportEntries = 5000;
  static const int maxLabelLength = 64;
  static const int maxAddressLength = 128;
  static final RegExp _legacyAddressRegex = RegExp(r'^[bB83][1-9A-HJ-NP-Za-km-z]{24,33}$');
  static final RegExp _bech32AddressRegex = RegExp(r'^bs1[a-z0-9]{39,59}$');

  final List<AddressBookEntry> _entries = [];

  List<AddressBookEntry> get entries => List.unmodifiable(_entries);

  // Bech32 is case-insensitive, Base58 is not.
  static String normalizeAddress(String address) {
    final trimmed = address.trim();
    final lower = trimmed.toLowerCase();
    return lower.startsWith('bs1') ? lower : trimmed;
  }

  static bool isValidAddress(String address) {
    final trimmed = address.trim();
    if (trimmed.isEmpty || trimmed.length > maxAddressLength) return false;
    return _legacyAddressRegex.hasMatch(trimmed) || _bech32AddressRegex.hasMatch(trimmed.toLowerCase());
  }

  static bool isValidLabel(String label) {
    final trimmed = label.trim();
    return trimmed.isNotEmpty && trimmed.length <= maxLabelLength;
  }

  int _indexOf(String address) {
    final normalized = normalizeAddress(address);
    return _entries.indexWhere((e) => normalizeAddress(e.address) == normalized);
  }

  AddressBookEntry? find(String address) {
    if (address.trim().isEmpty) return null;
    final index = _indexOf(address);
    return index == -1 ? null : _entries[index];
  }

  /// Replaces the contents with previously stored JSON (our own storage
  /// format). Unreadable data yields an empty book rather than an error.
  void loadJson(String? data) {
    _entries.clear();
    if (data == null || data.isEmpty) return;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! List) return;
      _entries.addAll(
        decoded
            .whereType<Map>()
            .map((e) => AddressBookEntry.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.label.isNotEmpty && e.address.isNotEmpty),
      );
    } catch (_) {
      _entries.clear();
    }
  }

  String toJson() => jsonEncode(_entries.map((e) => e.toJson()).toList());

  /// Adds a new entry, or edits the one at [originalAddress]. Returns an error
  /// message, or null on success.
  String? addOrUpdate({
    required String label,
    required String address,
    String? originalAddress,
    DateTime? now,
  }) {
    final cleanLabel = label.trim();
    final cleanAddress = normalizeAddress(address);

    if (cleanLabel.isEmpty || cleanAddress.isEmpty) {
      return 'Label and address are required.';
    }
    if (!isValidLabel(cleanLabel)) {
      return 'Label is too long (max $maxLabelLength characters).';
    }
    if (cleanAddress.length > maxAddressLength) {
      return 'Address is too long (max $maxAddressLength characters).';
    }
    if (!isValidAddress(cleanAddress)) {
      return 'Address format is invalid.';
    }

    final existing = _indexOf(cleanAddress);
    final editing = originalAddress != null && originalAddress.trim().isNotEmpty;
    final originalIndex = editing ? _indexOf(originalAddress) : -1;

    if (existing != -1 && existing != originalIndex) {
      return 'This address is already saved as "${_entries[existing].label}".';
    }

    if (originalIndex != -1) {
      _entries[originalIndex] = _entries[originalIndex].copyWith(label: cleanLabel, address: cleanAddress);
    } else {
      _entries.insert(
        0,
        AddressBookEntry(
          label: cleanLabel,
          address: cleanAddress,
          createdAt: now ?? DateTime.now(),
        ),
      );
    }
    return null;
  }

  bool remove(String address) {
    final index = _indexOf(address);
    if (index == -1) return false;
    _entries.removeAt(index);
    return true;
  }

  /// The Android wallet's `.btcs` export format.
  String exportBtcs({DateTime? now}) {
    final contacts = _entries
        .map((e) => <String, dynamic>{
              'username': e.label,
              'address': e.address,
              'isFavorite': true,
              'addedAt': e.createdAt.toIso8601String(),
            })
        .toList();

    return jsonEncode(<String, dynamic>{
      'version': '1.0',
      'exportDate': (now ?? DateTime.now()).toIso8601String(),
      'contactCount': contacts.length,
      'contacts': contacts,
    });
  }

  /// Merges a `.btcs` file into the book. Known addresses get the file's
  /// label; new ones are appended. Invalid contacts are skipped. The book is
  /// left untouched when the file itself is rejected.
  AddressBookImportResult importBtcs(String content) {
    final sanitized = content.replaceAll('\u0000', '').replaceFirst(RegExp(r'^﻿'), '').trim();
    Object? decoded;
    var ignoredTrailingData = false;
    try {
      decoded = jsonDecode(sanitized);
    } on FormatException catch (e) {
      if (e.message.toLowerCase().contains('unexpected end of input')) {
        return const AddressBookImportResult(
          success: false,
          message: 'The .btcs file looks incomplete or truncated. Please choose the original file.',
        );
      }
      // The Android wallet can overwrite an older, longer export without
      // truncating it, leaving the old file's tail after a complete export.
      decoded = _completeExportFollowedByLeftovers(sanitized);
      if (decoded == null) {
        return const AddressBookImportResult(
          success: false,
          message: 'The selected file is not a valid .btcs file.',
        );
      }
      ignoredTrailingData = true;
    }

    if (decoded is! Map || !decoded.containsKey('version') || !decoded.containsKey('contacts')) {
      return const AddressBookImportResult(
        success: false,
        message: 'Invalid .btcs format. Missing required fields.',
      );
    }

    final rawEntries = decoded['contacts'];
    if (rawEntries is! List) {
      return const AddressBookImportResult(
        success: false,
        message: 'Invalid .btcs format. Contacts must be a list.',
      );
    }
    if (rawEntries.length > maxImportEntries) {
      return const AddressBookImportResult(
        success: false,
        message: 'File contains too many entries (max $maxImportEntries).',
      );
    }

    final declaredCount = decoded['contactCount'];
    if (declaredCount is num && rawEntries.length < declaredCount.toInt()) {
      return AddressBookImportResult(
        success: false,
        message: 'The file appears incomplete (${rawEntries.length} of '
            '${declaredCount.toInt()} contacts). Please choose the original .btcs file.',
      );
    }

    var imported = 0;
    var skipped = 0;
    for (final item in rawEntries) {
      if (item is! Map) {
        skipped++;
        continue;
      }
      final entry = AddressBookEntry.fromJson(Map<String, dynamic>.from(item));
      if (!isValidLabel(entry.label) || !isValidAddress(entry.address)) {
        skipped++;
        continue;
      }

      final address = normalizeAddress(entry.address);
      final existing = _indexOf(address);
      if (existing != -1) {
        _entries[existing] = _entries[existing].copyWith(label: entry.label);
      } else {
        _entries.add(AddressBookEntry(
          label: entry.label,
          address: address,
          createdAt: entry.createdAt,
        ));
      }
      imported++;
    }

    if (imported == 0) {
      return AddressBookImportResult(
        success: false,
        skipped: skipped,
        message: 'No valid contacts found in this .btcs file.',
      );
    }
    final summary = skipped == 0
        ? 'Imported $imported contacts.'
        : 'Imported $imported contacts. Skipped $skipped invalid contacts.';
    return AddressBookImportResult(
      success: true,
      imported: imported,
      skipped: skipped,
      message: ignoredTrailingData
          ? '$summary Leftover data from an older export at the end of the file was ignored.'
          : summary,
    );
  }

  /// Decodes the JSON object at the start of [text] when non-JSON leftovers
  /// follow it. Only accepted when the object says how many contacts it holds
  /// and holds exactly that many, so a cut-off export is never mistaken for a
  /// whole one. Returns null otherwise.
  static Map? _completeExportFollowedByLeftovers(String text) {
    if (!text.startsWith('{')) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{' || c == '[') {
        depth++;
      } else if (c == '}' || c == ']') {
        depth--;
        if (depth == 0) {
          try {
            final head = jsonDecode(text.substring(0, i + 1));
            if (head is! Map) return null;
            final count = head['contactCount'];
            final contacts = head['contacts'];
            if (count is num && contacts is List && contacts.length == count.toInt()) return head;
          } on FormatException {
            return null;
          }
          return null;
        }
      }
    }
    return null;
  }
}
