# Changelog

All notable changes to this project are documented in this file.

This project follows a release-oriented changelog style inspired by Keep a Changelog.

## [Unreleased]

### Added

- No unreleased changes yet.

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
