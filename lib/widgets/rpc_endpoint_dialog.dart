import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../providers/wallet_provider.dart';
import '../services/rpc_endpoint.dart';

Future<void> showRpcEndpointDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const RpcEndpointDialog(),
  );
}

/// Lets the user pick which RPC server the wallet talks to. This dialog is the
/// only way to change the endpoint.
class RpcEndpointDialog extends StatefulWidget {
  const RpcEndpointDialog({super.key});

  @override
  State<RpcEndpointDialog> createState() => _RpcEndpointDialogState();
}

class _RpcEndpointDialogState extends State<RpcEndpointDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    final provider = context.read<WalletProvider>();
    _controller = TextEditingController(
      text: provider.usingCustomEndpoint ? provider.rpcUrl : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final provider = context.read<WalletProvider>();
    if (provider.isCheckingEndpoint) return;
    setState(() => _error = null);

    final error = await provider.setCustomEndpoint(_controller.text);
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final text = provider.usingCustomEndpoint
        ? 'Now using ${provider.rpcHostLabel}.'
        : 'Using the default server.';
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  void _reset() {
    final provider = context.read<WalletProvider>();
    provider.resetRpcEndpoint();
    setState(() {
      _controller.clear();
      _error = null;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Using the default server.')));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WalletProvider>();
    final checking = provider.isCheckingEndpoint;
    final custom = provider.usingCustomEndpoint;

    return AlertDialog(
      title: const Text('Server connection'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.circle,
                      size: 8, color: custom ? Colors.orangeAccent : Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      custom
                          ? 'Using a custom server: ${provider.rpcHostLabel}'
                          : 'Using the default server: '
                              '${RpcEndpointUrl.hostLabel(Config.defaultRpcUrl)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                enabled: !checking,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                  labelText: 'Custom server address',
                  hintText: 'https://my-node.example.com/btcs-rpc',
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                ),
                child: const Text(
                  'A custom endpoint cannot access your keys, but an untrusted '
                  'one can show wrong balances or block transactions. Only use '
                  'endpoints you trust or run yourself.',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'The server can see the addresses you look up, but never your keys.',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
              if (checking) ...[
                const SizedBox(height: 14),
                const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('Checking the server...', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: checking ? null : _reset,
          child: const Text('Reset to default'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        ElevatedButton(
          onPressed: checking ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
