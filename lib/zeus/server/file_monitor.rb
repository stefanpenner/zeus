require 'rb-kqueue'

module Zeus
  module Server
    class FileMonitor

      def initialize(&change_callback)
        configure_file_descriptor_resource_limit
        @queue = KQueue::Queue.new
        @watched_files = {}
        @deleted_files = []
        @callback = callback
      end

      def process_events
        @queue.poll
      end

      def file_did_change(event)
        Zeus.ui.log("Dependency change at #{event.watcher.path}")
        resubscribe_deleted_file(event) if event.flags.include?(:delete)
        @change_callback.call(event.watcher.path)
      end

      def watch(file)
        return if @watched_files[file]
        @watched_files[file] = true
        @queue.watch_file(file, :write, :extend, :rename, :delete, &method(:file_did_change))
      rescue Errno::ENOENT
        Zeus.ui.debug("No file found at #{file}")
      end

      TARGET_FD_LIMIT = 8192

      def configure_file_descriptor_resource_limit
        limit = Process.getrlimit(Process::RLIMIT_NOFILE)
        if limit[0] < TARGET_FD_LIMIT && limit[1] >= TARGET_FD_LIMIT
          Process.setrlimit(Process::RLIMIT_NOFILE, TARGET_FD_LIMIT)
        else
          puts "\x1b[33m[zeus] Warning: increase the max number of file descriptors. If you have a large project, this max cause a crash in about 10 seconds.\x1b[0m"
        end
      end

      private

      def resubscribe_deleted_file(event)
        event.watcher.disable!
        begin
          @queue.watch_file(event.watcher.path, :write, :extend, :rename, :delete, &method(:file_did_change))
        rescue Errno::ENOENT
          @deleted_files << event.watcher.path
        end
      end

    end
  end
end