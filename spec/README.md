# Running Tests

## Using rspec

All tests should be run using `bundle exec rspec`

```bash
# Run all tests
bundle exec rspec

# Run with fail-fast (stop on first failure)
bundle exec rspec --fail-fast

# For verbose output
DEBUG=1 bundle exec rspec

# Show zero coverage lines
SHOW_ZERO_COVERAGE=1 bundle exec rspec

# Run single spec file at exact line number
DEBUG=1 bundle exec rspec spec/style_capsule/css_processor_spec.rb:10

# Run with verbose logging
DEBUG=1 DEVLOG_ENABLED=1 DEVLOG=1 LOGLOC=1 bundle exec rspec
```

## Test Structure

- `spec/style_capsule/` - Module and class specs for the gem's core functionality
  - `css_processor_spec.rb` - CSS selector scoping logic
  - `stylesheet_registry_spec.rb` - Thread-safe stylesheet registry
  - `component_spec.rb` - Phlex component concern
  - `helper_spec.rb` - ERB view helpers
  - `phlex_helper_spec.rb` - Phlex helper methods
  - `railtie_spec.rb` - Rails integration
  - `view_component_spec.rb` - ViewComponent component concern
  - `view_component_helper_spec.rb` - ViewComponent helper methods

- `spec/integration/` - Integration tests with real gems
  - `phlex_integration_spec.rb` - Real Phlex component integration tests (requires phlex-rails)
  - `view_component_integration_spec.rb` - Real ViewComponent integration tests (requires view_component)

Integration tests use the actual `phlex-rails` and `view_component` gems to verify real-world compatibility. These tests will be automatically skipped if the gems are not available.

### Running Integration Tests

```bash
# Run all integration tests
bundle exec rspec spec/integration/

# Run Phlex integration tests only
bundle exec rspec spec/integration/phlex_integration_spec.rb

# Run ViewComponent integration tests only
bundle exec rspec spec/integration/view_component_integration_spec.rb
```

Integration tests verify:
- Real component rendering with actual Phlex/ViewComponent gems
- CSS scoping works correctly in real components
- Head rendering functionality
- Cache strategies
- Helper methods work with real view contexts
- Scope ID generation and consistency

## RSpec Testing Guidelines

### Core Principles

- **Always assume RSpec has been integrated** - Never edit `rails_helper.rb` or `spec_helper.rb` or add new testing gems
- Focus on testing behavior, not implementation details
- Keep test scope minimal - start with the most crucial and essential tests
- Never test features that are built into the Rails framework
- Never write tests for performance unless specifically requested

### Test Type Selection

#### Module/Class Specs (`spec/style_capsule/`)

- Use for: Module methods, class methods, instance methods, business logic
- Test: Public API behavior, edge cases, error handling
- Example: Testing `CssProcessor.scope_selectors`, `StylesheetRegistry.register`, `Component#component_scope`

### Testing Workflow

1. **Plan First**: Think carefully about what tests should be written for the given scope/feature
2. **Isolate Dependencies**: Use mocks/stubs for external services or Rails-specific functionality
3. **Minimal Scope**: Start with essential tests, add edge cases only when specifically requested
4. **DRY Principles**: Review `spec/support/` for existing shared examples and helpers before duplicating code

### Test Data Management

#### Let/Let! Usage

- **`let`**: Lazy evaluation - only creates when accessed; use by default
- **`let!`**: Eager evaluation - creates immediately; use when laziness causes issues
- Keep `let` blocks close to where they're used
- Avoid creating unused data with `let!`

#### Test Data for StyleCapsule

Since this is a gem library (not a Rails app), test data is typically:
- Simple strings for CSS content
- Mock objects for Rails view context
- Test doubles for Phlex components
- No database fixtures or factories needed

#### Test Output Directory Configuration

**Important**: Tests are configured to use a temporary directory for CSS file writing to avoid creating directories in the project root.

- `CssFileWriter` is automatically configured in `spec_helper.rb` to use a temporary directory (`/tmp/style_capsule_spec_*`)
- Individual tests that need a specific output directory should configure it explicitly using `Dir.mktmpdir`
- Tests should clean up their output directories in `after` blocks
- The test suite automatically cleans up the default test output directory after all tests complete

**Example**:
```ruby
RSpec.describe StyleCapsule::CssFileWriter do
  let(:test_output_dir) { Pathname.new(Dir.mktmpdir) }

  before do
    StyleCapsule::CssFileWriter.configure(output_dir: test_output_dir)
  end

  after do
    StyleCapsule::CssFileWriter.clear_files
    FileUtils.rm_rf(test_output_dir) if Dir.exist?(test_output_dir)
  end
end
```

Example:

```ruby
RSpec.describe StyleCapsule::CssProcessor do
  let(:css_content) { ".section { color: red; }" }
  let(:scope_id) { "abc123" }

  it "scopes CSS selectors" do
    result = described_class.scope_selectors(css_content, scope_id)
    expect(result).to include('[data-capsule="abc123"]')
  end
end
```

### Shared Contexts

- Use `spec/support/` for shared examples, custom matchers, and test helpers
- Create shared contexts for truly shared behavior across multiple spec files
- Scope helpers appropriately using `config.include` by spec type

### Isolation Best Practices

#### When to Isolate

- Rails-specific functionality (ActionView, Rails::Railtie) → stub or mock
- External dependencies → stub to avoid requiring full Rails stack
- Nondeterminism (random, time, UUIDs) → stub to deterministic values
- Thread-local storage → clear between tests

#### When NOT to Isolate

- Pure Ruby logic (CSS processing, string manipulation)
- Simple data transformations
- Where integration tests provide clearer coverage

#### Isolation Techniques

- **Verifying Doubles**: Prefer `instance_double`, `class_double` over plain `double` to catch interface mismatches
- **Stubs**: `allow(obj).to receive(:method).and_return(value)` for replacing behavior
- **Spies**: `expect(obj).to have_received(:method).with(args)` for verifying side effects
- **Time Stubs**: Use `travel_to` or `Timecop` for deterministic time-dependent tests
- **Sequential Returns**: `and_return(value1, value2)` for modeling retries and fallbacks

#### Isolation Rules

1. **Preserve Public Behavior**: Test via public API, never test private methods directly
2. **Scope Narrowly**: Keep stubs local to examples; avoid global state and `allow_any_instance_of`
3. **Use Verifying Doubles**: Prefer `instance_double`, `class_double` over plain doubles
4. **Assert Outcomes**: Focus on behavior, not internal call choreography

### Example Test Patterns

#### Testing Module Methods

```ruby
RSpec.describe StyleCapsule::CssProcessor do
  describe ".scope_selectors" do
    it "scopes simple class selectors" do
      css = ".section { color: red; }"
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to include('[data-capsule="abc123"] .section')
    end
  end
end
```

#### Testing Concerns/Modules

```ruby
RSpec.describe StyleCapsule::Component do
  let(:component_class) do
    Class.new do
      include StyleCapsule::Component

      def component_styles
        ".section { color: red; }"
      end
    end
  end

  it "generates scope ID" do
    component = component_class.new
    expect(component.component_scope).to be_a(String)
  end
end
```

#### Testing with Rails Dependencies

```ruby
RSpec.describe StyleCapsule::Helper do
  let(:helper_class) do
    Class.new do
      include StyleCapsule::Helper

      def content_tag(name, content, options = {})
        # Mock implementation
      end
    end
  end

  it "scopes CSS content" do
    helper = helper_class.new
    result = helper.style_capsule(".test { color: red; }") do
      '<div>Content</div>'
    end
    expect(result).to include('[data-capsule=')
  end
end
```

#### Testing Thread-Local Storage

```ruby
RSpec.describe StyleCapsule::StylesheetRegistry do
  before do
    described_class.clear  # Clear thread-local storage
  end

  it "registers stylesheets per thread" do
    described_class.register("stylesheets/test")
    expect(described_class.any?).to be true
  end
end
```

### Anti-Patterns to Avoid

- Testing implementation details over behavior
- Over-testing edge cases without being asked
- Testing Rails framework features
- Not clearing thread-local state between tests
- Creating unnecessary test doubles when simple values suffice
- Testing private methods directly

### Coverage Goals

- Aim for comprehensive coverage of public APIs
- Test edge cases (empty strings, nil values, special characters)
- Test error conditions and boundary cases
- Focus on behavior that matters to users of the gem

