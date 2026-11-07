#!/usr/bin/env ruby
# frozen_string_literal: true

# Load probe: wall time, CPU time, allocations.
#
# Usage:
#   env -u BUNDLE_PATH bundle exec ruby benchmarks/load.rb
#   make bench-load
#   make bench-fiber
#   CSS_RULES=50 CSS_SELECTORS_PER_RULE=180 BENCH_REPS=3 env -u BUNDLE_PATH bundle exec ruby benchmarks/load.rb
#   SCENARIO=fiber BENCH_FIBER_N=3000 BENCH_FIBER_COUNT=8 env -u BUNDLE_PATH bundle exec ruby benchmarks/load.rb
#
# Env:
#   SCENARIO=css|fiber (default css)
#   CSS_RULES — rules in synthetic sheet (default 45)
#   CSS_SELECTORS_PER_RULE — comma-separated simple selectors per rule (default 160)
#   BENCH_REPS — repetitions per CSS sample (default 2)
#   BENCH_FIBER_N — register/render ops for fiber scenario (default 3000)
#   BENCH_FIBER_COUNT — concurrent Fibers per wave (default 8)
#   STYLE_CAPSULE_LIB — optional path to lib/ (defaults to ../lib from this file)

lib = ENV["STYLE_CAPSULE_LIB"] || File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "style_capsule"

module StyleCapsule
  module Bench
    module Load
      module_function

      CAPSULE_ID = "bench_capsule"

      def env_int(name, default)
        Integer(ENV.fetch(name, default.to_s))
      end

      def build_synthetic_css(rules, selectors_per_rule)
        parts = []
        rules.times do |r|
          sels = selectors_per_rule.times.map { |i| ".b#{r}_#{i}" }.join(",")
          parts << "#{sels}{color:red}"
        end
        parts.join
      end

      def ensure_fits_max_css!(css)
        return if css.bytesize <= StyleCapsule::CssProcessor::MAX_CSS_SIZE

        raise ArgumentError,
          "Synthetic CSS #{css.bytesize}B exceeds CssProcessor::MAX_CSS_SIZE (#{StyleCapsule::CssProcessor::MAX_CSS_SIZE})"
      end

      def workload_once!(css, strategy:)
        StyleCapsule::StylesheetRegistry.clear
        StyleCapsule::StylesheetRegistry.clear_manifest

        scoped =
          case strategy
          when :patch then StyleCapsule::CssProcessor.scope_selectors(css, CAPSULE_ID)
          when :nesting then StyleCapsule::CssProcessor.scope_with_nesting(css, CAPSULE_ID)
          else
            raise ArgumentError, "strategy must be :patch or :nesting"
          end

        StyleCapsule::StylesheetRegistry.register_inline(scoped, capsule_id: CAPSULE_ID)
        StyleCapsule::StylesheetRegistry.render_head_stylesheets(nil)
      end

      def sample!(rules, selectors_per_rule, reps, strategy:, label:)
        css = build_synthetic_css(rules, selectors_per_rule)
        ensure_fits_max_css!(css)

        alloc_before = GC.stat(:total_allocated_objects)
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        c0 = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
        reps.times { workload_once!(css, strategy: strategy) }
        c1 = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
        t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        alloc_after = GC.stat(:total_allocated_objects)

        wall = t1 - t0
        cpu = c1 - c0
        allocs = alloc_after - alloc_before

        {
          "label" => label,
          "strategy" => strategy.to_s,
          "rules" => rules,
          "selectors_per_rule" => selectors_per_rule,
          "reps" => reps,
          "wall_s" => wall.round(6),
          "cpu_s" => cpu.round(6),
          "allocations" => allocs,
          "wall_per_rep_ms" => ((wall / reps) * 1000).round(4),
          "cpu_per_rep_ms" => ((cpu / reps) * 1000).round(4),
          "allocations_per_rep" => (allocs.to_f / reps).round(1)
        }
      end

      def with_isolation(level)
        previous = StyleCapsule.isolation_level
        StyleCapsule.isolation_level = level
        yield
      ensure
        StyleCapsule.isolation_level = previous
        StyleCapsule::StylesheetRegistry.clear
      end

      def measure_fiber_ops!(label, ops, fiber_count:, isolation:)
        with_isolation(isolation) do
          alloc_before = GC.stat(:total_allocated_objects)
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          c0 = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)

          i = 0
          while i < ops
            batch = [fiber_count, ops - i].min
            fibers = batch.times.map do |f|
              idx = i + f
              Fiber.new do
                StyleCapsule::StylesheetRegistry.clear
                StyleCapsule::StylesheetRegistry.register_inline(
                  ".f#{idx}{color:red}",
                  namespace: :"fiber_#{f}",
                  capsule_id: "c#{idx}"
                )
                Fiber.yield
                StyleCapsule::StylesheetRegistry.render_head_stylesheets(nil)
              end
            end
            fibers.each(&:resume)
            fibers.each(&:resume)
            i += batch
          end

          c1 = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
          t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          alloc_after = GC.stat(:total_allocated_objects)

          wall = t1 - t0
          {
            "label" => label,
            "isolation_level" => isolation.to_s,
            "fiber_count" => fiber_count,
            "ops" => ops,
            "wall_s" => wall.round(6),
            "cpu_s" => (c1 - c0).round(6),
            "allocations" => alloc_after - alloc_before,
            "ops_per_s" => (ops / wall).round(1)
          }
        end
      end

      def measure_fiber_sequential!(label, ops)
        with_isolation(:fiber) do
          alloc_before = GC.stat(:total_allocated_objects)
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          c0 = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)

          ops.times do |idx|
            StyleCapsule::StylesheetRegistry.clear
            StyleCapsule::StylesheetRegistry.register_inline(
              ".s#{idx}{color:blue}",
              namespace: :seq,
              capsule_id: "s#{idx}"
            )
            StyleCapsule::StylesheetRegistry.render_head_stylesheets(nil)
          end

          c1 = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID)
          t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          alloc_after = GC.stat(:total_allocated_objects)

          wall = t1 - t0
          {
            "label" => label,
            "isolation_level" => "fiber",
            "ops" => ops,
            "wall_s" => wall.round(6),
            "cpu_s" => (c1 - c0).round(6),
            "allocations" => alloc_after - alloc_before,
            "ops_per_s" => (ops / wall).round(1)
          }
        end
      end

      def run_css!
        rules = env_int("CSS_RULES", 45)
        selectors = env_int("CSS_SELECTORS_PER_RULE", 160)
        reps = env_int("BENCH_REPS", 2)

        puts "StyleCapsule load bench scenario=css rules=#{rules} selectors_per_rule=#{selectors} reps=#{reps}"

        rows = [
          sample!(rules, selectors, reps, strategy: :patch, label: "selector_patching"),
          sample!(rules, selectors, reps, strategy: :nesting, label: "nesting")
        ]

        rows.each do |r|
          puts format(
            "%s [%s] wall=%ss cpu=%ss allocs=%i (~%.0f/rep) wall/rep=%sms",
            r["label"],
            r["strategy"],
            r["wall_s"],
            r["cpu_s"],
            r["allocations"],
            r["allocations_per_rep"],
            r["wall_per_rep_ms"]
          )
        end
      end

      def run_fiber!
        fiber_n = env_int("BENCH_FIBER_N", 3000)
        fiber_count = env_int("BENCH_FIBER_COUNT", 8)

        puts "StyleCapsule fiber bench fiber_n=#{fiber_n} fiber_count=#{fiber_count}"

        rows = [
          measure_fiber_sequential!("baseline_fiber_sequential", fiber_n),
          measure_fiber_ops!("baseline_fiber_concurrent", fiber_n, fiber_count: fiber_count, isolation: :fiber),
          measure_fiber_ops!("baseline_thread_concurrent_fibers", fiber_n, fiber_count: fiber_count, isolation: :thread)
        ]

        rows.each do |r|
          puts format(
            "%s isolation=%s ops=%i wall=%ss cpu=%ss allocs=%i ops/s=%.1f",
            r["label"],
            r["isolation_level"],
            r["ops"],
            r["wall_s"],
            r["cpu_s"],
            r["allocations"],
            r["ops_per_s"]
          )
        end

        FileUtils.mkdir_p(File.expand_path("output", __dir__))
        path = File.expand_path("output/fiber_sample.log", __dir__)
        File.write(path, rows.map(&:inspect).join("\n") + "\n")
        puts "wrote #{path}"
      end

      def run!
        scenario = ENV.fetch("SCENARIO", "css")
        case scenario
        when "css" then run_css!
        when "fiber" then run_fiber!
        else
          raise ArgumentError, "Unknown SCENARIO=#{scenario.inspect} (css|fiber)"
        end
      end
    end
  end
end

require "fileutils"
StyleCapsule::Bench::Load.run! if $PROGRAM_NAME == __FILE__
