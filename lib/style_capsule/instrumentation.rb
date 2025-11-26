# frozen_string_literal: true

module StyleCapsule
  # Centralized instrumentation module for StyleCapsule
  #
  # Provides efficient, non-blocking instrumentation using ActiveSupport::Notifications.
  # Metrics (time, size) are only calculated when subscribers are present, ensuring
  # zero performance impact when instrumentation is not being used.
  #
  # All events follow Rails naming convention: style_capsule.{module}.{event}
  #
  # @example Subscribing to CSS processing events
  #   ActiveSupport::Notifications.subscribe("style_capsule.css_processor.scope") do |name, start, finish, id, payload|
  #     duration_ms = (finish - start) * 1000
  #     input_size = payload[:input_size]
  #     Rails.logger.info "CSS scoped in #{duration_ms}ms, input: #{input_size} bytes"
  #   end
  #
  # @example Using Event object for more details
  #   ActiveSupport::Notifications.subscribe("style_capsule.css_processor.scope") do |event|
  #     Rails.logger.info "CSS scoped in #{event.duration}ms, input: #{event.payload[:input_size]} bytes"
  #   end
  #
  # @example Subscribing to file write events
  #   ActiveSupport::Notifications.subscribe("style_capsule.css_file_writer.write") do |name, start, finish, id, payload|
  #     StatsD.timing("style_capsule.write.duration", (finish - start) * 1000)
  #     StatsD.histogram("style_capsule.write.size", payload[:size])
  #   end
  module Instrumentation
    # Check if ActiveSupport::Notifications is available
    #
    # @return [Boolean]
    def self.available?
      defined?(ActiveSupport::Notifications)
    end

    # Instrument an operation with automatic timing and size metrics
    #
    # This method is highly efficient:
    # - Only measures time if subscribers exist (ActiveSupport::Notifications is optimized for this)
    # - Only calculates sizes if subscribers exist (lazy evaluation)
    # - Uses monotonic time for accurate measurements
    #
    # @param event_name [String] Event name following Rails convention (e.g., "style_capsule.css_processor.scope")
    # @param payload [Hash] Additional payload data
    # @yield The operation to instrument
    # @yieldreturn [Object] Result of the operation (used for output size calculation if needed)
    # @return [Object] Return value of the block
    # @example Instrumenting CSS processing
    #   result = Instrumentation.instrument(
    #     "style_capsule.css_processor.scope",
    #     component_class: component_class.name,
    #     capsule_id: capsule_id,
    #     strategy: :selector_patching,
    #     input_size: css_content.bytesize
    #   ) do
    #     CssProcessor.scope_selectors(css_content, capsule_id)
    #   end
    def self.instrument(event_name, payload = {}, &block)
      return yield unless available?

      # Check if there are any subscribers (ActiveSupport optimizes this check)
      # If no subscribers, just execute the block without any overhead
      unless ActiveSupport::Notifications.notifier.listening?(event_name)
        return yield
      end

      # Calculate input size if not provided but css_content/input is in payload
      unless payload[:input_size]
        if payload[:css_content]
          payload[:input_size] = payload[:css_content].bytesize
        elsif payload[:input]
          payload[:input_size] = payload[:input].bytesize
        end
      end

      # Use ActiveSupport::Notifications.instrument which automatically:
      # - Measures duration using monotonic time (available in event.duration)
      # - Only does work if subscribers exist (zero overhead if no subscribers)
      # Note: output_size is not included in payload (subscribers can calculate from result if needed)
      result = nil
      ActiveSupport::Notifications.instrument(event_name, payload) do
        result = yield
        result
      end

      result
    end

    # Instrument an event without a block (for events that don't have duration)
    #
    # @param event_name [String] Event name
    # @param payload [Hash] Payload data
    # @return [void]
    # @example Instrumenting a fallback event
    #   Instrumentation.notify(
    #     "style_capsule.css_file_writer.fallback",
    #     component_class: component_class.name,
    #     original_path: original_path,
    #     fallback_path: fallback_path,
    #     exception: [e.class.name, e.message],
    #     exception_object: e
    #   )
    def self.notify(event_name, payload = {})
      return unless available?

      # Only notify if subscribers exist
      return unless ActiveSupport::Notifications.notifier.listening?(event_name)

      ActiveSupport::Notifications.instrument(event_name, payload)
    end

    # Instrument CSS processing operations
    #
    # @param strategy [Symbol] Scoping strategy (:selector_patching or :nesting)
    # @param component_class [Class, String] Component class
    # @param capsule_id [String] Capsule ID
    # @param css_content [String] CSS content (for size calculation)
    # @yield The CSS processing operation
    # @return [String] Processed CSS
    def self.instrument_css_processing(strategy:, component_class:, capsule_id:, css_content:, &block)
      component_name = component_class.is_a?(Class) ? component_class.name : component_class.to_s
      input_size = css_content.bytesize

      instrument(
        "style_capsule.css_processor.scope",
        strategy: strategy,
        component_class: component_name,
        capsule_id: capsule_id,
        input_size: input_size
      ) do
        result = yield
        # Output size will be calculated by subscribers if needed
        # They can access it via: result.bytesize
        result
      end
    end

    # Instrument CSS file write operations
    #
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

    # Instrument fallback to temporary directory
    #
    # @param component_class [Class] Component class
    # @param capsule_id [String] Capsule ID
    # @param original_path [String] Original file path that failed
    # @param fallback_path [String] Fallback file path used
    # @param exception [Array<String>] Exception [class_name, message]
    # @param exception_object [Exception] The exception object
    # @return [void]
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

    # Instrument fallback failure (both original and fallback failed)
    #
    # @param component_class [Class] Component class
    # @param capsule_id [String] Capsule ID
    # @param original_path [String] Original file path that failed
    # @param fallback_path [String] Fallback file path that also failed
    # @param original_exception [Array<String>] Original exception [class_name, message]
    # @param original_exception_object [Exception] Original exception object
    # @param fallback_exception [Array<String>] Fallback exception [class_name, message]
    # @param fallback_exception_object [Exception] Fallback exception object
    # @return [void]
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

    # Instrument write failure (non-permission errors)
    #
    # @param component_class [Class] Component class
    # @param capsule_id [String] Capsule ID
    # @param file_path [String] File path that failed
    # @param exception [Array<String>] Exception [class_name, message]
    # @param exception_object [Exception] The exception object
    # @return [void]
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

    # Instrument stylesheet registration
    #
    # @param namespace [Symbol, String] Namespace
    # @param file_path [String, nil] File path (if file-based)
    # @param inline_size [Integer, nil] Inline CSS size in bytes (if inline)
    # @param cache_strategy [Symbol] Cache strategy
    # @yield The registration operation
    # @return [Object] Return value of the block
    def self.instrument_registration(namespace:, file_path: nil, inline_size: nil, cache_strategy: :none, &block)
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
