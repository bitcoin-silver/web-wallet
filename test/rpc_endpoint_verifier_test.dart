import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:btcs_web_wallet/config.dart';
import 'package:btcs_web_wallet/services/rpc_endpoint_verifier.dart';

const btcGenesis =
    '000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f';
const bestHash =
    '0000000000000000000a1b2c3d4e5f60718293a4b5c6d7e8f9a0b1c2d3e4f506';

// Response shape observed from the default proxy: jsonrpc "2.0", the id
// replaced by the proxy, and no "error" key on success.
http.Response rpcOk(dynamic result) => http.Response(
    jsonEncode({'jsonrpc': '2.0', 'result': result, 'id': 'BTCS-RPC-PROXY'}), 200);

Map<String, dynamic> chainInfo({dynamic blocks = 12345, dynamic best = bestHash}) =>
    {'chain': 'main', 'blocks': blocks, 'bestblockhash': best};

/// A mock node answering by method name.
MockClient node({
  Object? info,
  Object? genesis = Config.btcsGenesisHash,
  List<http.Request>? log,
}) {
  return MockClient((request) async {
    log?.add(request);
    final method = (jsonDecode(request.body) as Map)['method'];
    switch (method) {
      case 'getblockchaininfo':
        return rpcOk(info ?? chainInfo());
      case 'getblockhash':
        return rpcOk(genesis);
    }
    return http.Response('{"error":"Method not allowed"}', 403);
  });
}

void main() {
  const url = 'https://node.example.com/btcs-rpc';

  group('genesis hash constant', () {
    test('is a 64-character hex string, so it cannot ship blank', () {
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(Config.btcsGenesisHash), isTrue);
    });
    test('matches the value from chainparams', () {
      expect(Config.btcsGenesisHash,
          '00000ea8e97e04892a03df35947ff0c4df705723f5b18be7cc6456ed16e9788e');
    });
  });

  group('valid endpoint', () {
    test('a BTCS node passes', () async {
      final result = await RpcEndpointVerifier(client: node()).verify(url);
      expect(result.ok, isTrue);
    });

    test('a proxy that rewrites id and jsonrpc still passes', () async {
      // rpcOk() already mimics the default proxy; this documents that intent.
      final result = await RpcEndpointVerifier(client: node()).verify(url);
      expect(result.problem, isNull);
    });

    test('asks getblockchaininfo then getblockhash [0], without credentials',
        () async {
      final log = <http.Request>[];
      await RpcEndpointVerifier(client: node(log: log)).verify(url);
      final bodies = log.map((r) => jsonDecode(r.body) as Map).toList();
      expect(bodies.map((b) => b['method']), ['getblockchaininfo', 'getblockhash']);
      expect(bodies[1]['params'], [0]);
      for (final r in log) {
        expect(r.method, 'POST');
        expect(r.url.toString(), url);
        expect(r.headers.keys.map((k) => k.toLowerCase()),
            isNot(contains('authorization')));
        expect(r.headers['Content-Type'], contains('application/json'));
      }
    });

    test('an upper-case genesis hash is accepted', () async {
      final result = await RpcEndpointVerifier(
        client: node(genesis: Config.btcsGenesisHash.toUpperCase()),
      ).verify(url);
      expect(result.ok, isTrue);
    });
  });

  group('wrong chain', () {
    test('a Bitcoin node is rejected with a clear message', () async {
      final result =
          await RpcEndpointVerifier(client: node(genesis: btcGenesis)).verify(url);
      expect(result.problem, EndpointProblem.wrongChain);
      expect(result.message, contains('different network'));
    });

    test('one differing character is enough to reject', () async {
      final almost = '${Config.btcsGenesisHash.substring(0, 63)}f';
      final result =
          await RpcEndpointVerifier(client: node(genesis: almost)).verify(url);
      expect(result.problem, EndpointProblem.wrongChain);
    });
  });

  group('invalid responses', () {
    Future<EndpointCheckResult> run(MockClient client) =>
        RpcEndpointVerifier(client: client).verify(url);

    test('an HTML page', () async {
      final r = await run(MockClient((_) async => http.Response('<html></html>', 200)));
      expect(r.problem, EndpointProblem.invalidResponse);
    });

    test('JSON that is not an object', () async {
      final r = await run(MockClient((_) async => http.Response('[1,2]', 200)));
      expect(r.problem, EndpointProblem.invalidResponse);
    });

    test('a JSON-RPC error', () async {
      final r = await run(MockClient((_) async =>
          http.Response('{"result":null,"error":{"code":-1,"message":"x"}}', 200)));
      expect(r.problem, EndpointProblem.invalidResponse);
    });

    test('a null result', () async {
      final r = await run(MockClient((_) async => http.Response('{"result":null}', 200)));
      expect(r.problem, EndpointProblem.invalidResponse);
    });

    test('chain info with a negative or fractional block count', () async {
      for (final blocks in [-1, 1.5, 'many']) {
        final r = await run(node(info: chainInfo(blocks: blocks)));
        expect(r.problem, EndpointProblem.invalidResponse, reason: '$blocks');
      }
    });

    test('chain info with a malformed best block hash', () async {
      final r = await run(node(info: chainInfo(best: 'nothex')));
      expect(r.problem, EndpointProblem.invalidResponse);
    });

    test('a genesis result that is not a hash', () async {
      for (final g in ['abc', 12345, '<script>']) {
        final r = await run(node(genesis: g));
        expect(r.problem, EndpointProblem.invalidResponse, reason: '$g');
      }
    });

    test('server text is never echoed into the message', () async {
      final r = await run(MockClient((_) async => http.Response(
          '{"error":"SECRET-SERVER-TEXT <b>hi</b>"}', 200)));
      expect(r.message, isNot(contains('SECRET-SERVER-TEXT')));
    });
  });

  group('http status', () {
    test('403 (method not on the allow-list) names the request', () async {
      final r = await RpcEndpointVerifier(
        client: MockClient((request) async {
          final method = (jsonDecode(request.body) as Map)['method'];
          return method == 'getblockchaininfo'
              ? rpcOk(chainInfo())
              : http.Response('{"error":"Method not allowed"}', 403);
        }),
      ).verify(url);
      expect(r.problem, EndpointProblem.requestRefused);
      expect(r.message, contains('getblockhash'));
    });

    test('other error statuses report the code', () async {
      final r = await RpcEndpointVerifier(
        client: MockClient((_) async => http.Response('oops', 502)),
      ).verify(url);
      expect(r.problem, EndpointProblem.badStatus);
      expect(r.message, contains('502'));
    });
  });

  group('network failures', () {
    MockClient failing() =>
        MockClient((_) async => throw http.ClientException('Failed to fetch'));

    test('reachable-but-blocked is reported as CORS', () async {
      final r = await RpcEndpointVerifier(
        client: failing(),
        probe: (_) async => true,
      ).verify(url);
      expect(r.problem, EndpointProblem.corsBlocked);
      expect(r.message, contains('CORS'));
    });

    test('not reachable at all is reported as unreachable', () async {
      final r = await RpcEndpointVerifier(
        client: failing(),
        probe: (_) async => false,
      ).verify(url);
      expect(r.problem, EndpointProblem.unreachable);
      expect(r.message, isNot(contains('Safari')));
    });

    test('without a probe it is reported as unreachable', () async {
      final r = await RpcEndpointVerifier(client: failing()).verify(url);
      expect(r.problem, EndpointProblem.unreachable);
    });

    test('a local http address mentions Safari', () async {
      final r = await RpcEndpointVerifier(
        client: failing(),
        probe: (_) async => false,
      ).verify('http://localhost:8332');
      expect(r.problem, EndpointProblem.unreachable);
      expect(r.message, contains('Safari'));
    });

    test('a slow server times out', () async {
      final r = await RpcEndpointVerifier(
        client: MockClient((_) async {
          await Future.delayed(const Duration(seconds: 2));
          return rpcOk(chainInfo());
        }),
        timeout: const Duration(milliseconds: 30),
      ).verify(url);
      expect(r.problem, EndpointProblem.timeout);
    });
  });
}
