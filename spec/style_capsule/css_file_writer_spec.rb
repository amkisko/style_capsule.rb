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
  end
end
