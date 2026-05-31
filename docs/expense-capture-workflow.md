# Expense capture workflow

Experimental add-on for capturing business receipts and invoices, extracting
structured data via an LLM, and storing it in the `Edenflowers.Expenses`
domain for review. Not a core business concern.

## Decision: Phoenix-native, no n8n

An earlier draft of this plan orchestrated the flow through n8n (Papra webhook
→ n8n → Claude → Google Sheets). We dropped n8n: the processing is simple
enough to live in Phoenix, where it's testable, versioned, and reuses the
existing `StripeHandler` → Oban worker pattern. Papra is still the capture UI
and document store. The superseded n8n workflow JSON
(`docs/n8n-expense-workflow.json`) is kept only for historical reference.

## Stack

- **Papra** — document store and capture UI (upload, email ingestion, storage,
  tagging). Self-hosted.
- **Phoenix** — receives Papra's `document:created` webhook, fetches the
  document, calls Claude, and writes to the `Expenses` domain.
- **Claude API via ReqLLM** — structured extraction (vision-capable, handles
  PDFs and photos).

## Flow

```
Receipt/invoice
  → Papra (upload UI or email forward)
  → Papra "document:created" webhook (HMAC-SHA256 signed)
  → EdenflowersWeb.Plugs.PapraWebhook   (verify signature, enqueue, 200)
  → EdenflowersWeb.PapraHandler         (parse payload → enqueue job)
  → Edenflowers.Workers.ProcessExpenseDocument
      ├── Edenflowers.Papra.fetch_document/2   (download bytes)
      ├── Edenflowers.Claude.extract_expense/2 (ReqLLM.generate_object)
      └── Expense.ingest/1                     (upsert into Postgres)
```

## Components

| Module | Responsibility |
| --- | --- |
| `EdenflowersWeb.Plugs.PapraWebhook` | Endpoint plug (before `Plug.Parsers`). Verifies HMAC-SHA256 over the raw body, dispatches to the handler, returns fast. Mirrors `Stripe.WebhookPlug`. |
| `EdenflowersWeb.PapraHandler` | Thin handler. Parses `document:created`, enqueues the worker. Mirrors `StripeHandler`. |
| `Edenflowers.Papra` | Thin Papra API client. `fetch_document/2` returns the raw bytes + content type. |
| `Edenflowers.Claude` | Wraps `ReqLLM.generate_object/4`. Holds the prompt and output schema. Returns a raw map — no casting. |
| `Edenflowers.Workers.ProcessExpenseDocument` | Oban worker. Fetch → extract → ingest, with per-stage logging. Unique on `document_id`. |
| `Edenflowers.Expenses.Expense` | Ash resource. `:ingest` upserts on `document_id` and coerces all types. |

## Idempotency

Two layers, so an at-least-once webhook redelivery never duplicates:

1. The Oban worker is `unique: [keys: [:document_id], period: :infinity]`, so a
   second `document:created` collapses to the existing job.
2. `Expense.ingest` is an upsert on the `unique_document_id` identity.

## Type coercion lives in Ash

`Edenflowers.Claude` returns a raw map (`date` as an ISO string, amounts as
floats, `currency`/`category`/`confidence` as lowercase strings). The
`:ingest` action coerces these into `Date`, `Decimal`, and the `Currency` /
`Category` / `Confidence` enums. The worker does no casting.

## Confidence-based review

`confidence` (`:high` / `:medium` / `:low`) is required and stored. Review
happens in AshAdmin; `reviewed_at` is null until an admin runs
`:mark_reviewed`. A future "needs review" report can filter on
`confidence == :low and is_nil(reviewed_at)`.

## Configuration (runtime.exs, all non-raising)

| Env var | Used by |
| --- | --- |
| `PAPRA_BASE_URL` | `Edenflowers.Papra` |
| `PAPRA_API_KEY` | `Edenflowers.Papra` (Bearer auth) |
| `PAPRA_WEBHOOK_SECRET` | `PapraWebhook` plug (fails closed if unset) |
| `ANTHROPIC_API_KEY` | `Edenflowers.Claude` (via ReqLLM) |

Left non-raising on purpose: a missing key must not block app boot for an
experimental feature. The webhook fails closed; the worker logs and retries.

## To verify on first run

- **Papra signature scheme.** The plug verifies an HMAC-SHA256 *hex* digest of
  the raw body in the `x-signature` header. If your Papra is on the Standard
  Webhooks scheme (v0.8+), the signed content is `<id>.<timestamp>.<body>`
  with different headers/encoding — adjust `verify_signature/3`.
- **ReqLLM specifics.** Confirm the model slug (`anthropic:claude-sonnet-4-6`),
  the response accessor (`ReqLLM.Response.object/1`), and that the per-call
  `api_key:` option is honoured.

## What this does not do

- No automatic accounting entries — `Expenses` is a review layer, not a ledger.
- No CSV/Excel export yet — straightforward to add from the Ash resource later.
