# frozen_string_literal: true

RSpec.describe StyleCapsule::AssetPath do
  describe ".validate_logical_path!" do
    it "accepts normal logical paths" do
      expect(described_class.validate_logical_path!("stylesheets/admin/foo")).to eq("stylesheets/admin/foo")
    end

    it "accepts builds paths without parent segments" do
      expect(described_class.validate_logical_path!("builds/capsules/my_component-abc123")).to eq("builds/capsules/my_component-abc123")
    end

    it "rejects parent path segments" do
      expect {
        described_class.validate_logical_path!("../../../../var/tmp/capsule-abc123")
      }.to raise_error(ArgumentError, /parent segments not allowed/)
    end

    it "rejects leading slash" do
      expect {
        described_class.validate_logical_path!("/stylesheets/foo")
      }.to raise_error(ArgumentError, /no leading slash/)
    end

    it "rejects empty paths" do
      expect {
        described_class.validate_logical_path!("   ")
      }.to raise_error(ArgumentError, /cannot be empty/)
    end

    it "rejects non-string paths" do
      expect {
        described_class.validate_logical_path!(:stylesheets)
      }.to raise_error(ArgumentError, /must be a String/)
    end

    it "rejects paths exceeding max length" do
      expect {
        described_class.validate_logical_path!("a" * (described_class::MAX_PATH_LENGTH + 1))
      }.to raise_error(ArgumentError, /max #{described_class::MAX_PATH_LENGTH}/)
    end

    it "rejects injection characters" do
      expect { described_class.validate_logical_path!('foo"><script') }.to raise_error(ArgumentError, /disallowed/)
    end
  end
end
