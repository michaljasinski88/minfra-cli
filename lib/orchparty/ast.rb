require 'hashie'

module Orchparty
  class AST
    class Node < ::Hashie::Mash
      include Hashie::Extensions::DeepMerge
      include Hashie::Extensions::DeepMergeConcat
      include Hashie::Extensions::MethodAccess
      include Hashie::Extensions::Mash::KeepOriginalKeys
      disable_warnings

      def get_binding
        binding
      end

      def inspect(indent=0)
        start="\n"
        each_pair do |name, ast|
          begin
            start << "#{'  ' * indent}#{name}: #{ast.inspect(indent+1)}\n"
          rescue ArgumentError
            start << "#{'  ' * indent}#{name}: #{ast.inspect}\n"
          end  
        end
        start
      end
    end

    def self.hash(args = {})
      Node.new.merge(args)
    end

    def self.array(args = [])
      args
    end

    def self.root(args = {})
      Node.new(applications: {}, _mixins: {}).merge(args)
    end

    def self.mixin(args = {})
      Node.new({services: {}, _mixins: {}, volumes: {}, _variables: {}, networks: {}, _service_order: []}).merge(args)
    end

    def self.application(args = {})
      Node.new({services: {}, _mixins: {}, _mix:[], volumes: {}, _variables: {}, networks: {}, _service_order: []}).merge(args)
    end

    def self.all(args = {})
      Node.new(_mix:[], _variables: {}).merge(args)
    end

    def self.application_mixin(args = {})
      Node.new(_mix:[], _variables: {}).merge(args)
    end

    def self.service(args = {})
      Node.new(_mix:[], _variables: {}).merge(args)
    end

    def self.chart(args = {})
      Node.new(_mix:[], _variables: {}, _services: []).merge(args)
    end

  end
end
