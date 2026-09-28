## Decisions

Sync appraisal lockfiles to style_capsule 2.0.2 after the release bump left gemfiles/*.gemfile.lock on 2.0.1. Change usr/bin/release.rb to run appraisal install so path-gem version changes update those locks before the next push.

## Effects

test #37 on main (c41eb95) failed: all three matrix jobs exited bundle with code 16 under frozen install because the gemspec version no longer matched the appraisal locks. quality used Gemfile.lock (already 2.0.2) and passed. After updating the three locks, BUNDLE_FROZEN=true bundle check succeeds for each appraisal gemfile. BUNDLE_GEMFILE=gemfiles/rails8ruby34.gemfile bundle exec polyrun parallel-rspec --workers 5 --merge-failures exited 0.

## Next

Push patch/sync-appraisal-locks-2-0-2 and confirm the test workflow on main after merge.

## Source

https://github.com/amkisko/style_capsule.rb/actions/runs/36104324632
