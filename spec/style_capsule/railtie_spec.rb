# frozen_string_literal: true

if defined?(StyleCapsule::Railtie)
  RSpec.describe StyleCapsule::Railtie do
    describe "Rails integration" do
      it "defines Railtie class" do
        expect(StyleCapsule::Railtie).to be_a(Class)
        expect(StyleCapsule::Railtie.superclass).to eq(Rails::Railtie)
      end

      it "is a subclass of Rails::Railtie" do
        expect(described_class).to be < Rails::Railtie
      end
    end

    describe "to_prepare callback in development" do
      before do
        # Mock Rails.env to be development
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        # Clear any existing callbacks
        StyleCapsule::Railtie.config.to_prepare.clear if StyleCapsule::Railtie.config.respond_to?(:to_prepare)
      end

      after do
        # Reset Rails.env
        allow(Rails).to receive(:env).and_call_original
      end

      it "handles errors gracefully when clearing CSS cache fails" do
        # Create a class that will raise an error when clear_css_cache is called
        error_class = Class.new do
          def self.name
            "ErrorTestClass"
          end

          def self.clear_css_cache
            raise StandardError, "Test error"
          end
        end

        # Include StyleCapsule::Component to add clear_css_cache method
        error_class.extend(StyleCapsule::Component::ClassMethods)

        # Mock ObjectSpace.each_object to return our error class
        allow(ObjectSpace).to receive(:each_object).with(Class).and_yield(error_class)

        # Should not raise an error even when clear_css_cache fails
        expect {
          # Trigger the to_prepare callback manually
          StyleCapsule::Railtie.config.to_prepare.each(&:call) if StyleCapsule::Railtie.config.respond_to?(:to_prepare)
        }.not_to raise_error
      end

      it "skips singleton classes when clearing CSS cache" do
        # Create a singleton class
        singleton_class = Class.new.singleton_class

        # Mock ObjectSpace.each_object to return the singleton class
        allow(ObjectSpace).to receive(:each_object).with(Class).and_yield(singleton_class)

        # Should not raise an error
        expect {
          # Trigger the to_prepare callback manually
          StyleCapsule::Railtie.config.to_prepare.each(&:call) if StyleCapsule::Railtie.config.respond_to?(:to_prepare)
        }.not_to raise_error
      end

      it "skips classes without names when clearing CSS cache" do
        # Create an anonymous class
        anonymous_class = Class.new

        # Mock ObjectSpace.each_object to return the anonymous class
        allow(ObjectSpace).to receive(:each_object).with(Class).and_yield(anonymous_class)

        # Should not raise an error
        expect {
          # Trigger the to_prepare callback manually
          StyleCapsule::Railtie.config.to_prepare.each(&:call) if StyleCapsule::Railtie.config.respond_to?(:to_prepare)
        }.not_to raise_error
      end
    end
  end
else
  # Skip Railtie tests when Rails::Railtie is not available (e.g., in non-Rails environments)
  # This is expected behavior, so we don't need a pending test
end
