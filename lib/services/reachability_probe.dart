import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Sends a body-less, credential-free no-cors GET. The promise resolves when
/// the server answers at all (the response stays opaque) and rejects when it
/// cannot be reached.
Future<bool> probeReachable(Uri uri) async {
  try {
    await web.window
        .fetch(
          uri.toString().toJS,
          web.RequestInit(
            method: 'GET',
            mode: 'no-cors',
            credentials: 'omit',
            cache: 'no-store',
          ),
        )
        .toDart
        .timeout(const Duration(seconds: 8));
    return true;
  } catch (_) {
    return false;
  }
}
