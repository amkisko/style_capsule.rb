# frozen_string_literal: true

module StyleCapsule
  # Validates logical asset paths for stylesheet registration (blocks injection / absurd paths).
  module AssetPath
    MAX_PATH_LENGTH = 1024

    # @param path [String] Logical path (e.g. "stylesheets/admin/foo" or "builds/capsules/my_component")
    # @return [String] Stripped path
    # @raise [ArgumentError] If path is invalid
    def self.validate_logical_path!(path)
      unless path.is_a?(String)
        raise ArgumentError, "stylesheet path must be a String (got #{path.class})"
      end

      s = path.strip
      validate_non_empty_path!(s)
      validate_path_segments!(s, path)
      s
    end

    def self.validate_non_empty_path!(stripped_path)
      raise ArgumentError, "stylesheet path cannot be empty" if stripped_path.empty?
      raise ArgumentError, "invalid stylesheet path (no leading slash / absolute URL path): #{stripped_path.inspect}" if stripped_path.start_with?("/")
      raise ArgumentError, "invalid stylesheet path (max #{MAX_PATH_LENGTH} characters, got #{stripped_path.length})" if stripped_path.length > MAX_PATH_LENGTH
    end

    def self.validate_path_segments!(stripped_path, original_path)
      if stripped_path.split("/").any? { |segment| segment == ".." }
        raise ArgumentError, "invalid stylesheet path (parent segments not allowed): #{original_path.inspect}"
      end

      if /["<>|\0\\]/.match?(stripped_path)
        raise ArgumentError, "invalid stylesheet path (disallowed characters): #{original_path.inspect}"
      end
    end
    private_class_method :validate_non_empty_path!, :validate_path_segments!
  end
end
