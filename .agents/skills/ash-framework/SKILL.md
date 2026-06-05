---
name: ash-framework
description: "Expert on the Ash Framework ecosystem."
metadata:
  managed-by: usage-rules
---

<!-- usage-rules-skill-start -->
## Additional References

- [actions](references/actions.md)
- [aggregates](references/aggregates.md)
- [authorization](references/authorization.md)
- [calculations](references/calculations.md)
- [code_interfaces](references/code_interfaces.md)
- [code_structure](references/code_structure.md)
- [data_layers](references/data_layers.md)
- [exist_expressions](references/exist_expressions.md)
- [generating_code](references/generating_code.md)
- [migrations](references/migrations.md)
- [query_filter](references/query_filter.md)
- [querying_data](references/querying_data.md)
- [relationships](references/relationships.md)
- [testing](references/testing.md)
- [best_practices](references/best_practices.md)
- [debugging_form_submissions](references/debugging_form_submissions.md)
- [error_handling](references/error_handling.md)
- [form_integration](references/form_integration.md)
- [nested_forms](references/nested_forms.md)
- [union_forms](references/union_forms.md)
- [advanced_features](references/advanced_features.md)
- [check_constraints](references/check_constraints.md)
- [configuration](references/configuration.md)
- [custom_indexes](references/custom_indexes.md)
- [custom_sql_statements](references/custom_sql_statements.md)
- [foreign_keys](references/foreign_keys.md)
- [multitenancy](references/multitenancy.md)
- [ash](references/ash.md)
- [ash_authentication](references/ash_authentication.md)
- [ash_phoenix](references/ash_phoenix.md)
- [ash_postgres](references/ash_postgres.md)

## Searching Documentation

```sh
mix usage_rules.search_docs "search term" -p ash -p ash_admin -p ash_archival -p ash_authentication -p ash_authentication_phoenix -p ash_phoenix -p ash_postgres -p ash_rate_limiter -p ash_state_machine -p ash_translation
```

## Available Mix Tasks

- `mix ash` - Prints Ash help information
- `mix ash.codegen` - Runs all codegen tasks for any extension on any resource/domain in your application.
- `mix ash.extend` - Adds an extension or extensions to the given domain/resource
- `mix ash.gen.base_resource` - Generates a base resource. This is a module that you can use instead of `Ash.Resource`, for consistency.
- `mix ash.gen.change` - Generates a custom change module.
- `mix ash.gen.custom_expression` - Generates a custom expression module.
- `mix ash.gen.domain` - Generates an Ash.Domain
- `mix ash.gen.enum` - Generates an Ash.Type.Enum
- `mix ash.gen.gettext` - Copies Ash's .pot file for error message translation
- `mix ash.gen.preparation` - Generates a custom preparation module.
- `mix ash.gen.resource` - Generate and configure an Ash.Resource.
- `mix ash.gen.validation` - Generates a custom validation module.
- `mix ash.generate_livebook` - Generates a Livebook for each Ash domain
- `mix ash.generate_policy_charts` - Generates a Mermaid Flow Chart for a given resource's policies.
- `mix ash.generate_resource_diagrams` - Generates Mermaid Resource Diagrams for each Ash domain
- `mix ash.gettext.extract` - Extracts Ash error messages into a .pot file
- `mix ash.install` - Installs Ash into a project. Should be called with `mix igniter.install ash`
- `mix ash.manifest.dump` - Dump the Ash app manifest as JSON
- `mix ash.migrate` - Runs all migration tasks for any extension on any resource/domain in your application.
- `mix ash.patch.extend` - Adds an extension or extensions to the given domain/resource
- `mix ash.reset` - Runs all tear down & setup tasks for any extension on any resource/domain in your application.
- `mix ash.rollback` - Runs all rollback tasks for any extension on any resource/domain in your application.
- `mix ash.setup` - Runs all setup tasks for any extension on any resource/domain in your application.
- `mix ash.tear_down` - Runs all tear_down tasks for any extension on any resource/domain in your application.
- `mix ash_admin.install` - Installs AshAdmin
- `mix ash_admin.install.docs`
- `mix ash_authentication.add_add_on` - Adds the provided add-on to your user resource
- `mix ash_authentication.add_add_on.audit_log` - Adds an audit log add-on to your user resource
- `mix ash_authentication.add_add_on.confirmation` - Adds email confirmation to your user resource
- `mix ash_authentication.add_strategy` - Adds the provided strategy or strategies to your user resource
- `mix ash_authentication.add_strategy.api_key` - Adds API key authentication to your user resource
- `mix ash_authentication.add_strategy.apple` - Adds Apple Sign In authentication to your user resource
- `mix ash_authentication.add_strategy.auth0` - Adds Auth0 OAuth authentication to your user resource
- `mix ash_authentication.add_strategy.dynamic_oidc` - Adds a data-driven OIDC strategy + OidcConnection resource
- `mix ash_authentication.add_strategy.github` - Adds GitHub OAuth authentication to your user resource
- `mix ash_authentication.add_strategy.google` - Adds Google OAuth authentication to your user resource
- `mix ash_authentication.add_strategy.magic_link` - Adds magic link authentication to your user resource
- `mix ash_authentication.add_strategy.microsoft` - Adds Microsoft OAuth authentication to your user resource
- `mix ash_authentication.add_strategy.oauth2` - Adds a generic OAuth2 authentication strategy to your user resource
- `mix ash_authentication.add_strategy.oidc` - Adds a generic OpenID Connect authentication strategy to your user resource
- `mix ash_authentication.add_strategy.okta` - Adds Okta OIDC authentication to your user resource
- `mix ash_authentication.add_strategy.otp` - Adds one-time password (OTP) authentication to your user resource
- `mix ash_authentication.add_strategy.password` - Adds password authentication to your user resource
- `mix ash_authentication.add_strategy.recovery_code` - Adds the recovery code authentication strategy
- `mix ash_authentication.add_strategy.slack` - Adds Slack OAuth authentication to your user resource
- `mix ash_authentication.add_strategy.totp` - Adds TOTP authentication to your user resource
- `mix ash_authentication.add_strategy.webauthn` - Adds WebAuthn/Passkey authentication to your user resource
- `mix ash_authentication.install` - Installs AshAuthentication. Invoke with `mix igniter.install ash_authentication`
- `mix ash_authentication.upgrade`
- `mix ash_authentication.phoenix.routes` - Prints all routes generated by AshAuthentication Phoenix
- `mix ash_authentication_phoenix.add_add_on.confirmation` - Adds Phoenix integration for the email confirmation add-on
- `mix ash_authentication_phoenix.add_strategy` - Adds a strategy to your user resource with Phoenix integration
- `mix ash_authentication_phoenix.add_strategy.magic_link` - Adds Phoenix integration for the magic link authentication strategy
- `mix ash_authentication_phoenix.add_strategy.otp` - Adds Phoenix integration for the OTP authentication strategy
- `mix ash_authentication_phoenix.add_strategy.password` - Adds Phoenix integration for the password authentication strategy
- `mix ash_authentication_phoenix.add_strategy.recovery_code` - Adds Phoenix integration for the recovery code authentication strategy
- `mix ash_authentication_phoenix.add_strategy.totp` - Adds Phoenix integration for the TOTP authentication strategy
- `mix ash_authentication_phoenix.add_strategy.webauthn` - Adds Phoenix integration for the WebAuthn authentication strategy
- `mix ash_authentication_phoenix.install` - Installs AshAuthenticationPhoenix. Invoke with `mix igniter.install ash_authentication_phoenix`
- `mix ash_authentication_phoenix.setup` - Ensures Phoenix authentication infrastructure (routes, controller, sign-in page) exists
- `mix ash_authentication_phoenix.upgrade`
- `mix ash_phoenix.gen.html` - Generates a controller and HTML views for an existing Ash resource.
- `mix ash_phoenix.gen.live` - Generates liveviews for a given domain and resource.
- `mix ash_phoenix.install` - Installs AshPhoenix into a project. Should be called with `mix igniter.install ash_phoenix`
- `mix ash_postgres.create` - Creates the repository storage
- `mix ash_postgres.drop` - Drops the repository storage for the repos in the specified (or configured) domains
- `mix ash_postgres.gen.resources` - Generates resources based on a database schema
- `mix ash_postgres.generate_migrations` - Generates migrations, and stores a snapshot of your resources
- `mix ash_postgres.install` - Installs AshPostgres. Should be run with `mix igniter.install ash_postgres`
- `mix ash_postgres.migrate` - Runs the repository migrations for all repositories in the provided (or configured) domains
- `mix ash_postgres.rollback` - Rolls back the repository migrations for all repositories in the provided (or configured) domains
- `mix ash_postgres.setup_vector` - Sets up pgvector for AshPostgres
- `mix ash_postgres.setup_vector.docs`
- `mix ash_postgres.squash_snapshots` - Cleans snapshots folder, leaving only one snapshot per resource
- `mix ash_rate_limiter.install` - Installs AshRateLimiter
- `mix ash_rate_limiter.upgrade` - Upgrades AshRateLimiter
- `mix ash_state_machine.generate_flow_charts` - Generates Mermaid Flow Charts for each resource using `AshStateMachine`
- `mix ash_state_machine.install` - Installs AshStateMachine
- `mix ash_state_machine.install.docs`
<!-- usage-rules-skill-end -->
