# Privacy policy: proportionate GDPR/legal review

## Scope and conclusion

Reviewed `lib/edenflowers_web/features/marketing/privacy_live.ex`, the existing `privacy-policy-data-audit.md`, relevant account/Brevo sync, session/Stripe loading, delivery-email source, translation entries, domain documentation and ADR-0004. This is a source-based compliance assessment, not Finnish legal advice or a production compliance certification. No provider dashboards/contracts, production data, live browser storage, mailbox or operational deletion evidence were inspected. The existing audit's provider and retention findings are starting points, not independent verification of production settings.

**Conclusion:** retain the concise six-section notice. It covers most of the right subjects, but it is not ready to be treated as a completed Articles 13/14 notice. The material gaps concern actual processing and unverified promises, not insufficient legal boilerplate. A few hundred annual orders supports simple manual procedures and modest documentation; it does not remove transparency, lawful-basis, retention, processor, security or rights obligations.

The draft label and noindex are editorial choices, not exemptions from GDPR. If the shop is already processing data, the notice obligations already apply.

## Findings on the current notice

### 1. Controller: substantially adequate

The notice identifies Jennie McCrea trading as Eden Flowers and supplies business ID, address, email and telephone. Earlier task notes record owner confirmation of the controller and Hetzner Finland hosting. Keep those details accurate. A business ID and telephone are useful but not individually mandated by GDPR if identity/contact information is otherwise adequate. Do not invent a DPO title; an ordinary privacy contact is sufficient unless Article 37 criteria apply.

### 2. Purposes and legal bases: improve mapping, not length

The existing contract/accounting/legitimate-interest/newsletter-consent structure is sensible. Specify the actual legitimate interests: arranging gifts requested by customers, confirming delivery, handling relevant customer administration and protecting the service against abuse. Explicitly cover delivery photography and sharing that photograph with the Customer. A Recipient who did not place the order is not automatically party to the Customer's contract.

A compact table is preferable to two disconnected lists:

| Activity | Typical basis |
| --- | --- |
| Purchases, subscriptions, course bookings, purchase enquiries | Contract / requested pre-contract steps |
| Gift-recipient delivery details | Legitimate interests in fulfilling requested gifts, subject to balancing |
| Delivery evidence and complaint handling | Legitimate interests, limited to what is necessary |
| Accounting records | Legal obligation |
| Necessary security and abuse prevention | Legitimate interests, with cookie/device-access rules assessed separately |
| Newsletter | Consent |

Document a short legitimate-interest necessity/balancing assessment internally. Do not put a full assessment in the notice. A newsletter opt-in does not automatically authorise every purchase-statistics enrichment or marketing profile.

Explain what happens if necessary details are withheld: for example, the shop cannot process the purchase or delivery. Do not call optional Instagram handles, newsletter choices or unnecessary notes required. Explain that a checkout identity and purchase history can be created without separate account registration. General enquiries unrelated to a prospective purchase need an appropriate basis rather than an assumed contract.

### 3. Delivery photograph statement: factual correction required

The notice says photographs are emailed to the Recipient. `Email.order_left_at_door/3` uses `customer_email`, and `SendFulfillmentEmail` records `fulfillment_emailed_to: order.customer_email`. The attachment goes to the Customer, who may be someone else.

Disclose that accurately and assess necessity. Photograph the flowers and their location, avoiding people, interiors, unrelated labels, and other unnecessary details. Disclose the purpose and short retention. For a low-volume shop, not taking photographs at all is a legitimate simplification if delivery evidence is unnecessary. Existing recipient-held email copies cannot simply be recalled, but that does not exempt shop/provider-controlled copies from retention and applicable rights obligations.

### 4. Gift recipients: Article 14 delivery of information is missing

The notice correctly says recipient details come from the Customer. Merely publishing it does not establish that Recipients receive it.

Under Article 14, information is generally due within a reasonable period, no later than one month, and earlier where the first communication or first disclosure requires it. Consider timing when addresses are sent to service providers, not only the eventual flower delivery. A proportionate design could combine an appropriate first-contact notice/link with a small card or QR at delivery. A delivery card alone is not a universal answer if an earlier deadline applies.

Do not assume gift surprise or small-business size establishes a disproportionate-effort exemption. An instruction asking the Customer to pass on the notice can help, but does not by itself prove the shop fulfilled its obligation. Assess a genuinely applicable exception before relying on it, and document the reasoning. Do not add Recipients to marketing lists.

### 5. Retention: highest operational priority

The six-year wording is imprecise. Finnish Accounting Act chapter 2 section 10 measures the six-year minimum from **the end of the calendar year in which the financial year ended**, not necessarily the financial year in which the purchase occurred. Specified accounts and related records have a ten-year minimum from the financial-year end. Ask the accountant to classify the relevant records and check any additional tax requirements. The accountant advises on legal classification; they do not arbitrarily decide the law.

An accounting obligation does not justify retaining every delivery instruction, photograph, free-text message or CRM attribute for the same period. Some correspondence can itself be accounting material: classify it rather than deleting all correspondence indiscriminately.

The current data audit found no general age-based cleanup for placed purchases, identities, subscriptions, histories or mailbox enquiries. Populated abandoned checkouts are not generally purged. Photo expiry is acknowledged as unimplemented. Recheck actual practice before promising any period. Manual deletion is lawful; request-only deletion after a deadline is not an adequate substitute for routine expiry.

Suggested policy decisions, **not statutory defaults**:

- Accounting core: applicable statutory retention; preserve financial reference, items, amounts, VAT and relevant payments/history.
- Delivery photographs: the owner-approved two weeks, with actual scheduled manual or automatic deletion and a defined scope for attachments, caches and backups.
- Delivery-only instructions, coordinates and card messages: a justified short post-fulfilment period; a period such as 30–90 days is a decision to assess, not a legal requirement. Preserve specific evidence longer only where genuinely needed.
- Enquiries that do not become purchases: twelve months can be reasonable if implemented; accounting correspondence may differ.
- Abandoned checkouts: define short expiry, such as 30 days after inactivity, subject to unresolved-payment/reconciliation safeguards.
- Inactive accounts: choose and justify a review/deletion period; do not retain the entire profile merely because one accounting record must remain.
- Error reports: 90 days can be proportionate, but redact secrets/free text and check jobs and logs separately.
- Routine backups: roughly 30 days, if true, with restricted access and a restoration process that reapplies deletions. Existing infrastructure uses a pruning window, not an exact universal deadline for all dumps/files.
- Newsletter: until withdrawal or a justified inactivity review. Retain limited suppression data and proportionate evidence of consent as necessary; do not describe suppression as continued permission to market.

ADR-0004 treats Orders as the sales record. Privacy minimisation must preserve required financial records and their integrity; it does not authorise wholesale purchase deletion. Separating delivery-only fields from the accounting core is compatible in principle, but needs an implementation design for histories and references.

### 6. Service providers and international transfers: unfinished

The current list is useful. Confirm the mailbox provider, any delivery helpers, accounting arrangements and relevant in-person/invoice providers (domain docs name Zettle, MobilePay and Zervant). Not all recipients are processors; Stripe can have controller roles for some processing, and accountant roles require assessment.

Keep Article 28 arrangements for actual processors; acceptance of the provider's standard DPA can suffice. No bespoke contract drafting is automatically needed. Check subprocessors, locations and access, not just the main database location.

The promise to confirm overseas safeguards later is not enough as a final disclosure. Establish which transfers occur and their mechanisms: an applicable adequacy decision, qualifying EU–US Data Privacy Framework certification where relied on, or SCCs with the necessary assessment/supplementary safeguards. A US brand alone does not prove a transfer, and an EU server alone does not rule one out. Explain applicable safeguards and how to obtain information/copies. Do not use a blanket customer-consent checkbox to bypass this work.

### 7. Brevo enrichment: reduce unnecessary processing

The source sync includes newsletter subscribers and non-subscribing customers with phone numbers. It sends name, email, phone, language, order count, latest order date and total spent. Non-subscribers remain outside the newsletter list.

Transactional use of an email processor does not automatically need marketing consent. A separate CRM sync with spend statistics still requires a defined necessary purpose, legal basis and retention. If order texts are not actually used, remove speculative non-subscriber syncing. If segmentation is unused, remove the statistics. This reduces both legal work and data exposure. If profiling is actually used, disclose it appropriately; do not assume every automated statistic is an Article 22 significant decision.

### 8. Cookies and fraud prevention: no unconditional banner answer yet

The signed session cookie has a configured 30-day maximum age. Necessary cart/authentication functionality can qualify for the Finnish terminal-equipment consent exception; check each purpose and whether the duration is proportionate, rather than treating the cookie's name as an exemption.

`assets/js/app.js` loads Stripe.js on page load site-wide. Stripe documents advanced fraud signals and an option to disable their collection. Absence of analytics/advertising scripts is not evidence that every other storage/access operation is exempt.

Audit actual cookies, local storage and device access, purposes, recipients and lifetimes before deciding whether consent is needed. Browser settings are not a replacement for prior consent where required. Loading Stripe only where payment functionality is needed and disabling optional fraud signals can reduce the burden, but neither change alone proves no banner is needed. Do not recommend removing necessary payment security without understanding the consequences.

No banner is necessary merely to display a policy or because the site uses strictly necessary cookies. If non-exempt storage/access is retained, implement consent before it occurs, including practical rejection and withdrawal. A cookie section can stay inside the privacy notice; a separate cookie page or commercial CMP is not inherently mandatory.

Check Stripe Radar settings before claiming no significant automated decisions. Document whether any shop-controlled automated refusal is solely automated and legally/similarly significant; do not assume all fraud scores trigger Article 22.

### 9. Rights: mostly sound

Keep access, correction, conditional erasure/restriction/portability, objection, consent withdrawal and the Finnish regulator complaint route. Email requests handled manually are adequate. First responses/copies are ordinarily free. Explain any lawful extension within the initial month; do not routinely demand identity documents.

An access response must consider relevant notes/history and provider-held data, while protecting other people's information. Some statutory accounting records must remain. Marketing objections must be respected; legitimate-interest objections outside marketing have a different legal test. Applicable rectification/erasure/restriction notifications to recipients also need handling. No automated export portal or delete-account button is mandated merely by GDPR.

### 10. Language and collection points

Sampled Finnish and Swedish privacy translation entries are empty, so language-prefixed routes are not evidence of translated notices. GDPR requires intelligibility to the intended audience, not automatically translation into every EU language. A shop selling in Swedish and Finnish should provide understandable Swedish and Finnish versions. Use one consistent source of truth.

Check privacy links or short information at contact/wedding enquiries, newsletter signup, checkout, manual purchases and Recipient communications—not just the footer. Do not require customers to consent to the whole privacy policy to order.

The visible last-updated date should match actual publication. No independent current-date comparison was established in this review.

### 11. Flower-shop-specific sensitive information

Ordinary order data is not automatically special-category data. Nevertheless, card messages and Florist Notes may contain identifiable health, religious or other Article 9 information. A generic legitimate-interest basis alone does not satisfy Article 9 where it applies. Avoid soliciting sensitive details, record neutral practical instructions, minimise access and retention, and assess any genuinely necessary special-category processing separately. Funeral flowers alone should not be casually labelled proof of religious belief.

## Minimum proportionate compliance package

1. A short accurate public notice, understandable in the store's customer languages, with appropriate collection-point and Recipient information.
2. One internal processing register with controller, purposes/bases, people/data categories, recipients/transfers, retention and general security measures. Regular order handling is not occasional: the under-250-person Article 30 exception is not a blanket exemption. A small spreadsheet is sufficient in form if it contains the required information.
3. A small provider folder: agreements/DPAs and applicable transfer evidence. Brief legitimate-interest assessments and a recorded check of whether a DPIA/DPO is needed.
4. An actual retention routine across database/history, uploads, mailbox, provider copies, jobs/logs and backups. Manual review/deletion can be proportionate; automation is useful where a short promise would otherwise be missed.
5. A rights-request checklist and a breach checklist/log. Notify the authority within 72 hours of awareness where required, unless the breach is unlikely to risk rights/freedoms; notify affected people where high risk requires it. Record breaches even if notification is not required.
6. Appropriate security: restricted admin/provider access, strong authentication, updates, protected transport, redacted diagnostics, backups and tested restoration. GDPR does not prescribe a single enterprise product or universal encryption-at-rest rule; safeguards must fit the risks. Never use real customer data in developer/AI tools merely because the business is small.

## What can be skipped on the known facts

- A dedicated DPO: no apparent Article 37 trigger for this ordinary small florist; reassess if activities change.
- A full DPIA: no identified likely-high-risk processing requiring one; retain a short screening, especially around sensitive notes, location and fraud settings.
- GDPR certification, annual external audits, enterprise privacy platforms, custom lawyer-written DPAs and a consent platform where no non-exempt tracking is used.
- Consent for ordinary order fulfilment/accounting or a mandatory 'I accept the privacy policy' checkbox.
- A separate cookie notice page, exhaustive technical cookie tables for unnecessary fields, long security descriptions, a public processing register and public incident-response procedures.
- Automatically registering customer databases with the authority or pre-approving the privacy notice. Particular high-risk residual processing can have separate prior-consultation requirements, but none is established here.
- Automated access/export/deletion portals and instant deletion of immutable backup copies, provided applicable rights are fulfilled and backups expire safely without resurrecting deleted data.
- Marketing profiling, speculative CRM enrichment, site-wide optional tracking and delivery photography if the shop does not need them. Removing optional processing is often more proportionate than documenting elaborate controls around it.

## Priority order

1. Fix inaccurate photo disclosure and address the draft's unresolved retention/transfer claims; check live practices before finalising promises.
2. Decide and implement real minimisation/retention, preserving the accounting core.
3. Confirm provider roles, DPAs and transfer mechanisms; cut unused Brevo enrichment.
4. Complete a browser/Stripe audit and implement the right consent design, if any.
5. Design Article 14 Recipient information with timing/disclosures in mind; complete translations and collection-point notices.
6. Keep a lean internal register, rights/breach process and security checks. No purchase of compliance software is necessary to begin.

## Primary sources and verification limits

- [GDPR, Regulation (EU) 2016/679](https://eur-lex.europa.eu/eli/reg/2016/679/oj): especially Articles 5–6, 9, 12–14, 17, 19–22, 24–25, 28, 30, 32–37 and 44–49. EUR-Lex returned an empty challenge response in this environment; the detailed official EDPB guides below were accessible and used to check the relevant obligations.
- [EDPB SME guide: be compliant](https://www.edpb.europa.eu/sme-data-protection-guide/be-compliant_en): accountability, Article 30/under-250 exception and DPIA screening.
- [EDPB SME guide: respect individuals' rights](https://www.edpb.europa.eu/sme-data-protection-guide/respect-individuals-rights_en): Articles 13/14, indirect-collection timing/exceptions, layered notices, requests and significant automated decisions.
- [EDPB SME guide: lawful processing](https://www.edpb.europa.eu/sme-data-protection-guide/process-personal-data-lawfully_en): legal bases and special-category conditions.
- [EDPB SME guide: DPO](https://www.edpb.europa.eu/sme-data-protection-guide/data-protection-officer_en).
- [EDPB SME guide: international transfers](https://www.edpb.europa.eu/sme-data-protection-guide/international-data-transfers_en).
- [EDPB SME guide: breaches](https://www.edpb.europa.eu/sme-data-protection-guide/data-breaches_en).
- [Finnish Accounting Act 1336/1997](https://www.finlex.fi/fi/lainsaadanto/1997/1336), chapter 2 section 10. Relevant current statutory Finnish text was present in the page payload, including six-year timing and the separate ten-year category.
- [Finnish Act on Electronic Communications Services 917/2014](https://www.finlex.fi/fi/lainsaadanto/2014/917), section 205: terminal-equipment storage/access consent and necessary-service/communication exceptions. Relevant statutory Finnish text was present in the page payload.
- [Stripe: advanced fraud detection](https://docs.stripe.com/disputes/prevention/advanced-fraud-detection): signals and disabling optional advanced fraud collection. This is evidence of product behaviour/options, not a regulator's determination of the shop's cookie-law compliance.

No finding here establishes the actual provider transfer mechanism, live cookies, deployed translations or successful operational deletion. Those require production-configuration and business confirmation, not more boilerplate.
