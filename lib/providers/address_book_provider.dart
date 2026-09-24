import 'package:flutter/foundation.dart';

import '../services/address_book.dart';
import '../services/storage_service.dart';

class AddressBookProvider with ChangeNotifier {
  static const String _saveFailedMessage =
      'Could not save the address book. Browser storage may be full or blocked.';

  final StorageService _storage = StorageService();
  final AddressBook _book = AddressBook();

  AddressBookProvider() {
    _book.loadJson(_storage.loadAddressBook());
  }

  List<AddressBookEntry> get entries => _book.entries;

  AddressBookEntry? find(String address) => _book.find(address);

  // Applies [change] and persists it; restores the previous state if the
  // browser refuses the write, so the list never shows unsaved data.
  bool _commit(void Function() change) {
    final before = _book.toJson();
    change();
    final saved = _storage.saveAddressBook(_book.toJson());
    if (!saved) _book.loadJson(before);
    notifyListeners();
    return saved;
  }

  /// Returns an error message, or null on success.
  String? addOrUpdate({required String label, required String address, String? originalAddress}) {
    String? error;
    final saved = _commit(() {
      error = _book.addOrUpdate(label: label, address: address, originalAddress: originalAddress);
    });
    return error ?? (saved ? null : _saveFailedMessage);
  }

  bool remove(String address) => _commit(() => _book.remove(address));

  String exportBtcs() => _book.exportBtcs();

  AddressBookImportResult importBtcs(String content) {
    late AddressBookImportResult result;
    final saved = _commit(() => result = _book.importBtcs(content));
    if (!saved) {
      return const AddressBookImportResult(success: false, message: _saveFailedMessage);
    }
    return result;
  }
}
