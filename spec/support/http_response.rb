class HTTPResponse

end

class HTTPRequest
  def initialize(request)
    lines = request.dup
    @type, @response_code, @request_method = text.shift.split(" ")
    @headers = {}
    while (line = lines.shift) != "\n" do
      key, value = line.split(": ", 2)
      @headers[key] = value
    end
    @body = @lines.join("\n")
  end
end
