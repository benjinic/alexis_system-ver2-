# Phase 0.3-B: Unified Payment Ledger — Technical Implementation Plan

Status: **DESIGN ONLY / NOT DEPLOYED**  
Owner: Alexis Tailor management; developer review required.  
Date: 2026-11-05  
Base: `main` (read-only source inspection)

## 1. Confirmed business rules

- `deposit` means **payment actually received**, not pledged or invoiced.
- Existing `payments[]` means **balance payments** (not deposit). `balancePayment` is the sum, `balancePaymentMethod` and `balancePaidDate` represent the last entry.
- `paymentMethod` is the **deposit payment method**.
- Original deposit payment timestamp is **not available** in most legacy records; **do not** equate `createdAt` with confirmed receipt date.
- `completed` in `pos_page.dart` currently means `balance <= 0`; it is **not proof of delivery or workshop completion**.
- Pre-2024 data is historical/estimated; 2024 transition period; never present estimated records as independently verified financial facts.

## 2. Findings verified in current repository

| File | Observed behavior | Engineering consequence |
|---|---|---|
| `lib/pages/pos_page.dart` around 799-865 | `balancePayment = sum(_payments.amount)`; `balancePaidDate = _payments.last.paidAt`; `paymentMethod = _selectedPaymentMethod` | Preserve deposit/balance distinction; do not add `payments[]` on top of `balancePayment`. |
| `lib/pages/pos_page.dart` around 1562-1758 | Employee adds `BalancePayment(amount,method,paidAt)` | Later payments can have different receipt dates. |
| `lib/models/order.dart` around 169-195 | Missing `payments[]` synthesized from old summary; missing date falls back to `DateTime.now()` | This date is synthetic and MUST NOT be treated as a verified receipt date or migrated as if known. |
| `lib/pages/dashboard_page.dart` around 295-306 | Deposit reported by order `createdAt`, total balance payments reported by last `balancePaidDate` | Daily receipts can be misallocated. |
| `lib/services/database_service.dart` around 143-154, 330-364 | POS client directly writes financial summary fields in `orders` | Ledger writes must not coexist with uncoordinated client summary writes. |
| `firestore.rules` around 85-188 and 361-366 | Staff can update financial summary fields, and delete orders | Need controlled ledger write authority, order deletion protections, and explicit subcollection rules. |
| `functions/index.js` around 512-548 | Existing aggregation triggers can update orders | Verify ledger summary writes do not create trigger cycles or replace historical cost values. |

## 3. Proposed schema (new records)

Path: `orders/{orderId}/payment_records/{paymentId}`

```json
{
  "schemaVersion": 1,
  "type": "deposit",
  "direction": "receipt",
  "amountCents": 300000,
  "currency": "HKD",
  "method": "Cash",
  "paidAt": "Firestore Timestamp (nullable only for marked historical imports)",
  "paidAtPrecision": "exact | date_only | unknown",
  "recordedAt": "server timestamp",
  "recordedBy": "Firebase Auth UID or migration service identity",
  "status": "posted",
  "source": "pos_v2 | legacy_import",
  "idempotencyKey": "unique client operation ID",
  "originalPaymentId": null,
  "migrationEvidence": null
}
```

Rules: positive integer `amountCents`, valid type `deposit | balance | refund`, valid `direction` (`receipt` for deposit/balance, `outflow` for refund), currency HKD, immutable amount/time/type once posted. A refund links to the original payment and is a **separate** record. Voiding should record who/when/why; do not erase financial history. Track server-side `createdAt` separately from client-asserted `paidAt` when useful.

**Important:** A Firestore subcollection is NOT deleted automatically if its parent document is deleted. The current `orders/{orderId}` rule permits staff deletion. Before production rollout, block or replace hard deletes with a controlled archival workflow, including associated payment records.

## 4. Authority and atomicity

**Preferred write path:** authenticated, App Check-aware Cloud Function callable/HTTPS endpoint with explicit staff authorization and a Firestore transaction.

1. Validate auth, staff membership, amount, currency, type, date, and refund authorization.
2. Require a stable idempotency key; reject reuse with a different payload. A retry with the same key returns the original result.
3. Transaction reads the order, checks the latest ledger state / version and permitted outstanding amount; blocks overpayment or applies defined credit-handling policy (management approval required).
4. Create exactly one payment event and update order derived payment summaries atomically. Legacy summaries remain **derived compatibility outputs**, never a second posting source.
5. Use a server-owned ledger mode/rollout marker (e.g. `paymentLedgerVersion`) to route old and new orders deterministically.
6. Enforce rules: staff may read permitted ledger records, but **client direct create/update/delete of ledger events is denied**. Admin SDK may bypass rules, so backend authorization is mandatory.
7. Disable direct client edits to `deposit`, `balancePayment`, `balancePaymentMethod`, `balancePaidDate`, `balance`, `payments`, `paymentMethod` for ledger-enabled orders, while retaining backward-compatible old-order behavior until cutover. Explicitly test this with Firestore Emulator.
8. Ledger-derived receipt reports must not sum the same money from both ledger events and legacy summary fields.

**Do not deploy a feature that writes ledger events while existing `updateOrder` can overwrite those order payment summaries.** Order editing must use a versioned, transaction-safe strategy, and payment mutation must be separate from generic order edits.

## 5. Reconciliation logic

For a ledger-enabled order:
- `netReceiptsCents = sum(posted receipts) - sum(posted refunds)`.
- `balanceCents = max(0, order.totalCents - netReceiptsCents)`, subject to explicit rules for overpayment/credit.
- `deposit` summary = net deposit-category receipts per approved policy.
- `balancePayment` summary = net balance-category receipts per approved policy.
- Today's receipts use **actual payment event paidAt in Asia/Hong_Kong**; no implicit assumption that `createdAt` is a receipt date.
- Unknown legacy receipt dates are included in lifetime/unknown-date totals, **not** silently allocated to particular days.
- Order sales (non-cancelled orders by `createdAt`) are separate from receipts (payment events by `paidAt`).
- Refunds, cancellations, and deposits retained against cancelled orders require explicit finance policy. A cancelled sale does not imply the historical cash receipt never occurred.
- Never infer `paidAt` from fallback `DateTime.now()` produced during legacy deserialization.

For a legacy order:
- Audit `deposit + balancePayment + balance == total`, with tolerance of at most one cent for legacy double representations and separate overpayment flags.
- Audit `balancePayment == sum(payments[].amount)`; when `payments[]` absent, treat a positive legacy balancePayment as a **single summary**, not an additional payment.
- Missing payment timestamps or ambiguous dates are quality findings, not zero-valued receipts.
- Treat `balancePaymentMethod` and `balancePaidDate` as cached last-payment values, not independent events.
- Avoid printing customer names, phones, measurements or notes in MCP output.

## 6. Implementation slices (future PRs)

1. **Read-only audit**: new backend/MCP audit reporting counts and anonymized order IDs, full scan completeness, and bounded date ranges; no production writes.
2. **Model + rules**: `PaymentRecord` typed model, Firestore subcollection security rules, emulator tests and service validation.
3. **Backend**: idempotent transactional post/refund/void endpoints with staff/App Check checks and summary projection; lock direct summary writes in ledger mode.
4. **POS UI**: explicit paidAt and receipt method for deposits, per-payment balance events, clear audit trail, separation of order editing and posting payments.
5. **Reporting**: replace daily receipts formula with actual ledger payment dates; keep sales reporting independent.
6. **Migration**: dry-run/preview only first, separate real and estimated records; never backfill unknown deposit paidAt as `createdAt`; log migration version and provenance.
7. **Controlled rollout**: backup, staged deployment, monitoring, rollback, approval.

## 7. Test matrix (must pass before deployment)

| Case | Expected |
|---|---|
| One deposit + one balance | Exactly 2 receipt events, correct balance |
| Three partial balance payments across 3 days | Each amount assigned to its own paidAt day |
| Deposit entered during order creation | Atomic payment record, no orphaned record |
| Deposit paid date missing on historical order | Mark unknown; no false daily receipt |
| Duplicate submit / network retry | Same idempotency key posts once |
| Parallel payment requests | Serialized aggregate and no overpayment |
| Refund, void and cancellation | Original record retained; net totals reconcile |
| Edit order price after posting | Defined adjustment policy, no silent cash rewrite |
| Completed / cancelled legacy order | No accidental write or cost recalculation |
| New order and payment model in legacy POS UI | No double counting / stale summaries |
| Direct SDK attempt to write payment record | Denied |
| Unauthorized user / non-staff access | Denied |
| Staff order delete | Blocked for ledger orders, preventing orphaned records |
| Cloud Function trigger and ledger summary write | No loop or stale overwrite |
| Midnight / month-end HKT | Correct half-open time windows |
| Historical synthesized payment dates | Never classified as verified |

## 8. Release gates / out of scope

- No live Firestore writes or production data migration under Phase 0.3-B.
- No modifications to `main`, deployment configuration, Firebase secrets, or IAM.
- No assertions of bank reconciliation without independent bank/cash receipt evidence.
- Next action: development PR(s) against this design branch and Emulator tests, followed by management review before production rollout.

## 9. Open design decisions to confirm during implementation

1. Are backdated payments allowed, by whom, and what audit reason is required?
2. When a refund applies to a partly paid order, how do legacy `deposit` and `balancePayment` summaries reflect it?
3. Should staff be able to void a posted payment, or only authorized finance/management roles?
4. Is `completed` purely paid-in-full, and what independent workshop/delivery status owns fulfilment?
5. How will historical imported deposits with unverified dates appear in daily and lifetime reports?

Nothing in this file constitutes a production migration or approval to change live data.
