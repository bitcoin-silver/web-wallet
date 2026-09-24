import 'package:flutter_test/flutter_test.dart';
import 'package:btcs_web_wallet/services/payment_request.dart';

void main() {
  const bech32 = 'bs1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
  const legacy = 'BQ1rKj8hZmW9vXcT2yNpL4sD6fG3aE7uVb';

  group('amounts', () {
    test('parse to satoshis', () {
      expect(PaymentRequest.parseAmount('1.5'), 150000000);
      expect(PaymentRequest.parseAmount('0.00000001'), 1);
      expect(PaymentRequest.parseAmount('.25'), 25000000);
      expect(PaymentRequest.parseAmount('2.'), 200000000);
      expect(PaymentRequest.parseAmount('21000000'), 2100000000000000);
    });

    test('reject what is not a plain positive decimal', () {
      for (final bad in ['', '.', '0', '0.0', '-1', '1e3', '1,5', '0.000000001', ' ', 'abc', '99999999999']) {
        expect(PaymentRequest.parseAmount(bad), isNull, reason: bad);
      }
    });

    test('format without trailing zeros or exponents', () {
      expect(PaymentRequest.formatAmount(150000000), '1.5');
      expect(PaymentRequest.formatAmount(100000000), '1');
      expect(PaymentRequest.formatAmount(1), '0.00000001');
      expect(PaymentRequest.formatAmount(2100000000000000), '21000000');
    });
  });

  group('parse', () {
    test('what the Android wallet puts in its QR code', () {
      // receive_view.dart: 'bitcoinsilver:$address?amount=$amount&message=${encodeComponent(msg)}'
      final r = PaymentRequest.parse('bitcoinsilver:$bech32?amount=1.5&message=Invoice%2042%20%26%20tip');
      expect(r.address, bech32);
      expect(r.amountSats, 150000000);
      expect(r.message, 'Invoice 42 & tip');
      expect(r.label, isNull);
    });

    test('a bare address, and the Android no-amount QR', () {
      expect(PaymentRequest.parse(legacy).address, legacy);
      expect(PaymentRequest.parse('  $bech32 ').isPlainAddress, isTrue);
    });

    test('uppercase scheme and address, as used for compact QR codes', () {
      final r = PaymentRequest.parse('BITCOINSILVER:${bech32.toUpperCase()}?amount=2');
      expect(r.address, bech32);
      expect(r.amountSats, 200000000);
    });

    test('miner QR with a label, bitcoin: prefix and scheme://', () {
      expect(PaymentRequest.parse('bitcoinsilver:$bech32?label=miner-3').label, 'miner-3');
      expect(PaymentRequest.parse('bitcoin:$bech32').address, bech32);
      expect(PaymentRequest.parse('bitcoinsilver://$bech32?amount=1').amountSats, 100000000);
    });

    test('unknown optional parameters are ignored, req- ones are refused', () {
      expect(PaymentRequest.parse('bitcoinsilver:$bech32?amount=1&foo=bar').amountSats, 100000000);
      expect(() => PaymentRequest.parse('bitcoinsilver:$bech32?req-expires=1'), throwsFormatException);
    });

    test('long or multi-line notes are flattened and shortened', () {
      final long = 'a' * 300;
      final r =
          PaymentRequest.parse('bitcoinsilver:$bech32?message=${Uri.encodeComponent('x\ny')}&label=$long');
      expect(r.message, 'x y');
      expect(r.label!.length, PaymentRequest.maxMessageLength + 1);
    });

    test('rejects bad addresses and amounts with readable messages', () {
      for (final bad in [
        'bitcoinsilver:',
        'bitcoinsilver:hello?amount=1',
        'bitcoin:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
        'bitcoinsilver:$bech32?amount=-1',
        'bitcoinsilver:$bech32?amount=1e3',
        'bitcoinsilver:$bech32?amount=0',
        'bitcoinsilver:$bech32?message=%E0%A4%A',
      ]) {
        expect(() => PaymentRequest.parse(bad), throwsFormatException, reason: bad);
      }
    });

    test('fromText accepts a pasted web link, a URI or an address', () {
      const r = PaymentRequest(address: bech32, amountSats: 150000000, message: 'Invoice 42');
      final fromLink = PaymentRequest.fromText('  ${r.webLink()} ');
      expect(fromLink.address, bech32);
      expect(fromLink.amountSats, 150000000);
      expect(fromLink.message, 'Invoice 42');
      expect(PaymentRequest.fromText(r.toUri()).amountSats, 150000000);
      expect(PaymentRequest.fromText(legacy).address, legacy);
      expect(PaymentRequest.looksLikeUri(r.webLink()), isTrue);
      expect(() => PaymentRequest.fromText('https://example.com/#pay='), throwsFormatException);
    });

    test('looksLikeUri', () {
      expect(PaymentRequest.looksLikeUri(' BitcoinSilver:abc'), isTrue);
      expect(PaymentRequest.looksLikeUri('bitcoin:abc'), isTrue);
      expect(PaymentRequest.looksLikeUri(bech32), isFalse);
    });
  });

  group('build', () {
    test('plain address when there is nothing to request', () {
      expect(const PaymentRequest(address: bech32).toUri(), bech32);
    });

    test('same shape as the Android wallet, and parses back', () {
      const r = PaymentRequest(address: bech32, amountSats: 150000000, message: 'Invoice 42 & tip');
      expect(r.toUri(), 'bitcoinsilver:$bech32?amount=1.5&message=Invoice%2042%20%26%20tip');
      final back = PaymentRequest.parse(r.toUri());
      expect(back.amountSats, r.amountSats);
      expect(back.message, r.message);
    });

    test('web link keeps the request after # and round-trips', () {
      const r = PaymentRequest(address: bech32, amountSats: 1, message: 'a?b=c&d#e');
      final link = r.webLink();
      expect(link, startsWith('https://bitcoinsilver.top/web-wallet/#pay=bitcoinsilver%3A'));
      final uri = Uri.parse(link);
      expect(uri.query, isEmpty);
      final back = PaymentRequest.fromFragment(uri.fragment)!;
      expect(back.address, bech32);
      expect(back.amountSats, 1);
      expect(back.message, 'a?b=c&d#e');
    });

    test('share text names amount, address, note, link and URI', () {
      const r = PaymentRequest(address: bech32, amountSats: 150000000, message: 'Invoice 42');
      final text = r.toShareText();
      expect(text, contains('Please send 1.5 BTCS to:'));
      expect(text, contains(bech32));
      expect(text, contains('Note: Invoice 42'));
      expect(text, contains(r.webLink()));
      expect(text, contains(r.toUri()));
    });
  });

  group('fromFragment', () {
    test('ignores fragments that are not payment links', () {
      expect(PaymentRequest.fromFragment(''), isNull);
      expect(PaymentRequest.fromFragment('/'), isNull);
      expect(PaymentRequest.fromFragment('#/settings'), isNull);
    });

    test('accepts #pay= and Flutter-style #/pay=', () {
      final encoded = Uri.encodeComponent('bitcoinsilver:$bech32?amount=1');
      expect(PaymentRequest.fromFragment('#pay=$encoded')!.amountSats, 100000000);
      expect(PaymentRequest.fromFragment('/pay=$encoded')!.address, bech32);
    });

    test('an unencoded request still works', () {
      expect(PaymentRequest.fromFragment('pay=bitcoinsilver:$bech32?amount=3')!.amountSats, 300000000);
    });

    test('broken links throw', () {
      expect(() => PaymentRequest.fromFragment('pay='), throwsFormatException);
      expect(() => PaymentRequest.fromFragment('pay=%E0%A4%A'), throwsFormatException);
      expect(() => PaymentRequest.fromFragment('pay=nonsense'), throwsFormatException);
    });
  });
}
