#![no_std]

//! PayFlex Safebox — a Soroban escrow contract for group savings.
//!
//! Enforcement lives on-chain, not in an app database:
//!   * Only the owner or a designated admin may withdraw.
//!   * There can never be more than MAX_ADMINS (= 3) admins.
//!   * Contributions and withdrawals are recorded in the contract's own
//!     storage ledger AND emitted as events — visible to every member
//!     through the Stellar indexer; PayFlex's backend cannot rewrite them.
//!
//! Funds are held by the contract's own address (see `init`). Assets are
//! SAC token contracts: pass the native-XLM SAC or an issued asset's SAC
//! address at init — the contract is asset-agnostic by design, so nothing
//! here hardcodes a network or an asset that could drift from reality.
//!
//! NOTE ON WITHDRAWALS AND AUTH: a withdrawal moves funds held by the
//! contract's own address. Soroban treats transfers originating inside a
//! contract's invocation frame as authorized by that contract when the
//! contract IS the invoker — no extra auth entries are required for the
//! token transfer itself. Only the CALLER's authorization is enforced here
//! (require_auth on owner/admin), which is the security boundary.

use soroban_sdk::{contract, contracterror, contractimpl, contracttype, Address, Env, String, Vec};

#[cfg(test)]
mod test;

/// Hard cap required by the product spec: a Safebox never has more than
/// three admins. Enforced in `add_admin`, not just documented.
pub const MAX_ADMINS: u32 = 3;

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum DataKey {
    Owner,
    Token,
    Admins,
    Closed,
    Ledger,
}

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum SafeboxError {
    AlreadyInitialized = 1,
    NotInitialized = 2,
    Unauthorized = 3,
    AdminLimitReached = 4,
    NotAnAdmin = 5,
    AlreadyAnAdmin = 6,
    Closed = 7,
    InvalidAmount = 8,
}

/// Event-ledger entry. Stored in contract state AND published as an event,
/// so members can read the ledger directly from contract state even before
/// an indexer surfaces the events.
#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LedgerEntry {
    pub entry_type: String, // "contribution" | "withdrawal"
    pub member: Address,
    pub amount: i128,
    pub created_at: u64,
}

#[contract]
pub struct SafeboxContract;

#[contractimpl]
impl SafeboxContract {
    /// Initializes the safebox. `token` is the SAC contract address of the
    /// asset being escrowed (native XLM SAC or an issued asset's SAC).
    /// Funds are held by the contract's own address.
    pub fn init(env: Env, owner: Address, token: Address) -> Result<(), SafeboxError> {
        let storage = env.storage().persistent();
        if storage.has(&DataKey::Owner) {
            return Err(SafeboxError::AlreadyInitialized);
        }
        owner.require_auth();

        storage.set(&DataKey::Owner, &owner);
        storage.set(&DataKey::Token, &token);
        storage.set(&DataKey::Admins, &Vec::<Address>::new(&env));
        storage.set(&DataKey::Closed, &false);
        storage.set(&DataKey::Ledger, &Vec::<LedgerEntry>::new(&env));
        Ok(())
    }

    /// A member (or the owner) contributes `amount` of the escrowed asset to
    /// the safebox. The contributor must authorize the transfer out of their
    /// own balance (require_auth below covers the token transfer's `from`).
    pub fn contribute(env: Env, member: Address, amount: i128) -> Result<(), SafeboxError> {
        let storage = env.storage().persistent();
        if !storage.has(&DataKey::Owner) {
            return Err(SafeboxError::NotInitialized);
        }
        if amount <= 0 {
            return Err(SafeboxError::InvalidAmount);
        }
        Self::ensure_open(&storage)?;

        let token: Address = storage
            .get(&DataKey::Token)
            .ok_or(SafeboxError::NotInitialized)?;
        let token_client = soroban_sdk::token::Client::new(&env, &token);
        member.require_auth();
        token_client.transfer(&member, &env.current_contract_address(), &amount);

        Self::record(&env, &storage, "contribution", &member, amount);
        Ok(())
    }

    /// Withdraw `amount` to `to`. ONLY the owner or an admin may call this —
    /// this is the on-chain enforcement the old app-level Safebox could only
    /// promise. The `to` recipient is unconstrained (caller's choice), but
    /// the CALLER is hard-gated on-chain.
    pub fn withdraw(
        env: Env,
        caller: Address,
        to: Address,
        amount: i128,
    ) -> Result<(), SafeboxError> {
        let storage = env.storage().persistent();
        let owner: Address = storage
            .get(&DataKey::Owner)
            .ok_or(SafeboxError::NotInitialized)?;
        if amount <= 0 {
            return Err(SafeboxError::InvalidAmount);
        }
        Self::ensure_open(&storage)?;

        let is_owner = caller == owner;
        let is_admin = !is_owner
            && storage
                .get::<_, Vec<Address>>(&DataKey::Admins)
                .unwrap_or(Vec::new(&env))
                .contains(&caller);
        if !is_owner && !is_admin {
            return Err(SafeboxError::Unauthorized);
        }

        caller.require_auth();
        let token: Address = storage
            .get(&DataKey::Token)
            .ok_or(SafeboxError::NotInitialized)?;
        let token_client = soroban_sdk::token::Client::new(&env, &token);
        token_client.transfer(&env.current_contract_address(), &to, &amount);

        Self::record(&env, &storage, "withdrawal", &caller, amount);
        Ok(())
    }

    /// Adds an admin. Owner-only. Enforces the 3-admin cap on-chain.
    pub fn add_admin(env: Env, caller: Address, admin: Address) -> Result<(), SafeboxError> {
        let storage = env.storage().persistent();
        let owner: Address = storage
            .get(&DataKey::Owner)
            .ok_or(SafeboxError::NotInitialized)?;
        if caller != owner {
            return Err(SafeboxError::Unauthorized);
        }
        if admin == owner {
            return Err(SafeboxError::AlreadyAnAdmin);
        }
        caller.require_auth();

        let mut admins: Vec<Address> = storage
            .get(&DataKey::Admins)
            .unwrap_or(Vec::new(&env));
        if admins.len() >= MAX_ADMINS {
            return Err(SafeboxError::AdminLimitReached);
        }
        if admins.contains(&admin) {
            return Err(SafeboxError::AlreadyAnAdmin);
        }
        admins.push_back(admin);
        storage.set(&DataKey::Admins, &admins);
        Ok(())
    }

    /// Removes an admin. Owner-only.
    pub fn remove_admin(env: Env, caller: Address, admin: Address) -> Result<(), SafeboxError> {
        let storage = env.storage().persistent();
        let owner: Address = storage
            .get(&DataKey::Owner)
            .ok_or(SafeboxError::NotInitialized)?;
        if caller != owner {
            return Err(SafeboxError::Unauthorized);
        }
        caller.require_auth();

        let mut admins: Vec<Address> = storage
            .get(&DataKey::Admins)
            .unwrap_or(Vec::new(&env));
        let index = admins.first_index_of(&admin).ok_or(SafeboxError::NotAnAdmin)?;
        admins.remove(index);
        storage.set(&DataKey::Admins, &admins);
        Ok(())
    }

    /// Closes the safebox. Owner-only. Withdrawals/contributions refuse
    /// afterwards; balances must be withdrawn BEFORE closing.
    pub fn close(env: Env, caller: Address) -> Result<(), SafeboxError> {
        let storage = env.storage().persistent();
        let owner: Address = storage
            .get(&DataKey::Owner)
            .ok_or(SafeboxError::NotInitialized)?;
        if caller != owner {
            return Err(SafeboxError::Unauthorized);
        }
        caller.require_auth();
        storage.set(&DataKey::Closed, &true);
        Ok(())
    }

    // ----- read-only views (no auth) -----

    pub fn get_owner(env: Env) -> Result<Address, SafeboxError> {
        env.storage()
            .persistent()
            .get(&DataKey::Owner)
            .ok_or(SafeboxError::NotInitialized)
    }

    pub fn get_token(env: Env) -> Result<Address, SafeboxError> {
        env.storage()
            .persistent()
            .get(&DataKey::Token)
            .ok_or(SafeboxError::NotInitialized)
    }

    pub fn get_admins(env: Env) -> Result<Vec<Address>, SafeboxError> {
        env.storage()
            .persistent()
            .get(&DataKey::Admins)
            .ok_or(SafeboxError::NotInitialized)
    }

    pub fn is_closed(env: Env) -> Result<bool, SafeboxError> {
        env.storage()
            .persistent()
            .get(&DataKey::Closed)
            .ok_or(SafeboxError::NotInitialized)
    }

    /// The contract's own ledger of contributions/withdrawals. Every entry
    /// is also emitted as an event at write time, so indexers can surface
    /// them for the app's UI.
    pub fn get_ledger(env: Env) -> Result<Vec<LedgerEntry>, SafeboxError> {
        env.storage()
            .persistent()
            .get(&DataKey::Ledger)
            .ok_or(SafeboxError::NotInitialized)
    }

    // ----- internal -----

    fn ensure_open(storage: &soroban_sdk::storage::Persistent) -> Result<(), SafeboxError> {
        if storage.get::<_, bool>(&DataKey::Closed).unwrap_or(false) {
            return Err(SafeboxError::Closed);
        }
        Ok(())
    }

    fn record(
        env: &Env,
        storage: &soroban_sdk::storage::Persistent,
        entry_type: &str,
        member: &Address,
        amount: i128,
    ) {
        let entry = LedgerEntry {
            entry_type: String::from_str(env, entry_type),
            member: member.clone(),
            amount,
            created_at: env.ledger().timestamp(),
        };

        let mut ledger: Vec<LedgerEntry> = storage
            .get(&DataKey::Ledger)
            .unwrap_or(Vec::new(env));
        ledger.push_back(entry.clone());
        storage.set(&DataKey::Ledger, &ledger);

        env.events()
            .publish((String::from_str(env, "safebox_ledger"),), entry);
    }
}
