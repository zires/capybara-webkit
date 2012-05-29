require 'spec_helper'
require 'self_signed_ssl_cert'
require 'stringio'
require 'capybara/driver/webkit/browser'
require 'capybara/driver/webkit/connection'
require 'socket'
require 'base64'

describe Capybara::Driver::Webkit::Browser do

  let(:browser) { Capybara::Driver::Webkit::Browser.new(Capybara::Driver::Webkit::Connection.new) }
  let(:browser_ignore_ssl_err) do
    Capybara::Driver::Webkit::Browser.new(Capybara::Driver::Webkit::Connection.new).tap do |browser|
      browser.ignore_ssl_errors
    end
  end
  let(:browser_skip_images) do
    Capybara::Driver::Webkit::Browser.new(Capybara::Driver::Webkit::Connection.new).tap do |browser|
      browser.set_skip_image_loading(true)
    end
  end

  context 'handling of SSL validation errors' do
    before do
      # set up minimal HTTPS server
      @host = "127.0.0.1"
      @server = TCPServer.new(@host, 0)
      @port = @server.addr[1]

      # set up SSL layer
      ssl_serv = OpenSSL::SSL::SSLServer.new(@server, $openssl_self_signed_ctx)

      @server_thread = Thread.new(ssl_serv) do |serv|
        while conn = serv.accept do
          # read request
          request = []
          until (line = conn.readline.strip).empty?
            request << line
          end

          # write response
          html = "<html><body>D'oh!</body></html>"
          conn.write "HTTP/1.1 200 OK\r\n"
          conn.write "Content-Type:text/html\r\n"
          conn.write "Content-Length: %i\r\n" % html.size
          conn.write "\r\n"
          conn.write html
          conn.close
        end
      end
    end

    after do
      @server_thread.kill
      @server.close
    end

    it "doesn't accept a self-signed certificate by default" do
      lambda { browser.visit "https://#{@host}:#{@port}/" }.should raise_error
    end

    it 'accepts a self-signed certificate if configured to do so' do
      browser_ignore_ssl_err.visit "https://#{@host}:#{@port}/"
    end
  end

  context "skip image loading" do
    before(:each) do
      # set up minimal HTTP server
      @host = "127.0.0.1"
      @server = TCPServer.new(@host, 0)
      @port = @server.addr[1]
      @received_requests = []

      @server_thread = Thread.new(@server) do |serv|
        while conn = serv.accept do
          # read request
          request = []
          until (line = conn.readline.strip).empty?
            request << line
          end

          @received_requests << request.join("\n")

          # write response
          html = <<-HTML
            <html>
              <head>
                <style>
                  body {
                    background-image: url(/path/to/bgimage);
                  }
                </style>
              </head>
              <body>
                <img src="/path/to/image"/>
              </body>
            </html>
        HTML
          conn.write "HTTP/1.1 200 OK\r\n"
          conn.write "Content-Type:text/html\r\n"
          conn.write "Content-Length: %i\r\n" % html.size
          conn.write "\r\n"
          conn.write html
          conn.write("\r\n\r\n")
          conn.close
        end
      end
    end

    after(:each) do
      @server_thread.kill
      @server.close
    end

    it "should load images in image tags by default" do
      browser.visit("http://#{@host}:#{@port}/")
      @received_requests.find {|r| r =~ %r{/path/to/image}   }.should_not be_nil
    end

    it "should load images in css by default" do
      browser.visit("http://#{@host}:#{@port}/")
      @received_requests.find {|r| r =~ %r{/path/to/image}   }.should_not be_nil
    end

    it "should not load images in image tags when skip_image_loading is true" do
      browser_skip_images.visit("http://#{@host}:#{@port}/")
      @received_requests.find {|r| r =~ %r{/path/to/image} }.should be_nil
    end

    it "should not load images in css when skip_image_loading is true" do
      browser_skip_images.visit("http://#{@host}:#{@port}/")
      @received_requests.find {|r| r =~ %r{/path/to/bgimage} }.should be_nil
    end
  end

  describe "basic auth" do
    before do
      @host = '127.0.0.1'
      @user = 'user'
      @password = 'password'

      @server = TCPServer.new(@host, 0)
      @port = @server.addr[1]
      @server_thread = Thread.new(@server) do |serv|
        while conn = serv.accept do
          begin
            request = []
            until (line = conn.readline.strip).empty?
              request << line
            end

            request_lines = request.dup
            response = request_lines.shift
            @headers = {}
            while (line = request_lines.shift || "").strip != ""
              header, value = line.split(": ", 2)
              @headers[header] = value
            end

            if @headers["Authorization"]
              html = "<html><head></head><body>Ok</body></html>"
              conn.write "HTTP/1.1 200 OK\r\n"
              conn.write "Content-Type:text/html\r\n"
              conn.write "Content-Length: %i\r\n" % html.size
              conn.write "\r\n"
              conn.write html
              conn.write "\r\n\r\n"
              conn.close
            else
              html = <<-HTML
  <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
   "http://www.w3.org/TR/1999/REC-html401-19991224/loose.dtd">
  <HTML>
    <HEAD>
      <TITLE>Error</TITLE>
      <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=ISO-8859-1">
    </HEAD>
    <BODY><H1>401 Unauthorized.</H1></BODY>
  </HTML>
              HTML

              conn.write "HTTP/1.1 401 Authorization Required\r\n"
              conn.write "Content-Type:text/html\r\n"
              conn.write "Content-Length: %i\r\n" % html.size
              conn.write %{WWW-Authenticate: Basic realm="Secure Area"\r\n}
              conn.write "\r\n"
              conn.write html
              conn.write "\r\n\r\n"
              conn.close
            end
          rescue Exception => e
            $stdout.puts e.to_s
          end
        end
      end
    end

    after(:each) do
      @server_thread.kill
      @server.close
    end

    it "can authenticate a request" do
      browser.authenticate('user', 'password')
      browser.visit("http://#{@host}:#{@port}/")
      @headers["Authorization"].should == "Basic "+Base64.encode64("user:password").strip
    end
  end

  describe "forking", :skip_on_windows => true do
    it "only shuts down the server from the main process" do
      browser.reset!
      pid = fork {}
      Process.wait(pid)
      expect { browser.reset! }.not_to raise_error
    end
  end

  describe '#set_proxy' do
    before do
      @host = '127.0.0.1'
      @user = 'user'
      @pass = 'secret'
      @url  = "http://example.org/"

      @server = TCPServer.new(@host, 0)
      @port = @server.addr[1]

      @proxy_requests = []
      @proxy = Thread.new(@server, @proxy_requests) do |serv, proxy_requests|
        while conn = serv.accept do
          # read request
          request = []
          until (line = conn.readline.strip).empty?
            request << line
          end

          # send response
          auth_header = request.find { |h| h =~ /Authorization:/i }
          if auth_header || request[0].split(/\s+/)[1] =~ /^\//
            html = "<html><body>D'oh!</body></html>"
            conn.write "HTTP/1.1 200 OK\r\n"
            conn.write "Content-Type:text/html\r\n"
            conn.write "Content-Length: %i\r\n" % html.size
            conn.write "\r\n"
            conn.write html
            conn.close
            proxy_requests << request if auth_header
          else
            conn.write "HTTP/1.1 407 Proxy Auth Required\r\n"
            conn.write "Proxy-Authenticate: Basic realm=\"Proxy\"\r\n"
            conn.write "\r\n"
            conn.close
            proxy_requests << request
          end
        end
      end

      browser.set_proxy(:host => @host,
                        :port => @port,
                        :user => @user,
                        :pass => @pass)
      browser.visit @url
      @proxy_requests.size.should == 2
      @request = @proxy_requests[-1]
    end

    after do
      @proxy.kill
      @server.close
    end

    it 'uses the HTTP proxy correctly' do
      @request[0].should match /^GET\s+http:\/\/example.org\/\s+HTTP/i
      @request.find { |header|
        header =~ /^Host:\s+example.org$/i }.should_not be nil
    end

    it 'sends correct proxy authentication' do
      auth_header = @request.find { |header|
        header =~ /^Proxy-Authorization:\s+/i }
      auth_header.should_not be nil

      user, pass = Base64.decode64(auth_header.split(/\s+/)[-1]).split(":")
      user.should == @user
      pass.should == @pass
    end

    it "uses the proxies' response" do
      browser.body.should include "D'oh!"
    end

    it 'uses original URL' do
      browser.url.should == @url
    end

    it 'uses URLs changed by javascript' do
      browser.execute_script "window.history.pushState('', '', '/blah')"
      browser.requested_url.should == 'http://example.org/blah'
    end

    it 'is possible to disable proxy again' do
      @proxy_requests.clear
      browser.clear_proxy
      browser.visit "http://#{@host}:#{@port}/"
      @proxy_requests.size.should == 0
    end
  end

  it "doesn't try to read an empty response" do
    connection = stub("connection")
    connection.stub(:puts)
    connection.stub(:print)
    connection.stub(:gets).and_return("ok\n", "0\n")
    connection.stub(:read).and_raise(StandardError.new("tried to read empty response"))

    browser = Capybara::Driver::Webkit::Browser.new(connection)

    expect { browser.visit("/") }.not_to raise_error(/empty response/)
  end
end
