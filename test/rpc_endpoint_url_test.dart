import 'package:flutter_test/flutter_test.dart';
import 'package:btcs_web_wallet/config.dart';
import 'package:btcs_web_wallet/services/rpc_endpoint.dart';

void main() {
  String? ok(String input) => RpcEndpointUrl.normalize(input).url;
  String? err(String input) => RpcEndpointUrl.normalize(input).error;

  group('accepted addresses are normalized', () {
    const cases = {
      'https://bitcoinsilver.eu/btcs-rpc': 'https://bitcoinsilver.eu/btcs-rpc',
      '  https://Example.COM/rpc/  ': 'https://example.com/rpc',
      'HTTPS://EXAMPLE.COM': 'https://example.com',
      'https://example.com/': 'https://example.com',
      'https://example.com///': 'https://example.com',
      'https://example.com:8443/rpc': 'https://example.com:8443/rpc',
      'https://example.com:443/rpc': 'https://example.com/rpc',
      'https://192.168.1.10:8443': 'https://192.168.1.10:8443',
      'https://[2001:db8::1]:8443/rpc': 'https://[2001:db8::1]:8443/rpc',
      'http://localhost:8332': 'http://localhost:8332',
      'http://LOCALHOST/': 'http://localhost',
      'http://127.0.0.1:8080/rpc/': 'http://127.0.0.1:8080/rpc',
    };
    cases.forEach((input, expected) {
      test(input, () => expect(ok(input), expected));
    });

    test('normalizing twice changes nothing', () {
      for (final input in [
        ...cases.keys,
        'https://example.com/a b',
        'https://example.com/a%20b/',
        'https://example.com/a/../b',
      ]) {
        final first = ok(input);
        if (first == null) continue;
        expect(ok(first), first, reason: input);
      }
    });

    test('the default endpoint is recognised as the default', () {
      expect(ok(Config.defaultRpcUrl), Config.defaultRpcUrl);
      expect(RpcEndpointUrl.isDefault(ok('  HTTPS://BitcoinSilver.eu/btcs-rpc/ ')!),
          isTrue);
      expect(RpcEndpointUrl.isDefault(ok('https://example.com')!), isFalse);
    });
  });

  group('rejected addresses', () {
    const rejected = [
      '',
      '   ',
      // http is only for localhost / 127.0.0.1, exactly
      'http://example.com',
      'http://localhost.evil.com',
      'http://127.0.0.1.evil.com',
      'http://127.1',
      'http://0.0.0.0',
      'http://[::1]',
      'http://192.168.1.10',
      // other schemes
      'ftp://example.com',
      'javascript:alert(1)',
      'file:///etc/passwd',
      'ws://localhost',
      'data:text/plain,hi',
      // no scheme
      'example.com',
      'example.com/rpc',
      'localhost:8332',
      // embedded credentials, incl. the host-spoofing form
      'https://user:pass@example.com',
      'https://bitcoinsilver.eu@evil.com/rpc',
      'http://localhost@evil.com',
      // things after the path
      'https://example.com/rpc?x=1',
      'https://example.com/rpc?',
      'https://example.com/#frag',
      // odd characters
      'https://exa mple.com',
      'https://example.com\\@evil.com',
      'https://exämple.com',
      'https://bit%63oin.com',
      'https://exa_mple.com',
      // structure
      'https://',
      'https:///rpc',
      'https:example.com',
      // ports
      'https://example.com:0',
      'https://example.com:70000',
    ];
    for (final input in rejected) {
      test(input.isEmpty ? '(empty)' : input, () {
        final result = RpcEndpointUrl.normalize(input);
        expect(result.isValid, isFalse, reason: 'accepted as ${result.url}');
        expect(result.error, isNotEmpty);
      });
    }

    test('over-long addresses', () {
      expect(err('https://example.com/${'a' * 2100}'), contains('too long'));
    });

    test('non-localhost http explains what is allowed', () {
      expect(err('http://example.com'), contains('localhost'));
    });
  });

  test('hostLabel shows host and non-default port only', () {
    expect(RpcEndpointUrl.hostLabel('https://example.com:8443/rpc'),
        'example.com:8443');
    expect(RpcEndpointUrl.hostLabel('https://bitcoinsilver.eu/btcs-rpc'),
        'bitcoinsilver.eu');
    expect(RpcEndpointUrl.hostLabel('https://[2001:db8::1]:8443'),
        '[2001:db8::1]:8443');
  });
}
