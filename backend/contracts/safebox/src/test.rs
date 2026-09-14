#![cfg(test)]

use crate::{SafeboxContract, SafeboxContractClient, SafeboxError, MAX_ADMINS};
use soroban_sdk::{
    testutils::Address as _,
    token::{Client as TokenClient, StellarAssetClient},
    Address, Env, String as SdkString,
};

/// Creates a real Stellar Asset Contract (SAC) token with `admin` as its
/// admin — this is exactly what an issued asset on Stellar is, so the tests
/// exercise the same token interface the contract will see on-chain (and the
/// same one the native-XLM SAC exposes).
fn create_token_admin(env: &Env, admin: &Address) -> Address {
    env.register_stellar_asset_contract(admin.clone())
}

struct Setup {
    env: Env,
    owner: Address,
    member: Address,
    outsider: Address,
    contract_id: Address,
    token: Address,
    client: SafeboxContractClient<'static>,
}

fn setup() -> Setup {
    let env = Env::default();
    env.mock_all_auths();

    let owner = Address::generate(&env);
    let member = Address::generate(&env);
    let outsider = Address::generate(&env);
    let token = create_token_admin(&env, &owner);

    let contract_id = env.register(SafeboxContract, ());
    let client = SafeboxContractClient::new(&env, &contract_id);
    client.init(&owner, &token);

    // Fund the member so contributions can actually move tokens.
    StellarAssetClient::new(&env, &token).mint(&member, &10_000);

    Setup {
        env,
        owner,
        member,
        outsider,
        contract_id,
        token,
        client,
    }
}

#[test]
fn contribute_moves_tokens_into_the_contract() {
    let s = setup();
    s.client.contribute(&s.member, &1_000);

    let balance = TokenClient::new(&s.env, &s.token).balance(&s.contract_id);
    assert_eq!(balance, 1_000);
}

#[test]
fn member_withdrawal_is_rejected_on_chain() {
    let s = setup();
    s.client.contribute(&s.member, &1_000);

    // A plain member (not owner, not admin) must be refused BY THE CONTRACT —
    // this is the enforcement the old app-level Safebox could only promise.
    let result = s.client.try_withdraw(&s.member, &s.member, &500);
    assert_eq!(result, Err(Ok(SafeboxError::Unauthorized)));

    let balance = TokenClient::new(&s.env, &s.token).balance(&s.contract_id);
    assert_eq!(balance, 1_000);
}

#[test]
fn outsider_withdrawal_is_rejected() {
    let s = setup();
    s.client.contribute(&s.member, &1_000);

    let result = s.client.try_withdraw(&s.outsider, &s.outsider, &500);
    assert_eq!(result, Err(Ok(SafeboxError::Unauthorized)));
}

#[test]
fn owner_can_withdraw_to_any_recipient() {
    let s = setup();
    s.client.contribute(&s.member, &1_000);

    s.client.withdraw(&s.owner, &s.member, &400);

    let contract_balance = TokenClient::new(&s.env, &s.token).balance(&s.contract_id);
    assert_eq!(contract_balance, 600);
}

#[test]
fn admin_can_withdraw() {
    let s = setup();
    s.client.contribute(&s.member, &1_000);
    s.client.add_admin(&s.owner, &s.outsider);

    s.client.withdraw(&s.outsider, &s.outsider, &100);

    let contract_balance = TokenClient::new(&s.env, &s.token).balance(&s.contract_id);
    assert_eq!(contract_balance, 900);
}

#[test]
fn admin_cap_is_enforced_at_three() {
    let s = setup();

    let a1 = Address::generate(&s.env);
    let a2 = Address::generate(&s.env);
    let a3 = Address::generate(&s.env);
    let a4 = Address::generate(&s.env);

    s.client.add_admin(&s.owner, &a1);
    s.client.add_admin(&s.owner, &a2);
    s.client.add_admin(&s.owner, &a3);
    assert_eq!(s.client.get_admins().len(), MAX_ADMINS);

    let result = s.client.try_add_admin(&s.owner, &a4);
    assert_eq!(result, Err(Ok(SafeboxError::AdminLimitReached)));
}

#[test]
fn only_owner_manages_admins() {
    let s = setup();
    let result = s.client.try_add_admin(&s.member, &s.outsider);
    assert_eq!(result, Err(Ok(SafeboxError::Unauthorized)));

    s.client.add_admin(&s.owner, &s.outsider);
    let result = s.client.try_remove_admin(&s.member, &s.outsider);
    assert_eq!(result, Err(Ok(SafeboxError::Unauthorized)));
}

#[test]
fn closed_safebox_refuses_contributions_and_withdrawals() {
    let s = setup();
    s.client.contribute(&s.member, &1_000);
    s.client.close(&s.owner);

    let result = s.client.try_contribute(&s.member, &100);
    assert_eq!(result, Err(Ok(SafeboxError::Closed)));

    let result = s.client.try_withdraw(&s.owner, &s.member, &100);
    assert_eq!(result, Err(Ok(SafeboxError::Closed)));
}

#[test]
fn close_is_owner_only() {
    let s = setup();
    let result = s.client.try_close(&s.member);
    assert_eq!(result, Err(Ok(SafeboxError::Unauthorized)));
}

#[test]
fn double_init_is_rejected() {
    let s = setup();
    let result = s.client.try_init(&s.owner, &s.token);
    assert_eq!(result, Err(Ok(SafeboxError::AlreadyInitialized)));
}

#[test]
fn zero_and_negative_amounts_are_rejected() {
    let s = setup();
    let result = s.client.try_contribute(&s.member, &0);
    assert_eq!(result, Err(Ok(SafeboxError::InvalidAmount)));

    let result = s.client.try_withdraw(&s.owner, &s.member, &0);
    assert_eq!(result, Err(Ok(SafeboxError::InvalidAmount)));
}

#[test]
fn event_ledger_records_the_full_flow() {
    let s = setup();
    s.client.contribute(&s.member, &1_000);
    s.client.withdraw(&s.owner, &s.member, &400);

    let ledger = s.client.get_ledger();
    assert_eq!(ledger.len(), 2);
    assert_eq!(
        ledger.get(0).unwrap().entry_type,
        SdkString::from_str(&s.env, "contribution")
    );
    assert_eq!(ledger.get(0).unwrap().amount, 1_000);
    assert_eq!(
        ledger.get(1).unwrap().entry_type,
        SdkString::from_str(&s.env, "withdrawal")
    );
    assert_eq!(ledger.get(1).unwrap().amount, 400);
}
