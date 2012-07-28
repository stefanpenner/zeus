require 'zeus/server/stage'
require 'zeus/server/acceptor'

module Zeus
  module DSL

    class Evaluator
      def stage(name, &b)
        stage = DSL::Stage.new(name)
        stage.instance_eval(&b)
      end
    end

    class Acceptor

      attr_reader :name, :command, :action
      def initialize(name, command, &b)
        @name = name
        @command = command
        @action = b
      end

      def to_domain_object(server)
        Zeus::Server::Acceptor.new(server).tap do |stage|
          stage.name = @name
          stage.command = @command
          stage.action = @action
        end
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
        self
      end

      def stage(name, &b)
        @stages << DSL::Stage.new(name).tap { |s| s.instance_eval(&b) }
        self
      end

      def acceptor(name, socket, &b)
        @stages << DSL::Acceptor.new(name, socket, &b)
        self
      end

      def to_domain_object(server)
        Zeus::Server::Stage.new(server).tap do |stage|
          stage.name = @name
          stage.stages = @stages.map { |stage| stage.to_domain_object(server) }
          stage.actions = @actions
        end
      end

    end

  end
end

