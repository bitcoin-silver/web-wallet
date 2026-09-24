import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'payment_request.dart';

/// Holds a payment request that arrived through a web link
/// (`https://bitcoinsilver.top/web-wallet/#pay=...`) until the dashboard
/// is shown, i.e. after the wallet is unlocked.
///
/// The link only pre-fills the Send tab. It never sends anything and never
/// changes settings.
class PaymentLinkInbox with ChangeNotifier {
  PaymentRequest? _pending;
  String? _error;

  PaymentLinkInbox() {
    _receive(_takePayFragment());
    // A link opened in an already open wallet tab only changes the hash, which
    // fires popstate. Flutter's hash URL handling would read "pay=..." as a
    // page name and fail, so take the event first (capture listeners run
    // before Flutter's) and keep it from reaching Flutter.
    web.window.addEventListener(
      'popstate',
      ((web.Event event) {
        final fragment = _takePayFragment();
        if (fragment == null) return;
        event.stopImmediatePropagation();
        _receive(fragment);
      }).toJS,
      true.toJS,
    );
  }

  bool get hasPending => _pending != null;

  /// Returns the waiting request once, or null.
  PaymentRequest? takeRequest() {
    final request = _pending;
    _pending = null;
    return request;
  }

  /// Returns why the last link could not be read, once, or null.
  String? takeError() {
    final error = _error;
    _error = null;
    return error;
  }

  void _receive(String? fragment) {
    if (fragment == null) return;
    try {
      _pending = PaymentRequest.fromFragment(fragment);
      _error = null;
    } on FormatException catch (e) {
      _pending = null;
      _error = e.message;
    }
    notifyListeners();
  }

  /// Reads a `#pay=` fragment and removes it from the address bar, so a
  /// reload or a bookmark does not bring the request back. Must run before
  /// Flutter reads the URL, which would otherwise treat it as a route name.
  static String? _takePayFragment() {
    try {
      final hash = web.window.location.hash;
      final body = hash.startsWith('#') ? hash.substring(1) : hash;
      if (!body.startsWith('pay=') && !body.startsWith('/pay=')) return null;
      final location = web.window.location;
      web.window.history.replaceState(null, '', '${location.pathname}${location.search}');
      return body;
    } catch (_) {
      return null;
    }
  }
}
