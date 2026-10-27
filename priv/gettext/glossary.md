# Translation glossary and style

This is a starting reference drawn from current copy, not native-translator or
Jennie approval. Use terms in context rather than doing global replacements.
Unresolved terminology belongs in [the review queue](review-queue.md).

## Working terminology

| Meaning | Swedish | Finnish | Guidance |
| --- | --- | --- | --- |
| Customer order | beställning | tilaus | An order being accepted does not imply payment received. |
| Recurring flower subscription | prenumeration | kestotilaus | Current shared labels; Finnish variants need review (T14). Distinguish from a one-off flower order. |
| Delivery | leverans | toimitus | General delivery, including venues. Receipt home-delivery wording needs review (R04). |
| Pickup | avhämtning | nouto | Do not use a delivery-only label for a state that also includes pickup (S05). |
| Value-added tax | moms | ALV | Working app terminology; receipt wording needs native/accounting review (R03). |
| Swedish/Finnish shop address | Myrvägen 1 | Muurahaistie 1 | These name the same place. Align shop copy only, never customer-entered addresses (T09). |
| Related information heading | Relaterad information | Lisätietoja | AI-reviewed correction T01; native approval outstanding. |

Bouquet size names, an admin-entered customer order, fulfillment states and
wedding product/price terms remain decisions for Jennie and native editors
(T06–T07, S02, S05). Preserve existing wording until decided.

## Voice and meaning

- Preserve Jennie's personal first-person voice and Finland-Swedish usage,
  including Vasa, Korsholm, Vändagen, rat and drar kurser where appropriate.
- Prefer natural Finnish sentences over English word order or keyword-like
  headings. Preserve product scope and the distinction between payment,
  confirmation, cancellation and stopping future subscription bouquets.
- Check who is addressed: an individual sender and a wedding couple may need
  different pronouns. Resolve shared-string ambiguity with context rather than a
  global pronoun replacement.
- Reconstruct linked sentences and email paragraphs before editing fragments.
- Preserve `%{placeholders}`, `{selector}` and `__N__`. Avoid attaching fixed
  Finnish case suffixes to arbitrary personal names. The four existing generic
  recipient exceptions are documented in `check-exceptions.json`; they are not
  permission to omit placeholders elsewhere.
- Treat route translations as URL changes requiring redirect planning. Changes
  to legal rights, payment deadlines or cancellation policy require business
  review, and qualified legal review where needed.
