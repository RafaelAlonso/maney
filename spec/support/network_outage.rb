require "socket"

# A real, socket-level outage for system specs that need the *browser* to lose
# the network — service workers included.
#
# Chrome's `Network.emulateNetworkConditions` (via CDP or Selenium's
# `network_conditions=`) only applies to the page's own session: a service
# worker runs on a separate target, so its `fetch()` still resolves 200 while
# the page believes it is offline, and a `fetch(...).catch(...)` fallback never
# fires. Capybara's own server, meanwhile, cannot be stopped and restarted
# mid-example.
#
# So this puts a plain TCP forwarder in front of Capybara's server and points
# the browser at it. Going "offline" closes the forwarder's listening socket
# and every connection currently open through it, which is the same failure a
# phone in airplane mode produces: the browser — and the service worker with it
# — cannot reach the origin at all. Going "online" listens again on the very
# same port, so the origin, and therefore the worker's registration and its
# cache, stay put for the whole example.
class NetworkOutage
  attr_reader :host, :port

  def initialize(target_host:, target_port:, host: "127.0.0.1")
    @target_host = target_host
    @target_port = target_port
    @host = host
    @mutex = Mutex.new
    @connections = []
    @listener = nil
    @acceptor = nil
    @port = nil

    listen(0)
  end

  def origin = "http://#{host}:#{port}"

  def online? = @mutex.synchronize { !@listener.nil? }

  def go_offline
    listener, acceptor = @mutex.synchronize do
      pair = [ @listener, @acceptor ]
      @listener = nil
      @acceptor = nil
      pair
    end
    return if listener.nil?

    close(listener)
    acceptor&.join(5)
    close_connections
  end

  def go_online
    listen(port) unless online?
  end

  private

  def listen(port)
    listener = bind(port)
    @port ||= listener.addr[1]
    acceptor = Thread.new { accept_loop(listener) }
    @mutex.synchronize do
      @listener = listener
      @acceptor = acceptor
    end
  end

  # Sockets closed a moment ago can leave the port in TIME_WAIT. TCPServer sets
  # SO_REUSEADDR, which covers that, but a connection still being torn down can
  # briefly refuse the bind anyway — hence the short retry.
  def bind(port)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    begin
      TCPServer.new(host, port)
    rescue Errno::EADDRINUSE
      raise if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.05
      retry
    end
  end

  def accept_loop(listener)
    loop do
      client =
        begin
          listener.accept
        rescue IOError, SystemCallError
          break # the listener was closed: we are offline
        end

      forward(client)
    end
  end

  def forward(client)
    upstream = TCPSocket.new(@target_host, @target_port)
    track(client, upstream)
    pipe(client, upstream)
    pipe(upstream, client)
  rescue StandardError
    close(client)
  end

  def pipe(from, to)
    Thread.new do
      IO.copy_stream(from, to)
    rescue StandardError
      # The other end went away; the ensure block below is the whole cleanup.
    ensure
      close(from)
      close(to)
    end
  end

  def track(*sockets)
    @mutex.synchronize do
      @connections.reject!(&:closed?)
      @connections.concat(sockets)
    end
  end

  def close_connections
    open = @mutex.synchronize do
      taken = @connections
      @connections = []
      taken
    end
    open.each { |socket| close(socket) }
  end

  def close(socket)
    socket.close
  rescue IOError, SystemCallError
    nil
  end
end

# Routes a system spec's traffic through a NetworkOutage instead of straight at
# Capybara's server, and gives it `go_offline` / `go_online`.
#
# Included into every system spec but inert until `route_through_network_outage`
# runs, so only the specs that ask for it change origin.
module NetworkOutageHelpers
  def route_through_network_outage
    server = Capybara.current_session.server
    NetworkOutageHelpers.outage ||= NetworkOutage.new(target_host: server.host, target_port: server.port)

    @capybara_app_host_before_outage = Capybara.app_host
    Capybara.app_host = network_outage.origin
  end

  def restore_direct_network
    Capybara.app_host = @capybara_app_host_before_outage
    network_outage&.go_online
  end

  def network_outage = NetworkOutageHelpers.outage

  def go_offline = network_outage.go_offline

  def go_online = network_outage.go_online

  class << self
    attr_accessor :outage
  end
end

RSpec.configure do |config|
  config.include NetworkOutageHelpers, type: :system
end

at_exit { NetworkOutageHelpers.outage&.go_offline }
