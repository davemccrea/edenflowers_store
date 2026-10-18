# Add Credo with the module-layout and alias checks

Status: ready-for-agent
Type: chore

## What to build

- `{:credo, "~> 1.7", only: [:dev, :test], runtime: false}` in `mix.exs`.
- `.credo.exs` that enables only these checks, so the first run reports conventions and nothing else:
  - `Credo.Check.Readability.StrictModuleLayout`, configured `order: [:moduledoc, :behaviour, :use, :require, :import, :alias, :module_attribute]`, ignoring `:module_attribute` if it flags attributes that legitimately follow a `use` (e.g. `use Oban.Worker` options), and with `ignore` for whatever proves noisy.
  - `Credo.Check.Readability.AliasOrder`
  - `Credo.Check.Readability.MultiAlias`
  - `Credo.Check.Consistency.MultiAliasImportRequireUse`
  - `Credo.Check.Design.AliasUsage`, with `if_nested_deeper_than: 1` and `if_called_more_often_than: 1`, and `excluded_namespaces` / `excluded_lastnames` for anything that reads worse aliased. Check what it flags in Ash DSL blocks; if it doesn't see module arguments there, ticket 02's sweep covers them.
- `"credo --strict"` in the `precommit` alias in `mix.exs`, after `format --check-formatted`.
- Fix everything the checks flag. Mostly mechanical: sorting aliases, splitting grouped ones, reordering the 8 files with directives out of order, moving the six `require Ash.Query` / `import Ash.Expr` out of the admin search helpers (with `only: [expr: 1]`).

## Acceptance criteria

- [ ] `mix credo --strict` passes on lib/ and test/
- [ ] `mix precommit` runs Credo and passes
- [ ] No behaviour change; the existing suite passes

## Comments
