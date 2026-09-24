import 'address_book.dart';

/// A payment request: `bitcoinsilver:<address>?amount=<BTCS>&message=<text>`.
///
/// This is the format the Android wallet puts in its receive QR code
/// (wallet/lib/views/home/receive_view.dart), following BIP21. The web wallet
/// also wraps it in a link, [webLink], that opens the Send tab pre-filled.
class PaymentRequest {
  static const String scheme = 'bitcoinsilver';
  static const String webWalletUrl = 'https://bitcoinsilver.top/web-wallet/';
  static const int satsPerCoin = 100000000;
  static const int maxMessageLength = 200;

  final String address;

  /// Requested amount in satoshis, or null when the payer chooses.
  final int? amountSats;

  /// Note for the payer. Shown to them only; never written on-chain.
  final String? message;

  /// Suggested name for the recipient (e.g. a miner's QR: `?label=miner-3`).
  final String? label;

  const PaymentRequest({required this.address, this.amountSats, this.message, this.label});

  bool get isPlainAddress => amountSats == null && message == null && label == null;

  /// The `bitcoinsilver:` URI, or just the address when there is nothing else
  /// to say (the Android wallet does the same, so older scanners keep working).
  String toUri() {
    if (isPlainAddress) return address;
    final params = <String>[
      if (amountSats != null) 'amount=${formatAmount(amountSats!)}',
      if (label != null) 'label=${Uri.encodeComponent(label!)}',
      if (message != null) 'message=${Uri.encodeComponent(message!)}',
    ];
    return '$scheme:$address?${params.join('&')}';
  }

  /// Link that opens the web wallet with this request. The request sits after
  /// `#`, which browsers never send to the server, so it stays out of logs.
  String webLink() => '$webWalletUrl#pay=${Uri.encodeComponent(toUri())}';

  /// Plain text for chats and email.
  String toShareText() {
    final buffer = StringBuffer();
    buffer.writeln(
        amountSats == null ? 'Please send BTCS to:' : 'Please send ${formatAmount(amountSats!)} BTCS to:');
    buffer.writeln(address);
    if (message != null) buffer.writeln('Note: $message');
    buffer.writeln();
    buffer.writeln('Pay with the web wallet: ${webLink()}');
    buffer.write('Payment request: ${toUri()}');
    return buffer.toString();
  }

  /// Formats satoshis as BTCS without trailing zeros, e.g. 150000000 -> "1.5".
  static String formatAmount(int sats) {
    final whole = sats ~/ satsPerCoin;
    final fraction = (sats % satsPerCoin).toString().padLeft(8, '0').replaceFirst(RegExp(r'0+$'), '');
    return fraction.isEmpty ? '$whole' : '$whole.$fraction';
  }

  /// Parses a BTCS amount such as "1.5" or ".25" into satoshis. Returns null
  /// for anything else: signs, exponents, commas, more than 8 decimals, or 0.
  static int? parseAmount(String text) {
    final match = RegExp(r'^(\d*)(?:\.(\d{0,8}))?$').firstMatch(text.trim());
    if (match == null) return null;
    final whole = match.group(1)!;
    final fraction = match.group(2) ?? '';
    if (whole.isEmpty && fraction.isEmpty) return null;
    if (whole.length > 10) return null;
    final sats = int.parse(whole.isEmpty ? '0' : whole) * satsPerCoin + int.parse(fraction.padRight(8, '0'));
    return sats > 0 ? sats : null;
  }

  /// True when [text] looks like a payment URI or payment link rather than a
  /// bare address.
  static bool looksLikeUri(String text) {
    final lower = text.trim().toLowerCase();
    return lower.startsWith('$scheme:') || lower.startsWith('bitcoin:') || _isWebLink(lower);
  }

  static bool _isWebLink(String text) =>
      (text.startsWith('https://') || text.startsWith('http://')) && text.contains('#pay=');

  /// Parses whatever a user pasted or scanned: a web payment link, a
  /// `bitcoinsilver:` URI or a bare address. Throws a [FormatException].
  static PaymentRequest fromText(String text) {
    final trimmed = text.trim();
    final lower = trimmed.toLowerCase();
    if (_isWebLink(lower)) {
      final request = fromFragment('pay=${trimmed.substring(lower.indexOf('#pay=') + 5)}');
      if (request == null) throw const FormatException('The payment link is empty.');
      return request;
    }
    return parse(trimmed);
  }

  /// Parses a `bitcoinsilver:` (or `bitcoin:`) URI or a bare address.
  /// Throws a [FormatException] whose message can be shown to the user.
  static PaymentRequest parse(String text) {
    var rest = text.trim();
    final lower = rest.toLowerCase();
    if (lower.startsWith('$scheme:')) {
      rest = rest.substring(scheme.length + 1);
    } else if (lower.startsWith('bitcoin:')) {
      rest = rest.substring('bitcoin:'.length);
    }
    // Some apps write "scheme://address".
    if (rest.startsWith('//')) rest = rest.substring(2);

    final queryStart = rest.indexOf('?');
    final rawAddress = (queryStart == -1 ? rest : rest.substring(0, queryStart)).trim();
    final query = queryStart == -1 ? '' : rest.substring(queryStart + 1);

    if (!AddressBook.isValidAddress(rawAddress)) {
      throw const FormatException('The payment request does not contain a valid BTCS address.');
    }

    Map<String, String> params;
    try {
      params = query.isEmpty ? const {} : Uri.splitQueryString(query);
    } on ArgumentError {
      throw const FormatException('The payment request is badly encoded.');
    }

    int? amountSats;
    String? message;
    String? label;
    for (final entry in params.entries) {
      final key = entry.key.toLowerCase();
      final value = entry.value.trim();
      switch (key) {
        case 'amount':
          amountSats = parseAmount(value);
          if (amountSats == null) {
            throw FormatException('The requested amount "$value" is not valid.');
          }
        case 'message':
          message = _clip(value);
        case 'label':
          label = _clip(value);
        default:
          // BIP21: parameters starting with "req-" must be understood.
          if (key.startsWith('req-')) {
            throw FormatException('The payment request needs a feature this wallet does not support ($key).');
          }
      }
    }

    return PaymentRequest(
      address: AddressBook.normalizeAddress(rawAddress),
      amountSats: amountSats,
      message: message,
      label: label,
    );
  }

  /// Reads the request from a web link's fragment (`pay=<encoded URI>`).
  /// Returns null when the fragment carries no request at all.
  static PaymentRequest? fromFragment(String fragment) {
    var f = fragment.startsWith('#') ? fragment.substring(1) : fragment;
    if (f.startsWith('/')) f = f.substring(1);
    if (!f.startsWith('pay=')) return null;
    final String decoded;
    try {
      decoded = Uri.decodeComponent(f.substring(4));
    } on ArgumentError {
      throw const FormatException('The payment link is badly encoded.');
    }
    if (decoded.trim().isEmpty) {
      throw const FormatException('The payment link is empty.');
    }
    return parse(decoded);
  }

  // Characters a request could use to make its text look different from what
  // it is: control characters, direction overrides (e.g. U+202E, which shows
  // text right-to-left) and invisible zero-width characters.
  static final RegExp _hiddenChars = RegExp(
    '[\u0000-\u001F\u007F-\u009F\u00AD\u061C\u180E\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF\uFFF9-\uFFFB]',
  );

  /// Text from a request (label, note) made safe to show: hidden and
  /// direction-changing characters removed, whitespace collapsed to single
  /// spaces. The text itself stays untrusted: it was written by whoever
  /// made the request.
  static String sanitizeText(String value) =>
      value.replaceAll(_hiddenChars, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String? _clip(String value) {
    final clean = sanitizeText(value);
    if (clean.isEmpty) return null;
    final runes = clean.runes;
    // Count characters, not UTF-16 units, so an emoji is never cut in half.
    return runes.length <= maxMessageLength
        ? clean
        : '${String.fromCharCodes(runes.take(maxMessageLength))}…';
  }
}
