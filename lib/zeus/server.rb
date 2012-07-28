require 'json'
require 'socket'

require 'rb-kqueue'

require 'zeus/process'
require 'zeus/dsl'
require 'zeus/server/file_monitor'
require 'zeus/server/master'
require 'zeus/server/process_tree_monitor'
require 'zeus/server/acceptor'

module Zeus
  class Server

    def self.define!(&b)
      @@definition = Zeus::DSL::Evaluator.new.instance_eval(&b)
    end

    attr_reader :master
    def initialize
      @file_monitor = FileMonitor.new(&method(:dependency_did_change))
      @master = Master.new
      @process_tree_monitor = ProcessTreeMonitor.new
      # TODO: deprecate Zeus::Server.define! maybe. We can do that better...
      @plan = @@definition.to_domain_object(self)
    end

    def dependency_did_change(file)
      @process_tree_monitor.kill_nodes_with_feature(file)
    end

    def run
      $0 = "zeus master"
      trap("INT") { exit 0 }
      at_exit { Process.killall_descendants(9) }

      $r_features, $w_features = IO.pipe
      $w_features.sync = true

      $r_pids, $w_pids = IO.pipe
      $w_pids.sync = true

      # boot the actual app
      @plan.run

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

  end
end
