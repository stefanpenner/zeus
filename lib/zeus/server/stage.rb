module Zeus
  class Server
    class Stage
      attr_reader :pid
      def initialize(name)
        @name = name
        @stages, @actions = [], []
      end

      def action(&b)
        @actions << b
      end

      def stage(name, &b)
        @stages << Stage.new(name).tap { |s| s.instance_eval(&b) }
      end

      def acceptor(name, socket, &b)
        @stages << Acceptor.new(name, socket, &b)
      end

      # There are a few things we want to accomplish:
      # 1. Running all the actions (each time this stage is killed and restarted)
      # 2. Starting all the substages (and restarting them when necessary)
      # 3. Starting all the acceptors (and restarting them when necessary)
      def run
        @pid = fork {
          $0 = "zeus spawner: #{@name}"
          pid = Process.pid
          $w_pids.puts "#{pid}:#{Process.ppid}\n"
          puts "\x1b[35m[zeus] starting spawner `#{@name}`\x1b[0m"
          trap("INT") {
            puts "\x1b[35m[zeus] killing spawner `#{@name}`\x1b[0m"
            exit 0
          }

          @actions.each(&:call)

          $LOADED_FEATURES.each do |f|
            $w_features.puts "#{pid}:#{f}\n"
          end

          pids = {}
          @stages.each do |stage|
            pids[stage.run] = stage
          end

          loop do
            begin
              pid = Process.wait
            rescue Errno::ECHILD
              raise "Stage `#{@name}` has no children. All terminal nodes must be acceptors"
            end
            if (status = $?.exitstatus) > 0
              exit status
            else # restart the stage that died.
              stage = pids[pid]
              pids[stage.run] = stage
            end
          end

        }
      end

    end

  end
end
