module Zeus
  module DSL

    class Evaluator
      def stage(name, &b)
        stage = DSL::Stage.new(name)
        stage.instance_eval(&b)
      end
    end

    class Acceptor

      attr_reader :pid, :name, :command, :action
      def initialize(name, command, &b)
        @name = name
        @command = command
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
        @stages << DSL::Stage.new(name).tap { |s| s.instance_eval(&b) }
      end

      def acceptor(name, socket, &b)
        @stages << DSL::Acceptor.new(name, socket, &b)
      end

    end

  end
end

