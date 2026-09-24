# BitcoinSilver Web-Wallet

## Introduction

A community-built, non-custodial web wallet for the Bitcoin Silver network. Keys are created and used in your browser, and transactions are signed on your device. It is separate from the Bitcoin Silver Core project, and it is not the only wallet for BTCS.

<p align="center">
  <img src="assets/logo.png" alt="BitcoinSilver Web-Wallet" width="600">
</p>

<p align="center">
  <strong>A community-built web wallet for Bitcoin Silver (BTCS)</strong><br>
  Built with Flutter for Web
</p>

<p align="center">
  <a href="https://bitcoinsilver.top">Website</a> •
  <a href="https://explorer.bitcoinsilver.top">Explorer</a>
</p>

## Release Notes

Detailed version history is in [CHANGELOG.md](CHANGELOG.md).

Latest release: v3.1.1 (payment request safety: unverified names, look-alike contact warning, hidden characters removed)

v3.1:

- Address book: a Contacts tab to save and search labelled addresses, with `.btcs` import and export in the same format as the Android wallet. See [Address book](#address-book).
- Payment requests: ask for an amount with a QR code, a link or a text message, and pay a request by opening its link or pasting it. See [Payment requests](#payment-requests).

v3.0 added the choice of RPC server, fixed fee limits that do not depend on the server, and this README's description of what the wallet trusts.

## Trust model

The wallet is a client-side app that runs in your browser.

- **Keys stay on your device.** Seed phrases and private keys are created and used in the browser, and transactions are signed there.
- **It reads the chain through an RPC server.** The wallet asks an RPC proxy for chain data (balances, unspent coins, fees, network information) and sends it signed transactions to broadcast.
- **The server never receives your keys or seed phrase.** It does see the addresses the wallet looks up, the signed transactions, and your IP address.
- **The wallet does not hold or have access to funds.** Whoever has your seed phrase or private key does.
- **The server is not trusted.** A dishonest server can show wrong balances or refuse to relay a transaction, but it cannot sign for you. The wallet also refuses fees above fixed limits, whatever the server reports (see [Fee limits](#fee-limits)).
- **The default server is the project's proxy.** You can replace it with any server you trust or run yourself.

## Choosing a server

By default the wallet uses the project's RPC proxy, `https://bitcoinsilver.eu/btcs-rpc`. If you never open the setting, nothing changes.

**How to change it.** Open **Server connection** on the start screen, or in **Settings** after loading a wallet. If loading a wallet stops because the server cannot be reached, a **Choose another server** button appears under the error. Enter the address of the server and press **Save**. **Reset to default** is always available. While a non-default server is in use, a **Custom server** badge is shown. The setting is stored in your browser, separately from your wallet data, and it can only be changed on this screen: not from links, query parameters or the URL hash.

**Address rules**

- `https://` only. The one exception is `http://localhost` and `http://127.0.0.1` (any port), for people running their own node. Safari may block plain `http://localhost` from a secure page; use Chrome or Firefox, or serve your node over HTTPS.
- No user name or password in the address, and nothing after a `?` or `#`. Trailing slashes are removed.

**Checks before saving.** The wallet asks the server for `getblockchaininfo` and for the hash of block 0, and the hash must be the Bitcoin Silver genesis block. If any check fails, your previous setting is kept and the message says why (unreachable, timed out, request refused, not a node, wrong network, or blocked by CORS).

**What the wallet asks the server.** JSON-RPC over HTTP `POST` with `Content-Type: application/json`, and no credentials. It expects HTTP 200 and a JSON body with a `result`.

| Call | Used for |
| --- | --- |
| `scantxoutset` | Finding the unspent coins of the wallet address (balance, coins to spend) |
| `getblockcount` | Current block height, to count confirmations |
| `getrawmempool`, `getrawtransaction` | Pending transactions, and confirmations in the history list |
| `gettxout` | The output script of a coin, when it is not already known |
| `estimatesmartfee` | Suggested fee rate |
| `getnetworkinfo`, `getmempoolinfo` | Minimum fee rates, and the Network screen |
| `getblockchaininfo`, `getmininginfo` | The Network screen, and the check when saving a server |
| `validateaddress` | Checking a recipient address |
| `sendrawtransaction` | Broadcasting a transaction the wallet has already signed |
| `getblockhash` (block 0 only) | Only when saving a server: must return `00000ea8e97e04892a03df35947ff0c4df705723f5b18be7cc6456ed16e9788e` |

**Not affected by this setting.** These are not RPC calls and always go to the same services:

- Transaction history: `GET https://explorer.bitcoinsilver.top/api/getaddress/<address>/txs`. This sends your address to the project's explorer, even when you use a custom server.
- Pending-transaction fallback: `GET https://explorer.bitcoinsilver.top/api/mempool`, used only if the RPC server cannot list the mempool.
- Price: `POST https://api.livecoinwatch.com/coins/single`. No address is sent.
- Links to the explorer and the website.

### Fee limits

The fee rate a server suggests is not trusted. Whatever the server reports, the wallet will not send a transaction if:

- the fee rate is above 0.01 BTCS/kvB, or
- the fee rate is above 0.0004 BTCS/kvB and the fee is more than 10% of the amount sent.

If the server reports a rate above the limit, automatic fees are treated as unavailable and you can enter a manual fee instead. Manual fees are checked against the same limits before signing.

## Running your own server

The RPC proxy is not part of this repository. A server that works with the wallet must:

- serve HTTPS (or be used at `http://localhost` / `http://127.0.0.1`);
- answer the calls in the table above, and forward only those. Do not expose a node's wallet or administrative methods, and do not point the wallet at a node's raw RPC port;
- allow the wallet's origin with CORS. The browser enforces this, because the wallet is hosted on GitHub Pages.

CORS requirements: answer the `OPTIONS` preflight, allow `POST` and the `Content-Type` header, and send exactly one `Access-Control-Allow-Origin` header with the origin the wallet is loaded from (for the hosted wallet: `https://bitcoinsilver.top`).

Example nginx configuration. It only adds the CORS headers; it assumes the upstream on port 8080 is your own proxy that already limits which methods can be called:

```nginx
location /btcs-rpc {
    proxy_hide_header Access-Control-Allow-Origin;   # avoid a duplicate header

    if ($request_method = OPTIONS) {
        add_header Access-Control-Allow-Origin  "https://bitcoinsilver.top" always;
        add_header Access-Control-Allow-Methods "POST, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type" always;
        add_header Access-Control-Max-Age       86400 always;
        return 204;
    }

    add_header Access-Control-Allow-Origin "https://bitcoinsilver.top" always;
    proxy_pass http://127.0.0.1:8080;
}
```

If you host the wallet somewhere else, use that origin instead.

## Backup and portability

- Back up your 12- or 24-word seed phrase, or your private key (WIF), offline. Anyone who has it controls the funds, and nobody can recover it for you.
- Your keys are not tied to this website. The private key (WIF) can be imported into Bitcoin Silver Core: see [IMPORT_KEY_INTO_CORE.md](IMPORT_KEY_INTO_CORE.md) (tested on Bitcoin Silver Core 31.1.3).
- Bitcoin Silver Core does not import seed phrases. A seed phrase only works in wallets that derive keys the same way: the first address of the BIP44 path `m/44'/0'/0'/0/0` (a native SegWit `bs1...` address).
- Step-by-step restore instructions for other wallets are not included yet.
- The address book is not part of the wallet backup. Export it from the Contacts tab (a `.btcs` file) if you want to keep it.

## Address book

- The Contacts tab stores labelled addresses in this browser's local storage. They are not encrypted, are shared by every wallet opened in this browser, and stay after logout. Clearing the site's data removes them.
- Export and import use `.btcs` files in the same format as the Android wallet, so contacts move between the two in both directions.
- Import merges: new addresses are added, known addresses get the label from the file, and invalid contacts are skipped. A damaged or incomplete file is refused without changing anything. Exports made by Android wallet 6.3 or older can end with leftover data from an older file; these are still imported when the export itself is complete.

## Payment requests

A payment request is one line of text in the BIP21 style, the same one the Android wallet uses:

```
bitcoinsilver:bs1q...?amount=1.5&message=Invoice%2042
```

- **Request money** on the Receive tab: enter an amount and an optional note. The QR code then holds the request (the Android wallet's scanner reads it). "Copy Payment Link" gives a link such as `https://bitcoinsilver.top/web-wallet/#pay=...`, and "Copy as Text" gives a short message with the amount, address, note and link.
- **Pay a request** by opening its link or pasting the request or link into the recipient field on the Send tab. If the wallet is locked, the request waits until it is unlocked. The web wallet has no camera scanner; scan request QR codes with the Android wallet.
- Anyone can make a request with any name and note, so the wallet shows them as unverified. Only your address book vouches for a name ("Saved contact: …"), a request that borrows a saved contact's name for another address gets a warning, and hidden or direction-changing characters are removed before display. Pay only requests from people you trust.
- A request only fills in the Send form. Nothing is sent without the usual review and confirmation, the note is shown to you but never written to the blockchain, and a link cannot change any setting.
- Privacy: the request in a link comes after `#`, which browsers do not send to the web server, and the wallet removes it from the address bar as soon as it has read it. Anyone who sees the link itself sees the address, amount and note.

## Technical Stack

- **Derivation**: BIP39 Mnemonic Seed / BIP44 Standard Paths.
- **Cryptography**: PointyCastle (RIPEMD160/SHA256).
- **Frontend**: Flutter Web (Optimized for performance).
- **Communication**: JSON-RPC over HTTPS.
- **Web runtime**: logic is written for strict `dart2js` constraints (for example custom 64-bit integer handling).

## Features

- **Seed Phrase Wallet**: Modern 12/24 word recovery phrases (Recommended).
- **Legacy WIF Wallet**: Support for existing raw Private Keys (WIF).
- **Send/Receive**: Full transaction support with Bech32 (bs1...) addresses and QR codes.
- **On-Chain Messages**: Attach an optional public note (up to 80 bytes) to a send via OP_RETURN.
- **Coin Control**: Advanced UTXO selection for privacy and fee optimization.
- **Choose your server**: Use the default RPC proxy or your own.
- **Address Book**: Labelled contacts, stored in this browser, with `.btcs` import/export shared with the Android wallet.
- **Payment Requests**: Request an amount by QR code, link or text; pay a request by opening its link or pasting it.
- **Glassmorphism UI**: A sleek, dark-themed interface with neon purple and gold accents.

## Security Warning

⚠️ **Web wallets are intended for convenience, not long-term high-value storage.**

- Private keys exist ONLY in memory during your active session.
- Closing the tab or refreshing the page logs you out instantly.
- Always verify the URL is `https://bitcoinsilver.top`.
- For large amounts, always use a desktop or hardware wallet.

## Optional Remembered Session (Encrypted Local Storage)

You can optionally enable "Remember Wallet On This Device" from the Settings tab.

When enabled:

- Wallet session data is encrypted and stored in browser local storage.
- The wallet can auto-restore without re-entering your seed/WIF every time.

Risk notes:

- If this device is compromised (malware/extensions), local encrypted data can still be attacked.
- In web builds, dart-define secrets are extractable from shipped assets; this improves resistance but is not absolute secrecy.
- Never enable remembered sessions on shared/public devices.

## Development

Run locally:

```bash
flutter run -d chrome --dart-define-from-file=dart_defines.json
```

or

```bash
flutter run -d web-server --web-port 8080 --dart-define-from-file=dart_defines.json
```

Tests:

```bash
flutter test                                        # unit tests

node tool/mock_rpc_server.mjs &                     # local mock node on 127.0.0.1:19911
flutter test --platform chrome test/browser         # browser tests (needs Chrome or Chromium)
```

The browser tests only talk to the local mock node.

## Building for Deployment

Build the web app:

```bash
flutter build web --release --base-href "/web-wallet/" --dart-define-from-file=dart_defines.json
```

## License

MIT License.
