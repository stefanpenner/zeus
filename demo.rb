require 'socket'
require 'json'

class Master
  SERVER_SOCK = ".zeus.sock"

  def initialize
    s, r = Socket.pair(:UNIX, :STREAM)
    @reg_master   = UNIXSocket.for_fd(s.fileno)
    @reg_acceptor = UNIXSocket.for_fd(r.fileno)
  end

  def run
    @socks = {}
    spawn_acceptor
    listen
    Process.waitall
  end

  def listen
    begin
      server = UNIXServer.new(SERVER_SOCK)
      server.listen(10)
      at_exit { server.close ; File.unlink(SERVER_SOCK) }
    rescue Errno::EADDRINUSE
      # Zeus.ui.error "Zeus appears to be already running in this project. If not, remove .zeus.sock and try again."
    end
    loop do
      rs, = IO.select([server, @reg_master])
      next unless rs
      rs.include?(server) and handle_server_connection(server)
      rs.include?(@reg_master) and handle_registration
    end
  end

  # master   acceptor
  #    <---------     | socket
  def handle_registration
    io = @reg_master.recv_io
    pid = io.readline.chomp.to_i
    sock = UNIXSocket.for_fd(io.fileno)
    @socks[pid] = sock
  end

  def handle_server_connection(server)
    s_client = server.accept
    fork do
      handshake_client_to_acceptor(s_client)
    end
  end

  # client    master    acceptor
  #   ---------->                | {command: String, arguments: [String]}
  #   ---------->                | Terminal IO
  #             ----------->     | Terminal IO
  #             ----------->     | Arguments (json array)
  #             <-----------     | pid
  #   <---------                 | pid
  def handshake_client_to_acceptor(s_client)
    data = JSON.parse(s_client.readline.chomp)
    command, arguments = data.values_at('command', 'arguments')

    client_terminal = s_client.recv_io

    s_acceptor = find_acceptor_sock(command)

    s_acceptor.send_io(client_terminal)

    s_acceptor.puts arguments.to_json

    pid = s_acceptor.readline.chomp.to_i
    s_client.puts pid
  end

  def find_acceptor_sock(command)
    puts @socks.inspect
    # TODO lookup command
    @socks.values.first
  end

  def acceptor_registration_socket
    @reg_acceptor
  end

  def register_acceptor(pid, s, r)
    @socks[pid] = [s,r]
  end

  # Problem: we have to pass stuff into the acceptor.
  # It should be able to register itself with the master.
  # How do we accomplish this?
  #
  # 1. Initialize a global socket in the master process
  # 2. when Acceptor spawns, it initializes its own internal socket
  # 3. It sends the sockets to the global thing
  # 4. It sends a message on the socket pair indicating who it is.
  #
  def spawn_acceptor
    Acceptor.new(self).run
  end
end

class Acceptor
  def initialize(master)
    @master = master
  end

  def register_with_master(pid)
    a, b = Socket.pair(:UNIX, :STREAM)
    @s_master = UNIXSocket.for_fd(a.fileno)
    @s_acceptor = UNIXSocket.for_fd(b.fileno)
    @s_acceptor.puts "#{pid}\n"
    @master.acceptor_registration_socket.send_io(@s_master)
  end

  def run
    fork {
      register_with_master($$)
      loop do
        terminal = @s_acceptor.recv_io
        arguments = JSON.parse(@s_acceptor.readline.chomp)
        child = fork do
          @s_acceptor << $$ << "\n"
          $stdin.reopen(terminal)
          $stdout.reopen(terminal)
          $stderr.reopen(terminal)
          ARGV.replace(arguments)

          exec("htop")
        end
        Process.detach(child)
        terminal.close
      end
    }
  end
end


__FILE__ == $0 and Master.new.run
