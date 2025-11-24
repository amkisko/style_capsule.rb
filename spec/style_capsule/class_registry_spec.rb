# frozen_string_literal: true

require "securerandom"

RSpec.describe StyleCapsule::ClassRegistry do
  before do
    # Clear registry before each test
    described_class.clear
  end

  after do
    # Clear registry after each test
    described_class.clear
  end

  describe ".register" do
    it "registers a class with a name" do
      klass = Class.new do
        def self.name
          "TestClass"
        end
      end

      described_class.register(klass)
      expect(described_class.all).to include(klass)
    end

    it "does not register nil" do
      described_class.register(nil)
      expect(described_class.all).to be_empty
    end

    it "does not register singleton classes" do
      klass = Class.new
      singleton = klass.singleton_class

      described_class.register(singleton)
      expect(described_class.all).not_to include(singleton)
    end

    it "does not register anonymous classes" do
      klass = Class.new

      described_class.register(klass)
      expect(described_class.all).not_to include(klass)
    end

    it "does not register classes with empty names" do
      klass = Class.new do
        def self.name
          ""
        end
      end

      described_class.register(klass)
      expect(described_class.all).not_to include(klass)
    end

    it "does not register classes with blank names" do
      klass = Class.new do
        def self.name
          "   "
        end
      end

      described_class.register(klass)
      expect(described_class.all).not_to include(klass)
    end

    it "handles classes that raise ArgumentError when name is called" do
      klass = Class.new do
        def self.name
          raise ArgumentError, "missing keywords"
        end
      end

      expect { described_class.register(klass) }.not_to raise_error
      expect(described_class.all).not_to include(klass)
    end

    it "handles classes that raise NoMethodError when name is called" do
      klass = Class.new do
        def self.name
          raise NoMethodError, "undefined method"
        end
      end

      expect { described_class.register(klass) }.not_to raise_error
      expect(described_class.all).not_to include(klass)
    end

    it "handles classes that raise NameError when name is called" do
      klass = Class.new do
        def self.name
          raise NameError, "uninitialized constant"
        end
      end

      expect { described_class.register(klass) }.not_to raise_error
      expect(described_class.all).not_to include(klass)
    end

    it "does not duplicate classes in registry" do
      klass = Class.new do
        def self.name
          "TestClass"
        end
      end

      described_class.register(klass)
      described_class.register(klass)
      expect(described_class.count).to eq(1)
    end
  end

  describe ".unregister" do
    it "removes a class from the registry" do
      klass = Class.new do
        def self.name
          "TestClass"
        end
      end

      described_class.register(klass)
      expect(described_class.all).to include(klass)

      described_class.unregister(klass)
      expect(described_class.all).not_to include(klass)
    end
  end

  describe ".each" do
    it "iterates over registered classes" do
      klass1 = Class.new do
        def self.name
          "TestClass1"
        end
      end

      klass2 = Class.new do
        def self.name
          "TestClass2"
        end
      end

      described_class.register(klass1)
      described_class.register(klass2)

      classes = []
      described_class.each { |k| classes << k }
      expect(classes).to include(klass1, klass2)
    end

    it "filters out classes with nil names" do
      klass = Class.new do
        def self.name
          "TestClass"
        end
      end

      described_class.register(klass)

      # Make the class return nil for name
      allow(klass).to receive(:name).and_return(nil)

      classes = []
      described_class.each { |k| classes << k }
      expect(classes).not_to include(klass)
    end

    it "filters out singleton classes" do
      klass = Class.new do
        def self.name
          "TestClass"
        end
      end

      described_class.register(klass)

      # Make the class appear as a singleton class
      allow(klass).to receive(:singleton_class?).and_return(true)

      classes = []
      described_class.each { |k| classes << k }
      expect(classes).not_to include(klass)
    end

    it "filters out classes that raise errors when name is called" do
      klass = Class.new do
        def self.name
          "TestClass"
        end
      end

      described_class.register(klass)

      # Make the class raise an error when name is called
      allow(klass).to receive(:name).and_raise(ArgumentError, "error")

      classes = []
      described_class.each { |k| classes << k }
      expect(classes).not_to include(klass)
    end

    it "filters out classes that raise NoMethodError when name is called" do
      klass = Class.new do
        def self.name
          "TestClass"
        end
      end

      described_class.register(klass)

      allow(klass).to receive(:name).and_raise(NoMethodError, "error")

      classes = []
      described_class.each { |k| classes << k }
      expect(classes).not_to include(klass)
    end

    it "filters out classes that raise NameError when name is called" do
      klass = Class.new do
        def self.name
          "TestClass"
        end
      end

      described_class.register(klass)

      allow(klass).to receive(:name).and_raise(NameError, "error")

      classes = []
      described_class.each { |k| classes << k }
      expect(classes).not_to include(klass)
    end
  end

  describe ".all" do
    it "returns all registered classes as an array" do
      klass1 = Class.new do
        def self.name
          "TestClass1"
        end
      end

      klass2 = Class.new do
        def self.name
          "TestClass2"
        end
      end

      described_class.register(klass1)
      described_class.register(klass2)

      all_classes = described_class.all
      expect(all_classes).to be_an(Array)
      expect(all_classes).to include(klass1, klass2)
    end
  end

  describe ".clear" do
    it "clears all registered classes" do
      klass = Class.new do
        def self.name
          "TestClass"
        end
      end

      described_class.register(klass)
      expect(described_class.count).to eq(1)

      described_class.clear
      expect(described_class.count).to eq(0)
      expect(described_class.all).to be_empty
    end
  end

  describe ".count" do
    it "returns the number of registered classes" do
      expect(described_class.count).to eq(0)

      klass1 = Class.new do
        def self.name
          "TestClass1"
        end
      end

      klass2 = Class.new do
        def self.name
          "TestClass2"
        end
      end

      described_class.register(klass1)
      expect(described_class.count).to eq(1)

      described_class.register(klass2)
      expect(described_class.count).to eq(2)
    end
  end

  describe "integration with StyleCapsule::Component" do
    it "automatically registers classes that include StyleCapsule::Component" do
      skip "Phlex not available" unless defined?(Phlex::HTML)

      # Create a named class so it gets registered
      klass_name = "TestPhlexComponent_#{SecureRandom.hex(4)}"

      # Create the class first, then set the constant so it has a name
      klass = Class.new(Phlex::HTML) do
        def view_template
          div { "Test" }
        end
      end

      # Set the constant first so the class has a name
      Object.const_set(klass_name, klass)

      begin
        # Now include the module - this should register the class
        klass.include(StyleCapsule::Component)

        # The include StyleCapsule::Component should have registered it
        expect(described_class.all).to include(klass)
      ensure
        # Clean up
        Object.send(:remove_const, klass_name) if Object.const_defined?(klass_name)
      end
    end
  end
end
