module Zeus
  module DSL
    class Acceptor

      attr_reader :pid, :name, :socket, :action
      def initialize(name, socket, &b)
        @name = name
        @socket = socket
        @action = b
      end

    end

    class Stage

      attr_reader :pid, :stages, :actions
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

    end

  end
end

