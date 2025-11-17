#!/usr/bin/env ruby
# frozen_string_literal: true

# API Client Example
# This example demonstrates how to use Moxml for API interactions:
# - Building XML API requests (SOAP)
# - Parsing XML API responses
# - Handling authentication elements
# - Working with namespaces
# - Error handling and validation

# Load moxml from the local source (use 'require "moxml"' in production)
require_relative "../../lib/moxml"
require "securerandom"
require "time"

# User class to represent API user data
class User
  attr_reader :id, :username, :email, :full_name, :role, :status,
              :created_at, :last_login, :permissions, :profile

  def initialize(data)
    @id = data[:id]
    @username = data[:username]
    @email = data[:email]
    @full_name = data[:full_name]
    @role = data[:role]
    @status = data[:status]
    @created_at = data[:created_at]
    @last_login = data[:last_login]
    @permissions = data[:permissions] || []
    @profile = data[:profile] || {}
  end

  def to_s
    output = []
    output << "User ID: #{@id}"
    output << "Username: #{@username}"
    output << "Email: #{@email}"
    output << "Full Name: #{@full_name}"
    output << "Role: #{@role}"
    output << "Status: #{@status}"
    output << "Created: #{@created_at}"
    output << "Last Login: #{@last_login}"
    output << "Permissions: #{@permissions.join(', ')}"
    output << "Profile:"
    @profile.each { |key, value| output << "  #{key}: #{value}" }
    output.join("\n")
  end
end

# APIResponse class to encapsulate API response data
class APIResponse
  attr_reader :status_code, :message, :data, :metadata, :session_id, :request_id

  def initialize(status_code:, message:, data: nil, metadata: {},
session_id: nil, request_id: nil)
    @status_code = status_code.to_i
    @message = message
    @data = data
    @metadata = metadata
    @session_id = session_id
    @request_id = request_id
  end

  def success?
    @status_code >= 200 && @status_code < 300
  end

  def to_s
    output = []
    output << "Status: #{@status_code} - #{@message}"
    output << "Session ID: #{@session_id}" if @session_id
    output << "Request ID: #{@request_id}" if @request_id
    output << "Metadata: #{@metadata.inspect}" unless @metadata.empty?
    output.join("\n")
  end
end

# SOAPClient class for making SOAP API requests
class SOAPClient
  # SOAP namespaces used in requests/responses
  NAMESPACES = {
    "soap" => "http://schemas.xmlsoap.org/soap/envelope/",
    "xsi" => "http://www.w3.org/2001/XMLSchema-instance",
    "xsd" => "http://www.w3.org/2001/XMLSchema",
    "auth" => "http://api.example.com/auth",
    "users" => "http://api.example.com/users",
  }.freeze

  def initialize
    @moxml = Moxml.new
  end

  # Build a SOAP GetUser request
  def build_get_user_request(user_id, session_id = nil)
    # Generate request ID and timestamp
    request_id = "req-#{SecureRandom.hex(6)}"
    timestamp = Time.now.utc.iso8601

    # Build the SOAP envelope using Moxml::Builder
    Moxml::Builder.new(@moxml).build do
      # XML declaration
      declaration version: "1.0", encoding: "UTF-8"

      # SOAP Envelope with namespaces
      element "soap:Envelope",
              "xmlns:soap" => NAMESPACES["soap"],
              "xmlns:xsi" => NAMESPACES["xsi"],
              "xmlns:xsd" => NAMESPACES["xsd"] do
        # SOAP Header with authentication
        element "soap:Header" do
          element "AuthHeader", "xmlns" => NAMESPACES["auth"] do
            element "SessionId" do
              text(session_id || "demo-session-id")
            end
            element "Timestamp" do
              text timestamp
            end
            element "RequestId" do
              text request_id
            end
          end
        end

        # SOAP Body with request
        element "soap:Body" do
          element "GetUserRequest", "xmlns" => NAMESPACES["users"] do
            element "UserId" do
              text user_id.to_s
            end
          end
        end
      end
    end
  end

  # Build a SOAP CreateUser request
  def build_create_user_request(username, email, full_name, role)
    request_id = "req-#{SecureRandom.hex(6)}"
    timestamp = Time.now.utc.iso8601

    Moxml::Builder.new(@moxml).build do
      declaration version: "1.0", encoding: "UTF-8"

      element "soap:Envelope",
              "xmlns:soap" => NAMESPACES["soap"],
              "xmlns:xsi" => NAMESPACES["xsi"],
              "xmlns:xsd" => NAMESPACES["xsd"] do
        element "soap:Header" do
          element "AuthHeader", "xmlns" => NAMESPACES["auth"] do
            element "SessionId" do
              text "demo-session-id"
            end
            element "Timestamp" do
              text timestamp
            end
            element "RequestId" do
              text request_id
            end
          end
        end

        element "soap:Body" do
          element "CreateUserRequest", "xmlns" => NAMESPACES["users"] do
            element "Username" do
              text username
            end
            element "Email" do
              text email
            end
            element "FullName" do
              text full_name
            end
            element "Role" do
              text role
            end
          end
        end
      end
    end
  end

  # Parse a SOAP response
  def parse_response(xml_string)
    # Parse the XML response
    doc = begin
      @moxml.parse(xml_string)
    rescue Moxml::ParseError => e
      puts "Failed to parse API response: #{e.message}"
      raise
    end

    # Extract authentication header
    session_id = extract_text(doc, "//auth:SessionId", NAMESPACES)
    request_id = extract_text(doc, "//auth:RequestId", NAMESPACES)

    # Extract status information
    status_code = extract_text(doc, "//users:Status/users:Code", NAMESPACES)
    status_message = extract_text(doc, "//users:Status/users:Message",
                                  NAMESPACES)

    # Extract metadata
    metadata = extract_metadata(doc)

    # Check if response contains user data
    user_element = doc.at_xpath("//users:User", NAMESPACES)
    user_data = user_element ? parse_user(user_element) : nil

    APIResponse.new(
      status_code: status_code,
      message: status_message,
      data: user_data,
      metadata: metadata,
      session_id: session_id,
      request_id: request_id,
    )
  end

  private

  # Parse user data from XML element
  def parse_user(user_element)
    # Extract basic user fields
    id = extract_text(user_element, "./users:Id", NAMESPACES)
    username = extract_text(user_element, "./users:Username", NAMESPACES)
    email = extract_text(user_element, "./users:Email", NAMESPACES)
    full_name = extract_text(user_element, "./users:FullName", NAMESPACES)
    role = extract_text(user_element, "./users:Role", NAMESPACES)
    status = extract_text(user_element, "./users:Status", NAMESPACES)
    created_at = extract_text(user_element, "./users:CreatedAt", NAMESPACES)
    last_login = extract_text(user_element, "./users:LastLogin", NAMESPACES)

    # Extract permissions array
    permission_nodes = user_element.xpath(
      "./users:Permissions/users:Permission", NAMESPACES
    )
    permissions = permission_nodes.map(&:text)

    # Extract profile data
    profile_element = user_element.at_xpath("./users:Profile", NAMESPACES)
    profile = if profile_element
                {
                  "Department" => extract_text(profile_element, "./users:Department",
                                               NAMESPACES),
                  "Title" => extract_text(profile_element, "./users:Title",
                                          NAMESPACES),
                  "Location" => extract_text(profile_element, "./users:Location",
                                             NAMESPACES),
                  "PhoneNumber" => extract_text(profile_element, "./users:PhoneNumber",
                                                NAMESPACES),
                }
              else
                {}
              end

    User.new(
      id: id,
      username: username,
      email: email,
      full_name: full_name,
      role: role,
      status: status,
      created_at: created_at,
      last_login: last_login,
      permissions: permissions,
      profile: profile,
    )
  end

  # Extract metadata from response
  def extract_metadata(doc)
    metadata_element = doc.at_xpath("//users:Metadata", NAMESPACES)
    return {} unless metadata_element

    {
      response_time: extract_text(metadata_element, "./users:ResponseTime",
                                  NAMESPACES),
      server_version: extract_text(metadata_element, "./users:ServerVersion",
                                   NAMESPACES),
      cache_hit: extract_text(metadata_element, "./users:CacheHit", NAMESPACES),
    }
  end

  # Helper method to safely extract text from XPath
  def extract_text(node, xpath, namespaces = {})
    element = node.at_xpath(xpath, namespaces)
    element&.text&.strip || ""
  end
end

# Demonstrate request building
def demonstrate_request_building
  puts "=" * 80
  puts "Building SOAP Requests"
  puts "=" * 80
  puts

  client = SOAPClient.new

  # Build GetUser request
  puts "1. GetUser Request:"
  puts "-" * 80
  get_user_doc = client.build_get_user_request(1001, "session-abc-123")
  puts get_user_doc.to_xml(indent: 2)
  puts

  # Build CreateUser request
  puts "2. CreateUser Request:"
  puts "-" * 80
  create_user_doc = client.build_create_user_request(
    "janedoe",
    "jane.doe@example.com",
    "Jane Doe",
    "Developer",
  )
  puts create_user_doc.to_xml(indent: 2)
  puts
end

# Demonstrate response parsing
def demonstrate_response_parsing(response_file)
  puts "=" * 80
  puts "Parsing SOAP Response"
  puts "=" * 80
  puts

  # Read response XML
  xml_content = File.read(response_file)

  # Parse response
  client = SOAPClient.new
  response = begin
    client.parse_response(xml_content)
  rescue Moxml::ParseError => e
    puts "Error parsing response: #{e.message}"
    return
  rescue Moxml::XPathError => e
    puts "Error querying response: #{e.message}"
    return
  end

  # Display response information
  puts "Response Information:"
  puts "-" * 80
  puts response
  puts

  # Display user data if present
  if response.data
    puts "User Data:"
    puts "-" * 80
    puts response.data
    puts
  end

  # Show success/failure
  puts "Result: #{response.success? ? 'SUCCESS ✓' : 'FAILED ✗'}"
  puts
end

# Main execution
if __FILE__ == $0
  puts "SOAP API Client Example"
  puts "=" * 80
  puts

  # Demonstrate building requests
  demonstrate_request_building

  # Demonstrate parsing responses
  response_file = ARGV[0] || File.join(__dir__, "example_response.xml")

  unless File.exist?(response_file)
    puts "Error: Response file not found: #{response_file}"
    puts "Usage: ruby api_client.rb [path/to/response.xml]"
    exit 1
  end

  demonstrate_response_parsing(response_file)

  # Summary
  puts "=" * 80
  puts "API Client Example Complete"
  puts "=" * 80
  puts
  puts "Key Takeaways:"
  puts "  - Use Moxml::Builder for clean XML request construction"
  puts "  - Namespace handling is crucial for SOAP/XML APIs"
  puts "  - XPath with namespaces extracts response data efficiently"
  puts "  - Proper error handling ensures robust API interactions"
  puts "  - Structure data into Ruby objects for easy manipulation"
  puts "=" * 80
end
