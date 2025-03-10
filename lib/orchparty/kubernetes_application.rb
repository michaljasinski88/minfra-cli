require 'erb'
require 'erubis'
require 'open3'
require 'ostruct'
require 'yaml'
require 'tempfile'
require 'active_support'
require 'active_support/core_ext'

module Orchparty
  module Services
    class Context
      include ::Minfra::Cli::Logging 

      attr_accessor :cluster_name
      attr_accessor :namespace
      attr_accessor :dir_path
      attr_accessor :app_config
      attr_accessor :options

      def initialize(cluster_name: , namespace:, file_path: , app_config:, out_io: STDOUT, app: )
        self.cluster_name = cluster_name
        self.namespace = namespace
        self.dir_path = file_path
        self.app_config = app_config
        @app = app
        @out_io = out_io
        self.options=options
      end

      def template(file_path, helm, flag: "-f ", fix_file_path: nil)
        return "" unless file_path
        puts "Rendering: #{file_path}"
        file_path = File.join(self.dir_path, file_path)
        if(file_path.end_with?(".erb"))
          helm.application = OpenStruct.new(cluster_name: cluster_name, namespace: namespace)
          template = Erubis::Eruby.new(File.read(file_path))
          template.filename = file_path
          yaml = template.result(helm.get_binding)
          file = Tempfile.new("kube-deploy.yaml")
          file.write(yaml)
          file.close
          file_path = file.path
        end
        "#{flag}#{fix_file_path || file_path}"
      end

      def print_install(helm)
        @out_io.puts "---"
        @out_io.puts install_cmd(helm, value_path(helm))
        @out_io.puts upgrade_cmd(helm, value_path(helm))
        @out_io.puts "---"
        @out_io.puts File.read(template(value_path(helm), helm, flag: "")) if value_path(helm)
      end

      # On 05.02.2021 we have decided that it would be best to print both commands.
      # This way it would be possible to debug both upgrade and install and also people would not see git diffs all the time.
      def print_upgrade(helm)
        print_install(helm)
      end

      def upgrade(helm)
        @out_io.puts system(upgrade_cmd(helm))
      end

      def install(helm)
        @out_io.puts system(install_cmd(helm))
      end
    end

    class Helm < Context
      def value_path(helm)
        helm[:values]
      end

      def upgrade_cmd(helm, fix_file_path = nil)
        "helm upgrade --namespace #{namespace} --kube-context #{cluster_name} --version #{helm.version} #{helm.name} #{helm.chart} #{template(value_path(helm), helm, fix_file_path: fix_file_path)}"
      end

      def install_cmd(helm, fix_file_path = nil)
        "helm install --create-namespace --namespace #{namespace} --kube-context #{cluster_name} --version #{helm.version} #{helm.name} #{helm.chart} #{template(value_path(helm), helm, fix_file_path: fix_file_path)}"
      end
    end

    class Apply < Context
      def value_path(apply)
        apply[:name]
      end

      def upgrade_cmd(apply, fix_file_path = nil)
        "kubectl apply --namespace #{namespace} --context #{cluster_name} #{template(value_path(apply), apply, fix_file_path: fix_file_path)}"
      end

      def install_cmd(apply, fix_file_path = nil)
        "kubectl apply --namespace #{namespace} --context #{cluster_name} #{template(value_path(apply), apply, fix_file_path: fix_file_path)}"
      end
    end

    class SecretGeneric < Context
      def value_path(secret)
        secret[:from_file]
      end

      def upgrade_cmd(secret, fix_file_path=nil)
        "kubectl --namespace #{namespace} --context #{cluster_name} create secret generic --dry-run -o yaml #{secret[:name]}  #{template(value_path(secret), secret, flag: "--from-file=", fix_file_path: fix_file_path)} | kubectl --context #{cluster_name} apply -f -"
      end

      def install_cmd(secret, fix_file_path=nil)
        "kubectl --namespace #{namespace} --context #{cluster_name} create secret generic --dry-run -o yaml #{secret[:name]}  #{template(value_path(secret), secret, flag: "--from-file=", fix_file_path: fix_file_path)} | kubectl --context #{cluster_name} apply -f -"
      end
    end

    class Label < Context
      def print_install(label)
        @out_io.puts "---"
        @out_io.puts install_cmd(label)
      end

      def print_upgrade(label)
        @out_io.puts "---"
        @out_io.puts upgrade_cmd(label)
      end

      def upgrade_cmd(label)
        "kubectl --namespace #{namespace} --context #{cluster_name} label --overwrite #{label[:resource]} #{label[:name]} #{label["value"]}"
      end

      def install_cmd(label)
        "kubectl --namespace #{namespace} --context #{cluster_name} label --overwrite #{label[:resource]} #{label[:name]} #{label["value"]}"
      end
    end

    class Wait < Context
      def print_install(wait)
        @out_io.puts "---"
        @out_io.puts wait.cmd
      end

      def print_upgrade(wait)
        @out_io.puts "---"
        @out_io.puts wait.cmd
      end

      def upgrade(wait)
        eval(wait.cmd)
      end

      def install(wait)
        eval(wait.cmd)
      end
    end

    class Chart < Context
      class CleanBinding
        def get_binding(params)
          params.instance_eval do
            binding
          end
        end
      end


      def print_install(chart)
        
        build_chart(chart) do |chart_path|
          cmd="helm template --namespace #{namespace} --kube-context #{cluster_name} #{chart.name} #{chart_path}"
          @out_io.puts `$cmd`
          if system("#{cmd} > /dev/null")
            info("helm template check: OK")
          else
            error("helm template check: FAIL")
          end  
        end
        
      end

      def print_upgrade(chart)
        print_install(chart)
      end

      def install(chart)
        info("Install: #{chart}")
        build_chart(chart) do |chart_path|
          @out_io.puts system("helm install --create-namespace --namespace #{namespace} --kube-context #{cluster_name} #{chart.name} #{chart_path}")
        end
      end

      def upgrade(chart)
        info("Upgrade: #{chart}")
        build_chart(chart) do |chart_path|
          @out_io.puts system("helm upgrade --namespace #{namespace} --kube-context #{cluster_name} #{chart.name} #{chart_path}")
        end
      end
      private
      
      def build_chart(chart)
        
        
        dir = @app.status_dir.join('helm') # duplication
        
        params = chart._services.map {|s| app_config.services[s.to_sym] }.map{|s| [s.name, s]}.to_h
        run(templates_path: File.expand_path(chart.template, self.dir_path), params: params, output_chart_path: dir, chart: chart)
        yield dir
      end



      # remember:
      # this is done for an app
      # that app can have multiple charts with multiple services!
      
      def run(templates_path:, params:, output_chart_path:, chart: )

        generate_chart_yaml(
          templates_path: templates_path,
          output_chart_path: output_chart_path,
          chart_name: chart.name,
        )
        
        File.open(File.join(output_chart_path, 'values.yaml'),'a') do |helm_values|
          params.each do |app_name, subparams|
            subparams[:chart] = chart
            used_vars=generate_documents_from_erbs(
              templates_path: templates_path,
              app_name: app_name,
              params: subparams,
              output_chart_path: output_chart_path
            )
            used_vars.each do |variable,value| 
              helm_values.puts "#{variable}: #{value}"
            end
          end
        end
        
      end

      def generate_documents_from_erbs(templates_path:, app_name:, params:, output_chart_path:)
        if params[:kind].nil?
          warn "ERROR: Could not generate service '#{app_name}'. Missing key: 'kind'."
          exit 1
        end

        kind = params.fetch(:kind)
        params._used_vars = {} #here we'll collect all used vars

        Dir[File.join(templates_path, kind, '*.erb')].each do |template_path|
          info("Rendering Template: #{template_path}")
          template_name = File.basename(template_path, '.erb')
          output_path = File.join(output_chart_path, 'templates', "#{app_name}-#{template_name}")
          
          template = Erubis::Eruby.new(File.read(template_path))
          template.filename = template_path

          params.app = @app
          params.app_name = app_name
          params.templates_path = templates_path
          begin
            document = template.result(CleanBinding.new.get_binding(params))
          rescue Exception
            error "#{template_path} has a problem: #{$!.inspect}"
            raise
          end
          File.write(output_path, document)
        end
        params._used_vars
      end

      def generate_chart_yaml(templates_path:, output_chart_path:, chart_name: )
        template_path = File.join(templates_path, 'Chart.yaml.erb')
        output_path = File.join(output_chart_path, 'Chart.yaml')

        template = Erubis::Eruby.new(File.read(template_path))
        template.filename = template_path
        params = Hashie::Mash.new(chart_name: chart_name)
        document = template.result(CleanBinding.new.get_binding(params))
        File.write(output_path, document)
      end
    end
  end
end

class KubernetesApplication
  include Minfra::Cli::Logging

  attr_accessor :cluster_name
  attr_accessor :file_path
  attr_accessor :namespace
  attr_accessor :app_config
  attr_reader :status_dir

  def initialize(app_config: [], namespace:, cluster_name:, file_name:, status_dir:, out_io: STDOUT)
    self.file_path = Pathname.new(file_name).parent.expand_path #path of the stack
    self.cluster_name = cluster_name
    self.namespace = namespace
    self.app_config = app_config
    @status_dir = status_dir
    @out_io= out_io
  end

  def install
    each_service(:install)
  end

  def upgrade
    each_service(:upgrade)
  end

  def print(method)
    each_service("print_#{method}".to_sym)
  end

  private
  def prepare
    output_chart_path = @status_dir.join('helm')
    output_chart_path.rmtree if File.exists?(output_chart_path)
    output_chart_path.mkpath
    templates_path = file_path.join('../../chart-templates').expand_path #don't ask. the whole concept of multiple charts in an app stinks...
    
    info("generating base helm structure from: #{output_chart_path} from #{templates_path}")
    system("mkdir -p #{File.join(output_chart_path, 'templates')}")

    system("cp #{File.join(templates_path, 'values.yaml')} #{File.join(output_chart_path, 'values.yaml')}")
    system("cp #{File.join(templates_path, '.helmignore')} #{File.join(output_chart_path, '.helmignore')}")
    system("cp #{File.join(templates_path, 'templates/_helpers.tpl')} #{File.join(output_chart_path, 'templates/_helpers.tpl')}")

  end
  
  def combine_charts(app_config)
    services = app_config._service_order.map(&:to_s)
    app_config._service_order.each do |name|
      current_service = app_config[:services][name]
      if current_service._type == "chart"
        current_service._services.each do |n|
          services.delete n.to_s
        end
      end
    end
    services
  end

  def each_service(method)
    prepare
    services = combine_charts(app_config)
    services.each do |name|
      service = app_config[:services][name]
      info "Service: #{name}(#{service._type}) #{method}"
      deployable_class="::Orchparty::Services::#{service._type.classify}".constantize
      deployable=deployable_class.new(cluster_name: cluster_name, 
                     namespace: namespace, 
                     file_path: file_path, 
                     app_config: app_config, 
                     out_io: @out_io, 
                     app: self)
                     
      deployable.send(method, service)
    end
  end
end
