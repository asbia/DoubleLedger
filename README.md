# DoubleLedger

**A double-entry ledger service with idempotent payment APIs, an append-only event log, automated reconciliation, and a documented load test and security review.**

> Working title. Status: **design phase**. Commands and endpoints below describe the intended interface. Every value marked `TBD` will be filled in only from measured results.

---

## Why this exists

Money-moving systems fail in boring ways: a client retries a request and is charged twice, two requests race and overdraw an account, a row is edited after the fact and the books no longer balance. This project builds a small ledger where those failures are prevented by design, and where each guarantee comes with a test that tries to break it.

The goals, in order:

1. **Correctness first.** Retries and concurrent requests cannot create duplicate or unbalanced transactions.
2. **Auditability.** History is immutable. Mistakes are corrected with reversing entries, never edits.
3. **Detectability.** A reconciliation job finds discrepancies between the ledger and external records.
4. **Evidence.** Performance and security claims are backed by published methodology, not assertions.

## Guarantees

| Guarantee | Enforced by | Verified by |
|---|---|---|
| Every transaction balances (debits = credits) | Service validation and a deferred constraint trigger in PostgreSQL | Unit tests and a post-run invariant check |
| A retried request never creates a second transaction | Idempotency key with a unique constraint in PostgreSQL | Concurrent duplicate-request test and crash-recovery test |
| Concurrent requests cannot overdraw an account | Ordered row locking on accounts (or optimistic locking with retry, see decision records) | Multi-threaded random-transfer test |
| History cannot be altered | Revoked `UPDATE`/`DELETE` privileges and triggers on ledger tables | Tests that attempt mutation and expect failure |
| Tampering is detectable | Hash chain across events (optional) | Chain verification job |

## Architecture

```
client ──> REST API (Spring Boot)
              │
              ├─ auth (JWT, roles: client / auditor / admin)
              ├─ idempotency layer (key, request hash, stored response)
              └─ ledger service ──> PostgreSQL
                                      ├─ accounts
                                      ├─ transactions + entries
                                      ├─ events (append-only)
                                      └─ outbox ──> (optional) Kafka

reconciliation job <── external records / simulated bank statements
metrics ──> Prometheus ──> Grafana
```

PostgreSQL is the single source of truth. Redis and Kafka are optional and only added where a decision record justifies them. Redis, if used, is a fast path in front of the idempotency table and never the authority.

### Data model

- `accounts`: id, owner, currency
- `transactions`: id, reference, created_at
- `entries`: transaction_id, account_id, direction (debit/credit), amount in integer minor units
- `events`: append-only log of every state change, optionally hash-chained
- `idempotency_keys`: client, key, request hash, status, stored response
- `outbox`: events awaiting publication (only if Kafka is used)

Money is stored as integer minor units. No floating point anywhere.

### Idempotency semantics

Clients send an `Idempotency-Key` header on every write.

| Situation | Result |
|---|---|
| New key | Request is processed and the response stored |
| Same key, same body | The original response is returned, nothing is reprocessed |
| Same key, different body | `422 Unprocessable Entity` |
| Same key while the first request is still running | `409 Conflict` |

## API (planned)

| Method | Path | Description |
|---|---|---|
| `POST` | `/v1/accounts` | Create an account |
| `POST` | `/v1/transactions` | Post a balanced transaction (requires `Idempotency-Key`) |
| `GET` | `/v1/transactions/{id}` | Fetch a transaction and its entries |
| `POST` | `/v1/transactions/{id}/reverse` | Post a reversing transaction |
| `GET` | `/v1/accounts/{id}/balance` | Current balance |
| `GET` | `/v1/reconciliation/runs/{id}` | Reconciliation report |

Example:

```http
POST /v1/transactions
Idempotency-Key: 7c1f2a9e-0b44-4d1e-9a52-3f6d8b2e1c10
Authorization: Bearer <token>

{
  "reference": "invoice-1042",
  "entries": [
    { "account": "acc_customer_1", "direction": "DEBIT",  "amount": 12500 },
    { "account": "acc_revenue",    "direction": "CREDIT", "amount": 12500 }
  ]
}
```

## Reconciliation

A simulated bank-statement generator produces CSV statements with known, injected discrepancies: missing items, duplicates, amount mismatches, and timing differences. The matcher pairs ledger entries with statement lines (exact reference match first, then amount plus a date window) and outputs a categorized discrepancy report.

The reconciler is tested by checking that it reports every injected discrepancy and nothing else. Results: `TBD`.

## Security

A STRIDE-style threat model is in `docs/threat-model.md`. The API is then attacked directly:

| Attack | Target | Status |
|---|---|---|
| Replay of captured requests | Idempotency layer | TBD |
| Double-spend race conditions | Balance checks, locking | TBD |
| SQL injection | All inputs | TBD |
| Broken authorization (accessing another user's account) | Account and transaction endpoints | TBD |
| Negative, zero, or overflowing amounts | Validation | TBD |
| Mass assignment | Request binding | TBD |

Each finding becomes a failing test, a fix, and an entry in `docs/security-findings.md`. Total vulnerabilities found and fixed: `TBD`.

## Load testing

Load tests use k6 with an open-model (constant arrival rate) executor, which avoids coordinated omission and gives honest tail latencies.

Scenarios:

1. Mixed read/write traffic across many accounts
2. Hot-account contention (many writers on a few accounts)
3. Retry storm (many duplicate idempotency keys)

Every run records the hardware, JVM and Postgres settings, connection pool size, and warm-up period, and ends with an invariant check (all balances sum to zero, no duplicate transactions).

| Scenario | Throughput (tx/s) | p95 (ms) | p99 (ms) | Invariants |
|---|---|---|---|---|
| Mixed traffic | TBD | TBD | TBD | TBD |
| Hot-account contention | TBD | TBD | TBD | TBD |
| Retry storm | TBD | TBD | TBD | TBD |

Hardware: `TBD`. Full methodology: `docs/load-testing.md`.

## Quickstart (planned)

Requirements: Java 21, Docker.

```bash
git clone https://github.com/<your-username>/double-ledger.git
cd double-ledger

docker compose up -d postgres        # database (add kafka/redis if enabled)
./mvnw spring-boot:run               # run the service

./mvnw verify                        # unit and integration tests (Testcontainers)
k6 run loadtest/mixed.js             # load test
```

## Repository layout

```
src/main/java/      service code (api, ledger, idempotency, reconciliation, security)
src/main/resources/ Flyway migrations, configuration
src/test/java/      unit, integration, concurrency, and crash-recovery tests
loadtest/           k6 scenarios
tools/              bank statement simulator
docs/               design doc, threat model, security findings, load-test method, decision records
```

## Tech stack

Java 21, Spring Boot 3, PostgreSQL, Flyway, Testcontainers, JUnit 5, k6, Docker Compose, Micrometer with Prometheus and Grafana. Kafka and Redis only if justified in a decision record.

## Roadmap

- [ ] Design doc, schema, OpenAPI spec
- [ ] Core ledger with balance invariants
- [ ] Idempotent transaction API
- [ ] Concurrency control and race-condition tests
- [ ] Append-only event log, reversals, and immutability enforcement
- [ ] Authentication and authorization
- [ ] Reconciliation job and statement simulator
- [ ] Observability and invariant-checker job
- [ ] Load tests and published results
- [ ] Security review, fixes, and documented findings
- [ ] Decision records and final documentation

## Limitations

- Single currency per account, no foreign-exchange conversion.
- Single-region, single-database design. Horizontal scaling and distributed transactions are out of scope.
- The bank is simulated. Real bank integration, settlement timing, and regulatory requirements are out of scope.
- This is a learning and portfolio project, not production financial software.

## License

MIT (to be confirmed).
