import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

/// Tells whether a server answers at all, even if the browser would not let
/// this page read the answer (used to tell "unreachable" from "CORS blocked").
typedef ReachabilityProbe = Future<bool> Function(Uri uri);

enum EndpointProblem {
  unreachable,
  timeout,
  corsBlocked,
  requestRefused,
  badStatus,
  invalidResponse,
  wrongChain,
}

class EndpointCheckResult {
  final EndpointProblem? problem;
  final String? message;

  const EndpointCheckResult.ok()
      : problem = null,
        message = null;
  const EndpointCheckResult.failed(EndpointProblem this.problem, String this.message);

  bool get ok => problem == null;
}

class _CheckFailure implements Exception {
  final EndpointProblem problem;
  final String message;
  const _CheckFailure(this.problem, this.message);
}

/// Checks that an RPC endpoint answers like a Bitcoin Silver node before it is
/// saved. Everything the endpoint returns is treated as untrusted.
///
/// This is a guard against pointing the wallet at the wrong server by mistake.
/// A malicious server can still lie, which is why the fee limits and the
/// on-device signing do not depend on it.
class RpcEndpointVerifier {
  RpcEndpointVerifier({
    http.Client? client,
    ReachabilityProbe? probe,
    String genesisHash = Config.btcsGenesisHash,
    Duration timeout = const Duration(seconds: 10),
  })  : _client = client,
        _probe = probe,
        _genesisHash = genesisHash.toLowerCase(),
        _timeout = timeout;

  final http.Client? _client;
  final ReachabilityProbe? _probe;
  final String _genesisHash;
  final Duration _timeout;

  static final RegExp _hash = RegExp(r'^[0-9a-fA-F]{64}$');

  /// [url] must already be normalized (see RpcEndpointUrl).
  Future<EndpointCheckResult> verify(String url) async {
    final uri = Uri.parse(url);
    final client = _client ?? http.Client();
    try {
      final info = await _call(client, uri, 'getblockchaininfo', const []);
      if (!_looksLikeChainInfo(info)) {
        throw const _CheckFailure(EndpointProblem.invalidResponse,
            'The server answered, but not like a Bitcoin Silver node. '
            'Check that the address points to the node\'s RPC proxy.');
      }

      final genesis = await _call(client, uri, 'getblockhash', const [0]);
      if (genesis is! String || !_hash.hasMatch(genesis)) {
        throw const _CheckFailure(EndpointProblem.invalidResponse,
            'The server answered, but not like a Bitcoin Silver node. '
            'Check that the address points to the node\'s RPC proxy.');
      }
      if (genesis.toLowerCase() != _genesisHash) {
        throw const _CheckFailure(EndpointProblem.wrongChain,
            'This server is on a different network, not Bitcoin Silver (BTCS). '
            'Check the address.');
      }
      return const EndpointCheckResult.ok();
    } on _CheckFailure catch (failure) {
      return EndpointCheckResult.failed(failure.problem, failure.message);
    } finally {
      if (_client == null) client.close();
    }
  }

  bool _looksLikeChainInfo(dynamic info) {
    if (info is! Map) return false;
    final blocks = info['blocks'];
    final best = info['bestblockhash'];
    return blocks is num &&
        blocks >= 0 &&
        blocks == blocks.truncate() &&
        best is String &&
        _hash.hasMatch(best);
  }

  /// Sends one JSON-RPC request and returns its `result`. No credentials are
  /// ever sent, and text from the server is never passed on to the user.
  Future<dynamic> _call(
    http.Client client,
    Uri uri,
    String method,
    List<dynamic> params,
  ) async {
    final http.Response response;
    try {
      response = await client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '1.0',
              'id': 'web',
              'method': method,
              'params': params,
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const _CheckFailure(
          EndpointProblem.timeout, 'The server took too long to answer.');
    } catch (_) {
      throw await _classifyNetworkFailure(uri);
    }

    if (response.statusCode == 403 || response.statusCode == 405) {
      throw _CheckFailure(
          EndpointProblem.requestRefused,
          'The server refused the request "$method" (HTTP ${response.statusCode}). '
          'It must allow the requests the wallet uses; see the README.');
    }
    if (response.statusCode != 200) {
      throw _CheckFailure(EndpointProblem.badStatus,
          'The server returned an error (HTTP ${response.statusCode}).');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw _invalid();
    }
    if (decoded is! Map || decoded['error'] != null || decoded['result'] == null) {
      throw _invalid();
    }
    return decoded['result'];
  }

  _CheckFailure _invalid() => const _CheckFailure(
      EndpointProblem.invalidResponse,
      'The server answered, but not like a Bitcoin Silver node. '
      'Check that the address points to the node\'s RPC proxy.');

  // Browsers report CORS, DNS, offline and blocked-request failures identically.
  // If the server answers a plain no-cors request, it is online and the block
  // is almost certainly CORS.
  Future<_CheckFailure> _classifyNetworkFailure(Uri uri) async {
    final probe = _probe;
    if (probe != null && await probe(uri)) {
      return const _CheckFailure(
          EndpointProblem.corsBlocked,
          'The server is online, but the browser blocked the request. This '
          'usually means the server does not allow this website to connect '
          '(CORS). See the README for the setting.');
    }
    if (uri.scheme == 'http') {
      return const _CheckFailure(
          EndpointProblem.unreachable,
          'Could not reach the local server. Check that it is running. '
          'Safari may block http://localhost from a secure page; try Chrome '
          'or Firefox, or serve your node over https://.');
    }
    return const _CheckFailure(
        EndpointProblem.unreachable,
        'Could not reach this server. Check the address and that the server '
        'is online.');
  }
}
