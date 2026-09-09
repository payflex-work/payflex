/// Maps Stellar's own transaction/operation result codes to specific,
/// honest messages — never a generic "transfer failed." These codes are
/// part of Stellar's protocol (stable across SDKs/networks), not
/// something this app invents: https://developers.stellar.org/docs/learn/encyclopedia/errors-and-error-codes/anatomy-of-a-transaction/error-codes.
class StellarErrors {
  static const Map<String, String> _operationMessages = {
    'op_underfunded': "You don't have enough balance to send this amount.",
    'op_no_destination': "That destination account doesn't exist on the network yet — "
        'it needs to be funded (e.g. via Friendbot on testnet, or a minimum-balance '
        'payment on mainnet) before it can receive anything.',
    'op_no_trust': "The recipient hasn't set up a trustline for this asset yet — "
        'they need to add it before you can send it to them.',
    'op_line_full': "This would push the recipient's balance past their trustline "
        'limit for this asset.',
    'op_not_authorized': 'This asset requires issuer authorization, and this account '
        "isn't authorized to hold or send it.",
    'op_no_issuer': "This asset's issuer account doesn't exist.",
    'op_low_reserve': 'This would drop the account below the minimum XLM reserve '
        'required to stay open.',
    'op_invalid_limit': 'That trustline limit is invalid.',
  };

  static const Map<String, String> _transactionMessages = {
    'tx_bad_seq': 'This transaction is out of sequence — reload and try again.',
    'tx_insufficient_balance': "Not enough XLM to cover this transaction's fee.",
    'tx_insufficient_fee': 'The network fee offered was too low — try again.',
    'tx_too_late': 'This transaction took too long to submit and expired — try again.',
    'tx_bad_auth': "This transaction's signature is invalid.",
    'tx_no_source_account': "This account doesn't exist on the network yet.",
  };

  /// The single most useful message across every operation/transaction
  /// result code Horizon returned — operation-level codes are more
  /// specific than the transaction-level one, so they take priority.
  static String describe({String? transactionResultCode, List<String?>? operationResultCodes}) {
    for (final code in operationResultCodes ?? const []) {
      if (code != null && _operationMessages.containsKey(code)) {
        return _operationMessages[code]!;
      }
    }
    if (transactionResultCode != null && _transactionMessages.containsKey(transactionResultCode)) {
      return _transactionMessages[transactionResultCode]!;
    }
    String? firstOperationCode;
    for (final code in operationResultCodes ?? const []) {
      if (code != null) {
        firstOperationCode = code;
        break;
      }
    }
    final rawCode = firstOperationCode ?? transactionResultCode;
    return rawCode != null
        ? 'Stellar rejected this transaction ($rawCode).'
        : 'Stellar rejected this transaction for an unknown reason.';
  }
}
