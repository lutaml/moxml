# API Client Example

This example demonstrates how to use Moxml for XML API interactions, including building SOAP requests, parsing responses, and handling namespaces.

## What This Example Demonstrates

- **XML Request Building**: Creating SOAP requests with Moxml::Builder
- **Response Parsing**: Extracting data from XML API responses
- **Namespace Handling**: Working with multiple XML namespaces (SOAP, custom)
- **Authentication**: Including authentication headers
- **Error Handling**: Robust error handling for API interactions
- **Data Structuring**: Converting XML responses to Ruby objects

## Files

- `api_client.rb` - Main API client implementation
- `example_response.xml` - Sample SOAP API response
- `README.md` - This file

## Running the Example

### Using the Example Response

```bash
ruby examples/api_client/api_client.rb
```

### Using Your Own Response

```bash
ruby examples/api_client/api_client.rb path/to/your/response.xml
```

## Expected Output

```
SOAP API Client Example
================================================================================

Building SOAP Requests
================================================================================

1. GetUser Request:
--------------------------------------------------------------------------------
<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" ...>
  <soap:Header>
    <AuthHeader xmlns="http://api.example.com/auth">
      <SessionId>session-abc-123</SessionId>
      <Timestamp>2024-10-30T10:00:00Z</Timestamp>
      <RequestId>req-a1b2c3</RequestId>
    </AuthHeader>
  </soap:Header>
  <soap:Body>
    <GetUserRequest xmlns="http://api.example.com/users">
      <UserId>1001</UserId>
    </GetUserRequest>
  </soap:Body>
</soap:Envelope>

[Additional request examples...]

Parsing SOAP Response
================================================================================

Response Information:
--------------------------------------------------------------------------------
Status: 200 - Success
Session ID: a1b2c3d4-e5f6-g7h8-i9j0-k1l2m3n4o5p6
Request ID: req-12345
Metadata: {:response_time=>"45", :server_version=>"2.1.0", :cache_hit=>"false"}

User Data:
--------------------------------------------------------------------------------
User ID: 1001
Username: johndoe
Email: john.doe@example.com
Full Name: John Doe
Role: Administrator
Status: Active
Created: 2024-01-15T08:30:00Z
Last Login: 2024-10-29T14:22:00Z
Permissions: users.read, users.write, admin.access
Profile:
  Department: Engineering
  Title: Senior Developer
  Location: San Francisco, CA
  PhoneNumber: +1-555-0123

Result: SUCCESS ✓
```

## Key Concepts

### Building SOAP Requests

Use Moxml::Builder to create well-formed SOAP envelopes:

```ruby
doc = Moxml::Builder.new(@moxml).build do
  declaration version: "1.0", encoding: "UTF-8"

  element 'soap:Envelope',
          'xmlns:soap' => 'http://schemas.xmlsoap.org/soap/envelope/' do

    element 'soap:Header' do
      # Authentication headers
    end

    element 'soap:Body' do
      # Request payload
    end
  end
end
```

### Namespace Declaration

Define namespaces as constants for reusability:

```ruby
NAMESPACES = {
  'soap' => 'http://schemas.xmlsoap.org/soap/envelope/',
  'auth' => 'http://api.example.com/auth',
  'users' => 'http://api.example.com/users'
}.freeze

# Use in XPath queries
doc.at_xpath('//users:User', NAMESPACES)
```

### Parsing Responses

Extract data using namespace-aware XPath:

```ruby
# Extract with namespace
user_id = extract_text(doc, '//users:User/users:Id', NAMESPACES)

# Extract arrays
permissions = doc.xpath('//users:Permission', NAMESPACES).map(&:text)

# Extract nested structures
profile = doc.at_xpath('//users:Profile', NAMESPACES)
department = extract_text(profile, './users:Department', NAMESPACES)
```

### Error Handling

Handle parsing and query errors:

```ruby
begin
  doc = @moxml.parse(xml_string)
  response = parse_response(doc)
rescue Moxml::ParseError => e
  puts "Parse error: #{e.message}"
rescue Moxml::XPathError => e
  puts "Query error: #{e.message}"
end
```

### Authentication Headers

Include authentication in SOAP headers:

```ruby
element 'soap:Header' do
  element 'AuthHeader', 'xmlns' => NAMESPACES['auth'] do
    element 'SessionId' do
      text session_id
    end
    element 'Timestamp' do
      text Time.now.utc.iso8601
    end
  end
end
```

## Code Structure

### User Class

Represents API user data:
- Basic info (id, username, email, etc.)
- Permissions array
- Profile hash

### APIResponse Class

Encapsulates API response:
- Status code and message
- Response data
- Metadata (response time, version, etc.)
- Session and request IDs

### SOAPClient Class

Main API client with methods:
- `build_get_user_request` - Build GetUser SOAP request
- `build_create_user_request` - Build CreateUser SOAP request
- `parse_response` - Parse SOAP response
- `parse_user` - Extract user data
- `extract_metadata` - Extract response metadata

## SOAP Structure Reference

### Request Structure

```xml
<soap:Envelope>
  <soap:Header>
    <AuthHeader>
      <!-- Authentication data -->
    </AuthHeader>
  </soap:Header>
  <soap:Body>
    <OperationRequest>
      <!-- Request parameters -->
    </OperationRequest>
  </soap:Body>
</soap:Envelope>
```

### Response Structure

```xml
<soap:Envelope>
  <soap:Header>
    <AuthHeader>
      <!-- Session info -->
    </AuthHeader>
  </soap:Header>
  <soap:Body>
    <OperationResponse>
      <Status>
        <!-- Status code/message -->
      </Status>
      <Result>
        <!-- Response data -->
      </Result>
      <Metadata>
        <!-- Additional info -->
      </Metadata>
    </OperationResponse>
  </soap:Body>
</soap:Envelope>
```

## Customization

### Adding New Operations

Create new request builders:

```ruby
def build_delete_user_request(user_id)
  Moxml::Builder.new(@moxml).build do
    declaration version: "1.0", encoding: "UTF-8"

    element 'soap:Envelope', 'xmlns:soap' => NAMESPACES['soap'] do
      element 'soap:Header' do
        # Auth header
      end

      element 'soap:Body' do
        element 'DeleteUserRequest', 'xmlns' => NAMESPACES['users'] do
          element 'UserId' do
            text user_id.to_s
          end
        end
      end
    end
  end
end
```

### Custom Response Parsers

Parse different response types:

```ruby
def parse_list_response(doc)
  users = doc.xpath('//users:User', NAMESPACES)
  users.map { |user_elem| parse_user(user_elem) }
end
```

### Error Responses

Handle SOAP faults:

```ruby
fault = doc.at_xpath('//soap:Fault', NAMESPACES)
if fault
  fault_code = extract_text(fault, './faultcode')
  fault_string = extract_text(fault, './faultstring')
  raise "SOAP Fault: #{fault_code} - #{fault_string}"
end
```

## Namespace Best Practices

1. **Define once**: Keep namespace URIs in constants
2. **Use prefixes**: Consistent prefixes make code readable
3. **Pass to XPath**: Always include namespaces in queries
4. **Document**: Comment namespace purposes

```ruby
# Good: Clear namespace management
NAMESPACES = {
  'soap' => 'http://schemas.xmlsoap.org/soap/envelope/',  # SOAP envelope
  'auth' => 'http://api.example.com/auth',                # Authentication
  'users' => 'http://api.example.com/users'               # User operations
}.freeze

# Use consistently
doc.xpath('//users:User', NAMESPACES)
```

## Common Patterns

### Conditional Elements

Include elements conditionally:

```ruby
element 'soap:Body' do
  element 'Request' do
    element 'UserId' do
      text user_id
    end

    # Optional filter
    if filter
      element 'Filter' do
        text filter
      end
    end
  end
end
```

### Array Elements

Create multiple elements:

```ruby
permissions.each do |perm|
  element 'Permission' do
    text perm
  end
end
```

### Nested Structures

Build complex hierarchies:

```ruby
element 'User' do
  element 'BasicInfo' do
    element 'Username' do
      text username
    end
  end

  element 'Profile' do
    element 'Department' do
      text department
    end
  end
end
```

## Learning Points

1. **Builder pattern**: Clean, readable XML construction
2. **Namespaces**: Critical for SOAP and enterprise XML
3. **XPath + namespaces**: Powerful data extraction
4. **Structure data**: Convert XML to Ruby objects
5. **Error handling**: Robust API client behavior
6. **Reusability**: Extract common patterns to methods

## Testing

Test API clients thoroughly:

```ruby
# Test request building
request = client.build_get_user_request(123)
assert request.to_xml.include?('<UserId>123</UserId>')

# Test response parsing
response = client.parse_response(sample_xml)
assert_equal 200, response.status_code
assert response.success?
```

## Real-World Usage

To use with actual APIs:

1. Replace `example_response.xml` with real responses
2. Add HTTP client (e.g., Net::HTTP, HTTParty)
3. Handle network errors
4. Implement retry logic
5. Add request/response logging
6. Implement authentication refresh

## Next Steps

- Add more API operations (update, delete, list)
- Implement HTTP transport layer
- Add request/response logging
- Implement authentication token refresh
- Handle pagination in list responses
- Add response caching
- Implement request rate limiting

## Related Examples

- [RSS Parser](../rss_parser/) - XPath and namespace handling
- [Web Scraper](../web_scraper/) - DOM navigation techniques