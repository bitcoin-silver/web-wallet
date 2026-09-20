import '../config.dart';

/// Outcome of checking a user-entered RPC endpoint address.
class RpcUrlResult {
  /// The normalized address when it is acceptable.
  final String? url;

  /// A user-facing explanation when it is not.
  final String? error;

  const RpcUrlResult.ok(String this.url) : error = null;
  const RpcUrlResult.invalid(String this.error) : url = null;

  bool get isValid => url != null;
}

/// Rules for the RPC endpoint address.
///
/// Applied to what the user types and again to the stored value when the app
/// starts, so a tampered stored value is ignored.
class RpcEndpointUrl {
  static const int _maxLength = 2048;

  // Printable ASCII without spaces or backslashes.
  static final RegExp _plainChars = RegExp(r'^[\x21-\x5B\x5D-\x7E]+$');
  static final RegExp _hostName = RegExp(r'^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$');
  static final RegExp _ipv6Host = RegExp(r'^[0-9a-f:.]+$');

  /// Hosts that may be used over plain http (for people running their own node).
  static bool isLocalHost(String host) =>
      host == 'localhost' || host == '127.0.0.1';

  static bool isDefault(String normalizedUrl) =>
      normalizedUrl == Config.defaultRpcUrl;

  static RpcUrlResult normalize(String input) {
    final text = input.trim();

    if (text.isEmpty) {
      return const RpcUrlResult.invalid(
          'Enter the address of the server, for example '
          'https://my-node.example.com/btcs-rpc');
    }
    if (text.length > _maxLength) {
      return const RpcUrlResult.invalid('That address is too long.');
    }
    if (!_plainChars.hasMatch(text)) {
      return const RpcUrlResult.invalid(
          'The address can only contain plain letters, numbers and symbols, '
          'with no spaces.');
    }

    final uri = Uri.tryParse(text);
    if (uri == null) {
      return const RpcUrlResult.invalid(
          'That does not look like a valid web address.');
    }

    final scheme = uri.scheme;
    if (scheme != 'https' && scheme != 'http') {
      return const RpcUrlResult.invalid('The address must start with https://');
    }
    if (!uri.hasAuthority || uri.host.isEmpty) {
      return const RpcUrlResult.invalid(
          'The address needs a server name, for example '
          'https://my-node.example.com');
    }
    if (uri.userInfo.isNotEmpty) {
      return const RpcUrlResult.invalid(
          'Remove the user name and password from the address.');
    }

    // Uri decodes percent-escapes in the host, which would make the stored
    // address differ from what was typed.
    final authorityStart = text.indexOf('//') + 2;
    final authorityEnd = text.indexOf('/', authorityStart);
    final rawAuthority = authorityEnd == -1
        ? text.substring(authorityStart)
        : text.substring(authorityStart, authorityEnd);

    final host = uri.host;
    final validHost = !rawAuthority.contains('%') &&
        (host.contains(':')
            ? _ipv6Host.hasMatch(host)
            : _hostName.hasMatch(host));
    if (!validHost) {
      return const RpcUrlResult.invalid(
          'The server name contains characters that are not allowed.');
    }

    if (scheme == 'http' && !isLocalHost(host)) {
      return const RpcUrlResult.invalid(
          'Plain http:// is only allowed for localhost or 127.0.0.1. '
          'Use https:// for any other server.');
    }
    if (uri.hasQuery || uri.hasFragment) {
      return const RpcUrlResult.invalid(
          'Remove everything after "?" or "#" from the address.');
    }
    if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
      return const RpcUrlResult.invalid('The port number is not valid.');
    }

    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final hostPart = host.contains(':') ? '[$host]' : host;
    final portPart = uri.hasPort ? ':${uri.port}' : '';
    return RpcUrlResult.ok('$scheme://$hostPart$portPart$path');
  }

  /// Short label for display, e.g. "my-node.example.com:8443".
  static String hostLabel(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    return uri.hasPort ? '$host:${uri.port}' : host;
  }
}
