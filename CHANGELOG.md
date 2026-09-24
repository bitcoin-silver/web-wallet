# Changelog

All notable changes to this project are documented in this file.

This project follows a release-oriented changelog style inspired by Keep a Changelog.

## [Unreleased]

### Added

- No unreleased changes yet.

## [3.1]

Works together with Android wallet 6.4: both use the same payment requests and `.btcs` address book files.

### Added

- Address book: a "Contacts" tab (between Assets and Send) to save, edit, search and delete labelled addresses. Contacts are stored in this browser only, are shared by every wallet opened in it, and stay after logout. Addresses are checked with the same rules as the Android wallet, and a Bitcoin Silver `bs1` address is saved in lowercase.
- Import and export of the address book as `.btcs` files, the same format as the Android wallet, so contacts can be moved between the two apps in both directions. On import, invalid contacts are skipped and known addresses get the label from the file. An incomplete or damaged file is refused and the address book is left unchanged. One exception: when the Android wallet saves over an older, longer export, part of the old file stays after the new content. If the new export is complete and its contact count matches, it is imported and the leftover part is ignored.
- Send tab: a button that fills the recipient from the address book, the contact's name shown under the recipient address, and an offer to save a new recipient after a successful send. Each contact also has a "Send" button that opens the Send tab with the address filled in.
- Payment requests on the Receive tab: enter an amount and an optional note, and the QR code becomes a `bitcoinsilver:` payment request (the same format the Android wallet uses, so its scanner can read it). "Copy Payment Link" copies a link such as `https://bitcoinsilver.top/web-wallet/#pay=...` and "Copy as Text" copies a message with the amount, address, note and link.
- Paying a request: opening a payment link fills in the Send tab with the address and amount, after the wallet is unlocked if needed. Pasting a `bitcoinsilver:` request or a payment link into the recipient field does the same. A card shows the requested amount and note, and warns when the amount is changed. Nothing is sent without the usual confirmation, the note is never put in the on-chain message, and a link can only fill in the Send form: it cannot change any setting.

### Changed

- The mobile bottom bar uses a smaller label font so its five tabs fit on a 360px screen.
- The version shown on the start, setup and settings screens now comes from one place (`Config.appVersion`).

### Privacy

- The payment request in a link sits after `#`, which browsers do not send to the server, and the wallet removes it from the address bar as soon as it has read it.

## [3.0]

### Added

- "Server connection" setting to choose the RPC server the wallet uses, on the start screen and in Settings. It has a "Reset to default" button, and a "Custom server" badge is shown whenever a non-default server is in use.
- A "Choose another server" button under the error when loading a wallet stops because the RPC server cannot be reached, so nobody is left without a way to change the server. The check itself is unchanged.
- Checks before a custom server is saved: the address must be `https://` (`http://` only for `localhost` and `127.0.0.1`), and the server must answer like a node and report the Bitcoin Silver genesis block. If a check fails, the previous setting is kept and the reason is shown (unreachable, timed out, request refused, not a node, wrong network, or CORS).
- Fixed fee limits that do not depend on the server: a fee rate above 0.01 BTCS/kvB is refused, and above 0.0004 BTCS/kvB the fee may not exceed 10% of the amount sent. If the server reports a rate above the limit, automatic fees count as unavailable and a manual fee can be entered.
- Local mock RPC node (`tool/mock_rpc_server.mjs`) and browser tests that run against it.
- Guide for importing a wallet's private key into Bitcoin Silver Core (`IMPORT_KEY_INTO_CORE.md`), linked from the README.

### Changed

- The default RPC server is unchanged and is used unless a custom one is saved. The setting is stored separately from wallet and session data, and it can only be changed from the settings screen (never from links, query parameters or the URL hash).
- Content Security Policy: connections are allowed to any `https://` server and to `http://localhost` / `http://127.0.0.1` (needed for custom servers), `object-src 'none'` is added, and `script-src` no longer allows `unsafe-inline` or `unsafe-eval` (it allows `wasm-unsafe-eval` instead).
- README: trust model, choosing a server, running your own server, the calls the wallet makes, and backup and portability. The wallet is described as community-built, and the claim that the server never sees balance information is corrected: it sees the addresses the wallet looks up.

### Removed

- The unused `btcs_rpc` browser-storage key is no longer read. Nothing in the app wrote it, but anything that could would have redirected the wallet without checks. The unused `RPC_*` entries are also gone from `dart_defines.json.example`.

## [2.9]

### Added

- Optional on-chain message field in the Send flow, embedded via a standard OP_RETURN output (up to 80 bytes).
- Live byte counter and validation for the message field, with clear warning that OP_RETURN data is permanent and publicly visible.
- Message shown in the pre-send confirmation dialog so it's reviewed before broadcast.

### Changed

- Fee estimation and transaction sizing account for the extra OP_RETURN output when a message is attached.
- Batch-sweep send path is skipped when a message is set, since a single message doesn't apply across multiple sweep transactions.

## [2.8]

### Added

- Batch-send candidate assessment for large or high-input transfers before broadcast.
- Send decision dialog with explicit options to proceed with batch, continue normal send, or cancel.
- Retry-as-batch flow when a normal send fails due to likely single-transaction constraints.
- Batch-send result acknowledgement showing multiple TXIDs and progress context.
- Migration batch candidate assessment with estimated input count, size, and batch count.
- Migration batch consent dialog explaining multiple TXIDs, partial-completion risk, and backup urgency.

### Changed

- Migration flow now supports explicit opt-in batch sweeping instead of forcing unsafe single-transaction behavior.
- Partial migration completion handling improved: successful earlier batches are preserved and users are guided to back up the new seed immediately.

## [2.7]

### Added

- Smart fee sanity guard for estimatesmartfee values.
- Baseline fallback from relayfee, incrementalfee, and mempoolminfee when smart fee is missing or unusable.
- Outlier clamp for extreme fee estimator spikes.
- Always-available manual fee mode in send flow.
- Quick revert from manual fee mode back to node fee mode.
- Expanded send preview details (inputs, fee source, fee rate, change).
- Deterministic migration sweep fee resolution before broadcast.
- Migration send path aligned with improved fee safety logic.

## [2.6]

### Added

- Migration preflight gates for unsafe sweep conditions.
- Pending-transaction hard stop before migration.
- Large send safety block for near-max unsafe single-sweep transfers.

### Changed

- Unsafe chunked migration and send behavior replaced with explicit user-facing aborts and warnings.
- Core send arithmetic hardened with satoshi-level integer math for fee/input/output calculation.

## [2.5]

### Added

- Coin control UI for manual UTXO selection.
- Live UTXO selection summary.
- UTXO All and None selection controls.
- Dynamic fee estimation by estimated transaction size.
- Real-time RPC address validation with debounce.
- Validation guardrails for dust, negative amounts, and insufficient funds.
- Confirmation accuracy based on current chain height.
- Automatic script routing for supported BTCS address types.

## [2.4]

### Added

- LiveCoinWatch price integration with periodic refresh.
- USD balance display based on BTCS market price.
- Provider-based modular architecture (models, providers, services, screens).
- BIP39 seed phrase support with 12 and 24 words.
- BIP44 derivation support.
- WIF-to-seed migration sweep flow.
- Real-time network information dashboard.

### Changed

- Security model shifted to client-side signing and signed-hex-only broadcast.
- Web runtime compatibility improvements for dart2js constraints.
- Sensitive runtime behavior hardened (in-memory keys, refresh logout, reduced sensitive logging).
