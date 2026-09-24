import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:btcs_web_wallet/services/address_book.dart';

void main() {
  const bech32 = 'bs1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
  const bech32Other = 'bs1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3qccfmv3';
  const legacy = 'BQ1rKj8hZmW9vXcT2yNpL4sD6fG3aE7uVb';

  // Shape produced by the Android wallet's AddressbookProvider.exportToBtcsJson.
  String androidExport(List<Map<String, dynamic>> contacts, {int? contactCount}) => jsonEncode({
        'version': '1.0',
        'exportDate': '2026-09-01T10:00:00.000',
        'contactCount': contactCount ?? contacts.length,
        'contacts': contacts,
      });

  Map<String, dynamic> contact(String label, String address) => {
        'username': label,
        'address': address,
        'isFavorite': true,
        'addedAt': '2026-08-15T12:30:00.000',
      };

  group('validation', () {
    test('accepts bech32 in either case and legacy addresses', () {
      expect(AddressBook.isValidAddress(bech32), isTrue);
      expect(AddressBook.isValidAddress(bech32.toUpperCase()), isTrue);
      expect(AddressBook.isValidAddress(legacy), isTrue);
    });

    test('rejects garbage and foreign addresses', () {
      expect(AddressBook.isValidAddress(''), isFalse);
      expect(AddressBook.isValidAddress('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4'), isFalse);
      expect(AddressBook.isValidAddress('BQ1rKj8hZmW9vXcT2yNpL4sD6fG3aE7uV0'), isFalse); // 0 is not base58
    });
  });

  group('addOrUpdate', () {
    test('adds newest first and stores bech32 lowercase', () {
      final book = AddressBook();
      expect(book.addOrUpdate(label: 'Alice', address: legacy), isNull);
      expect(book.addOrUpdate(label: ' Bob ', address: bech32.toUpperCase()), isNull);
      expect(book.entries.map((e) => e.label), ['Bob', 'Alice']);
      expect(book.entries.first.address, bech32);
    });

    test('rejects duplicates regardless of bech32 case', () {
      final book = AddressBook()..addOrUpdate(label: 'Bob', address: bech32);
      expect(book.addOrUpdate(label: 'Bobby', address: bech32.toUpperCase()), contains('already saved'));
      expect(book.entries, hasLength(1));
    });

    test('rejects empty, too long and invalid input', () {
      final book = AddressBook();
      expect(book.addOrUpdate(label: '', address: bech32), isNotNull);
      expect(book.addOrUpdate(label: 'x' * 65, address: bech32), contains('too long'));
      expect(book.addOrUpdate(label: 'Eve', address: 'not-an-address'), contains('invalid'));
      expect(book.entries, isEmpty);
    });

    test('edits label and address in place', () {
      final book = AddressBook()
        ..addOrUpdate(label: 'Alice', address: legacy)
        ..addOrUpdate(label: 'Bob', address: bech32);
      expect(book.addOrUpdate(label: 'Alice 2', address: bech32Other, originalAddress: legacy), isNull);
      expect(book.entries.map((e) => e.label), ['Bob', 'Alice 2']);
      expect(book.find(legacy), isNull);
      expect(book.find(bech32Other)!.label, 'Alice 2');
    });

    test('editing cannot take over another contact\'s address', () {
      final book = AddressBook()
        ..addOrUpdate(label: 'Alice', address: legacy)
        ..addOrUpdate(label: 'Bob', address: bech32);
      expect(book.addOrUpdate(label: 'Alice', address: bech32, originalAddress: legacy), isNotNull);
    });
  });

  test('findByLabel ignores case, spacing and invisible characters', () {
    final book = AddressBook()..addOrUpdate(label: 'Alice Smith', address: legacy);
    expect(book.findByLabel('alice smith')!.address, legacy);
    expect(book.findByLabel('  ALICE   Smith ')!.address, legacy);
    expect(book.findByLabel('Alice\u200B Smith')!.address, legacy);
    expect(book.findByLabel('Alice S.'), isNull);
    expect(book.findByLabel(''), isNull);
  });

  test('find and remove match bech32 case-insensitively', () {
    final book = AddressBook()..addOrUpdate(label: 'Bob', address: bech32);
    expect(book.find(bech32.toUpperCase())!.label, 'Bob');
    expect(book.find(''), isNull);
    expect(book.remove(bech32.toUpperCase()), isTrue);
    expect(book.entries, isEmpty);
  });

  test('storage JSON round-trips and ignores corrupt data', () {
    final book = AddressBook()
      ..addOrUpdate(label: 'Alice', address: legacy)
      ..addOrUpdate(label: 'Bob', address: bech32);
    final restored = AddressBook()..loadJson(book.toJson());
    expect(restored.entries.map((e) => e.label), ['Bob', 'Alice']);
    expect(restored.entries.last.createdAt, book.entries.last.createdAt);

    expect((AddressBook()..loadJson('{broken')).entries, isEmpty);
    expect((AddressBook()..loadJson('{"a":1}')).entries, isEmpty);
    expect((AddressBook()..loadJson(null)).entries, isEmpty);
  });

  group('export', () {
    test('matches the Android .btcs format', () {
      final book = AddressBook()..addOrUpdate(label: 'Alice', address: legacy, now: DateTime(2026, 8, 15));
      final decoded = jsonDecode(book.exportBtcs(now: DateTime(2026, 9, 1))) as Map<String, dynamic>;

      expect(decoded.keys, containsAll(['version', 'exportDate', 'contactCount', 'contacts']));
      expect(decoded['version'], '1.0');
      expect(decoded['contactCount'], 1);
      expect(decoded['contacts'], [
        {'username': 'Alice', 'address': legacy, 'isFavorite': true, 'addedAt': '2026-08-15T00:00:00.000'},
      ]);
    });

    test('an export imports back unchanged', () {
      final book = AddressBook()
        ..addOrUpdate(label: 'Alice', address: legacy)
        ..addOrUpdate(label: 'Bob', address: bech32);
      final copy = AddressBook();
      final result = copy.importBtcs(book.exportBtcs());
      expect(result.success, isTrue);
      expect(result.imported, 2);
      expect(copy.toJson(), book.toJson());
    });
  });

  group('import', () {
    test('reads an Android export, keeping labels and dates', () {
      final book = AddressBook();
      final result = book.importBtcs(androidExport([contact('Alice', legacy), contact('Pool', bech32)]));
      expect(result.success, isTrue);
      expect(result.message, 'Imported 2 contacts.');
      expect(book.entries.map((e) => e.label), ['Alice', 'Pool']);
      expect(book.entries.first.createdAt, DateTime.parse('2026-08-15T12:30:00.000'));
    });

    test('updates labels of known addresses instead of duplicating', () {
      final book = AddressBook()..addOrUpdate(label: 'Old name', address: bech32);
      final result = book.importBtcs(androidExport([contact('New name', bech32.toUpperCase())]));
      expect(result.imported, 1);
      expect(book.entries, hasLength(1));
      expect(book.entries.single.label, 'New name');
      expect(book.entries.single.address, bech32);
    });

    test('skips invalid contacts and reports them', () {
      final book = AddressBook();
      final result = book.importBtcs(androidExport([
        contact('Alice', legacy),
        contact('', bech32),
        contact('Eve', 'garbage'),
        {'nonsense': true},
      ]));
      expect(result.success, isTrue);
      expect(result.imported, 1);
      expect(result.skipped, 3);
      expect(result.message, 'Imported 1 contacts. Skipped 3 invalid contacts.');
    });

    test('tolerates a byte order mark and stray NUL bytes', () {
      final book = AddressBook();
      final result = book.importBtcs('\uFEFF${androidExport([contact('Alice', legacy)])}\u0000');
      expect(result.success, isTrue);
    });

    test('accepts the storage-style "label" key', () {
      final book = AddressBook();
      final result = book.importBtcs(jsonEncode({
        'version': '1.0',
        'contacts': [
          {'label': 'Alice', 'address': legacy},
        ],
      }));
      expect(result.success, isTrue);
      expect(book.entries.single.label, 'Alice');
    });

    // Android can write a shorter export over an older file without
    // truncating it, so the old file's tail follows the new JSON.
    group('leftovers from an older export', () {
      final export = androidExport([contact('Alice', legacy), contact('Pool', bech32)]);
      const leftover = '"username":"Old","address":"$bech32","isFavorite":true,"addedAt":"x"}]}';

      test('are ignored when the export before them is complete', () {
        final book = AddressBook();
        final result = book.importBtcs(export + leftover);
        expect(result.success, isTrue);
        expect(result.imported, 2);
        expect(result.message, contains('Leftover data'));
        expect(book.entries.map((e) => e.label), ['Alice', 'Pool']);
      });

      test('are refused when the contact count does not match', () {
        final book = AddressBook();
        final wrongCount = androidExport([contact('Alice', legacy)], contactCount: 0);
        expect(book.importBtcs(wrongCount + leftover).success, isFalse);
        expect(book.entries, isEmpty);
      });

      test('are refused when the export has no contact count', () {
        final noCount = jsonEncode({
          'version': '1.0',
          'contacts': [contact('Alice', legacy)],
        });
        expect(AddressBook().importBtcs(noCount + leftover).success, isFalse);
      });
    });

    test('rejects broken files without touching the book', () {
      final book = AddressBook()..addOrUpdate(label: 'Keep', address: legacy);
      final before = book.toJson();
      final full = androidExport([contact('Alice', bech32)]);

      for (final bad in [
        full.substring(0, full.length - 10), // truncated
        'not json',
        '[]',
        jsonEncode({'contacts': []}), // no version
        jsonEncode({'version': '1.0', 'contacts': 'x'}),
        androidExport([contact('Alice', bech32)], contactCount: 5), // incomplete
        androidExport(List.generate(5001, (i) => contact('C$i', bech32))),
        androidExport([contact('Eve', 'garbage')]), // nothing valid
      ]) {
        final result = book.importBtcs(bad);
        expect(result.success, isFalse, reason: bad.length > 80 ? bad.substring(0, 80) : bad);
        expect(book.toJson(), before);
      }
    });
  });
}
