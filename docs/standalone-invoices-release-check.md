# Standalone invoice release verification

Verified by Codex on 2 November 2026 for TASK-168.15. Implementation and automated checks are complete. Native language/business approval and the final Zervant cutover check remain open; this is not a deployment approval.

## Automated checks

- `mix precommit` passed: compile with warnings as errors, translation checks (12 existing documented exceptions), schema/codegen consistency, unused-dependency check, formatting, strict Credo, JavaScript tests, and 1,766 Elixir tests with zero failures. One existing wedding-estimate test remains skipped while public prices are hidden.
- Added an ordinary wedding advance/remainder workflow test. Each invoice owns its own billed amount/VAT, number and reference; paying the advance leaves the remainder untouched. A dated receipt/reversal reconstructs the historical unpaid balance, and unpaid credit/replacement documents preserve the shared number sequence.
- Existing tests cover draft/issue immutability, failed-send persistence/retry and reminders, invoice-only payment ownership, admin authorization, independent-transaction credit/payment and issuance races, frozen mixed-rate VAT allocation, month-end receivables, and retained order/course payment/refund/cancellation flows.
- Clean migrations passed through `20261102152649` in a new throwaway database.
- Upgrade migrations passed after restoring the existing local `production-v1.25.5-20261101T211604.dump` into a second throwaway database. All 18 orders, one registration and one payment were retained. Canonical full-row fingerprints matched before/after; the new nullable invoice ownership column was excluded from the payment comparison. The source backup had no invoice documents, matching the agreed migration scope. Original databases and backup files were untouched; verification databases were removed afterward.
- The final Docker release image built successfully for `linux/amd64`. On this Apple Silicon host only, the temporary build context and verification container used `ERL_FLAGS="+JPperf true +S 2:2"` to avoid an emulated Erlang startup failure. The repository Dockerfile was unchanged.
- Image `edenflowers-invoice-verification:local` (`sha256:b993b0b510749e15a1dee206fbe4022d0fb317570a96ac7360ff77238f3d6445`) rendered four invoice fixtures and three full-credit fixtures using the released `Edenflowers.Typst.render/3` path with `docker run --network none`. Dummy runtime configuration was used, without starting the application or connecting to a database/mail service. All outputs were PDFs; every invoice reference check digit and full 54-digit barcode matched its IBAN, amount, reference and due date. Vendored fonts and barcode packages were sufficient offline.

## Document and copy review

All seven fi/sv/en fixtures rendered locally and in the release image. Codex visually reviewed the Finnish and Swedish invoice/credit pages and inspected extracted text: own-amount VAT and negative credit base/VAT/total were present, bank details/barcodes appeared only on invoices, and the page content was legible without clipping. This is AI review, not native-language or accountant approval.

`mix print_emails sv fi en` generated the current standalone invoice, independent wedding advance/remainder, part-paid reminder and credit-note scenarios. Codex reviewed those scenarios for their own amounts, current standalone wording, reference/payment details and the distinction between an unpaid credit and a cash refund. Existing native/Jennie review remains open in [the translation review queue](../priv/gettext/review-queue.md); outdated purchase-linked entries were replaced or explicitly retired. Admin translations still contain documented deferrable gaps.

Local review artifacts are in `tmp/invoice-verification/` (local PDFs/PNGs) and `tmp/invoice-verification/release/` (the seven PDFs rendered offline in the release image). They are generated review artifacts, not versioned release assets.

## Human checks before cutover

- Jennie approves Swedish financial/business meaning; native Swedish and Finnish reviewers approve the affected PDF, email and admin wording. Review queue R05–R07, R09–R10 and T21–T25 identify the exact current entries. Accountant review remains appropriate for VAT/credit/receivables terminology.
- Confirm the configured seller details and bank account are still current. Code and rendered PDFs use the agreed seller Jennie McCrea, Y-tunnus 2944459-6, Stadsgatan 3, 65300 Vasa, and IBAN FI69 3939 0018 3959 05.
- Immediately before issuing the first live invoice, confirm Zervant has not advanced beyond its agreed last number 1336. The configured first number remains 1337; automated clean-database tests verify it, but no live Zervant account check was performed.

No deployment, real invoice issuance, external customer email, staging or commit was performed by this verification.
