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
      if s.empty?
        raise ArgumentError, "stylesheet path cannot be empty"
      end

      if s.start_with?("/")
        raise ArgumentError, "invalid stylesheet path (no leading slash / absolute URL path): #{path.inspect}"
      end

      if s.length > MAX_PATH_LENGTH
        raise ArgumentError, "invalid stylesheet path (max #{MAX_PATH_LENGTH} characters, got #{s.length})"
      end

      if s.split("/").any? { |segment| segment == ".." }
        raise ArgumentError, "invalid stylesheet path (parent segments not allowed): #{path.inspect}"
      end

      # Block characters that break HTML attributes or paths
      if /["<>|\0\\]/.match?(s)
        raise ArgumentError, "invalid stylesheet path (disallowed characters): #{path.inspect}"
      end

      s
    end
  end
end
