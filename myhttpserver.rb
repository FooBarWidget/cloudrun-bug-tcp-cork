#!/usr/bin/env ruby
require 'socket'
require 'thread'
require 'logger'
require 'json'
require 'time'
require 'base64'

PORT = (ENV['PORT'] || 9292).to_i
CORK = (ENV['CORK'] || 'true') == 'true'

class Main
  def run
    if CORK
      puts 'TCP_CORK enabled'
    else
      puts 'TCP_CORK disabled'
    end

    @server = TCPServer.new('0.0.0.0', PORT)
    @server.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

    puts "Server listening on port #{PORT}"

    while true
      client = @server.accept
      Thread.new(client, &method(:serve_client))
    end

  rescue Interrupt
    puts "Exiting..."
    exit 1
  end

private
  def serve_client(client)
    logger = Logger.new($stderr)
    logger.formatter = method(:format_log)

    logger.info 'Connection begin'
    begin
      while true
        logger.info 'Request begin'
        path = read_request(client, logger)
        logger.info "Read request: path=#{path}"

        cork_socket(client)
        if path == '/'
          respond_ok(client, logger)
        else
          respond_stream(client, logger)
        end
        uncork_socket(client)
        logger.info 'Request end'
      end
    rescue EOFError
      logger.info 'EOF'
    ensure
      logger.info 'Connection end'
      client.close
    end
  end

  def read_request(client, logger)
    line = client.readline
    log_data(logger, 'Read', line)
    path = line.split(' ')[1]

    while true
      line = client.readline
      log_data(logger, 'Read', line)
      break if line == "\r\n"
    end

    path
  end

  def respond_ok(client, logger)
    write_response_header(client, logger)
    write(client, logger, chunk('ok'))
    write(client, logger, chunk(''))
  end

  def respond_stream(client, logger)
    write_response_header(client, logger) do
      write(client, logger, "Content-Type: text/event-stream\r\n")
    end
    5.times do |i|
      write(client, logger, chunk("data: d#{i}\n\n"))
      sleep 1
    end
    write(client, logger, chunk(''))
  end

  def write_response_header(client, logger)
    write(client, logger, "HTTP/1.1 200 OK\r\n")
    write(client, logger, "Connection: keep-alive\r\n")
    write(client, logger, "Transfer-Encoding: chunked\r\n")
    yield if block_given?
    write(client, logger, "\r\n")
  end

  def write(client, logger, data)
    log_data(logger, 'Write', data)
    client.write(data)
    client.flush
  end

  def chunk(data)
    header = data.bytesize.to_s(16)
    "#{header}\r\n#{data.dup.force_encoding('binary')}\r\n"
  end

  def log_data(logger, message, data)
    data_utf8 = data.encode('UTF-8', 'binary', invalid: :replace, undef: :replace)
    logger.info(
      message: "#{message}: #{data_utf8}",
      data: data.inspect,
      data_b64: Base64.strict_encode64(data)
    )
  end

  def cork_socket(socket)
    if CORK
      socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_CORK, 1)
    end
  end

  def uncork_socket(socket)
    if CORK
      socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_CORK, 0)
    end
  end

  def format_log(severity, datetime, progname, msg)
    if msg.is_a?(String)
      JSON.generate({
        timestamp: datetime.to_datetime.rfc3339,
        severity: severity,
        message: msg,
      }) + "\n"
    else
      JSON.generate({
        timestamp: datetime.to_datetime.rfc3339,
        severity: severity,
        **msg,
      }) + "\n"
    end
  end
end

Main.new.run
