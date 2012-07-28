require 'socket'
require 'json'

class Master
  SERVER_SOCK = ".zeus.sock"

  def run
    @socks = {}
    spawn_acceptor
    listen
    Process.waitall
  end

  def listen
    begin
      server = UNIXServer.new(SERVER_SOCK)
    rescue Errno::EADDRINUSE
      # Zeus.ui.error "Zeus appears to be already running in this project. If not, remove .zeus.sock and try again."
    end
    at_exit { server.close ; File.unlink(SERVER_SOCK) }
    loop do
      s_client = server.accept
      fork do
        handshake_client_to_acceptor(s_client)
      end
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
    s, r = @socks.values.first
    s
  end

  def spawn_acceptor
    s, r = UNIXSocket.pair(:STREAM)
    pid = Acceptor.new(s,r).run
    @socks[pid] = [s,r]
  end
end

class Acceptor
  def initialize(send, recv)
    @send, @recv = send, recv
  end

  def run
    fork {
      loop do
        terminal = @recv.recv_io
        arguments = JSON.parse(@recv.readline.chomp)
        child = fork do
          @recv << $$ << "\n"
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
