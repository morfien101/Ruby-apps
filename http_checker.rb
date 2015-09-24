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
require 'openssl'

program_version = "0.0.3"

# Setup constants that represent the nagios exit codes.
OK_STATE=0
WARNING_STATE=1
CRITICAL_STATE=2
UNKNOWN_STATE=3

def exit_converter(code,return_type)
  case code
  when OK_STATE
    exit_code_number = 0
    exit_code_word = "OK_STATE" 
  when WARNING_STATE
    exit_code_number = 1
    exit_code_word = "WARNING_STATE"
  when CRITICAL_STATE
    exit_code_number = 2
    exit_code_word = "CRITICAL_STATE"
  else
    exit_code_number = 3
    exit_code_word = "UNKNOWN_STATE"
  end

  if return_type == :text
    return exit_code_word
  end
end

class Logger
  @@debug_enabled=false
  @@verbose_enabled=false
  #@@warn=false
  #@@critical=false

  def enable_debug(trigger)
    if trigger
      @@debug_enabled=true
    end
  end

  def debug_message(msg)
    if @@debug_enabled
      puts msg
    end
  end

  def debug_exec(&block)
    if @@debug_enabled
      yield 
    end
  end

  def enable_verbose(trigger)
    if trigger
      @@verbose_enabled=true
    end
  end

  def verbose_message(msg)
    if @@verbose_enabled
      puts msg
    end
  end

  def verbose_exec(&block)
    if @@verbose_enabled
      yield 
    end
  end
end

def exitcode_filter(exitcodes_array)
  return_code = 0
  exitcodes_array.each { |code|
    if code == WARNING_STATE && return_code < WARNING_STATE
      return_code = WARNING_STATE
    elsif code == CRITICAL_STATE && return_code < CRITICAL_STATE
      return_code = CRITICAL_STATE
    elsif code == UNKNOWN_STATE && return_code < UNKNOWN_STATE
      return_code = UNKNOWN_STATE
    end
  }
  return return_code
end


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
    @options.verbose = false
    @options.verify_https = false

    opt_parser = OptionParser.new do |opts|
      opts.banner = "http checker that combines arryas of options to make a list of links to check"
      opts.separator "Exit codes can be used with nagios checks"
      opts.separator ""
      opts.separator "Usage example: http_checker.rb -m get -s http,ttps -b www.example1.com,www.expample2.com -p /index.html,/p/p2"
      opts.separator ""

      opts.on("-m", "--method", Array, "HTTP Method for the request. supported methods: Get,Post,Head") do |methods|
        @options.methods = methods
      end

      opts.on("-s", "--schema x,y", Array, "Supprted: http and/or https") do |schema|
        @options.schema = schema
      end

      opts.on("-b", "--base_domains x,y,z", Array, "List of base domains seperated by a comma.") do |base_domains|
        @options.base_domains = base_domains
      end

      opts.on("-p", "--pages x,y,z", Array, "Pages to be checked") do |pages|
        @options.pages = pages
      end

      opts.on("-q", "--query", "query options") do |query_string|
        @options.query_string = query_string
      end

      opts.on("-h", "--headers x,y,z", Array, "headers to be added") do |headers|
        @options.headers = headers
      end

      opts.on("-t", "--timeout N", Integer, "Time out in seconds. Default if unset is 2 seconds.") do |timeout|
        @options.timeout = timeout
      end

      opts.on("-e", "--expected_codes N,N", Array, "Expected HTTP code to be returned") do |return_codes|
        @options.expected_code = return_codes
      end

      opts.on("--verify_https",  "Turn on Ruby's builtin https verification.") do
        @options.verify_https = true
      end

      opts.on("--verbose", "Set verbose on or off.") do
        @options.verbose = true
      end

      opts.on("--version", "Show version") do
        @options.show_version = true
      end

      opts.on("--debug", "Enables debug mode.") do
        @options.debug = true
      end
    
      opts.on_tail("--help", "Show this message") do
            puts opts
            exit
        end
    end
    opt_parser.parse!(args)
    @options
  end # self.parse()
end # class Optparser

options = Optparser.parse(ARGV)

logger=Logger.new
logger.enable_debug(options.debug)
logger.enable_verbose(options.verbose)

logger.debug_message "options list: "
logger.debug_exec { pp options }

if options.show_version
  puts program_version
  exit 0
end

validation_errors = []
# Required attributes
method = options.methods
schema = options.schema
base_domains = options.base_domains
pages = options.pages
query = options.query_string
expected_code = options.expected_code
verify_https = options.verify_https
timeout=  !options.timeout.nil? ? options.timeout : 2
headers = !options.headers.nil? ? options.headers : []

# Validate passed in arguments

# -m --method
puts method.class
method_values = ['get','head','post']
method.map! {|x| x.downcase}
method.each { |x| 
  unless method_values.include?(x) 
    validation_errors << "Method values are not correct."
  end
}
# -s --schema
schema_values = ['http','https']
schema.map! {|x| x.downcase}
schema.each { |x| 
  unless schema_values.include?(x) 
    validation_errors << "schema values are not correct."
  end
}
# -b --base_domains
base_regex = /^([A-Za-z\-_0-9]+\.+)+[A-Za-z0-9]+$/
base_domains.each {|bd|
  unless bd.match(base_regex)
    validation_errors << "#{bd} is a badly formed url."
  end
}
# -p --pages
pages_regex = /^[A-Za-z0-9\% \_\-\/\=]+$/
pages.each {|page|
  unless page.match(pages_regex)
    validation_errors << "#{page} is a badly formed page."
  end
}
# -q --query
## Match this data
## Not sure of the rule for this yet.

# -h --headers
headers_regex = /^[^\(\)\^\<\>\@\;\:\\\"\/\[\]\?\{\}]+\:.*$/
headers.each {|header|
  unless header.match(headers_regex)
    validation_errors << "#{header} is a badly formed header pair."
  end
}
# -t --timeout
unless timeout.is_a?(Fixnum)|| timeout.is_a?(Float)
  validation_errors << "The time out value is incorrect."
end

# -e --expected_codes
expected_code.each {|code|
  unless code.is_a?(Fixnum)
    validation_errors << "#{code} http code is not valid."
  end
}

if !validation_errors.empty?
  logger.debug_message "#{validation_errors}"
  validation_errors.each {|error|
    puts error
  }
  exit 1
end
# Default exit code.
# Assume everything is golden at first.
exitcode = 0

# Tests the URLs and spit out the status code and full url.
def url_tester(method,schema,base_domain,page,query,expected_code,timeout,headers,https_verify,logger)

  uri = URI.join("#{schema}://#{base_domain}",page)
  http = Net::HTTP.new(uri.host, uri.port)
  if schema == "https"
    http.use_ssl = true
    http.verify_mode = https_verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
  end
  http.open_timeout = timeout

  # Catch errors and set http status codes manually
  begin
    request = Net::HTTP::Get.new(uri.request_uri)
    if !headers.empty?
      headers.each { |header|
        header_array = header.split(':', 2)
        logger.debug_message "header_array: #{header_array}"
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
def code_parser(returned_code,expected_code,logger)
  code_status = false
  expected_code.each { |code| 
    if returned_code == code.to_i
      code_status = true
    end
  }

  if code_status
    exitcode = OK_STATE
    logger.debug_message "Set exit code to #{OK_STATE}. It is #{exitcode}"
  else
    exitcode = CRITICAL_STATE
    logger.debug_message "Set exit code to #{CRITICAL_STATE}. It is #{exitcode}"
  end

  return exitcode
end

url_list = {}

# Go through the base urls and pages to test each combination.
# Returns both the full url and the http status code.
schema.each { |schema|
  base_domains.each { |base_domain|
    pages.each{ |page|
      logger.debug_message "http method: url_tester(#{method},#{schema},#{base_domain},#{page},#{query}, #{expected_code}, #{timeout},#{headers},logger)"
      
      url,http_code, response_time = url_tester(method,schema,base_domain,page,query,expected_code,timeout,headers,verify_https,logger)
      url_list[url] = {http_code: http_code, response_time: response_time}
    }
  }
}

# Check the status code against the expected code.
# Set the exit code if the http codes do not match.
exitcodes = []
url_list.map { |url,metric|

  state = code_parser metric[:http_code], expected_code, logger

  if metric[:response_time].nil?
    time = "!Timed out!"
  else
    time = metric[:response_time]
  end
  # Gather the exit codes to set the check exit code.
  exitcodes << state
  # Send human data to STDOUT.
  # Nagios tests pick this up as meta data and is often readable in tests.
  logger.verbose_message "tested #{url} got: #{metric[:http_code]}. Expected #{expected_code}. Time to serve: #{time} Status: #{exit_converter(state, :text)}."
  # being padantic so if something goes wrong the same state is not used on
  # multiple tested urls.
  state = nil
}

final_exitcode = exitcode_filter exitcodes
exit final_exitcode