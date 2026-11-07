# Pressure optimizations and C-extension probe

## Participants

Andrei Makarov (@amkisko)

## Scope

`style_capsule.rb` after the pressure-cooker episode: remove pressure feature flags from `lib/`, keep permanent CSS/registry optimizations, throwaway C prefix probe (not shipped).

Host for cited numbers: Ruby 4.0.x, arm64-darwin. Host-relative, not SLOs.

## Decision: C extension

**Ship custom C extension: no.**

| Probe | Ruby median | C median | Ratio | Why not ship |
| --- | ---: | ---: | ---: | --- |
| `CssProcessor.patch_selectors` ~259 KiB CSS | **0.0444 s** | simple C prefix **0.00102 s** | ~44× | C stub is not a semantic substitute (`:host`, comments, at-rules, validation). |

Throwaway tree: `benchmarks/tmp_c_ext_probe/` (removed after measurement).

## When to try C extensions again

Retry custom C only when measurement shows the hot path is (1) a large enough share of total time and (2) a tight loop over primitives with full CSS semantics.

### Try again when

- Work is linear over CSS bytes in one rare boundary call (whole stylesheet in, scoped CSS out).
- The C implementation is a full semantic substitute for `CssProcessor` (same `:host`, comments, at-rules, validation).
- End-to-end `scope_selectors` / head-render improvement is clearly above ~20% median wall (n ≥ 3, same load). A prefix-only stub that is ~44× faster is not enough.
- Profile shows roughly ≥30–40% of time in one tight function before writing `ext/`.

### Do not retry when

- The win is only a simplified prefix stub without production CSS rules.
- The bottleneck is allocation, GC, or Rails notifications, not the scanner loop.
- Platform/ABI/maintenance cost exceeds the measured gain.

### Gate before shipping

1. Load measure: named primary series (`wall_s` / `storage_delta_bytes`) dominates at L1.
2. Profile: one tight function owns a large fraction of CSS processing time.
3. Throwaway C probe with the same semantics → only then add `ext/` if median wall drops enough on the full processor probe and tests stay green.

Short form: retry C for “full CSS byte loop”; skip C for “hashes, notifications, and partial stubs.”

## Permanent Ruby optimizations (flags removed)

| Optimization | Effect (observed during cooker / load) |
| --- | --- |
| Skip `ActiveSupport::Notifications` when no subscribers | Less instrument overhead on CSS path. |
| Comment strip only if `/*` present | Avoids useless scan. |
| `patch_selectors`: shared `scoped_prefix`, single-selector fast path, ASCII whitespace loop, `split(",", -1)` | Lower alloc/string churn on large sheets. |
| Capsule id length check before regex; frozen breakout pattern | Cheaper validation. |
| Registry in-place updates; buffered head render; frozen `<style>` fragments | Less hash rebuild on register/render. |

`StyleCapsule.pressure_opt` removed; optimized branches are unconditional. Specs: **508** examples green after cleanup.

## Documentation cleanup

Removed cooker episode docs, `pressure_run` / cooker harnesses, and joint multi-gem review content from this repository. Retained light `benchmarks/load.rb`.

## Source

- `lib/style_capsule/` permanent paths
- Throwaway C prefix probe numbers above (trees deleted)
