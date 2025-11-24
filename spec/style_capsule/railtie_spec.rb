# frozen_string_literal: true

require "securerandom"

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

      describe "after_initialize callback" do
        it "configures CSS file writer with Rails root" do
          # Trigger the after_initialize callback
          StyleCapsule::Railtie.config.after_initialize.each(&:call) if StyleCapsule::Railtie.config.respond_to?(:after_initialize)

          # Verify CssFileWriter was configured
          expect(StyleCapsule::CssFileWriter.output_dir).to be_a(Pathname)
        end

        it "adds output directory to asset paths when assets config exists" do
          # Ensure assets config exists
          unless Rails.application.config.respond_to?(:assets)
            Rails.application.config.define_singleton_method(:assets) do
              OpenStruct.new(paths: [])
            end
          end

          # Create the directory
          capsules_dir = Rails.root.join(StyleCapsule::CssFileWriter::DEFAULT_OUTPUT_DIR)
          FileUtils.mkdir_p(capsules_dir) unless Dir.exist?(capsules_dir)

          begin
            # Trigger the after_initialize callback
            StyleCapsule::Railtie.config.after_initialize.each(&:call) if StyleCapsule::Railtie.config.respond_to?(:after_initialize)

            # Verify the path was added
            expect(Rails.application.config.assets.paths).to include(capsules_dir)
          ensure
            # Clean up
            FileUtils.rm_rf(capsules_dir) if Dir.exist?(capsules_dir)
            Rails.application.config.assets.paths.delete(capsules_dir)
          end
        end

        it "does not add output directory when it doesn't exist" do
          # Ensure assets config exists
          unless Rails.application.config.respond_to?(:assets)
            Rails.application.config.define_singleton_method(:assets) do
              OpenStruct.new(paths: [])
            end
          end

          # Ensure directory doesn't exist
          capsules_dir = Rails.root.join(StyleCapsule::CssFileWriter::DEFAULT_OUTPUT_DIR)
          FileUtils.rm_rf(capsules_dir) if Dir.exist?(capsules_dir)

          initial_paths_count = Rails.application.config.assets.paths.size

          # Trigger the after_initialize callback
          StyleCapsule::Railtie.config.after_initialize.each(&:call) if StyleCapsule::Railtie.config.respond_to?(:after_initialize)

          # Verify the path was not added
          expect(Rails.application.config.assets.paths.size).to eq(initial_paths_count)
        end

        it "handles missing assets config gracefully" do
          # Remove assets config if it exists
          original_assets = Rails.application.config.instance_variable_get(:@assets) if Rails.application.config.respond_to?(:assets)
          if Rails.application.config.respond_to?(:assets)
            Rails.application.config.instance_eval { remove_method(:assets) if method_defined?(:assets) }
          end

          begin
            # Should not raise an error
            expect {
              StyleCapsule::Railtie.config.after_initialize.each(&:call) if StyleCapsule::Railtie.config.respond_to?(:after_initialize)
            }.not_to raise_error
          ensure
            # Restore assets config
            if original_assets
              Rails.application.config.define_singleton_method(:assets) { original_assets }
            end
          end
        end
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

      it "uses ClassRegistry to clear CSS caches" do
        # Create a class that includes StyleCapsule::Component
        klass_name = "TestComponent_#{SecureRandom.hex(4)}"
        test_class = Class.new do
          def self.name
            klass_name
          end
        end

        # Set constant so class has a name
        Object.const_set(klass_name, test_class)

        begin
          # Include StyleCapsule::Component to register it and add clear_css_cache
          test_class.include(StyleCapsule::Component)

          # Verify it's registered
          expect(StyleCapsule::ClassRegistry.all).to include(test_class)

          # Mock clear_css_cache to verify it's called
          allow(test_class).to receive(:clear_css_cache)

          # Trigger the to_prepare callback manually
          StyleCapsule::Railtie.config.to_prepare.each(&:call) if StyleCapsule::Railtie.config.respond_to?(:to_prepare)

          # Verify clear_css_cache was called
          expect(test_class).to have_received(:clear_css_cache)
        ensure
          # Clean up
          Object.send(:remove_const, klass_name) if Object.const_defined?(klass_name)
          StyleCapsule::ClassRegistry.clear
        end
      end

      it "handles errors gracefully when clearing CSS cache fails" do
        # Create a class that will raise an error when clear_css_cache is called
        klass_name = "ErrorTestClass_#{SecureRandom.hex(4)}"
        error_class = Class.new do
          def self.name
            klass_name
          end

          def self.clear_css_cache
            raise StandardError, "Test error"
          end
        end

        # Set constant so class has a name
        Object.const_set(klass_name, error_class)

        begin
          # Include StyleCapsule::Component to register it
          error_class.include(StyleCapsule::Component)

          # Should not raise an error even when clear_css_cache fails
          expect {
            # Trigger the to_prepare callback manually
            StyleCapsule::Railtie.config.to_prepare.each(&:call) if StyleCapsule::Railtie.config.respond_to?(:to_prepare)
          }.not_to raise_error
        ensure
          # Clean up
          Object.send(:remove_const, klass_name) if Object.const_defined?(klass_name)
          StyleCapsule::ClassRegistry.clear
        end
      end

      it "skips classes without clear_css_cache method" do
        # Create a class that doesn't have clear_css_cache
        klass_name = "NoCacheClass_#{SecureRandom.hex(4)}"
        no_cache_class = Class.new do
          def self.name
            klass_name
          end
        end

        # Set constant so class has a name
        Object.const_set(klass_name, no_cache_class)

        begin
          # Register it manually (not via include, so no clear_css_cache)
          StyleCapsule::ClassRegistry.register(no_cache_class)

          # Should not raise an error
          expect {
            # Trigger the to_prepare callback manually
            StyleCapsule::Railtie.config.to_prepare.each(&:call) if StyleCapsule::Railtie.config.respond_to?(:to_prepare)
          }.not_to raise_error
        ensure
          # Clean up
          Object.send(:remove_const, klass_name) if Object.const_defined?(klass_name)
          StyleCapsule::ClassRegistry.clear
        end
      end
    end
  end
else
  # Skip Railtie tests when Rails::Railtie is not available (e.g., in non-Rails environments)
  # This is expected behavior, so we don't need a pending test
end
