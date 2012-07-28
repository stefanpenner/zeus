require 'socket'
require 'json'

# The model here is kind of convoluted, so here's an explanation of what's
# happening with all these sockets:
#
# #### Acceptor Registration
# 1. Master creates a socketpair for Acceptor registration (S_REG)
# 2. When an acceptor is spawned, it:
#   1. Creates a new socketpair for communication with master (S_ACC)
#   2. Sends one side of S_ACC over S_REG to master.
#   3. Sends a JSON-encoded hash of `pid`, `commands`, and `description`. over S_REG.
# 3. Master received first the IO and then the JSON hash, and stores them for later reference.
#
# #### Running a command
# 1. Master has a UNIXServer (SVR) listening.
# 2. Master has a socketpair with the acceptor referenced by the command (see Registration) (S_ACC)
# 3. When master received a connection (S_CLI) on SVR:
#   1. Master sends S_CLI over S_ACC, so the acceptor can communicate with the server's client.
#   2. Master sends a JSON-encoded array of `arguments` over S_ACC
#   3. Acceptor sends the newly-forked worker PID over S_ACC to master.
#   4. Master forwards the pid to the client over S_CLI.
#
class Master
  SERVER_SOCK = ".zeus.sock"

  def initialize
    s, r = Socket.pair(:UNIX, :STREAM)
    @reg_master   = UNIXSocket.for_fd(s.fileno)
    @reg_acceptor = UNIXSocket.for_fd(r.fileno)
    @acceptors = []
  end

  def run
    @socks = {}
    spawn_acceptor
    listen
  end

  def listen
    begin
      begin
        server = UNIXServer.new(SERVER_SOCK)
        server.listen(10)
      rescue Errno::EADDRINUSE
        # Zeus.ui.error "Zeus appears to be already running in this project. If not, remove .zeus.sock and try again."
      end
      loop do
        rs, = IO.select([server, @reg_master])
        next unless rs
        rs.include?(server)      and handle_server_connection(server)
        rs.include?(@reg_master) and handle_registration
      end
    ensure
      server.close
      File.unlink(SERVER_SOCK)
    end
  end

  def handle_registration
    io = @reg_master.recv_io
    sock = UNIXSocket.for_fd(io.fileno)

    data = JSON.parse(io.readline.chomp)
    pid         = data['pid'].to_i
    commands    = data['commands']
    description = data['description']

    @acceptors << AcceptorStub.new(pid, sock, commands, description)
  end

  AcceptorStub = Struct.new(:pid, :socket, :commands, :description)

  def handle_server_connection(server)
    s_client = server.accept
    fork { handshake_client_to_acceptor(s_client) }
  end

  #  client    master    acceptor
  # 1  ---------->                | {command: String, arguments: [String]}
  # 2  ---------->                | Terminal IO
  # 3            ----------->     | Terminal IO
  # 4            ----------->     | Arguments (json array)
  # 5            <-----------     | pid
  # 6  <---------                 | pid
  def handshake_client_to_acceptor(s_client)
    # 1
    data = JSON.parse(s_client.readline.chomp)
    command, arguments = data.values_at('command', 'arguments')

    # 2
    client_terminal = s_client.recv_io

    # 3
    acceptor = find_acceptor_for_command(command)
    # TODO handle nothing found
    acceptor.socket.send_io(client_terminal)

    puts "accepting connection for #{command}"

    # 4
    acceptor.socket.puts arguments.to_json

    # 5
    pid = acceptor.socket.readline.chomp.to_i

    # 6
    s_client.puts pid
  end

  def find_acceptor_for_command(command)
    @acceptors.detect { |acceptor|
      acceptor.commands.include?(command)
    }
  end

  def acceptor_registration_socket
    @reg_acceptor
  end

  def register_acceptor(pid, s, r)
    @socks[pid] = [s,r]
  end

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

    @s_acceptor.puts registration_data(pid)

    @master.acceptor_registration_socket.send_io(@s_master)
  end

  def registration_data(pid)
    {pid: pid, commands: ['console', 'c'], description: "start a rails console"}.to_json
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
