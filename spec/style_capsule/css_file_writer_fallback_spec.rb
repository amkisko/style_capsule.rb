# frozen_string_literal: true

require "tmpdir"

# Test fallback paths when Rails is not available
# These tests stub the availability check to test the fallback paths

RSpec.describe StyleCapsule::CssFileWriter, "fallback paths" do
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

  describe "when Rails is not available" do
    before do
      # Stub the availability check to return false
      allow(described_class).to receive(:rails_available?).and_return(false)
    end

    it "uses default path in configure when Rails not available" do
      original_output_dir = described_class.instance_variable_get(:@output_dir)
      described_class.instance_variable_set(:@output_dir, nil)

      begin
        described_class.configure(output_dir: nil)
        expect(described_class.output_dir).to eq(Pathname.new(described_class::DEFAULT_OUTPUT_DIR))
      ensure
        described_class.instance_variable_set(:@output_dir, original_output_dir)
      end
    end

    it "uses default path in output_directory when Rails not available" do
      original_output_dir = described_class.instance_variable_get(:@output_dir)
      described_class.instance_variable_set(:@output_dir, nil)

      begin
        dir = described_class.send(:output_directory)
        expect(dir).to eq(Pathname.new(described_class::DEFAULT_OUTPUT_DIR))
      ensure
        described_class.instance_variable_set(:@output_dir, original_output_dir)
      end
    end

    it "uses fallback rails_assets_root when Rails not available" do
      root = described_class.send(:rails_assets_root)
      expect(root).to eq(Pathname.new("app/assets"))
    end

    it "writes CSS files correctly without Rails" do
      file_path = described_class.write_css(
        css_content: css_content,
        component_class: component_class,
        capsule_id: capsule_id
      )

      expect(file_path).to be_a(String)
      expect(described_class.file_exists?(component_class: component_class, capsule_id: capsule_id)).to be true
    end

    it "handles ArgumentError in write_css when paths don't share common prefix" do
      # Configure with a path that doesn't share common prefix with rails_assets_root
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

    it "handles ArgumentError in file_path_for when paths don't share common prefix" do
      # Configure with a path that doesn't share common prefix with rails_assets_root
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
end
