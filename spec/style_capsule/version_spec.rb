# frozen_string_literal: true

RSpec.describe StyleCapsule::VERSION do
  it "is a semantic version string" do
    expect(StyleCapsule::VERSION).to be_a(String)
    expect(StyleCapsule::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
