# frozen_string_literal: true

require "fileutils"
require "digest/sha1"
require_relative "instrumentation"

module StyleCapsule
  # Writes inline CSS to files for HTTP caching
  #
  # This allows inline CSS to be cached by browsers and CDNs, improving performance.
  # Files are written to a configurable output directory and can be precompiled
  # via Rails asset pipeline.
  #
  # In production environments where the app directory is read-only (e.g., Docker containers),
  # this class automatically falls back to writing files to /tmp/style_capsule when the
  # default location is not writable. When using the fallback directory, write_css returns
  # nil, causing StylesheetRegistry to fall back to inline CSS (keeping the UI functional).
  #
  # All fallback scenarios are instrumented via ActiveSupport::Notifications following
  # Rails conventions (https://guides.rubyonrails.org/active_support_instrumentation.html):
  # - style_capsule.css_file_writer.fallback: When fallback directory is used successfully
  # - style_capsule.css_file_writer.fallback_failure: When both primary and fallback fail
  # - style_capsule.css_file_writer.write_failure: When other write errors occur
  #
  # All events include exception information in the standard Rails format:
  # - :exception: Array of [class_name, message]
  # - :exception_object: The exception object itself
  #
  # These events can be subscribed to for monitoring, metrics collection, and error reporting.
  #
  # @example Configuration
  #   StyleCapsule::CssFileWriter.configure(
  #     output_dir: Rails.root.join(StyleCapsule::CssFileWriter::DEFAULT_OUTPUT_DIR),
  #     filename_pattern: ->(component_class, capsule_id) { "capsule-#{capsule_id}.css" },
  #     fallback_dir: "/tmp/style_capsule"  # Optional, defaults to /tmp/style_capsule
  #   )
  #
  # @example Usage
  #   file_path = StyleCapsule::CssFileWriter.write_css(
  #     css_content: ".section { color: red; }",
  #     component_class: MyComponent,
  #     capsule_id: "abc123"
  #   )
  #   # => "capsules/capsule-abc123" (or nil if fallback was used)
  #
  # @example Listening to instrumentation events for monitoring
  #   ActiveSupport::Notifications.subscribe("style_capsule.css_file_writer.fallback") do |name, start, finish, id, payload|
  #     Rails.logger.warn "StyleCapsule fallback: #{payload[:component_class]} -> #{payload[:fallback_path]}"
  #     # Exception info available: payload[:exception] and payload[:exception_object]
  #   end
  #
  # @example Subscribing for error reporting
  #   ActiveSupport::Notifications.subscribe("style_capsule.css_file_writer.fallback_failure") do |name, start, finish, id, payload|
  #     ActionReporter.notify(
  #       "StyleCapsule: CSS write failure (both primary and fallback failed)",
  #       context: {
  #         component_class: payload[:component_class],
  #         original_path: payload[:original_path],
  #         fallback_path: payload[:fallback_path],
  #         original_exception: payload[:original_exception],
  #         fallback_exception: payload[:fallback_exception]
  #       }
  #     )
  #   end
  #
  # @example Subscribing for metrics collection
  #   ActiveSupport::Notifications.subscribe("style_capsule.css_file_writer.fallback") do |name, start, finish, id, payload|
  #     StatsD.increment("style_capsule.css_file_writer.fallback", tags: [
  #       "component:#{payload[:component_class]}",
  #       "error:#{payload[:exception].first}"
  #     ])
  #   end
  class CssFileWriter
    # Default output directory for CSS files (relative to Rails root)
    DEFAULT_OUTPUT_DIR = "app/assets/builds/capsules"
    # Fallback directory for when default location is read-only (absolute path)
    FALLBACK_OUTPUT_DIR = "/tmp/style_capsule"

    class << self
      attr_accessor :output_dir, :filename_pattern, :enabled, :fallback_dir

      # Configure CSS file writer
      #
      # @param output_dir [String, Pathname] Directory to write CSS files (relative to Rails root or absolute)
      #   Default: `StyleCapsule::CssFileWriter::DEFAULT_OUTPUT_DIR`
      # @param filename_pattern [Proc, nil] Proc to generate filename
      #   Receives: (component_class, capsule_id) and should return filename string
      #   Default: `"capsule-#{capsule_id}.css"` (capsule_id is unique and deterministic)
      # @param enabled [Boolean] Whether file writing is enabled (default: true)
      # @param fallback_dir [String, Pathname, nil] Fallback directory when default location is read-only
      #   Default: `StyleCapsule::CssFileWriter::FALLBACK_OUTPUT_DIR` (/tmp/style_capsule)
      # @example
      #   StyleCapsule::CssFileWriter.configure(
      #     output_dir: Rails.root.join(StyleCapsule::CssFileWriter::DEFAULT_OUTPUT_DIR),
      #     filename_pattern: ->(klass, capsule) { "capsule-#{capsule}.css" }
      #   )
      # @example Custom pattern with component name
      #   StyleCapsule::CssFileWriter.configure(
      #     filename_pattern: ->(klass, capsule) { "#{klass.name.underscore}-#{capsule}.css" }
      #   )
      def configure(output_dir: nil, filename_pattern: nil, enabled: true, fallback_dir: nil)
        @enabled = enabled

        @output_dir = if output_dir
          output_dir.is_a?(Pathname) ? output_dir : Pathname.new(output_dir.to_s)
        elsif rails_available?
          Rails.root.join(DEFAULT_OUTPUT_DIR)
        else
          Pathname.new(DEFAULT_OUTPUT_DIR)
        end

        @fallback_dir = if fallback_dir
          fallback_dir.is_a?(Pathname) ? fallback_dir : Pathname.new(fallback_dir.to_s)
        else
          Pathname.new(FALLBACK_OUTPUT_DIR)
        end

        @filename_pattern = filename_pattern || default_filename_pattern
      end

      # Write CSS content to file
      #
      # @param css_content [String] CSS content to write
      # @param component_class [Class] Component class that generated the CSS
      # @param capsule_id [String] Capsule ID for the component
      # @return [String, nil] Relative file path (for stylesheet_link_tag) or nil if disabled/failed
      def write_css(css_content:, component_class:, capsule_id:)
        return nil unless enabled?

        filename = generate_filename(component_class, capsule_id)
        file_path = output_directory.join(filename)
        used_fallback = false

        begin
          ensure_output_directory
          # Write CSS to file with explicit UTF-8 encoding
          Instrumentation.instrument_file_write(
            component_class: component_class,
            capsule_id: capsule_id,
            file_path: file_path.to_s,
            size: css_content.bytesize
          ) do
            File.write(file_path, css_content, encoding: "UTF-8")
          end
        rescue Errno::EACCES, Errno::EROFS => e
          # Permission denied or read-only filesystem - try fallback directory
          fallback_path = fallback_directory.join(filename)

          begin
            ensure_fallback_directory
            File.write(fallback_path, css_content, encoding: "UTF-8")
            used_fallback = true
            file_path = fallback_path

            # Instrument the fallback for visibility
            Instrumentation.instrument_fallback(
              component_class: component_class,
              capsule_id: capsule_id,
              original_path: output_directory.join(filename).to_s,
              fallback_path: fallback_path.to_s,
              exception: [e.class.name, e.message],
              exception_object: e
            )
          rescue => fallback_error
            # Even fallback failed - instrument and return nil (will fall back to inline CSS)
            Instrumentation.instrument_fallback_failure(
              component_class: component_class,
              capsule_id: capsule_id,
              original_path: output_directory.join(filename).to_s,
              fallback_path: fallback_path.to_s,
              original_exception: [e.class.name, e.message],
              original_exception_object: e,
              fallback_exception: [fallback_error.class.name, fallback_error.message],
              fallback_exception_object: fallback_error
            )
            return nil
          end
        rescue => e
          # Other errors - instrument and return nil (will fall back to inline CSS)
          Instrumentation.instrument_write_failure(
            component_class: component_class,
            capsule_id: capsule_id,
            file_path: file_path.to_s,
            exception: [e.class.name, e.message],
            exception_object: e
          )
          return nil
        end

        # If we used fallback directory, return nil (can't serve via asset pipeline)
        # This will cause StylesheetRegistry to fall back to inline CSS
        return nil if used_fallback

        # Return relative path for stylesheet_link_tag
        # Path should be relative to app/assets
        # Handle case where output directory is not under rails_assets_root (e.g., in tests)
        begin
          file_path.relative_path_from(rails_assets_root).to_s.gsub(/\.css$/, "")
        rescue ArgumentError
          # If paths don't share a common prefix (e.g., in tests), return just the filename
          filename.gsub(/\.css$/, "")
        end
      end

      # Check if file exists for given component and capsule
      #
      # @param component_class [Class] Component class
      # @param capsule_id [String] Capsule ID
      # @return [Boolean]
      def file_exists?(component_class:, capsule_id:)
        return false unless enabled?

        filename = generate_filename(component_class, capsule_id)
        file_path = output_directory.join(filename)
        File.exist?(file_path)
      end

      # Get file path for given component and capsule
      #
      # @param component_class [Class] Component class
      # @param capsule_id [String] Capsule ID
      # @return [String, nil] Relative file path or nil if disabled
      def file_path_for(component_class:, capsule_id:)
        return nil unless enabled?

        filename = generate_filename(component_class, capsule_id)
        file_path = output_directory.join(filename)

        return nil unless File.exist?(file_path)

        # Return relative path for stylesheet_link_tag
        # Handle case where output directory is not under rails_assets_root (e.g., in tests)
        begin
          file_path.relative_path_from(rails_assets_root).to_s.gsub(/\.css$/, "")
        rescue ArgumentError
          # If paths don't share a common prefix (e.g., in tests), return just the filename
          filename.gsub(/\.css$/, "")
        end
      end

      # Ensure output directory exists
      #
      # @return [void]
      def ensure_output_directory
        return unless enabled?

        dir = output_directory
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      end

      # Ensure fallback directory exists
      #
      # @return [void]
      def ensure_fallback_directory
        return unless enabled?

        dir = fallback_directory
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      end

      # Clear all generated CSS files
      #
      # @return [void]
      def clear_files
        return unless enabled?

        dir = output_directory
        return unless Dir.exist?(dir)

        Dir.glob(dir.join("*.css")).each { |file| File.delete(file) }
      end

      # Check if file writing is enabled
      #
      # @return [Boolean]
      def enabled?
        @enabled != false
      end

      # Check if Rails is available
      # This method can be stubbed in tests to test fallback paths
      def rails_available?
        defined?(Rails) && Rails.respond_to?(:root) && Rails.root
      end

      private

      # Get output directory (with default)
      def output_directory
        @output_dir ||= if rails_available?
          Rails.root.join(DEFAULT_OUTPUT_DIR)
        else
          Pathname.new(DEFAULT_OUTPUT_DIR)
        end
      end

      # Get fallback directory (with default)
      def fallback_directory
        @fallback_dir ||= Pathname.new(FALLBACK_OUTPUT_DIR)
      end

      # Generate filename using pattern
      #
      # @param component_class [Class] Component class
      # @param capsule_id [String] Capsule ID
      # @return [String] Validated filename
      # @raise [SecurityError] If filename contains path traversal or invalid characters
      def generate_filename(component_class, capsule_id)
        pattern_result = filename_pattern.call(component_class, capsule_id)
        # Ensure .css extension
        filename = pattern_result.end_with?(".css") ? pattern_result : "#{pattern_result}.css"

        # Validate filename to prevent path traversal attacks
        validate_filename!(filename)

        filename
      end

      # Default filename pattern
      #
      # Uses only the capsule_id since it's unique and deterministic.
      # The capsule_id is generated from the component class name using SHA1,
      # ensuring uniqueness while keeping filenames concise and not exposing
      # internal component structure.
      #
      # @return [Proc] Proc that generates filename from (component_class, capsule_id)
      def default_filename_pattern
        ->(component_class, capsule_id) do
          # Validate capsule_id is safe (alphanumeric, hyphens, underscores only)
          # This ensures the filename is safe even if capsule_id generation changes
          safe_capsule_id = capsule_id.to_s.gsub(/[^a-zA-Z0-9_-]/, "")

          if safe_capsule_id.empty?
            raise ArgumentError, "Invalid capsule_id: must contain at least one alphanumeric character"
          end

          "capsule-#{safe_capsule_id}.css"
        end
      end

      # Get Rails assets root (app/assets)
      def rails_assets_root
        if rails_available?
          Rails.root.join("app/assets")
        else
          Pathname.new("app/assets")
        end
      end

      # Validate filename to prevent path traversal and other security issues
      #
      # @param filename [String] Filename to validate
      # @raise [SecurityError] If filename is invalid
      def validate_filename!(filename)
        # Reject path traversal attempts
        if filename.include?("..") || filename.include?("/") || filename.include?("\\")
          raise SecurityError, "Invalid filename: path traversal detected in '#{filename}'"
        end

        # Reject null bytes
        if filename.include?("\0")
          raise SecurityError, "Invalid filename: null byte detected"
        end

        # Ensure filename is reasonable length (filesystem limit is typically 255)
        if filename.length > 255
          raise SecurityError, "Invalid filename: too long (max 255 characters, got #{filename.length})"
        end

        # Ensure filename contains only safe characters (alphanumeric, dots, hyphens, underscores)
        # Must end with .css extension
        unless filename.match?(/\A[a-zA-Z0-9._-]+\.css\z/)
          raise SecurityError, "Invalid filename: contains unsafe characters (only alphanumeric, dots, hyphens, underscores allowed, must end with .css)"
        end
      end
    end
  end
end
