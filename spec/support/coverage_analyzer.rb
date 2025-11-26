#!/usr/bin/env ruby
# frozen_string_literal: true

# Coverage Analyzer - Shows lines with zero hits from coverage.xml
# Usage: Set SHOW_ZERO_COVERAGE=1 before running rspec
#
# This script parses coverage.xml (SimpleCov's final merged output) to get
# accurate coverage data and displays all uncovered lines (0 hits) in file:line format.
# It waits for coverage.xml to be created/updated after tests complete.
#
# Note: For accurate coverage measurement, run all tests without --fail-fast:
#   SHOW_ZERO_COVERAGE=1 bundle exec rspec

require "rexml/document"

module CoverageAnalyzer
  COVERAGE_XML_PATH = "coverage/coverage.xml"
  MAX_WAIT_SECONDS = 30
  WAIT_INTERVAL = 0.2

  def self.run
    return unless ENV["SHOW_ZERO_COVERAGE"] == "1"

    # Wait for coverage.xml to be created/updated
    wait_for_coverage_file

    unless File.exist?(COVERAGE_XML_PATH)
      warn "⚠️  Coverage XML not found at #{COVERAGE_XML_PATH}"
      warn "   Run rspec first to generate coverage data"
      return
    end

    uncovered = extract_uncovered_lines
    return if uncovered.empty?

    # Sort by file, then by line number
    uncovered.sort_by { |e| [e[:file], e[:line]] }.each do |line_info|
      puts "#{line_info[:file]}:#{line_info[:line]}"
    end
  end

  def self.wait_for_coverage_file
    # Since we're using SimpleCov.at_exit, the formatter should have already written
    # the file, but we'll wait a tiny bit just in case
    return if File.exist?(COVERAGE_XML_PATH)

    # Wait for file to be created (should be very quick since formatter just ran)
    elapsed = 0.0
    while !File.exist?(COVERAGE_XML_PATH) && elapsed < MAX_WAIT_SECONDS
      sleep(WAIT_INTERVAL)
      elapsed += WAIT_INTERVAL
    end
  end

  def self.extract_uncovered_lines
    uncovered = []

    # Read and parse the XML file
    xml_content = File.read(COVERAGE_XML_PATH)
    doc = REXML::Document.new(xml_content)

    # Extract uncovered lines from XML
    doc.elements.each("//class") do |class_elem|
      filename = class_elem.attributes["filename"]
      # Only process lib files
      next unless filename&.start_with?("lib/")

      class_elem.elements.each("lines/line") do |line_elem|
        hits = line_elem.attributes["hits"].to_i
        line_num = line_elem.attributes["number"].to_i

        # Only report lines with 0 hits (uncovered executable lines)
        if hits == 0
          uncovered << {file: filename, line: line_num}
        end
      end
    end

    uncovered
  end

  private_class_method :wait_for_coverage_file, :extract_uncovered_lines
end

# Run if executed directly
if __FILE__ == $PROGRAM_NAME
  CoverageAnalyzer.run
end
