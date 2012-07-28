require 'json'
require 'socket'

# See Zeus::Server::Master for relevant documentation
module Zeus
  module Server
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
  end
end
