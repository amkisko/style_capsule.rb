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

    it "uses Rails.root.join when Rails is available in output_directory" do
      # Stub rails_available? to return true
      allow(described_class).to receive(:rails_available?).and_return(true)
      allow(Rails).to receive(:root).and_return(Pathname.new("/rails/app"))

      original_output_dir = described_class.instance_variable_get(:@output_dir)
      described_class.instance_variable_set(:@output_dir, nil)

      begin
        dir = described_class.send(:output_directory)
        expect(dir).to eq(Rails.root.join(described_class::DEFAULT_OUTPUT_DIR))
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

  describe "fallback directory functionality" do
    let(:read_only_dir) { Pathname.new(Dir.mktmpdir) }
    let(:fallback_dir) { Pathname.new(Dir.mktmpdir) }

    before do
      # Make the primary directory read-only
      FileUtils.chmod(0o555, read_only_dir)
      described_class.configure(
        output_dir: read_only_dir,
        fallback_dir: fallback_dir,
        enabled: true
      )
    end

    after do
      # Restore permissions and clean up
      FileUtils.chmod(0o755, read_only_dir) if Dir.exist?(read_only_dir)
      FileUtils.rm_rf(read_only_dir) if Dir.exist?(read_only_dir)
      FileUtils.rm_rf(fallback_dir) if Dir.exist?(fallback_dir)
    end

    it "falls back to fallback directory when primary directory is read-only" do
      # This should trigger EACCES and use fallback
      file_path = described_class.write_css(
        css_content: css_content,
        component_class: component_class,
        capsule_id: capsule_id
      )

      # Should return nil because fallback directory can't be served via asset pipeline
      expect(file_path).to be_nil

      # But file should exist in fallback directory
      fallback_file = fallback_dir.join("capsule-#{capsule_id}.css")
      expect(File.exist?(fallback_file)).to be true
      expect(File.read(fallback_file)).to eq(css_content)
    end

    it "ensures fallback directory exists" do
      # Remove fallback directory
      FileUtils.rm_rf(fallback_dir)

      # Write should create it
      described_class.write_css(
        css_content: css_content,
        component_class: component_class,
        capsule_id: capsule_id
      )

      expect(Dir.exist?(fallback_dir)).to be true
    end

    it "uses default fallback directory when not configured" do
      original_fallback = described_class.instance_variable_get(:@fallback_dir)
      described_class.instance_variable_set(:@fallback_dir, nil)

      begin
        fallback = described_class.send(:fallback_directory)
        expect(fallback).to eq(Pathname.new(described_class::FALLBACK_OUTPUT_DIR))
      ensure
        described_class.instance_variable_set(:@fallback_dir, original_fallback)
      end
    end

    it "uses configured fallback directory" do
      custom_fallback = Pathname.new(Dir.mktmpdir)
      described_class.configure(fallback_dir: custom_fallback)

      begin
        fallback = described_class.send(:fallback_directory)
        expect(fallback).to eq(custom_fallback)
      ensure
        FileUtils.rm_rf(custom_fallback) if Dir.exist?(custom_fallback)
      end
    end

    it "calls ensure_fallback_directory when enabled" do
      # Remove fallback directory
      FileUtils.rm_rf(fallback_dir) if Dir.exist?(fallback_dir)

      # Write should create it via ensure_fallback_directory
      described_class.write_css(
        css_content: css_content,
        component_class: component_class,
        capsule_id: capsule_id
      )

      expect(Dir.exist?(fallback_dir)).to be true
    end

    it "skips ensure_fallback_directory when disabled" do
      described_class.configure(enabled: false)
      expect(described_class.send(:ensure_fallback_directory)).to be_nil
    end
  end

  describe "fallback failure scenarios" do
    let(:read_only_dir) { Pathname.new(Dir.mktmpdir) }
    let(:read_only_fallback) { Pathname.new(Dir.mktmpdir) }

    before do
      # Make both directories read-only
      FileUtils.chmod(0o555, read_only_dir)
      FileUtils.chmod(0o555, read_only_fallback)
      described_class.configure(
        output_dir: read_only_dir,
        fallback_dir: read_only_fallback,
        enabled: true
      )
    end

    after do
      # Restore permissions and clean up
      FileUtils.chmod(0o755, read_only_dir) if Dir.exist?(read_only_dir)
      FileUtils.chmod(0o755, read_only_fallback) if Dir.exist?(read_only_fallback)
      FileUtils.rm_rf(read_only_dir) if Dir.exist?(read_only_dir)
      FileUtils.rm_rf(read_only_fallback) if Dir.exist?(read_only_fallback)
    end

    it "returns nil when both primary and fallback directories fail" do
      file_path = described_class.write_css(
        css_content: css_content,
        component_class: component_class,
        capsule_id: capsule_id
      )

      expect(file_path).to be_nil
    end
  end

  describe "other write errors" do
    it "handles other write errors gracefully" do
      # Create a directory that will cause an error (e.g., invalid path)
      invalid_dir = Pathname.new("/invalid/path/that/does/not/exist")
      described_class.configure(output_dir: invalid_dir, enabled: true)

      # This should trigger a write error (not EACCES/EROFS)
      file_path = described_class.write_css(
        css_content: css_content,
        component_class: component_class,
        capsule_id: capsule_id
      )

      expect(file_path).to be_nil
    end

    it "instruments write failures for non-permission errors" do
      # Stub File.write to raise a non-permission error
      allow(File).to receive(:write).and_raise(Errno::ENOSPC, "No space left on device")

      # Subscribe to the write_failure event
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("style_capsule.css_file_writer.write_failure") do |*args|
        events << args
      end

      begin
        file_path = described_class.write_css(
          css_content: css_content,
          component_class: component_class,
          capsule_id: capsule_id
        )

        expect(file_path).to be_nil
        expect(events).not_to be_empty
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
    end
  end

  describe "fallback directory configuration" do
    it "configures custom fallback directory" do
      custom_fallback = Pathname.new(Dir.mktmpdir)
      described_class.configure(fallback_dir: custom_fallback)

      expect(described_class.fallback_dir).to eq(custom_fallback)

      FileUtils.rm_rf(custom_fallback)
    end

    it "uses default fallback directory when not provided" do
      original_fallback = described_class.instance_variable_get(:@fallback_dir)
      described_class.instance_variable_set(:@fallback_dir, nil)

      begin
        described_class.configure(fallback_dir: nil)
        expect(described_class.fallback_dir).to eq(Pathname.new(described_class::FALLBACK_OUTPUT_DIR))
      ensure
        described_class.instance_variable_set(:@fallback_dir, original_fallback)
      end
    end
  end
end
