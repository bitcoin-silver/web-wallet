import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;

import '../providers/address_book_provider.dart';
import '../services/address_book.dart';
import '../theme/app_theme.dart';

// Real exports are a few hundred KB at the 5000-contact import limit.
const int _maxImportFileBytes = 2 * 1024 * 1024;

/// The Address Book tab: add/edit form, search, list, and `.btcs`
/// import/export compatible with the Android wallet.
class AddressBookPanel extends StatefulWidget {
  final void Function(AddressBookEntry entry) onSend;

  const AddressBookPanel({super.key, required this.onSend});

  @override
  State<AddressBookPanel> createState() => _AddressBookPanelState();
}

class _AddressBookPanelState extends State<AddressBookPanel> {
  final _labelController = TextEditingController();
  final _addressController = TextEditingController();
  final _searchController = TextEditingController();
  String? _editingAddress;
  String? _formError;

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _save() {
    final provider = context.read<AddressBookProvider>();
    final wasEditing = _editingAddress != null;
    final error = provider.addOrUpdate(
      label: _labelController.text,
      address: _addressController.text,
      originalAddress: _editingAddress,
    );
    if (error != null) {
      setState(() => _formError = error);
      return;
    }
    _resetForm();
    _showSnack(wasEditing ? 'Contact updated.' : 'Contact saved.');
  }

  void _resetForm() {
    setState(() {
      _editingAddress = null;
      _formError = null;
      _labelController.clear();
      _addressController.clear();
    });
  }

  void _startEdit(AddressBookEntry entry) {
    setState(() {
      _editingAddress = entry.address;
      _formError = null;
      _labelController.text = entry.label;
      _addressController.text = entry.address;
    });
  }

  Future<void> _confirmDelete(AddressBookEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete contact?'),
        content: Text('"${entry.label}" will be removed from this browser\'s address book.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    if (!context.read<AddressBookProvider>().remove(entry.address)) {
      _showSnack('Could not delete the contact.', isError: true);
      return;
    }
    if (_editingAddress != null &&
        AddressBook.normalizeAddress(_editingAddress!) == AddressBook.normalizeAddress(entry.address)) {
      _resetForm();
    }
    _showSnack('Contact deleted.');
  }

  void _copy(AddressBookEntry entry) {
    Clipboard.setData(ClipboardData(text: entry.address));
    _showSnack('Address copied to clipboard.');
  }

  void _export() {
    final provider = context.read<AddressBookProvider>();
    if (provider.entries.isEmpty) {
      _showSnack('The address book is empty.', isError: true);
      return;
    }
    final blob = web.Blob(
      [provider.exportBtcs().toJS].toJS,
      web.BlobPropertyBag(type: 'application/json'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = 'BTCS_contacts.btcs';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    _showSnack('Address book exported (${provider.entries.length} contacts).');
  }

  void _import() {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = '.btcs,.json,application/json';
    input.onchange = ((web.Event _) {
      final file = input.files?.item(0);
      if (file != null) _readImportFile(file);
    }).toJS;
    input.click();
  }

  Future<void> _readImportFile(web.File file) async {
    if (file.size > _maxImportFileBytes) {
      _showSnack('This file is too large to be an address book export.', isError: true);
      return;
    }
    try {
      final content = (await file.text().toDart).toDart;
      if (!mounted) return;
      final result = context.read<AddressBookProvider>().importBtcs(content);
      _showSnack(result.message, isError: !result.success);
    } catch (_) {
      if (mounted) _showSnack('Could not read the selected file.', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade800 : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AddressBookProvider>();
    final entries = filterEntries(provider.entries, _searchController.text);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  const Text('Address Book', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: _import,
                        icon: const Icon(Icons.file_upload_outlined, size: 18),
                        label: const Text('Import'),
                      ),
                      TextButton.icon(
                        onPressed: _export,
                        icon: const Icon(Icons.file_download_outlined, size: 18),
                        label: const Text('Export'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Saved in this browser only. Import and export use .btcs files, the same format as the Android wallet.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 24),
              _buildForm(),
              const SizedBox(height: 32),
              if (provider.entries.isNotEmpty) ...[
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search by label or address',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Clear search',
                            onPressed: () => setState(_searchController.clear),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (provider.entries.isEmpty)
                const _EmptyNote('No saved addresses yet. Add one above or import a .btcs file.')
              else if (entries.isEmpty)
                const _EmptyNote('No contacts match your search.')
              else
                ...entries.map(_buildEntry),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final editing = _editingAddress != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(editing ? 'Edit contact' : 'Add contact',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextField(
              controller: _labelController,
              maxLength: AddressBook.maxLabelLength,
              onChanged: (_) => setState(() => _formError = null),
              decoration: const InputDecoration(labelText: 'Label', counterText: ''),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              onChanged: (_) => setState(() => _formError = null),
              onSubmitted: (_) => _save(),
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: const InputDecoration(labelText: 'Address', hintText: 'bs1...'),
            ),
            if (_formError != null) ...[
              const SizedBox(height: 10),
              Text(_formError!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (editing) ...[
                  TextButton(onPressed: _resetForm, child: const Text('Cancel')),
                  const SizedBox(width: 8),
                ],
                ElevatedButton.icon(
                  onPressed: _save,
                  icon: Icon(editing ? Icons.check_rounded : Icons.person_add_alt_1_rounded, size: 18),
                  label: Text(editing ? 'Update' : 'Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntry(AddressBookEntry entry) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        leading: const Icon(Icons.person_rounded, color: AppTheme.primaryColor),
        title: Text(entry.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          entry.address,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white54),
          overflow: TextOverflow.ellipsis,
        ),
        trailing:
            MediaQuery.of(context).size.width < 600 ? _buildCompactActions(entry) : _buildActions(entry),
      ),
    );
  }

  Widget _buildCompactActions(AddressBookEntry entry) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.send_rounded, size: 20),
          tooltip: 'Send to this address',
          onPressed: () => widget.onSend(entry),
        ),
        PopupMenuButton<String>(
          tooltip: 'More actions',
          onSelected: (action) {
            switch (action) {
              case 'copy':
                _copy(entry);
              case 'edit':
                _startEdit(entry);
              case 'delete':
                _confirmDelete(entry);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'copy', child: Text('Copy address')),
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.redAccent))),
          ],
        ),
      ],
    );
  }

  Widget _buildActions(AddressBookEntry entry) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.send_rounded, size: 20),
          tooltip: 'Send to this address',
          onPressed: () => widget.onSend(entry),
        ),
        IconButton(
          icon: const Icon(Icons.copy_rounded, size: 20),
          tooltip: 'Copy address',
          onPressed: () => _copy(entry),
        ),
        IconButton(
          icon: const Icon(Icons.edit_rounded, size: 20),
          tooltip: 'Edit',
          onPressed: () => _startEdit(entry),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
          tooltip: 'Delete',
          onPressed: () => _confirmDelete(entry),
        ),
      ],
    );
  }
}

List<AddressBookEntry> filterEntries(List<AddressBookEntry> entries, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return entries;
  return entries
      .where((e) => e.label.toLowerCase().contains(q) || e.address.toLowerCase().contains(q))
      .toList();
}

class _EmptyNote extends StatelessWidget {
  final String text;
  const _EmptyNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
    );
  }
}

/// Lets the user pick a saved contact, e.g. as a Send recipient.
Future<AddressBookEntry?> showAddressBookPicker(BuildContext context) {
  return showDialog<AddressBookEntry>(
    context: context,
    builder: (context) => const _AddressBookPicker(),
  );
}

class _AddressBookPicker extends StatefulWidget {
  const _AddressBookPicker();

  @override
  State<_AddressBookPicker> createState() => _AddressBookPickerState();
}

class _AddressBookPickerState extends State<_AddressBookPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = context.watch<AddressBookProvider>().entries;
    final entries = filterEntries(all, _query);

    return AlertDialog(
      title: const Text('Choose a contact'),
      content: SizedBox(
        width: 480,
        child: all.isEmpty
            ? const Text(
                'Your address book is empty. Add contacts in the Contacts tab.',
                style: TextStyle(color: Colors.white70),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      hintText: 'Search by label or address',
                      prefixIcon: Icon(Icons.search_rounded),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: entries.isEmpty
                        ? const _EmptyNote('No contacts match your search.')
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              return ListTile(
                                leading: const Icon(Icons.person_rounded, color: AppTheme.primaryColor),
                                title: Text(entry.label),
                                subtitle: Text(
                                  entry.address,
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                onTap: () => Navigator.pop(context, entry),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}
