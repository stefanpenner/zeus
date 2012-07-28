require 'json'
require 'socket'

require 'rb-kqueue'

require 'zeus/process'
require 'zeus/dsl'
require 'zeus/server/file_monitor'
require 'zeus/server/master'
require 'zeus/server/acceptor'

module Zeus
  class Server

    def self.define!(&b)
      @@spec = Zeus::DSL::Evaluator.new.instance_eval(&b)
    end

    def initialize
      @file_monitor = FileMonitor.new(&method(:dependency_did_change))
      @master = Master.new
      @process_tree_monitor = ProcessTreeMonitor.new
      # TODO: deprecate Zeus::Server.define! maybe. We can do that better...
      @spec = @@spec
    end

    # we need to keep track of:
    #
    # 1. Acceptors listening for each command
    # 2. Processes watching each file
    # 3. Process hierarchy
    # 4. ???

    def run
      $0 = "zeus master"
      trap("INT") { exit 0 }
      at_exit { Process.killall_descendants(9) }

      $r_features, $w_features = IO.pipe
      $w_features.sync = true

      $r_pids, $w_pids = IO.pipe
      $w_pids.sync = true
    end

    def dependency_did_change(file)
      @process_tree_monitor.kill_nodes_with_feature(file)
    end

    def self.run

      @@root_stage_pid = @@root.run

      loop do
        @file_monitor.process_events

        # TODO: It would be really nice if we could put the queue poller in the select somehow.
        #   --investigate kqueue. Is this possible?
        rs, _, _ = IO.select([$r_features, $r_pids], [], [], 1)
        rs.each do |r|
          case r
          when $r_pids     ; handle_pid_message(r.readline)
          when $r_features ; handle_feature_message(r.readline)
          end
        end if rs
      end

    end

    def handle_pid_message(data)
      data =~ /(\d+):(\d+)/
      pid, ppid = $1.to_i, $2.to_i
      @process_tree_monitor.process_has_parent(pid, ppid)
    end

    def handle_feature_message(data)
      data =~ /(\d+):(.*)/
      pid, file = $1.to_i, $2
      @process_tree_monitor.process_has_feature(pid, file)
      @file_monitor.watch(file)
    end

    def self.pid_has_file(pid, file)
      @@files[file] ||= []
      @@files[file] << pid
    end



=begin
    class Acceptor
      attr_reader :pid
      def initialize(name, socket, &b)
        @name = name
        @socket = socket
        @action = b
      end

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

    end
=end

  end
end
