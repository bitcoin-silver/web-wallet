/// Fixed, endpoint-independent limits on transaction fees.
///
/// Fee rates can come from the connected RPC endpoint, which is untrusted, so
/// none of these limits are derived from endpoint data.
class FeeGuard {
  /// Hard ceiling on the fee rate: 0.01 BTCS/kvB (1000 sat/vB).
  static const double maxFeeRateCoinPerKvB = 0.01;
  static const int _maxFeeRateSatPerKvB = 1000000;

  /// Fee rates up to this are always accepted: 0.0004 BTCS/kvB (40 sat/vB),
  /// the "high traffic" reference used by the manual fee dialog.
  static const int _relaxedFeeRateSatPerKvB = 40000;

  /// Above the relaxed rate, the fee may not exceed this share of the amount sent.
  static const int _maxFeePercentOfAmount = 10;

  static const String _hint =
      'If you entered the fee yourself, lower it. Otherwise the connected '
      'server may be reporting a wrong fee.';

  static bool isRateAboveCeiling(double rateCoinPerKvB) =>
      rateCoinPerKvB > maxFeeRateCoinPerKvB;

  static String rateAboveCeilingMessage(double rateCoinPerKvB) =>
      'The connected server reported an unusually high fee rate '
      '(${rateCoinPerKvB.toStringAsFixed(8)} BTCS/kvB). The safety limit is '
      '${maxFeeRateCoinPerKvB.toStringAsFixed(8)} BTCS/kvB. '
      'Enter a manual fee to continue.';

  /// Returns a user-facing error when the fee is unreasonably high, otherwise null.
  ///
  /// [amountSats] is what the recipient receives (for a sweep: inputs minus fee).
  static String? check({
    required int feeSats,
    required int vbytes,
    required int amountSats,
  }) {
    if (feeSats < 0 || vbytes <= 0) {
      return 'Transaction not sent: the network fee could not be verified.';
    }

    if (feeSats * 1000 > _maxFeeRateSatPerKvB * vbytes) {
      return 'Transaction not sent: the network fee (${_coins(feeSats)} BTCS) '
          'is above the safety limit of '
          '${maxFeeRateCoinPerKvB.toStringAsFixed(8)} BTCS/kvB. $_hint';
    }

    final aboveRelaxedRate = feeSats * 1000 > _relaxedFeeRateSatPerKvB * vbytes;
    if (aboveRelaxedRate && feeSats * 100 > amountSats * _maxFeePercentOfAmount) {
      return 'Transaction not sent: the network fee (${_coins(feeSats)} BTCS) '
          'is more than $_maxFeePercentOfAmount% of the amount being sent '
          '(${_coins(amountSats)} BTCS). $_hint';
    }

    return null;
  }

  static String _coins(int sats) => (sats / 1e8).toStringAsFixed(8);
}
