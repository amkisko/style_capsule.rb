# frozen_string_literal: true

require "fileutils"
require "digest/sha1"

module StyleCapsule
  # Writes inline CSS to files for HTTP caching
  #
  # This allows inline CSS to be cached by browsers and CDNs, improving performance.
  # Files are written to a configurable output directory and can be precompiled
  # via Rails asset pipeline.
  #
  # @example Configuration
  #   StyleCapsule::CssFileWriter.configure(
  #     output_dir: Rails.root.join(StyleCapsule::CssFileWriter::DEFAULT_OUTPUT_DIR),
  #     filename_pattern: ->(component_class, capsule_id) { "capsule-#{capsule_id}.css" }
  #   )
  #
  # @example Usage
  #   file_path = StyleCapsule::CssFileWriter.write_css(
  #     css_content: ".section { color: red; }",
  #     component_class: MyComponent,
  #     capsule_id: "abc123"
  #   )
  #   # => "capsules/capsule-abc123"
  class CssFileWriter
    # Default output directory for CSS files (relative to Rails root)
    DEFAULT_OUTPUT_DIR = "app/assets/builds/capsules"

    class << self
      attr_accessor :output_dir, :filename_pattern, :enabled

      # Configure CSS file writer
      #
      # @param output_dir [String, Pathname] Directory to write CSS files (relative to Rails root or absolute)
      #   Default: `StyleCapsule::CssFileWriter::DEFAULT_OUTPUT_DIR`
      # @param filename_pattern [Proc, nil] Proc to generate filename
      #   Receives: (component_class, capsule_id) and should return filename string
      #   Default: `"capsule-#{capsule_id}.css"` (capsule_id is unique and deterministic)
      # @param enabled [Boolean] Whether file writing is enabled (default: true)
      # @example
      #   StyleCapsule::CssFileWriter.configure(
      #     output_dir: Rails.root.join(StyleCapsule::CssFileWriter::DEFAULT_OUTPUT_DIR),
      #     filename_pattern: ->(klass, capsule) { "capsule-#{capsule}.css" }
      #   )
      # @example Custom pattern with component name
      #   StyleCapsule::CssFileWriter.configure(
      #     filename_pattern: ->(klass, capsule) { "#{klass.name.underscore}-#{capsule}.css" }
      #   )
      def configure(output_dir: nil, filename_pattern: nil, enabled: true)
        @enabled = enabled

        @output_dir = if output_dir
          output_dir.is_a?(Pathname) ? output_dir : Pathname.new(output_dir.to_s)
        elsif defined?(Rails) && Rails.root
          Rails.root.join(DEFAULT_OUTPUT_DIR)
        else
          Pathname.new(DEFAULT_OUTPUT_DIR)
        end

        @filename_pattern = filename_pattern || default_filename_pattern
      end

      # Write CSS content to file
      #
      # @param css_content [String] CSS content to write
      # @param component_class [Class] Component class that generated the CSS
      # @param capsule_id [String] Capsule ID for the component
      # @return [String, nil] Relative file path (for stylesheet_link_tag) or nil if disabled
      def write_css(css_content:, component_class:, capsule_id:)
        return nil unless enabled?

        ensure_output_directory

        filename = generate_filename(component_class, capsule_id)
        file_path = output_directory.join(filename)

        # Write CSS to file with explicit UTF-8 encoding
        File.write(file_path, css_content, encoding: "UTF-8")

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

      private

      # Get output directory (with default)
      def output_directory
        @output_dir ||= if defined?(Rails) && Rails.root
          Rails.root.join(DEFAULT_OUTPUT_DIR)
        else
          Pathname.new(DEFAULT_OUTPUT_DIR)
        end
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
        if defined?(Rails) && Rails.root
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
