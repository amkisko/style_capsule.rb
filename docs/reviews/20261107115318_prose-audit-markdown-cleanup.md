# Prose audit: markdown cleanup

## Participants

Andrei Makarov (@amkisko)

## Decisions

Apply writing-prose / AGENTS plain-prose rules beyond docs timestamp trees for product and maintainer markdown that still used bold, italic, or non-ASCII punctuation for emphasis. Keep headings, lists, links, badges, and fenced code. Prefer ASCII punctuation (`-`, `->`, `>=`, straight quotes).

## Effects

Timestamp trees (earlier in this note's first cut):

- `docs/reviews/20261107114500_fiber-isolation-experimental.md`: labelled bullets instead of a median table; no bold or multiplication-sign glyph.
- `docs/reviews/20261106210000_pressure-optimizations-and-c-ext.md`: prose and bullets instead of C-probe and optimization tables; no bold, Unicode arrow, curly quotes, or comparison glyphs.

Extended pass:

- `README.md`: removed bold labels and emphasis; gem badge query bumped to 2.0.4; softened the "without Rails" note.
- `CHANGELOG.md`: replaced em dash in the 2.0.4 load-harness bullet with ASCII `-`.
- `spec/README.md`: removed bold guideline labels.
- `.github/pull_request_template.md`: removed italic intro and bold checklist labels.

Already clean (no change): `docs/non_rails_support.md`, `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `GOVERNANCE.md`, `LICENSE.md`, `rfcs/README.md`.

## Next

- Keep new docs notes in labelled lists rather than tables.
- Leave badge images and hyperlinks as the only non-prose chrome in README.

## Source

- AGENTS.md Writing and changelog prose checks
- writing-prose skill
- `README.md`
- `CHANGELOG.md`
- `spec/README.md`
- `.github/pull_request_template.md`
- `docs/reviews/20261107114500_fiber-isolation-experimental.md`
- `docs/reviews/20261106210000_pressure-optimizations-and-c-ext.md`
