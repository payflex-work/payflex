# PayFlex Offline Payment Protocol & Optical Fountain Transport Specification

**Version:** 1.0.0  
**Status:** Canonical Implementation  
**Audience:** Core Engineering, Security Auditors, Compliance & Product Teams  

---

## 1. Executive Summary

In emerging microfinance markets, mobile network coverage is frequently degraded, congested, or entirely offline. Traditional digital payments fail unconditionally when either party loses connectivity.

PayFlex solves this with a **cryptographically-honest, zero-connectivity payment protocol** coupled with a **loss-tolerant Optical Fountain Transport**. Two physical devices can negotiate, authorize, and verify a genuine payment in total airplane mode using only their screens and cameras.

### Core Guarantees

1. **Tamper-Evident Integrity**: All requests and confirmations are canonicalized deterministically, hashed with SHA-256, and signed with device-bound Ed25519 keypairs.
2. **Loss-Tolerant Streaming**: Animated QR codes transmit data via Luby Transform (LT) fountain codes. Frames can arrive out of order or experience >50% frame drop, yet reconstruct the original payload with zero back-channel.
3. **Double-Spend Prevention (Local)**: The **Offline Reserve** model enforces monotonic sequence numbers and a continuous cryptographic state-hash chain against a pre-authorized allowance.
4. **Honest UI Representation**: Offline payments are explicitly badged as **"Payment verified — settlement pending"** until real reconciliation against BMONI occurs upon reconnection.

---

## 2. Protocol Flow & Architecture

```
   ┌───────────────────────┐                        ┌───────────────────────┐
   │    RECEIVER DEVICE    │                        │     SENDER DEVICE     │
   │  (Merchant / Peer)    │                        │  (Offline Payer)      │
   └──────────┬────────────┘                        └──────────┬────────────┘
              │                                                │
   (1) Create PaymentRequest                                   │
       (Amount, Currency, Nonce)                               │
       Sign with Device Ed25519                                │
              │                                                │
   (2) Stream Animated Optical QR ═══════════════════════════> │ (3) Scan Fountain Frames
       (PF_FTN:1:... chunks)       [Camera Scan - No Net]       │     Peeling Decoder solves K blocks
              │                                                │     Verifies Request Checksum & Sig
              │                                                │
              │                                                │ (4) Spend from Offline Reserve
              │                                                │     Check Allowance & Expiry
              │                                                │     Produce OfflineAuthorization
              │                                                │     Create PaymentConfirmation
              │                                                │
              │ <═════════════════════════════════════════════ │ (5) Stream Animated Optical QR
   (6) Scan Confirmation           [Camera Scan - No Net]       │     (Signed PaymentConfirmation)
       Verify binding to Request                               │
       Record Verified Claim                                   │
              │                                                │
     [Both Devices Store Local State · Status: Settlement Pending]
              │                                                │
    ─────── CONNECTION RESTORED ──────────────────────────────────────── connection restored ───────
              │                                                │
              │                                                │ (7) Sync & Redeem Queue
              │                                                │     Submit to BMONI Transfer API
              │                                                │     Sign with EVM Owner Key (PIN)
              │                                                │     Status flips: SETTLED
              ▼                                                ▼
```

---

## 3. Canonical Payment Protocol (`PaymentProtocol`)

### 3.1 `PaymentRequest` Payload

Constructed by the receiver. Carries all terms of the transaction:

| Field | Type | Description |
|---|---|---|
| `version` | String | Protocol identifier (`pf-payreq-v1`) |
| `requestId` | String | Unique UUID v4 for this transaction |
| `merchantId` | String | PayTag handle or BMONI User ID |
| `merchantName` | String? | Human-readable display name |
| `amountMinorUnits` | Integer | Amount in integer minor units (e.g. `500000` for ₦5,000.00) |
| `currency` | String | ISO-4217 code (`NGN`, `USD`, `CAD`, `EUR`, `MXN`) |
| `note` | String? | Optional memo or invoice reference |
| `nonce` | String | Cryptographic one-time nonce |
| `createdAt` | ISO-8601 UTC | Creation timestamp |
| `expiresAt` | ISO-8601 UTC | Expiration timestamp (e.g. +30 minutes) |
| `merchantPublicKey` | Hex String | 32-byte Ed25519 public key of merchant device |
| `checksum` | Hex String | SHA-256 hash over deterministic canonical string |
| `signature` | Hex String | 64-byte Ed25519 signature over checksum |

#### Canonical String Format

Before hashing and signing, fields are arranged in lexicographical key order:

```
pf-payreq-v1|amountMinorUnits=<int>|createdAt=<iso>|currency=<curr>|expiresAt=<iso>|merchantId=<id>|merchantName=<name>|merchantPublicKey=<hex>|nonce=<nonce>|note=<note>|requestId=<id>
```

### 3.2 `PaymentConfirmation` Payload

Constructed by the sender upon authorizing payment. Closes the optical loop:

| Field | Type | Description |
|---|---|---|
| `version` | String | Protocol identifier (`pf-payconf-v1`) |
| `confirmationId` | String | Unique UUID v4 for this confirmation |
| `requestId` | String | Strictly bound to the original `PaymentRequest.requestId` |
| `payerId` | String | Payer BMONI User ID or PayTag |
| `payerPublicKey` | Hex String | 32-byte Ed25519 public key of payer device |
| `amountMinorUnits` | Integer | Exact amount authorized |
| `currency` | String | Matching currency |
| `status` | String | `RESERVE_PENDING` (offline) or `SETTLED` (online BMONI) |
| `authorizationId` | String? | ID of the chained `OfflineAuthorization` |
| `timestamp` | ISO-8601 UTC | Confirmation issue timestamp |
| `checksum` | Hex String | SHA-256 hash over canonical confirmation string |
| `signature` | Hex String | 64-byte Ed25519 signature by payer device over checksum |

### 3.3 Replay Protection

The receiver maintains a persistent `ReplayProtector` store. Any received request or confirmation whose `requestId` or `nonce` was previously recorded is rejected with a `PaymentProtocolException`.

---

## 4. Optical Fountain Transport (`AnimatedOpticalQr`)

Standard QR codes suffer severe optical density limits when containing cryptographic signatures. Splitting data into fixed sequential frames (e.g., frame 1/5, 2/5...) fails if a single frame is repeatedly missed due to camera glare or frame drops.

PayFlex solves this with an **LT (Luby Transform) Fountain Code**:

### 4.1 Encoding Mechanism

1. **Source Slicing**: The payload is split into $K$ source blocks of size $B$ (default 48 bytes).
2. **Infinite Packet Generation**:
   - Packets $0 \dots K-1$ are emitted as systematic degree-1 packets (enabling immediate decoding in ideal optical conditions).
   - Subsequent packets ($seq \ge K$) sample degree $d \in [1, K]$ via a Robust Soliton probability distribution and combine $d$ distinct blocks using bitwise XOR ($\oplus$).
3. **Packet Serialization**: Packets are formatted compactly:
   ```
   PF_FTN:1:<sessionId>:<seq>:<k>:<totalLength>:<checksum>:<seed>:<base64XorData>
   ```
4. **Frame Rendering**: Rendered as a QR code regenerating every 150–220ms with a pulsing visual frame ticker.

### 4.2 Peeling Elimination Decoder

1. **Session Locking**: Decoder locks to the first detected `sessionId`, discarding frames from other sessions.
2. **Linear Reduction**: As encoded packets arrive, all already-solved blocks are XOR-subtracted:
   $$E_{\text{new}} = E_{\text{in}} \oplus \bigoplus_{j \in \text{solved}} S_j$$
3. **Cascade Resolution**: When an equation is reduced to degree 1, a new source block $S_i$ is solved. It is immediately cascaded through all pending equations in memory.
4. **Integrity Validation**: Once all $K$ blocks are solved, the payload is concatenated, sliced to `totalLength`, and validated against the SHA-256 payload checksum before release.

---

## 5. Device Cryptographic Keys vs. BMONI Wallet Keys

### Critical Architectural Boundary

| Dimension | BMONI Smart Wallet Key | Device Protocol Key |
|---|---|---|
| **Algorithm** | ECDSA secp256k1 (EIP-191) | Ed25519 (RFC 8032) |
| **Authentication** | 6-digit user PIN prompt | On-device hardware secure storage |
| **Network Need** | Requires online challenge from BMONI | Purely offline, zero network access |
| **Scope** | Authorizes custodial on-chain balance movement | Proves message authenticity from this specific device |
| **Identity / KYC** | Legally verified via BMONI KYC Tier | Machine-level device identity only |

> [!IMPORTANT]
> A valid signature from a Device Key proves:  
> *"This specific physical device created and authorized this exact message."*  
> It does **not** prove legal identity or replace BMONI KYC verification.

---

## 6. The Offline Reserve Model (`OfflineReserveService`)

Moving money without an internet connection requires pre-authorizing spendable value while online, then issuing cryptographically-chained commitments against that hold while offline.

### 6.1 `ReserveAllowance` Provisioning (Online)

While connected, the user provisions a spendable allowance:
- Amount: e.g. ₦20,000 NGN.
- Validity: 24 hours (configurable).
- State Hash Root: SHA-256 of the initial allowance certificate.
- Signed by the device key and stored in secure persistence.

*(Note: In current BMONI sandbox environments where an on-chain custodial hold primitive is pending, this allowance functions as a device-signed commitment against the user's available balance).*

### 6.2 `OfflineAuthorization` Chaining (Offline)

When spending offline:
1. `remainingAmountMinorUnits` is checked against requested amount.
2. The monotonic `sequenceNumber` is incremented ($seq = seq_{\text{prev}} + 1$).
3. The new state hash is computed by chaining the previous state hash:
   $$\text{StateHash}_n = \text{SHA-256}(\text{CanonicalAuth}_n \mathbin{\Vert} \text{StateHash}_{n-1})$$
4. The device signs $\text{StateHash}_n$ with Ed25519.
5. The authorization is strictly bound to `requestId` and `merchantId`.

---

## 7. Real-World Security Limitations & Trust Model

In compliance with financial integrity standards, PayFlex documents its exact security boundaries:

### What the Protocol Enforces
- **Single-Device Overspending**: A single device cannot issue authorizations exceeding its provisioned allowance; local sequence numbers and balance decrements are enforced atomically.
- **Single-Merchant Replay**: An authorization cannot be submitted to a different recipient or reused for a different request because it is bound to `requestId` and `merchantId`.
- **Payload Tampering**: Any modification of amounts, currencies, timestamps, or recipient IDs invalidates the SHA-256 checksum and Ed25519 signature.

### Real-World Limitation (Device State Cloning)
If an attacker makes a byte-for-byte clone of the entire mobile operating system storage and presents the same offline authorization to two different offline merchants before either reconnects, both offline merchants will verify the authorization as genuine.

**Mitigation & Defense**:
1. Hardware-backed secure enclaves with monotonic hardware counters (where available on modern iOS/Android chipsets).
2. Defined settlement redemption windows (24–48h) and first-seen redemption reconciliation at the BMONI backend layer.
3. Merchant risk controls: limiting single offline transaction sizes (e.g. max ₦10,000 per offline claim).

---

## 8. Reconciliation & Redemption Pipeline (`OfflineRedemptionService`)

When connectivity returns:
1. The app detects network restoration or the user taps **"Sync & Redeem"**.
2. For each pending `OfflineAuthorization`:
   - Checks validity against the 48-hour redemption window. Authorizations older than 48 hours are transitioned to `EXPIRED`.
   - Invokes `ApiClient.createTransfer(...)` with BMONI.
   - Retrieves the async EIP-191 sign payload hash.
   - Prompts the user for their 6-digit PIN to sign via `WalletService.signDigest(...)`.
   - Submits the signed proposal.
3. Upon BMONI confirmation, the local record transitions from `PENDING` to `SETTLED`, and is removed from the pending queue.
4. If settlement fails (e.g., insufficient account balance at real settlement time), the transaction is marked as `FAILED` with detailed diagnostics surfaced to the user.

---

## 9. UI & Honesty Guidelines

- **Status Labeling**:
  - Offline Reserve spend: **"Payment verified — settlement pending"** (Tone: `PfTone.info`, blue/amber badge).
  - BMONI settled transfer: **"Settled"** (Tone: `PfTone.success`, emerald badge).
- **Confirmation Payoff**: The animated ribbon confirmation clearly denotes whether settlement occurred in real time or via offline reserve.
- **Receipt Transparency**: Receipts clearly state:  
  *"Settlement: Signed on your device · Offline Reserve pending BMONI settlement"*.
