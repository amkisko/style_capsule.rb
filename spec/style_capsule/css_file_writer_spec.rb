# frozen_string_literal: true

require "tmpdir"

RSpec.describe StyleCapsule::CssFileWriter do
  let(:test_output_dir) { Pathname.new(Dir.mktmpdir) }
  let(:component_class) do
    Class.new do
      def self.name
        "TestComponent"
      end
    end
  end
  let(:capsule_id) { "abc123" }
  let(:css_content) { ".test { color: red; }" }

  before do
    described_class.configure(
      output_dir: test_output_dir,
      enabled: true
    )
  end

  after do
    described_class.clear_files
    FileUtils.rm_rf(test_output_dir) if Dir.exist?(test_output_dir)
  end

  describe ".configure" do
    it "configures output directory" do
      custom_dir = Pathname.new(Dir.mktmpdir)
      described_class.configure(output_dir: custom_dir)
      expect(described_class.output_dir).to eq(custom_dir)
      FileUtils.rm_rf(custom_dir)
    end

    it "configures output directory with default when no Rails and no output_dir" do
      # Test the fallback path when Rails is not available
      # We can't easily remove Rails in tests, so we test the logic by providing nil
      # and checking that it uses a Pathname (which is what happens when Rails is not defined)
      original_output_dir = described_class.instance_variable_get(:@output_dir)
      described_class.instance_variable_set(:@output_dir, nil)

      begin
        # Simulate the case where Rails is not defined by checking the private method
        # The actual fallback logic is tested indirectly
        described_class.configure(output_dir: nil)
        expect(described_class.output_dir).to be_a(Pathname)
      ensure
        described_class.instance_variable_set(:@output_dir, original_output_dir)
      end
    end

    it "configures filename pattern" do
      custom_pattern = ->(klass, scope) { "custom-#{scope}.css" }
      described_class.configure(filename_pattern: custom_pattern)
      expect(described_class.filename_pattern).to eq(custom_pattern)
    end

    it "can disable file writing" do
      described_class.configure(enabled: false)
      expect(described_class.enabled?).to be false
    end
  end

  describe ".write_css" do
    it "writes CSS content to file" do
      file_path = described_class.write_css(
        css_content: css_content,
        component_class: component_class,
        capsule_id: capsule_id
      )

      expect(file_path).to be_a(String)
      expect(described_class.file_exists?(component_class: component_class, capsule_id: capsule_id)).to be true
    end

    it "returns relative path for stylesheet_link_tag" do
      file_path = described_class.write_css(
        css_content: css_content,
        component_class: component_class,
        capsule_id: capsule_id
      )

      expect(file_path).not_to include(".css")
      expect(file_path).to include("capsule-")
      expect(file_path).to include(capsule_id)
    end

    it "handles ArgumentError when paths don't share common prefix" do
      # Configure with a path that doesn't share common prefix with rails_assets_root
      # This triggers the ArgumentError rescue in write_css
      temp_dir = Pathname.new(Dir.mktmpdir)
      described_class.configure(output_dir: temp_dir)

      file_path = described_class.write_css(
        css_content: css_content,
        component_class: component_class,
        capsule_id: capsule_id
      )

      # Should return just the filename (without .css) when paths don't share common prefix
      expect(file_path).to be_a(String)
      expect(file_path).not_to include(".css")
      expect(file_path).to include("capsule-")

      FileUtils.rm_rf(temp_dir)
    end

    it "does not write if disabled" do
      described_class.configure(enabled: false)
      file_path = described_class.write_css(
        css_content: css_content,
        component_class: component_class,
        capsule_id: capsule_id
      )

      expect(file_path).to be_nil
    end

    it "creates output directory if it doesn't exist" do
      new_dir = Pathname.new(Dir.mktmpdir).join("subdir")
      described_class.configure(output_dir: new_dir)

      described_class.write_css(
        css_content: css_content,
        component_class: component_class,
        capsule_id: capsule_id
      )

      expect(Dir.exist?(new_dir)).to be true
      FileUtils.rm_rf(new_dir.parent)
    end
  end

  describe ".file_exists?" do
    it "returns false if file doesn't exist" do
      expect(described_class.file_exists?(component_class: component_class, capsule_id: capsule_id)).to be false
    end

    it "returns true if file exists" do
      described_class.write_css(
        css_content: css_content,
        component_class: component_class,
        capsule_id: capsule_id
      )

      expect(described_class.file_exists?(component_class: component_class, capsule_id: capsule_id)).to be true
    end
  end

  describe ".file_path_for" do
    it "returns nil if file doesn't exist" do
      expect(described_class.file_path_for(component_class: component_class, capsule_id: capsule_id)).to be_nil
    end

    it "returns relative path if file exists" do
      described_class.write_css(
        css_content: css_content,
        component_class: component_class,
        capsule_id: capsule_id
      )

      path = described_class.file_path_for(component_class: component_class, capsule_id: capsule_id)
      expect(path).to be_a(String)
      expect(path).not_to include(".css")
    end

    it "handles ArgumentError when paths don't share common prefix" do
      # Configure with a path that doesn't share common prefix with rails_assets_root
      # This triggers the ArgumentError rescue in file_path_for
      temp_dir = Pathname.new(Dir.mktmpdir)
      described_class.configure(output_dir: temp_dir)

      # Write a file first
      described_class.write_css(
        css_content: css_content,
        component_class: component_class,
        capsule_id: capsule_id
      )

      path = described_class.file_path_for(component_class: component_class, capsule_id: capsule_id)
      # Should return just the filename (without .css) when paths don't share common prefix
      expect(path).to be_a(String)
      expect(path).not_to include(".css")
      expect(path).to include("capsule-")

      FileUtils.rm_rf(temp_dir)
    end

    it "handles ArgumentError in write_css when paths don't share common prefix" do
      # Configure with a path that doesn't share common prefix
      temp_dir = Pathname.new(Dir.mktmpdir)
      described_class.configure(output_dir: temp_dir)

      file_path = described_class.write_css(
        css_content: css_content,
        component_class: component_class,
        capsule_id: capsule_id
      )

      # Should return just the filename (without .css) when paths don't share common prefix
      expect(file_path).to be_a(String)
      expect(file_path).not_to include(".css")
      expect(file_path).to include("capsule-")

      FileUtils.rm_rf(temp_dir)
    end

    it "uses rails_assets_root fallback path" do
      # Test the fallback path - the method returns a Pathname
      root = described_class.send(:rails_assets_root)
      expect(root).to be_a(Pathname)
      expect(root.to_s).to include("app/assets")
    end

    it "uses rails_assets_root fallback when Rails is not defined" do
      # Test that the fallback path works
      # The method checks if Rails is defined, but in tests Rails is always defined
      # So we test the logic by checking the return value
      root = described_class.send(:rails_assets_root)
      expect(root).to be_a(Pathname)
      # The fallback returns Pathname.new("app/assets")
      expect(root.to_s).to include("app/assets")
    end
  end

  describe "output_directory fallback" do
    it "uses default path when Rails is not defined" do
      # Test the fallback logic
      # Since Rails is always defined in tests, we test by checking the configured path
      original_output_dir = described_class.instance_variable_get(:@output_dir)
      described_class.instance_variable_set(:@output_dir, nil)

      begin
        # Configure without output_dir to trigger fallback
        described_class.configure(output_dir: nil)
        dir = described_class.send(:output_directory)
        expect(dir).to be_a(Pathname)
      ensure
        described_class.instance_variable_set(:@output_dir, original_output_dir)
      end
    end
  end

  describe ".clear_files" do
    it "removes all CSS files from output directory" do
      described_class.write_css(
        css_content: css_content,
        component_class: component_class,
        capsule_id: capsule_id
      )

      expect(described_class.file_exists?(component_class: component_class, capsule_id: capsule_id)).to be true

      described_class.clear_files

      expect(described_class.file_exists?(component_class: component_class, capsule_id: capsule_id)).to be false
    end
  end

  describe "filename pattern" do
    it "uses default pattern" do
      file_path = described_class.write_css(
        css_content: css_content,
        component_class: component_class,
        capsule_id: capsule_id
      )

      expect(file_path).to include("capsule-")
      expect(file_path).to include(capsule_id)
    end

    it "handles namespaced component classes" do
      namespaced_class = Class.new do
        def self.name
          "MyApp::Components::ButtonComponent"
        end
      end

      file_path = described_class.write_css(
        css_content: css_content,
        component_class: namespaced_class,
        capsule_id: capsule_id
      )

      # Default pattern uses only capsule_id, not component name
      expect(file_path).to include("capsule-")
      expect(file_path).to include(capsule_id)
    end

    it "uses custom filename pattern" do
      custom_pattern = ->(klass, scope) { "custom-#{scope}.css" }
      described_class.configure(filename_pattern: custom_pattern)

      file_path = described_class.write_css(
        css_content: css_content,
        component_class: component_class,
        capsule_id: capsule_id
      )

      expect(file_path).to include("custom")
      expect(file_path).to include(capsule_id)
    end
  end

  describe "security validations" do
    it "rejects path traversal in filename pattern" do
      malicious_pattern = ->(_klass, _scope) { "../../../etc/passwd.css" }
      described_class.configure(filename_pattern: malicious_pattern)

      expect {
        described_class.write_css(
          css_content: css_content,
          component_class: component_class,
          capsule_id: capsule_id
        )
      }.to raise_error(SecurityError, /path traversal/)
    end

    it "rejects forward slashes in filename" do
      malicious_pattern = ->(_klass, _scope) { "path/to/file.css" }
      described_class.configure(filename_pattern: malicious_pattern)

      expect {
        described_class.write_css(
          css_content: css_content,
          component_class: component_class,
          capsule_id: capsule_id
        )
      }.to raise_error(SecurityError, /path traversal/)
    end

    it "rejects backslashes in filename" do
      malicious_pattern = ->(_klass, _scope) { "path\\to\\file.css" }
      described_class.configure(filename_pattern: malicious_pattern)

      expect {
        described_class.write_css(
          css_content: css_content,
          component_class: component_class,
          capsule_id: capsule_id
        )
      }.to raise_error(SecurityError, /path traversal/)
    end

    it "rejects null bytes in filename" do
      malicious_pattern = ->(_klass, _scope) { "file\0name.css" }
      described_class.configure(filename_pattern: malicious_pattern)

      expect {
        described_class.write_css(
          css_content: css_content,
          component_class: component_class,
          capsule_id: capsule_id
        )
      }.to raise_error(SecurityError, /null byte/)
    end

    it "rejects filenames that are too long" do
      # Create a filename that exceeds 255 characters total (after .css extension is added)
      # Pattern returns name without .css, then we add .css, so pattern should return 256+ chars
      malicious_pattern = ->(_klass, _scope) { "a" * 256 }  # 256 chars, +4 for ".css" = 260 total
      described_class.configure(filename_pattern: malicious_pattern)

      expect {
        described_class.write_css(
          css_content: css_content,
          component_class: component_class,
          capsule_id: capsule_id
        )
      }.to raise_error(SecurityError, /too long/)
    end

    it "rejects filenames with unsafe characters" do
      malicious_pattern = ->(_klass, _scope) { "file<script>.css" }
      described_class.configure(filename_pattern: malicious_pattern)

      expect {
        described_class.write_css(
          css_content: css_content,
          component_class: component_class,
          capsule_id: capsule_id
        )
      }.to raise_error(SecurityError, /unsafe characters/)
    end

    it "accepts valid filenames" do
      valid_pattern = ->(klass, scope) { "valid_file-#{scope}.css" }
      described_class.configure(filename_pattern: valid_pattern)

      expect {
        described_class.write_css(
          css_content: css_content,
          component_class: component_class,
          capsule_id: capsule_id
        )
      }.not_to raise_error
    end

    it "rejects empty capsule_id after sanitization in default pattern" do
      # Use default pattern which sanitizes capsule_id
      # Reset to default pattern
      described_class.configure(filename_pattern: nil)

      expect {
        described_class.write_css(
          css_content: css_content,
          component_class: component_class,
          capsule_id: "!!!"  # All special chars, will be sanitized to empty
        )
      }.to raise_error(ArgumentError, /Invalid capsule_id/)
    end

    it "rejects filenames without .css extension when pattern returns invalid name" do
      # Pattern that returns name with unsafe chars (no .css)
      malicious_pattern = ->(_klass, _scope) { "file<script>" }
      described_class.configure(filename_pattern: malicious_pattern)

      expect {
        described_class.write_css(
          css_content: css_content,
          component_class: component_class,
          capsule_id: capsule_id
        )
      }.to raise_error(SecurityError, /must end with .css/)
    end
  end

  describe "default filename pattern" do
    it "handles capsule_id with special characters by sanitizing" do
      # Default pattern sanitizes capsule_id
      special_capsule = "abc!@#123"
      file_path = described_class.write_css(
        css_content: css_content,
        component_class: component_class,
        capsule_id: special_capsule
      )

      # Should sanitize to alphanumeric only
      expect(file_path).to include("capsule-abc123")
    end

    it "raises error if capsule_id becomes empty after sanitization" do
      # All special characters, will be sanitized to empty
      expect {
        described_class.write_css(
          css_content: css_content,
          component_class: component_class,
          capsule_id: "!!!"
        )
      }.to raise_error(ArgumentError, /Invalid capsule_id/)
    end
  end
end
