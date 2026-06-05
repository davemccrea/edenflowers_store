# Passkey Authentication Support

## Goal

Add passkey authentication for customers and admins using AshAuthentication's WebAuthn strategy. This should support platform authenticators such as Touch ID, Face ID, Windows Hello, Android passkeys, and hardware security keys.

## Current Auth Baseline

The app already uses `AshAuthentication` on `Edenflowers.Accounts.User` with:

- OTP sign-in through `Edenflowers.Accounts.User.Senders.SendOtp`
- Google OAuth sign-in through `Edenflowers.Accounts.UserIdentity`
- JWT token storage through `Edenflowers.Accounts.Token`
- `require_token_presence_for_authentication? true`

This is a good base for WebAuthn because AshAuthentication requires tokens to be enabled for passkey flows.

## Proposed Scope

1. Add the optional WebAuthn dependency required by AshAuthentication.
2. Add a credential resource, for example `Edenflowers.Accounts.WebAuthnCredential`, backed by a `webauthn_credentials` table.
3. Add a `has_many :webauthn_credentials` relationship to `Edenflowers.Accounts.User`.
4. Configure a `webauthn :webauthn` strategy on `Edenflowers.Accounts.User`.
5. Configure relying-party values per environment:
   - `rp_id` as the site domain, without scheme or port.
   - `rp_name` as the public shop name.
   - `origin` as the full browser origin, including port in development.
6. Add Phoenix WebAuthn hooks to the asset pipeline.
7. Add account UI for users to register, label, and remove passkeys.
8. Add sign-in UI for "Sign in with passkey".
9. Decide whether passkeys are primary sign-in, second factor for protected admin routes, or both.

## Implementation Notes

AshAuthentication exposes `AshAuthentication.Strategy.WebAuthn` for WebAuthn/FIDO2 passkeys. The strategy expects a separate Ash resource for credential storage with fields for:

- `credential_id`
- `public_key`
- `sign_count`
- `label`
- `last_used_at`
- a `belongs_to` relationship back to the user

AshAuthenticationPhoenix also includes WebAuthn components and routes. Prefer using the generated setup where possible:

```sh
mix ash_authentication.add_strategy.webauthn
mix ash_authentication_phoenix.add_strategy.webauthn
```

If the feature is used as 2FA for admin areas, use the Phoenix WebAuthn verification helpers and route guards so sensitive admin routes require a fresh WebAuthn ceremony.

## Open Decisions

- Should passkeys be available for all customer accounts, only admins, or both?
- Should passkeys replace OTP as a primary sign-in option, or act only as 2FA?
- Should a user be required to keep at least one fallback sign-in method before removing their last passkey?
- Which production domains and preview domains should be valid WebAuthn origins?
- How should lost-passkey recovery work for admins?

## Acceptance Criteria

- A user can add a passkey from their account page.
- A user can sign in with a registered passkey on supported browsers/devices.
- A user can label and remove registered passkeys.
- WebAuthn origin and relying-party configuration works locally and in production.
- Unsupported browsers fall back cleanly to existing OTP or Google sign-in.
- Admin routes can require passkey verification if 2FA mode is selected.
- Tests cover credential registration, sign-in, deletion, and fallback auth behavior.
