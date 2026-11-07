# frozen_string_literal: true

module StyleCapsule
  # Centralized instrumentation module for StyleCapsule
  #
  # Hot paths skip ActiveSupport::Notifications subscriber checks and payload
  # work; subscribing remains supported for manual testing or targeted profiling.
  #
  # @example Subscribing to CSS processing events (manual profiling)
  #   ActiveSupport::Notifications.subscribe("style_capsule.css_processor.scope") do |name, start, finish, id, payload|
  #     duration_ms = (finish - start) * 1000
  #     input_size = payload[:input_size]
  #     Rails.logger.info "CSS scoped in #{duration_ms}ms, input: #{input_size} bytes"
  #   end
  module Instrumentation
    # Check if ActiveSupport::Notifications is available
    #
    # @return [Boolean]
    def self.available?
      !!defined?(ActiveSupport::Notifications)
    end

    # @param event_name [String] Event name
    # @param payload [Hash] Payload data
    # @yield The operation to run
    # @return [Object] Block return value
    def self.instrument(event_name, payload = {}, &block)
      return yield unless available?

      return yield unless ActiveSupport::Notifications.notifier.listening?(event_name)

      apply_input_size!(payload)

      result = nil
      ActiveSupport::Notifications.instrument(event_name, payload) do
        result = yield
        result
      end

      result
    end

    def self.apply_input_size!(payload)
      return if payload[:input_size]

      source = payload[:css_content] || payload[:input]
      payload[:input_size] = source.bytesize if source
    end
    private_class_method :apply_input_size!

    # @param event_name [String] Event name
    # @param payload [Hash] Payload data
    # @return [void]
    def self.notify(event_name, payload = {})
      return unless available?

      return unless ActiveSupport::Notifications.notifier.listening?(event_name)

      ActiveSupport::Notifications.instrument(event_name, payload)
    end

    # @param strategy [Symbol] Scoping strategy (:selector_patching or :nesting)
    # @param component_class [Class, String] Component class
    # @param capsule_id [String] Capsule ID
    # @param css_content [String] CSS content
    # @yield The CSS processing operation
    # @return [String] Processed CSS
    def self.instrument_css_processing(strategy:, component_class:, capsule_id:, css_content:, &block)
      component_name = component_class.is_a?(Class) ? component_class.name : component_class.to_s

      instrument(
        "style_capsule.css_processor.scope",
        strategy: strategy,
        component_class: component_name,
        capsule_id: capsule_id,
        css_content: css_content
      ) do
        result = yield
        result
      end
    end

    # @param component_class [Class] Component class
    # @param capsule_id [String] Capsule ID
    # @param file_path [String] File path
    # @param size [Integer] CSS content size in bytes
    # @yield The file write operation
    # @return [Object] Return value of the block
    def self.instrument_file_write(component_class:, capsule_id:, file_path:, size:, &block)
      instrument(
        "style_capsule.css_file_writer.write",
        component_class: component_class.name,
        capsule_id: capsule_id,
        file_path: file_path,
        size: size
      ) do
        yield
      end
    end

    def self.instrument_fallback(component_class:, capsule_id:, original_path:, fallback_path:, exception:, exception_object:)
      notify(
        "style_capsule.css_file_writer.fallback",
        component_class: component_class.name,
        capsule_id: capsule_id,
        original_path: original_path,
        fallback_path: fallback_path,
        exception: exception,
        exception_object: exception_object
      )
    end

    def self.instrument_fallback_failure(component_class:, capsule_id:, original_path:, fallback_path:, original_exception:, original_exception_object:, fallback_exception:, fallback_exception_object:)
      notify(
        "style_capsule.css_file_writer.fallback_failure",
        component_class: component_class.name,
        capsule_id: capsule_id,
        original_path: original_path,
        fallback_path: fallback_path,
        original_exception: original_exception,
        original_exception_object: original_exception_object,
        fallback_exception: fallback_exception,
        fallback_exception_object: fallback_exception_object
      )
    end

    def self.instrument_write_failure(component_class:, capsule_id:, file_path:, exception:, exception_object:)
      notify(
        "style_capsule.css_file_writer.write_failure",
        component_class: component_class.name,
        capsule_id: capsule_id,
        file_path: file_path,
        exception: exception,
        exception_object: exception_object
      )
    end

    # @param namespace [Symbol, String] Namespace
    # @param file_path [String, nil] File path (if file-based)
    # @param inline_size [Integer, nil] Inline CSS size in bytes (if inline)
    # @param cache_strategy [Symbol] Cache strategy
    # @yield The registration operation
    # @return [Object] Return value of the block
    def self.instrument_registration(namespace:, file_path: nil, inline_size: nil, cache_strategy: :none, &block)
      return yield unless available?

      return yield unless ActiveSupport::Notifications.notifier.listening?("style_capsule.stylesheet_registry.register")

      payload = {
        namespace: namespace.to_s,
        cache_strategy: cache_strategy
      }
      payload[:file_path] = file_path if file_path
      payload[:inline_size] = inline_size if inline_size

      instrument(
        "style_capsule.stylesheet_registry.register",
        payload
      ) do
        yield
      end
    end
  end
end
