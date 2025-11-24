# frozen_string_literal: true

module StyleCapsule
  # Registry for tracking classes that include StyleCapsule modules
  #
  # This provides a Rails-friendly way to track classes without using ObjectSpace,
  # which can be problematic with certain gems (e.g., Faker) that override Class#name.
  #
  # Classes are automatically registered when they include StyleCapsule::Component
  # or StyleCapsule::ViewComponent.
  #
  # @example
  #   # Classes are automatically registered when they include modules
  #   class MyComponent < ApplicationComponent
  #     include StyleCapsule::Component  # Automatically registered
  #   end
  #
  #   # Iterate over registered classes
  #   StyleCapsule::ClassRegistry.each do |klass|
  #     klass.clear_css_cache if klass.respond_to?(:clear_css_cache)
  #   end
  #
  #   # Clear registry (useful in development when classes are reloaded)
  #   StyleCapsule::ClassRegistry.clear
  class ClassRegistry
    # Use Set for O(1) lookups instead of O(n) with Array#include?
    @classes = Set.new

    class << self
      # Register a class that includes a StyleCapsule module
      #
      # @param klass [Class] The class to register
      # @return [void]
      def register(klass)
        return if klass.nil?
        return if klass.singleton_class?

        # Only register classes with names (skip anonymous classes)
        begin
          name = klass.name
          return if name.nil? || name.to_s.strip.empty?
        rescue
          # Skip classes that cause errors when calling name (e.g., ArgumentError, NoMethodError, NameError)
          return
        end

        @classes.add(klass)
      end

      # Remove a class from the registry
      #
      # @param klass [Class] The class to unregister
      # @return [void]
      def unregister(klass)
        @classes.delete(klass)
      end

      # Iterate over all registered classes
      #
      # @yield [Class] Each registered class
      # @return [void]
      def each(&block)
        # Filter out classes that no longer exist or have been unloaded
        # Use delete_if for Set (equivalent to reject! for Array)
        @classes.delete_if do |klass|
          # Check if class still exists and is valid
          klass.name.nil? || klass.singleton_class?
        rescue
          # Class has been unloaded or causes errors - remove from registry
          true
        end

        @classes.each(&block)
      end

      # Get all registered classes
      #
      # @return [Array<Class>] Array of registered classes
      def all
        # Filter out invalid classes
        each.to_a
      end

      # Clear the registry
      #
      # Useful in development when classes are reloaded.
      #
      # @return [void]
      def clear
        @classes.clear
      end

      # Get the number of registered classes
      #
      # @return [Integer]
      def count
        each.count
      end
    end
  end
end
