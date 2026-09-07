/// Shared app state model for PayFlex.
/// In a real app this would be backed by a state solution (Riverpod/Bloc);
/// here we keep it lean for scaffolding.
class User {
  final String id;
  final String name;
  final String email;
  final VerificationStatus verification;
  final AccountTier tier;

  const User({
    required this.id,
    required this.name,
    required this.email,
    this.verification = VerificationStatus.pending,
    this.tier = AccountTier.basic,
  });
}

enum VerificationStatus {
  pending,
  verifying,
  verified,
  rejected,
}

enum AccountTier {
  basic,
  standard,
  premium,
}

/// Wallet state
class WalletState {
  final double balance;
  final String currency;
  final bool isLoading;
  final String? error;

  const WalletState({
    this.balance = 0.0,
    this.currency = 'USD',
    this.isLoading = false,
    this.error,
  });

  WalletState copyWith({
    double? balance,
    String? currency,
    bool? isLoading,
    String? error,
  }) {
    return WalletState(
      balance: balance ?? this.balance,
      currency: currency ?? this.currency,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}
