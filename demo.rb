require 'socket'
require 'json'

class Master
  SERVER_SOCK = ".zeus.sock"

  def run
    @socks = {}
    spawn_server
    stuff
  end

  def stuff
    server = UNIXServer.new(SERVER_SOCK)
    loop do
      client = server.accept
      child = fork do
        client_terminal = client.recv_io
        arguments = client.readline.chomp
        pid = @socks.keys.first
        s, r = @socks.values.first
        s.send_io(client_terminal)
        s.puts arguments
        pid = s.readline.chomp.to_i
        client << {pid: pid}.to_json << "\n"
      end
    end
  end

  def spawn_server
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
        data = JSON.parse(@recv.readline.chomp)
        arguments = data['arguments']
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


Master.new.run
Process.waitall
