# Expense capture workflow

Experimental add-on for capturing business receipts and invoices, extracting
structured data via LLM, and writing it to a spreadsheet for accounting review.
Not a core business concern — kept simple and outside the Phoenix app.

## Goal

Forward/upload a receipt or invoice → structured row appears in a Google Sheet
(or Airtable) with vendor, date, amount, VAT, and category filled in
automatically. Low-confidence extractions are flagged for manual review.

## Stack

- **Papra** — document store and capture UI. Handles upload, email ingestion
  (forward receipts to a unique address), storage, and tagging.
- **n8n** — orchestration. Triggered by Papra webhook on new document; calls
  Claude; writes structured data to the sheet.
- **Claude API** — extraction. Vision-capable, so works on both PDFs and
  scanned/photographed receipts.
- **Google Sheets** — structured output store. Easy to review, correct, and
  export to the accountant.

## Flow

```
Receipt/invoice
  → Papra (upload UI or email forward)
  → Papra webhook (new document event)
  → n8n workflow
      ├── fetch document from Papra API
      ├── call Claude API (vision or text)
      ├── parse structured JSON response
      ├── write row to Google Sheets
      └── tag document in Papra as "processed"
```

## n8n workflow steps

1. **Webhook trigger** — Papra fires on document creation. Payload includes
   document ID.
2. **Fetch document** — HTTP request to Papra API to get file binary or OCR
   text (whichever Papra exposes).
3. **Claude extraction** — HTTP request node to Claude API. Use
   `claude-sonnet-4-6` (vision-capable). Pass the file as base64 image or
   extracted text depending on format.
4. **Structured output parser** — n8n's JSON parser with retry on malformed
   response. Schema: see below.
5. **Write to Google Sheets** — Sheets node appends one row per document.
6. **Tag in Papra** — HTTP request back to Papra API to apply tag `processed`.

## Claude prompt

```
You are an accounting assistant. Extract the following fields from this receipt
or invoice image. Return valid JSON only, no prose.

Fields:
- vendor_name: string
- vendor_vat_number: string or null
- date: ISO 8601 date string (YYYY-MM-DD)
- total_amount: number (include VAT)
- vat_amount: number or null
- currency: ISO 4217 code (e.g. "EUR")
- category: one of ["office_supplies", "travel", "meals", "software",
  "marketing", "utilities", "professional_services", "other"]
- description: short string, what was purchased
- confidence: one of ["high", "medium", "low"]

If a field cannot be determined, use null. confidence reflects your overall
certainty across all fields.
```

## Google Sheets schema

| Column          | Source              | Notes                          |
| --------------- | ------------------- | ------------------------------ |
| document_id     | Papra webhook       | For idempotency and linking    |
| date            | Claude              |                                |
| vendor_name     | Claude              |                                |
| description     | Claude              |                                |
| total_amount    | Claude              |                                |
| vat_amount      | Claude              |                                |
| currency        | Claude              |                                |
| category        | Claude              |                                |
| vendor_vat_no   | Claude              |                                |
| confidence      | Claude              | Flag "low" rows for review     |
| papra_link      | n8n constructed     | Direct link to doc in Papra    |
| processed_at    | n8n                 | Timestamp of extraction        |
| reviewed        | Manual              | Checkbox column, default false |

## Idempotency

Before writing, check whether `document_id` already exists in the sheet.
If it does, skip — prevents duplicate rows on webhook retries.

## Handling images vs PDFs

- If Papra returns OCR text, send that as the prompt content (cheaper,
  faster).
- If only the raw file is available, send as a base64-encoded image using
  Claude's vision input. Works for JPEG, PNG, and PDF (Claude handles PDF
  pages natively).

## Confidence-based review

- `high` — row written as-is, `reviewed` checkbox left unchecked.
- `medium` — same, but highlight row yellow in the sheet (conditional
  formatting on the `confidence` column).
- `low` — highlight row red. Consider an n8n step that sends a Slack/email
  nudge to review it.

## What this does not do

- No Phoenix involvement — entirely external to the app.
- No automatic accounting entries — the sheet is a review layer, not a
  ledger.
- No re-extraction on update — if a document is replaced in Papra, manually
  delete the old sheet row and re-trigger.

## Future extensions (if needed)

- Deduplicate across months (same vendor, same amount, same date — likely
  uploaded twice).
- Export sheet to CSV on a schedule and email to accountant.
- Move structured storage into Phoenix/Postgres if a review UI becomes
  worthwhile.
