-- App table for the triage workflow (Postgres). Mirrors the Airtable field list in the README.
CREATE TABLE IF NOT EXISTS support_messages (
  id                 SERIAL PRIMARY KEY,
  dedupe_key         TEXT NOT NULL UNIQUE,          -- md5 of message_id, or sender+text; the duplicate backstop
  message_id         TEXT,
  sender             TEXT,
  customer_message   TEXT NOT NULL,
  category           TEXT CHECK (category IN ('Billing','Access','Scheduling','Technical Support','General Question','Refund Request')),
  confidence         NUMERIC(4,3) CHECK (confidence BETWEEN 0 AND 1),
  needs_human_review BOOLEAN NOT NULL DEFAULT FALSE,
  reason             TEXT,
  draft_response     TEXT,
  status             TEXT NOT NULL DEFAULT 'received'
                     CHECK (status IN ('received','drafted','notified','notify_failed','failed')),
  notified           BOOLEAN NOT NULL DEFAULT FALSE,
  ai_attempts        INT NOT NULL DEFAULT 0,
  error              TEXT,
  execution_id       TEXT,                          -- lets the error workflow find the row to mark failed
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
