require 'json'
require 'socket'

# See Zeus::Server::Master for relevant documentation
module Zeus
  class Server
    class Acceptor

      attr_accessor :name, :command, :action
      def initialize(server)
        @master = server.master
      end

      def register_with_master(pid)
        a, b = Socket.pair(:UNIX, :STREAM)
        @s_master = UNIXSocket.for_fd(a.fileno)
        @s_acceptor = UNIXSocket.for_fd(b.fileno)

        @s_acceptor.puts registration_data(pid)

        puts ">>>"
        puts @master.acceptor_registration_socket.inspect
        puts @s_master.inspect
        @master.acceptor_registration_socket.send_io(@s_master)
      end

      def registration_data(pid)
        {pid: pid, commands: [command], description: "start a rails console"}.to_json
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

__END__
def run
  @pid = fork {
    $0 = "zeus acceptor: #{@name}"
    pid = Process.pid
    $w_pids.puts "#{pid}:#{Process.ppid}\n"
    $LOADED_FEATURES.each do |f|
      $w_features.puts "#{pid}:#{f}\n"
    end
    puts "\x1b[35m[zeus] starting acceptor `#{@name}`\x1b[0m"
    trap("INT") {
      puts "\x1b[35m[zeus] killing acceptor `#{@name}`\x1b[0m"
      exit 0
    }

    File.unlink(@socket) rescue nil
    server = UNIXServer.new(@socket)
    loop do
      ActiveRecord::Base.clear_all_connections! # TODO : refactor
      client = server.accept
      child = fork do
        ActiveRecord::Base.establish_connection # TODO :refactor
        ActiveSupport::DescendantsTracker.clear
        ActiveSupport::Dependencies.clear

        terminal = client.recv_io
        arguments = JSON.load(client.gets.strip)

        client << $$ << "\n"
        $stdin.reopen(terminal)
        $stdout.reopen(terminal)
        $stderr.reopen(terminal)
        ARGV.replace(arguments)

        @action.call
      end
      Process.detach(child)
      client.close
    end
  }
end

