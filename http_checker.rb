#!/usr/bin/env ruby

# Copyright 2015
# Author Randy Coburn
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ToDo
# [Done] Setup the options variables for the command line
# * Checks for correct values passed in via arguments.
# * Create functions for all supported methods
# * Figure out why time is not taking effect correctly 

# required gems.
require 'net/http'
require 'optparse'
require 'ostruct'
require 'pp'

# Setup constants that represent the nagios exit codes.
OK_STATE=0
WARNING_STATE=1
CRITICAL_STATE=2
UNKNOWN_STATE=3

program_version = "0.0.1"

#Create class that holds the values of the arguments.
class Optparser
  def self.parse(args)
    # -m HTTP Method (get,head,post)
    # -s Schema (https,http) as array
    # -b Base Domains as array
    # -p Pages as array
    # -q query sting as sting
    # -h headers commad seperated
    # -t timeout in miliseconds as interger
    # -e expected HTTP code as integer
    # --debug Used to debug the program
    # -v output detail level

    @@supported_methods = ['get','post','head']
    
    @options = OpenStruct.new
    @options.method = ['get']
    @options.debug = false
    @options.verbose = 0

    opt_parser = OptionParser.new do |opts|
      opts.banner = "http checker that combines arryas of options to make a list of links to check"
      opts.separator "Exit codes can be used with nagios checks"
      opts.separator ""
      opts.separator "Usage example: http_checker.rb -m get -s http,ttps -b www.example1.com,www.expample2.com -p /index.html,/p/p2"
      opts.separator ""
      opts.on("-m", "--method", Array, "HTTP Method for the request. supported methods: Get,Post,Head") do |m|
        options.method = [] # Empty the list if values are passed in.
        m.each do |method|
          if @@supported_methods.include?(m)
            @options.http_methods << m.downcase.capitilze
          else
            raise "Unsupported method passed in."
          end
        end
      end
      
      opts.on("-s", "--schema x,y", Array, "Supprted: http and/or https") do |schema|
        @options.schema = schema
      end

      opts.on("-b", "--base_domains x,y,z", Array, "List of base domains seperated by a comma.") do |base_domains|
        @options.base_domains = base_domains
      end

      opts.on("-p", "--pages x,y,z", Array, "Pages to be checked") do |pages|
        @options.pages = pages.map! {|page| page.downcase}
      end

      opts.on("-q", "--query", "query options") do |query_string|
        @options.query_string = query_string
      end

      opts.on("-h", "--headers x,y,z", Array, "headers to be added") do |headers|
        @options.headers = headers
      end

      opts.on("-t", "--timeout N", Integer, "Time out in seconds. D
        efault if unset is 2 seconds.") do |timeout|
        @options.timeout = timeout
      end

      opts.on("-e", "--expected_code N", Integer, "Expected HTTP code to be returned") do |return_code|
        @options.expected_code = return_code
      end

      opts.on("--verbose N", Integer, "Set verbose level (1 or 2)") do
        @options.verbose_level = 1
      end

      opts.on("--version", "Show version") do
        @options.show_version = true
      end

      opts.on("--debug", "Enables debug mode.") do
        @options.debug = true
      end
    
      opts.on_tail("-h", "--help", "Show this message") do
            puts opts
            exit
        end
    end
    opt_parser.parse!(args)
    @options
  end # self.parse()
end # class Optparser

options = Optparser.parse(ARGV)

if options.debug
  puts "options list"
  pp options
end

if options.show_version
  puts program_version
  exit 0
end

# Required attributes
method = options.base_domains
schema = options.schema
base_domains = options.base_domains
pages = options.pages
query = options.query_string
timeout=  !options.timeout.nil? ? options.timeout : 2
expected_code = options.expected_code
headers = !options.headers.nil? ? options.headers : []

# Default exit code.
# Assume everything is golden at first.
exitcode = 0

# Tests the URLs and spit out the status code and full url.
def url_tester(method,schema,base_domain,page,query,expected_code,timeout,headers)

  uri = URI.join("#{schema}://#{base_domain}",page)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true ? schema == "https" : false
  http.open_timeout = timeout

  # Catch errors and set http status codes manually
  begin
    request = Net::HTTP::Get.new(uri.request_uri)
    if !headers.empty?
      headers.each { |header|
        header_array = header.split(':', 2)
        puts "header_array: #{header_array}"
        puts header_array[0]
        puts header_array[1]
        request.initialize_http_header({header_array[0] => header_array[1]})
      }
    end
    start_time = Time.now
    response = http.request(request)
    end_time = Time.now
    response_time = end_time - start_time
    return uri.to_s, response.code.to_i, response_time  
  # Catch time outs and set code to HTTPGatewayTimeOut: 504.
  rescue Net::OpenTimeout
    return uri.to_s, 504
  end
end

# Check the HTTP status codes against our expected response.
def code_parser(test_results)
  if response_code == expected_code
    exitcode = OK_STATE
  else
    exitcode = CRITICAL_STATE
  end

  return exitcode
end

url_list = {}

# Go through the base urls and pages to test each combination.
# Returns both the full url and the http status code.
schema.each { |schema|
  base_domains.each { |base_domain|
    pages.each{ |page|
      if options.debug
        puts "http method: url_tester(#{method},#{schema},#{base_domain},#{page},#{query}, #{expected_code}, #{timeout},#{headers})"
      end
      url,http_code, response_time = url_tester(method,schema,base_domain,page,query,expected_code,timeout,headers)
      url_list[url] = {http_code: http_code, response_time: response_time}
    }
  }
}

# Check the status code against the expected code.
# Set the exit code if the http codes do not match.
url_list.map { |url,metric|
  if metric[:http_code] != expected_code
    state = "Critical"
    exitcode = CRITICAL_STATE
  else
    state = "OK"
  end

  if !metric[:response_time].nil?
    time = metric[:response_time]
  else
    time = "!Timed out!"
  end
  # Send human data to STDOUT.
  # Nagios tests pick this up as meta data and is often readable in tests.
  puts "tested #{url} got: #{metric[:http_code]}, expected #{expected_code}. Time to serve: #{time} Status #{state}."
  # being padantic so if something goes wrong the same state is not used on
  # multiple tested urls.
  state = nil
}

exit exitcode
