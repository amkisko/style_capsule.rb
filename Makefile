.PHONY: release lint test

release:
	ruby usr/bin/release.rb

lint:
	bundle exec rubocop
	bundle exec rbs validate

test:
	bundle exec rspec
