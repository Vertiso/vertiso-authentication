# Changelog

All notable changes to Vertiso Authentication will be documented in this
file.

## Unreleased

- Extract the production authentication baseline shared by GoalMindr and
  Vertiso Memory into a reusable Rails Engine.
- Add password, email-confirmation, password-reset, browser-session, linked
  OAuth identity, ViewComponent, theming, and generator support.
- Add SQLite and PostgreSQL portability and public-package quality gates.
- Make Google, Apple, and GitHub OmniAuth strategies optional host
  dependencies while retaining production construction profiles.
- Support arbitrary OmniAuth strategies with deferred positional arguments and
  keyword options.
- Support optional host-owned provider icon classes without requiring an icon
  library.
- Encrypt provider-issued user credential payloads at rest with Rails Active
  Record Encryption, validate host keys at boot, and document a coordinated
  migration of legacy plaintext rows.
- Preserve the patched `oauth2` security floor, isolate host-owned provider
  values from immutable middleware snapshots, and validate known-provider
  construction arguments.
- Prove provider-free host bundles and document generic strategy plugin loading.
