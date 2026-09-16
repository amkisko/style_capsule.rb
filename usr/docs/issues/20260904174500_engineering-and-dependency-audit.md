# Engineering and dependency audit of style_capsule 2.0.1

Recorded 2026-09-04. Library gem. No product UI, database, queue, or worker. Pipeline is CSS and HTML in, processor and helpers, class and thread caches, optional file writer, stylesheet registry, optional Rack head injection, HTML out.

## Decisions

This pass is an audit only. No code change, no lockfile bump, no workflow edit. Rankings follow engineering-audit order: danger, then certainty, then impact, then fix cost. Dependency-audit ran because the request named both. The published gemspec has no runtime gems. json 2.21.1 is a development lockfile pin from activesupport and rubocop, not a consumer runtime of this gem.

## Effects

Test workflow .github/workflows/test.yml runs on workflow_dispatch and push to main only. Lint and appraisal rspec do not run on pull_request. dependency-audit.yml does run on pull_request and would fail today on json 2.21.1 in Gemfile.lock and gemfiles/*.gemfile.lock.

Inline CSS is interpolated into style tags and marked html_safe. Helpers use raw(scoped_css). README documents Theme#scoped_css from stored CSS and shows raw in ERB. README Security section claims XSS prevention via Rails HTML escaping. Capsule id is validated. CSS body is not sanitized for a style-tag break. Specs cover attribute escaping in StandaloneHelper, not a closing style tag in CSS.

Non-Rails file stylesheet fallback interpolates option keys and values into a link tag. AssetPath rejects path traversal, quotes, angle brackets, and overlong logical paths. It does not reject a javascript: href scheme or quote characters in option values.

StylesheetRegistry @inline_cache and @manifest are process-wide hashes without a mutex. Component CSS cache and helper scope cache cap at 256. File path cache caps at 512 with a mutex. Inline cache only drops entries that have expires_at. Registrations with type proc or no TTL grow for the process lifetime. README claims thread-safe head rendering.

HeadInjectionMiddleware buffers a 2xx HTML body to inject before the first closing head tag. Chunked transfer is skipped. Live and SSE caveats are documented. Impact of the buffer under large HTML is inference. No RSS or timing bench this session.

CssFileWriter falls back to /tmp/style_capsule, writes CSS, then returns nil so the registry can fall back to inline. Shared-host /tmp collision and symlink follow are inference. Fallback specs exist.

README Requirements still say Ruby >= 3.0 and Rails >= 6.0. Gemspec required_ruby_version is >= 3.4. Development Rails gems are >= 7.0, < 9.0. Appraisals cover Rails 7.2 and 8.1 on Ruby 3.4 and 4.0. README badge still uses v=2.0.0. Version constant is 2.0.1.

lib/style_capsule/stylesheet_registry.rb is 827 lines. House guidance prefers around 150 with a 300 ceiling. AssetPath and HeadInjectionMiddleware are already split out.

CssProcessor walks CSS with regex up to 1MB. A comment claims MAX_CSS_SIZE mitigates ReDoS. ReDoS was not proven. Spike was not run.

Dependabot lists npm and docker at directory / with no package.json and no Dockerfile. Bundler updates only directory /. Appraisal lockfiles under gemfiles/ are not a separate Dependabot directory.

memory_profiler is a development gemspec dependency. No spec or lib caller was found this session.

bundle-audit check --no-update on Gemfile.lock, gemfiles/rails72.gemfile.lock, gemfiles/rails8ruby34.gemfile.lock, and gemfiles/rails8ruby4.gemfile.lock all reported json 2.21.1, CVE-2026-71847, GHSA-9hj4-r449-hfvc, fix >= 2.21.2. Advisory database updated 2026-09-04, commit 478717d. Evidence is in usr/docs/dependencies/20260904174500_json-cve-2026-71847.md.

bundle outdated --strict listed erb 6.0.6 to 6.0.7, io-console 0.8.2 to 0.9.2, json 2.21.1 to 2.21.2, polyrun 2.2.2 to 2.2.4, psych 5.4.0 to 5.5.0, rack 3.2.6 to 3.2.7, reline 0.6.3 to 0.7.0, view_component 4.12.0 to 4.15.0, webmock 3.26.2 to 3.26.4, zeitwerk 2.8.2 to 2.8.3. Release-date lag for those three named packages versus latest: json 18 days, polyrun 41 days, view_component 82 days. Full lockfile libyears versus every gem latest date was not computed. rspec was not run.

Modes skipped with reason: product-surface, this gem has no own UI. Privacy, the gem does not collect personal data; host CSS may appear in instrumentation payloads when a subscriber exists. Observability, no product runtime or SLO of its own. Learned systems, none. Resource cheaper-or-greener without a bench stays inference. Identity claims without HAR or log fixtures stay inference.

A later pass on 2026-09-04 implemented the ranked fixes on branch patch/audit-fixes. See usr/docs/changelogs/20260904180000_audit-fixes.md. bundle exec rspec: 498 examples, 0 failures. bundle exec rubocop and bundle exec rbs validate ran after the cop fix in CssProcessor.reject_style_element_breakout!. This file remains the audit record.

## Next

stylesheet_registry.rb remains over the house line-count ceiling. Split only if a later change owns that file. json lockfile bump is tracked in usr/docs/dependencies/20260904174500_json-cve-2026-71847.md.

## Source

engineering-audit and dependency-audit skills in .agents/skills. README Requirements and Security. style_capsule.gemspec. lib/style_capsule/version.rb. lib/style_capsule/stylesheet_registry.rb. lib/style_capsule/helper.rb. lib/style_capsule/standalone_helper.rb. lib/style_capsule/css_file_writer.rb. lib/style_capsule/head_injection_middleware.rb. .github/workflows/test.yml. .github/workflows/dependency-audit.yml. .github/dependabot.yml. Gemfile.lock and gemfiles/*.gemfile.lock. bundle-audit 0.9.x against ruby-advisory-db commit 478717d. bundle outdated --strict. ruby -Ilib require of StyleCapsule::ClassRegistry. Rubygems version API dates for json, polyrun, and view_component. Downstream canvas is outside this repo.
