# Prose audit: markdown cleanup in docs timestamp trees

## Participants

Andrei Makarov (@amkisko)

## Decisions

Apply writing-prose / AGENTS rules to `docs/` timestamp trees: plain prose readable without a rendered preview. No markdown tables, bold, italic, or other styling. Prefer ASCII punctuation (`x`, `->`, `>=`, straight quotes).

Out of scope for this pass: README.md and CHANGELOG.md (not timestamp trees; product/changelog markdown remains). Permanent `docs/non_rails_support.md` left unchanged.

## Effects

Cleaned:

- `docs/reviews/20261107114500_fiber-isolation-experimental.md`: replaced median sample table with labelled bullets; removed bold and multiplication-sign glyph (`1.07x`).
- `docs/reviews/20261106210000_pressure-optimizations-and-c-ext.md`: replaced C-probe and optimization tables with prose and bullets; removed bold, Unicode arrow, curly quotes, and `>=` / `x` glyphs.

Scan after edit: no markdown tables, bold/italic markers, or banned Unicode punctuation remain under `docs/**/*.md`.

## Next

- Prefer labelled lists for numeric series in future review notes.
- Optional later: separate README tone pass if product docs should drop section bold.

## Source

- AGENTS.md Writing and changelog prose checks
- writing-prose skill
- `docs/reviews/20261107114500_fiber-isolation-experimental.md`
- `docs/reviews/20261106210000_pressure-optimizations-and-c-ext.md`
