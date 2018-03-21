#!/usr/bin/env ruby
# encoding: utf-8
require 'optparse'
require File.dirname(File.dirname(__FILE__)) + '/environment.rb'
config_file = File.join(File.dirname(File.dirname(__FILE__)), 'config.yml')

options = {}

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: app.rb [options]"

  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end

  opts.on("-e", "--environment [ENVIRONMENT]", String, "Include environment, defaults to development") do |env|
    options[:environment] = env
  end

  opts.on("-c", "--config [FILE]", String, "Include a full path to the config.yml file") do |config|
    options[:config] = config
  end

end

begin
  optparse.parse!
  config_file = options[:config] if options[:config]
  ENV["ENVIRONMENT"] = options[:environment].nil? ? "development" : options[:environment]
  raise "Config file not found" unless File.exists?(config_file)

  ot = OrcidTaxonomist.new({ config_file: config_file })

#  ot.populate_taxonomists
#  ot.populate_taxa

  ot.write_webpage
  puts "Done".green

rescue
  puts $!.to_s
  puts optparse
  exit 
end