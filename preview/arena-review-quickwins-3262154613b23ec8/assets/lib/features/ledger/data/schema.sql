-- Khoroch Diary - initial local schema (B2 First, building block only).
--
-- Mirrors docs/spec/data-model.md. This file is pure DDL: it defines two tables
-- and two indexes, creates no rows, and never drops or rewrites anything, so it
-- is safe to execute against a brand-new local database.
--
-- Contract notes for the future Drift/Flutter adapter:
--   * money is INTEGER paise, always > 0 for transactions; direction lives in
--     `type`, never in the sign. INTEGER *affinity* alone is not enough - it
--     keeps 1.5 as REAL and happily stores 'abc' as TEXT - so both money
--     columns also assert `typeof(...) = 'integer'`;
--   * ids are client-generated TEXT, primary keys are the sync idempotency key;
--   * timestamps are UTC ISO-8601 TEXT; deletes are tombstones (`deleted_at`),
--     rows are never removed;
--   * `PRAGMA foreign_keys = ON` must be set on every connection by the caller,
--     because SQLite defaults it off.
--
-- Not included here on purpose: sync/outbox tables, migrations, seed data and
-- the remaining entities (categories, note counting, profile, settings).

-- A ledger. `opening_balance_paise` is the starting balance folded into total
-- income by the domain layer.
CREATE TABLE khatas (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  -- Integer paise only. Zero and negative opening balances are legal.
  opening_balance_paise INTEGER NOT NULL DEFAULT 0
    CHECK (typeof(opening_balance_paise) = 'integer'),
  currency TEXT NOT NULL DEFAULT 'INR',
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);

-- One income or expense row. `transactions` is quoted because it is a SQL
-- keyword; a Drift table name must be quoted the same way.
CREATE TABLE "transactions" (
  id TEXT PRIMARY KEY NOT NULL,
  khata_id TEXT NOT NULL REFERENCES khatas(id),
  type TEXT NOT NULL CHECK (type IN ('income','expense')),
  -- Strictly positive *and* really an integer: `typeof` rejects the fractional
  -- REAL (1.5) and non-numeric TEXT ('abc') that INTEGER affinity alone allows.
  amount_paise INTEGER NOT NULL
    CHECK (typeof(amount_paise) = 'integer' AND amount_paise > 0),
  category_id TEXT NOT NULL,
  description TEXT CHECK (description IS NULL OR length(description) <= 120),
  occurred_at TEXT NOT NULL,
  note_session_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);

-- Home reads the newest entries for one khata; this index serves that query
-- (and View All) without a sort step.
CREATE INDEX idx_transactions_khata_occurred_at
  ON "transactions" (khata_id, occurred_at DESC);

-- Sync scans rows waiting to be pushed.
CREATE INDEX idx_transactions_sync_state
  ON "transactions" (sync_state);
