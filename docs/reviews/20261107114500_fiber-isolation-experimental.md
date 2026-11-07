# Experimental Fiber isolation review

## Participants

Andrei Makarov (@amkisko)

## Decisions

Ship experimental `StyleCapsule.isolation_level = :fiber`. Default stays `:thread`. Fiber mode stores request-scoped stylesheet registry state (inline CSS and render-time file paths) and the helper scope cache on the current Fiber. When `:fiber` is set, the registry bypasses `ActiveSupport::CurrentAttributes` for those keys so interleaved Fibers on one Thread do not share request bag state. Do not flip Rails `ActiveSupport::IsolatedExecutionState.isolation_level` from this API; Falcon-style apps set Rails isolation separately.

Accept the feature on measured baselines (n = 3 samples, `SCENARIO=fiber`, `BENCH_FIBER_N=3000`, `BENCH_FIBER_COUNT=8`, Ruby 4.0.7 arm64-darwin). Keep the experimental label until a production Fiber server validates the API.

## Effects

Implementation: `lib/style_capsule/execution_state.rb`, wired from `StylesheetRegistry` request stores and `HelperScopeCache`. Specs cover concurrent Fiber isolation, sibling non-leak, and shared-stack behavior under `:thread`. `make bench-fiber` / `SCENARIO=fiber` covers sequential Fiber, concurrent Fiber under `:fiber`, and concurrent Fibers under default `:thread`.

Median of three host samples (`benchmarks/output/fiber_sample_{1,2,3}.log`):

| Series | median ops/s | median wall (s) | alloc |
| --- | ---: | ---: | ---: |
| `baseline_fiber_sequential` | 200561.6 | 0.0150 | 81056 |
| `baseline_fiber_concurrent` | 174286.9 | 0.0172 | 103165 |
| `baseline_thread_concurrent_fibers` | 162610.4 | 0.0184 | 97118 |

Fiber concurrent isolation stays in the same band as the shared-stack `:thread` concurrent Fiber path (about **1.07×** median ops/s). Sequential Fiber register/render remains the fastest of the three series.

## Next

- Keep experimental label until a production Fiber server validates the API.
- Optional later: calibrate pressure ceilings for fiber series if a hot path regresses.

## Source

- `lib/style_capsule/execution_state.rb`
- `lib/style_capsule/stylesheet_registry.rb`
- `lib/style_capsule/helper_scope_cache.rb`
- `spec/style_capsule/fiber_isolation_spec.rb`
- `benchmarks/load.rb` (`SCENARIO=fiber`)
- `benchmarks/output/fiber_sample_1.log`
- `benchmarks/output/fiber_sample_2.log`
- `benchmarks/output/fiber_sample_3.log`
