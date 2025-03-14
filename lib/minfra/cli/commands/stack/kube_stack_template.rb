require 'pathname'
module Minfra
  module Cli
    module StackM
      class KubeStackTemplate
      include ::Minfra::Cli::Logging

      attr_reader :name, :env, :deployment, :config_path
      def initialize(name, config, deployment: '', cluster:)
        @name       = name
        @config_path = config.stacks_path.join(name)
        @errors     = []
        @config     = config
        @env        = config.orch_env
        @deployment = deployment.freeze
        @cluster    = cluster.freeze || l!("cluster").id
        @result_path = config.status_path.join('stacks', @cluster, name)
        debug "Stack selection: #{@name}, #{@config_path}, #{@cluster}, #{@result_path}"
      end

      def cluster_name
        @cluster
      end

      def mixin_env
        "#{@env}#{dashed(@deployment)}"
      end

      def valid?
        unless @config_path.exist?
          @errors << "stack path #{@config_path} doesn't exist"
        end

        unless stack_rb_path.exist?
          @errors << "stack.rb file #{stack_rb_path} doesn't exist"
        end
        @errors.empty?
      end

      def stack_rb_path
        config_path.join('stack.rb')
      end

      def compose_path(blank: false)
        if blank
          release_path.join("compose.yaml")
        elsif @cluster
          release_path.join("compose#{dashed(@cluster)}.yaml")
        else
          release_path.join("compose#{dashed(@env)}#{dashed(@deployment)}.yaml")
        end
      end

      def error_message
        @errors.join(";\n")
      end

      def release_path
        @result_path
      end


      def check_plan
        errors = []
        errors
      end

      private
      def dashed(sth,set=nil)
        sth.nil? || sth.empty? ? '' : "-#{set||sth}"
      end
    end
  end
end
end
