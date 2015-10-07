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

# If running native ruby on CentOS 6 you will get ruby 1.8.7 :(
# Include rubygems in that sad situation.
if RUBY_VERSION <= "1.8.7"
	require 'rubygems'
end
require 'net/http'
require 'optparse'
# We need to install the JSON gem to digest json correctly.
require 'json'

program_version = '1.0.0'

# Setup constants that represent the nagios exit codes.
OK_STATE=0
WARNING_STATE=1
CRITICAL_STATE=2
UNKNOWN_STATE=3

# This class is responsible for the check itself.
class PartionCheck
  def initialize(options)
    @options = options
  end

  # This is where the magic happens
  def check_network_partition?()
    # set up some pre-req values
    body = []
    output = false
    # Setup a error capture. Mainly for http time outs.
    begin
      # http request to get JSON
      uri = URI.join("http://#{@options['servername']}","/api/nodes")
      http = Net::HTTP.new(uri.host,@options['port'])
      http.open_timeout = 1
      http.read_timeout = 1
      request = Net::HTTP::Get.new(uri.request_uri)
      request.initialize_http_header({"content-type" => "application/JSON"})
      request.basic_auth @options['username'], @options['password']
      response = http.request(request)
      # If we get a good response then process it.
      if response.code.to_i == 200
        # Read JSON
        json_response = JSON.parse(response.body)
        # Return true or false
        json_response.each { |i|
          # If a rabbitmq server dissapears then the partition comes back as a nil value
          # when parsed as JSON. Deal with this.
          if i['partitions'].nil?
            output = true
            body << "Node: #{i['name']} reported a nil partition."
          else
            # If the passed back array is empty. Good News!
            if i['partitions'].empty?
              output = false unless output
              body << "Node: #{i['name']} reports No partition detected"
            else
              # Else Bad News! build the output.
              output = true
              body << "Node: #{i['name']} reports a split from #{i['partitions'].join(',')}"
            end
          end
        }
      else
        output = true
        body << "Error: Got #{response.code} to http request. Body: #{response.body}"
      end
    rescue Exception => e
      # If we get some sort of error back then exit critical and display message.
      output = true
      body = e.message
    end
    return body,output
  end
end

# Digest the user input
options = Hash.new
OptionParser.new do |opts|
	options['username'] = "guest"
	options['password'] = "guest"
	options['servername'] = "localhost"
	options['port'] = "15672"

	opts.banner = "This script will check for partionions on rabbitmq cluster nodes."

	opts.on("-u username", "The username used on the API request. Defaults to guest") do |username|
		options['username'] = username
	end

	opts.on("-p password", "The password used for the API request. Defaults to guest.") do |passwd|
		options['password'] = passwd
	end

	opts.on("-s servername", "The server or host to connect to when running the check. Defaults to localhost") do |svrname|
		options['servername'] = svrname
	end

	opts.on("-P 15672", "RabbitMQ Management api port number. Defaults to 15672.") do |p|
    options['port'] = p
  end

	opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
    end
end.parse!

# Make a validation case
input_valid = true
input_errors = []
options.each { |option, value|
  case option
  when "username"
    unless value.match(/^[A-Za-z0-9\.\_\-]+$/)
      input_valid = false
      input_errors << "username: #{value} does not appear to be valid"
    end
  # Password can have special characters.
  # Does it need to be validated?
  #when "password"
  #  unless value.match(/^[A-Za-z0-9]+$/)
  #    input_valid = false
  #    input_errors << "password: #{value} does not appear to be valid"
  #  end
  when "servername"
    unless value.match(/^[A-Za-z0-9\-\_\.]+$/)
      input_valid = false
      input_errors << "servername: #{value} does not appear to be valid"
    end
  when "port"
    unless value.match(/^[0-9]+$/)
      input_valid = false
      input_errors << "port: #{value} does not appear to be valid"
    end
  end
}
if !input_valid 
  input_errors.each { |error| puts error}
  exit CRITICAL_STATE
else
  check = PartionCheck.new(options)
  message,result = check.check_network_partition?

  # Digest the check and exit out with the required code.
  if result
  	message.each { |mesg| puts mesg }
  	exit CRITICAL_STATE
  else
  	message.each { |mesg| puts mesg }
  	exit OK_STATE
  end
end
