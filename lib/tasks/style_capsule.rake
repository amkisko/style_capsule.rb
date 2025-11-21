# frozen_string_literal: true

namespace :style_capsule do
  desc "Build StyleCapsule CSS files from components (similar to Tailwind CSS build)"
  task build: :environment do
    require "style_capsule/component_builder"

    StyleCapsule::ComponentBuilder.build_all(output_proc: ->(msg) { puts msg })
  end

  desc "Clear StyleCapsule generated CSS files"
  task clear: :environment do
    require "style_capsule/css_file_writer"
    StyleCapsule::CssFileWriter.clear_files
    puts "StyleCapsule CSS files cleared"
  end
end

# Hook into Rails asset precompilation (similar to Tailwind CSS)
if defined?(Rails)
  Rake::Task["assets:precompile"].enhance(["style_capsule:build"]) if Rake::Task.task_defined?("assets:precompile")
end
