import 'package:flutter_test/flutter_test.dart';
import 'package:btcs_web_wallet/services/fee_guard.dart';

void main() {
  // A typical 1-input, 2-output transaction.
  const vbytes = 141;

  // Fee in sats for a rate given in BTCS/kvB.
  int feeAt(double coinPerKvB, int size) =>
      (coinPerKvB * size / 1000 * 1e8).round();

  group('FeeGuard.check', () {
    test('accepts a normal fee', () {
      expect(
        FeeGuard.check(
            feeSats: feeAt(0.00001, vbytes),
            vbytes: vbytes,
            amountSats: 100000000),
        isNull,
      );
    });

    test('accepts the hard ceiling when the amount is large enough', () {
      expect(
        FeeGuard.check(
            feeSats: feeAt(0.01, vbytes),
            vbytes: vbytes,
            amountSats: 1000000000),
        isNull,
      );
    });

    test('rejects a fee rate above the ceiling whatever the amount', () {
      final error = FeeGuard.check(
          feeSats: feeAt(0.01, vbytes) + 1,
          vbytes: vbytes,
          amountSats: 100000000000);
      expect(error, isNotNull);
      expect(error, contains('safety limit'));
    });

    test('rejects a fee above 10% of the amount when above the relaxed rate', () {
      // 0.001 BTCS/kvB is above the 0.0004 relaxed rate.
      final fee = feeAt(0.001, vbytes); // 14100 sats
      final error =
          FeeGuard.check(feeSats: fee, vbytes: vbytes, amountSats: 100000);
      expect(error, isNotNull);
      expect(error, contains('10%'));
    });

    test('accepts a fee above the relaxed rate when within 10% of the amount', () {
      final fee = feeAt(0.001, vbytes); // 14100 sats
      expect(
        FeeGuard.check(feeSats: fee, vbytes: vbytes, amountSats: 1000000),
        isNull,
      );
    });

    test('does not block tiny sends at or below the relaxed rate', () {
      // 5640 sats is 56% of a 10000 sat send, but exactly the relaxed rate.
      final fee = feeAt(0.0004, vbytes);
      expect(fee, 5640);
      expect(
        FeeGuard.check(feeSats: fee, vbytes: vbytes, amountSats: 10000),
        isNull,
      );
    });

    test('a fee one sat above the relaxed rate is subject to the 10% cap', () {
      expect(
        FeeGuard.check(feeSats: 5641, vbytes: vbytes, amountSats: 10000),
        isNotNull,
      );
    });

    test('fails closed on invalid input', () {
      expect(FeeGuard.check(feeSats: -1, vbytes: vbytes, amountSats: 1000), isNotNull);
      expect(FeeGuard.check(feeSats: 100, vbytes: 0, amountSats: 1000), isNotNull);
    });

    test('messages tell the user the transaction was not sent', () {
      final error = FeeGuard.check(
          feeSats: 10000000, vbytes: vbytes, amountSats: 100000000);
      expect(error, startsWith('Transaction not sent'));
    });
  });

  group('FeeGuard rate ceiling', () {
    test('0.01 BTCS/kvB is allowed, anything above is not', () {
      expect(FeeGuard.isRateAboveCeiling(0.01), isFalse);
      expect(FeeGuard.isRateAboveCeiling(0.0100001), isTrue);
      expect(FeeGuard.isRateAboveCeiling(0.00001), isFalse);
    });
  });
}
