enum TxDirection { received, sent, selfTransfer }

class TransactionModel {
  final String txid;
  final double amount;
  final TxDirection direction;
  final int confirmations;
  final DateTime? timestamp;
  final String? counterpartyAddress; // recipient (sent) or sender (received)

  const TransactionModel({
    required this.txid,
    required this.amount,
    required this.direction,
    required this.confirmations,
    this.timestamp,
    this.counterpartyAddress,
  });

  bool get isConfirmed => confirmations > 0;
  bool get isPending => confirmations == 0;

  String get shortTxid => '${txid.substring(0, 8)}…${txid.substring(txid.length - 6)}';
}
