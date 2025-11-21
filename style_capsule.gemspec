# frozen_string_literal: true

require_relative "lib/style_capsule/version"

Gem::Specification.new do |spec|
  spec.name = "style_capsule"
  spec.version = StyleCapsule::VERSION
  spec.authors = ["Andrei Makarov"]
  spec.email = ["contact@kiskolabs.com"]

  spec.summary = "Attribute-based CSS scoping for Phlex, ViewComponent, and ERB templates."
  spec.description = "Provides component-scoped CSS encapsulation using [data-capsule] attributes for Phlex components, ViewComponent components, and ERB templates. Styles are automatically scoped to prevent leakage between components. Inspired by component-based CSS approaches like Angular's view encapsulation and CSS modules. Works with Rails and can be used standalone in other Ruby frameworks (Sinatra, Hanami, etc.) or plain Ruby scripts."
  spec.homepage = "https://github.com/amkisko/style_capsule.rb"
  spec.license = "MIT"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*", "sig/**/*", "README.md", "LICENSE*", "CHANGELOG.md", "SECURITY.md"].select { |f| File.file?(f) }
  end
  spec.files += Dir["lib/tasks/**/*.rake"]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "changelog_uri" => "https://github.com/amkisko/style_capsule.rb/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/amkisko/style_capsule.rb/issues",
    "documentation_uri" => "https://github.com/amkisko/style_capsule.rb#readme",
    "rubygems_mfa_required" => "true"
  }

  spec.add_development_dependency "activesupport", ">= 6.0", "< 9.0"  # Optional, recommended for Rails
  spec.add_development_dependency "railties", ">= 6.0", "< 9.0"  # For testing Rails integration
  spec.add_development_dependency "rspec", "~> 3"
  spec.add_development_dependency "webmock", "~> 3"
  spec.add_development_dependency "rake", "~> 13"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "rspec_junit_formatter", "~> 0.6"
  spec.add_development_dependency "simplecov-cobertura", "~> 3"
  spec.add_development_dependency "standard", "~> 1"
  spec.add_development_dependency "standard-rails", "~> 1"
  spec.add_development_dependency "standard-performance", "~> 1"
  spec.add_development_dependency "appraisal", "~> 2"
  spec.add_development_dependency "memory_profiler", "~> 1"
  spec.add_development_dependency "rbs", "~> 3"
  spec.add_development_dependency "phlex-rails", "~> 2.0"  # For testing Phlex integration
  spec.add_development_dependency "view_component", "~> 4.0"  # For testing ViewComponent integration
end
