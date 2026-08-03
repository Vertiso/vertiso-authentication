# Vertiso Authentication

Reusable authentication for modern Rails applications.

`vertiso-authentication` extracts authentication behavior already operating in
GoalMindr and Vertiso Memory into a configurable Rails Engine. It connects to
an application's existing principal model, which the host application defines
and owns.

> [!IMPORTANT]
> This project is in internal preview. Its production-proven behavior is being
> extracted and validated through application adoptions before the first
> public release. Treat the documented API as provisional until then.

## Goals

- Keep the host application's principal model as the canonical identity
  record.
- Support password authentication, email confirmation, password recovery, and
  multiple linked external identities.
- Preserve provider-issued user credentials for host application API calls.
- Provide persistent browser authentication and database-backed session
  metadata.
- Ship Minitest-covered ViewComponents with host-controlled theming and
  overrides.
- Deliver fixes through gem upgrades instead of copied application code.
- Stay independent of billing, tenancy, accounts, seats, and authorization.

## Non-goals

This gem does not provide:

- Roles, permissions, policies, or application authorization.
- Accounts, organizations, memberships, seats, or subscriptions.
- Stripe or other ecommerce behavior.
- API bearer-token issuance or an OAuth 2 authorization server.
- MCP server transport or authorization.

Those concerns belong to the host application or focused companion gems.
`vertiso-authorization` will provide authorization.
`vertiso-mcp-auth` may provide MCP and OAuth 2 authorization-server behavior
while depending on this gem.

The dependency direction remains one-way. Authentication does not depend on
authorization, MCP, billing, or ecommerce.

## Requirements

- Ruby 4.0 or newer
- Rails 8.1 or newer
- ViewComponent 4.0 or newer
- An Active Record-compatible relational database

These are lower bounds, not upper pins. The gem will accept current compatible
releases so applications can receive maintenance and security updates.

PostgreSQL is not required. The engine uses portable Active Record schema and
query interfaces and supports SQLite. Representative CI adapters will include
SQLite and PostgreSQL.

The gem uses Minitest and Rails' built-in test infrastructure. It follows a
Rails-core-first dependency policy. ViewComponent, Tailwind integration,
`bcrypt`, OmniAuth, the supported provider strategies, and OmniAuth CSRF
protection are intentional dependencies.

## Architecture

Vertiso Authentication is a hybrid, namespaced Rails Engine.

### The host owns the principal

Each application configures one principal class, normally `User`. The host
model owns the canonical authentication fields:

- Normalized, unique primary email
- Unique public user name
- Password digest
- Email-confirmation timestamp

Email, user-name, and email-confirmation attribute names are configurable. An
existing model can map `handle` to the user-name contract or
`email_confirmed_at` to the email-confirmation contract.

The host remains free to associate a principal with any customer account,
household, organization, membership, seat, billing, or authorization model.

Including `Vertiso::Authentication::Authenticatable` applies Rails'
`has_secure_password`. The host therefore provides the conventional
`password_digest` column; it is not an attribute mapping.

### The gem owns authentication infrastructure

The engine owns:

- Browser authentication behavior
- Authentication-session metadata
- Linked external identities
- Password and external-provider authentication flows
- Email confirmation and password recovery
- Provider email-trust behavior
- Namespaced controllers and mailers
- Default ViewComponents and theme tokens
- Installation, migration, route, and component generators
- Minitest integration and regression coverage

The default implementation remains in the gem so a normal upgrade can deliver
authentication fixes to every adopting application.

## Production lineage

This is an extraction, not a greenfield authentication implementation.

GoalMindr and Vertiso Memory are the production authorities. When their
implementations differ, the extraction selects one existing production
implementation and records that provenance in compatibility tests.

TheMeowBeneath is a pre-launch compatibility target. It does not define the
preferred authentication behavior.

The baseline preserves:

- Rails `has_secure_password` authentication by email or unique user name.
- Rails `generates_token_for` tokens for browser authentication, email
  confirmation, and password recovery.
- A host-configurable browser-authentication lifetime with a long-lived
  default.
- GoalMindr's database-backed authentication-session record.
- Active and inactive session-state derivation from GoalMindr's session schema,
  as the approved session-model reconciliation.
- GoalMindr's Google and Apple OmniAuth protocol configuration.
- Vertiso Memory's provider-specific email trust policy.
- Multiple simultaneously linked Google, Apple, GitHub, and other external
  identities.
- Multiple linked identities from the same provider when provider UIDs differ.
- Per-identity provider profile and credential payloads.
- Neutral password-recovery responses that do not disclose account existence.
- Existing rate limits, session rotation, and return-location behavior.
- Transactional principal and linked-identity creation.
- Existing ViewComponent authentication surfaces and themes.

The extraction baseline does not include a security redesign. Behavioral
changes and hardening are considered only after GoalMindr, Vertiso Memory, and
TheMeowBeneath pass their compatibility suites using the gem.

The development-only seeded provider is the sole approved additive baseline
feature.

## Browser authentication and sessions

The browser credential is a Rails `generates_token_for` token stored through
the production encrypted-cookie and Rails-session flow. Its lifetime is
host-configurable and long-lived by default.

The engine's database-backed `AuthenticationSession` schema and model are
extracted from GoalMindr's `UserSession`. It stores session metadata such as
the principal, session identifier, network and user-agent information,
activity time, and expiry time.

As an explicitly approved reconciliation, the gem derives active and inactive
session states from those properties. GoalMindr's separate
`ActiveUserSession` telemetry model is not extracted.

The metadata record does not replace or redefine the browser credential.

## External identities

The engine stores providers and linked accounts under the
`Vertiso::Authentication` namespace.

The pair `(provider, provider_uid)` is the durable external identifier and can
belong to only one principal. A principal can link many external identities,
including more than one identity from the same provider.

Each linked account retains its callback-provided profile and
`auth.credentials` payload. A host can select a linked identity and use its
provider-issued access or refresh credentials when the provider has granted
the required scopes.

### Email trust

| Provider | Email policy |
| --- | --- |
| Google | Authoritative when present |
| Apple | Authoritative when present |
| GitHub | Trusted only when it matches a verified primary provider email |
| Other configured provider without an explicit trust policy | Untrusted |
| Any blank email | Untrusted |

A trusted provider email may link to an existing principal with the same
canonical email. An untrusted or user-entered email collision requires
authentication to the existing account before linking.

Providers that are not configured and active are rejected. A configured
provider without an authoritative email-verification signal can still
authenticate, but its email is not marked verified and cannot automatically
link an existing account.

### Provider application credentials

The host supplies provider application credentials through configuration.
Values can come from environment variables, Rails encrypted credentials, a
platform secret store, or another host-controlled source.

The engine will accept value resolvers instead of prescribing environment
variable names:

```ruby
Vertiso::Authentication.configure do |config|
  config.oauth_provider(
    :google_oauth2,
    client_id: -> { ENV.fetch("GOOGLE_CLIENT_ID") },
    client_secret: -> {
      Rails.application.credentials.dig(
        :oauth,
        :google,
        :client_secret
      )
    },
    scope: "email profile"
  )
end
```

Provider application secrets are passed to the provider strategy. They are not
stored in the engine's provider or linked-account records.

### Developer provider

The optional developer provider is available only when
`Rails.env.development?`.

It provides one-click authentication into a host-configured seeded developer
identity without exposing a reusable password. The request still traverses the
normal local OmniAuth callback, linked-account, credential, and browser-session
flow.

The seeded identity must already exist. Missing developer configuration or a
missing identity rejects the login and does not create a principal.

The developer provider is not registered or rendered outside the Rails
development environment, and its callback rejects non-development requests.

## Host integration

The principal integration is:

```ruby
class User < ApplicationRecord
  include Vertiso::Authentication::Authenticatable
end
```

```ruby
Vertiso::Authentication.configure do |config|
  config.principal_class_name = "User"
  config.email_attribute = :email
  config.user_name_attribute = :user_name
  config.email_confirmed_at_attribute = :email_verified_at
end
```

The host application must define its principal model before running the
installer. The installer aborts if the configured principal model is missing;
it does not generate the host's canonical identity model. Public authentication
paths and successful-login destinations remain host-configurable.

Executable documentation and generator tests cover the configuration and
installation contracts.

## ViewComponents and theming

ViewComponent is a runtime dependency.

The gem will provide default components for:

- Authentication shell
- Login and signup
- Password creation and recovery
- Email confirmation
- External-provider buttons
- Linked-identity management

Surface-level customization uses semantic theme inputs for color, typography,
spacing, borders, radii, surfaces, buttons, and fields.

Applications needing structural changes can run a generator that copies the
default components and templates into the host, where they override the engine
defaults.

Installation also registers engine component templates as Tailwind content
sources and connects engine styles to the host build. A dummy-host production
build test verifies that representative component utilities are emitted.

Components and generated overrides are tested with Minitest and ViewComponent's
test helpers.

## Security baseline

- Unconfigured or inactive providers are rejected.
- Untrusted or blank provider emails are not marked verified and cannot
  automatically link an existing principal.
- Passwords are stored through `has_secure_password`.
- Browser, confirmation, and recovery credentials use Rails signed,
  purpose-bound token infrastructure.
- Rails sessions rotate on login and logout.
- Browser tokens use encrypted, HTTP-only cookies. The selected production
  helper controls environment-specific secure flags, while SameSite behavior
  follows the host application's Rails cookie policy.
- Login and recovery responses preserve the selected production
  account-enumeration behavior.
- Public authentication and email-dispatch endpoints retain production rate
  limits.
- Authentication remains separate from application authorization.
- Security behavior is covered by compatibility and regression tests.

Provider-issued user credential payloads are intentionally retained per linked
identity so adopting applications can make authorized provider API calls.

Do not open a public issue containing an exploit, credential, token, or user
data. A `SECURITY.md` and GitHub private vulnerability-reporting instructions
are mandatory before public release.

See [SECURITY.md](SECURITY.md) for private reporting instructions and the
current support policy.

## Development and quality gates

This repository uses Minitest and SQLite by default:

```bash
bundle exec rake test
bundle exec rake test:sqlite
```

Run the identical suite against a dedicated PostgreSQL test database:

```bash
DATABASE_URL=postgresql://localhost/vertiso_authentication_test \
  bundle exec rake test:postgresql
```

Run individual quality and package gates:

```bash
bundle exec rake quality:rubocop
bundle exec rake quality:brakeman
bundle exec rake quality:audit
bundle exec rake package:validate
```

The complete local gate requires `DATABASE_URL` to identify a PostgreSQL test
database:

```bash
DATABASE_URL=postgresql://localhost/vertiso_authentication_test \
  bundle exec rake ci
```

The project remains in internal adoption before its first public release. The
compatibility baseline and public API are not final until the planned host
applications run against the extracted gem.

## Development status

Phase 0 establishes the repository, public contract, and private extraction
record.

Planned phases:

1. Scaffold the engine and Minitest dummy applications.
2. Extract principal mapping and password behavior.
3. Extract browser authentication and GoalMindr's session record.
4. Extract Vertiso Memory's confirmation and password-recovery behavior.
5. Extract external identities and provider trust.
6. Add the development-only seeded provider.
7. Extract and theme the ViewComponent interfaces.
8. Replace the tailored core authentication in GoalMindr and Vertiso Memory.
9. Adapt TheMeowBeneath to the selected production baseline.
10. Run all gem and application compatibility suites.
11. Consider hardening and enhancements.
12. Stabilize the public API and publish the first release.

The repository will use semantic versioning, a changelog, upgrade guides,
documented public APIs, and CI covering its supported runtime bounds.

## License

Vertiso Authentication is available under the [MIT License](LICENSE).

Copyright © 2026 Vertiso Corporation.

Contributions are accepted under the same license. Contributors are encouraged
to submit generally useful fixes and improvements upstream.
