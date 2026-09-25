# RFC 0006: Cache strategies and CSS file writer

- Feature Name: cache-and-file-writer
- Type: Standards Track
- Status: Stable
- Created: 2026-09-25
- Author: Andrei Makarov
- Relates: RFC 0002, RFC 0004, RFC 0005

## Summary

Configure how scoped CSS is reused: no cache (default), time-based TTL, custom proc, or file-based output for HTTP caching. File writes go through `CssFileWriter` with a configurable output directory and a tempdir fallback when the primary path is not writable. Instrumentation events report scope and write outcomes when subscribers exist.

## Motivation

Re-scoping CSS on every render wastes CPU. Shared head CSS needs stable URLs for browsers and CDNs. Read-only app directories (common in containers) must not take down the page when file cache is enabled; falling back to inline CSS keeps the UI working. Operators need optional metrics without paying instrumentation cost when nobody listens.

## Guide-level explanation

`style_capsule cache_strategy: :none` (default). Time: `style_capsule cache_strategy: :time, cache_ttl: 3600` (or an ActiveSupport duration). Proc: pass a callable that returns `[cache_key, should_cache, expires_at]`. File: `style_capsule cache_strategy: :file` and define `def self.component_styles`. Configure `StyleCapsule::CssFileWriter.configure(output_dir:, filename_pattern:, fallback_dir:)`. Precompile with `bin/rails style_capsule:build` or during `assets:precompile`. Clear with `bin/rails style_capsule:clear`.

## Reference-level explanation

`cache_strategy` accepts Symbol, String (coerced to Symbol), or Proc. File strategy REQUIRES class-method `component_styles`; instance-only styles MUST NOT silently write unstable files. Primary write failure MAY fall back under `Dir.tmpdir` via the configured fallback directory; when fallback is in use for serving, the gem MAY render inline CSS instead of a broken asset URL. Class CSS cache and registry inline cache bounds are defined in RFC 0004 and RFC 0005.

Instrumentation (zero-overhead without subscribers): `style_capsule.css_processor.scope`, `style_capsule.css_file_writer.write`, `style_capsule.css_file_writer.fallback`, `style_capsule.css_file_writer.fallback_failure`, `style_capsule.css_file_writer.write_failure`.

## Security considerations

File writes MUST stay under configured directories. Logical path and size rules from RFC 0003 and RFC 0005 still apply to content being cached or written.

## Registrar

Public methods: `style_capsule` cache options; `StyleCapsule::CssFileWriter.configure`. Rake tasks: `style_capsule:build`, `style_capsule:clear`. Notification names listed above.

## Drawbacks

File strategy couples components to class-level styles. Fallback directories can diverge from the asset pipeline URL map, which is why inline fallback exists. Proc strategies push correctness onto the host.

## Rationale and alternatives

Always writing files would fail on read-only disks and slow small apps. Only Redis or Rails.cache would add a mandatory store dependency. Skipping instrumentation would hide write and fallback failures in production.

## Prior art

Rails asset precompile; Propshaft build output directories; ActiveSupport::Notifications.

## Unresolved questions

Whether file strategy should support a host-supplied digester contract beyond the current filename pattern proc.

Whether instrumentation payload fields should be frozen in a dedicated Standards Track RFC when external dashboards depend on them.
