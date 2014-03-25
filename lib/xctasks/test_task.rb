require 'rake'
require 'rake/tasklib'

module XCTasks
  module Command
    def run(command)
      puts "Executing `#{command}`"
      system(command)
    end
    module_function :run
  end
  
  class TestReport
    include Singleton
    
    def initialize
      @subtask_results = {}
      @success = true
      
      at_exit do
        exit(-1) if failure?
      end
    end
    
    def add_result(subtask, options, success)
      @subtask_results[subtask] ||= {}
      @subtask_results[subtask][options] = success
      @success = false unless success
    end
    
    def [](ios_version)
      @namespaces[ios_version]
    end
    
    def success?
      @success
    end
    
    def failure?
      @success == false
    end
    
    def report
      @subtask_results.each do |subtask, options_results|
        options_results.each do |options, success|
          puts "\033[0;31m!! #{subtask.name} tests failed with options #{options}" unless success
        end
      end
      puts "\033[0;32m** All tests executed successfully" if success?
    end
  end
  
  class TestTask < Rake::TaskLib
    class Destination
      attr_accessor :platform, :name
      
      def initialize
        @platform = 'iOS Simulator'
        @name = 'iPhone Retina (4-inch)'
      end
      
      def to_arg(os_version)
        "platform='#{platform}',OS=#{os_version},name='#{name}'"
      end
    end
    
    class Config
      SETTINGS = [:workspace, :schemes_dir, :runner, :xctool_path, 
                  :xcodebuild_path, :settings, :destination, :actions]
      
      # Configures delegations to pass through configuration accessor when extended
      module Delegations
        def self.extended(base)
          base.extend Forwardable
          accessors = SETTINGS.map { |attr| [attr, "#{attr}=".to_sym] }.flatten
          base.def_delegators :@config, *accessors
        end        
      end
      attr_accessor *SETTINGS
      
      def initialize
        @schemes_dir = nil
        @xctool_path = '/usr/local/bin/xctool'
        @xcodebuild_path = '/usr/bin/xcodebuild'
        @runner = :xcodebuild
        @settings = {}
        @platform = 'iOS Simulator'
        @destination = Destination.new
        @actions = %w{clean build test}
      end
      
      def runner=(runner)
        raise ArgumentError, "Must be :xcodebuild, :xctool or :xcpretty" unless %w{xctool xcodebuild xcpretty}.include?(runner.to_s)
        @runner = runner.to_sym
      end
      
      def destination
        yield @destination if block_given?
        @destination
      end
    end
    
    class Subtask
      extend Config::Delegations
      include ::Rake::DSL if defined?(::Rake::DSL)
      
      attr_reader :name
      attr_accessor :scheme, :ios_versions
      
      def initialize(name_options, config)
        self.name = name_options.kind_of?(Hash) ? name_options.keys.first : name_options.to_s
        @scheme = name_options.values.first if name_options.kind_of?(Hash)
        @config = config.dup
        @ios_versions = []
      end
      
      def name=(name)
        @name = name.to_s
      end            
      
      def define_rake_tasks
        if namespaced?
          namespace(name) do
            ios_versions.each do |ios_version|
              desc "Run #{name} tests against iOS Simulator #{ios_version} SDK"
              task ios_version => :prepare do
                run_tests(ios_version: ios_version)
              end
            end
          end
          
          desc "Run #{name} tests against iOS Simulator #{ios_versions.join(', ')}"
          task name => ios_versions.map { |ios_version| "#{name}:#{ios_version}" }
        else
          desc "Run #{name} tests"
          task self.name => :prepare do
            run_tests
          end
        end
      end
      
      private
      
      def namespaced?
        ios_versions.any?
      end
    
      def run_tests(options = {})
        system(%q{killall "iPhone Simulator"})
        ios_version = options[:ios_version]
      
        settings_arg = " " << settings.map { |k,v| "#{k}=#{v}"}.join(' ')
        destination_arg = " -destination " << destination.to_arg(ios_version) if destination && ios_version
        actions_arg = actions.join(' ')
        success = if xctool?
          Command.run("#{xctool_path} -workspace #{workspace} -scheme '#{scheme}' -sdk iphonesimulator#{ios_version} #{actions_arg} -freshSimulator#{destination_arg}#{settings_arg}")
        elsif xcodebuild?
          Command.run("#{xcodebuild_path} -workspace #{workspace} -scheme '#{scheme}' -sdk iphonesimulator#{ios_version} #{actions_arg}#{destination_arg}#{settings_arg}")
        elsif xcpretty?
          Command.run("#{xcodebuild_path} -workspace #{workspace} -scheme '#{scheme}' -sdk iphonesimulator#{ios_version} #{actions_arg}#{destination_arg}#{settings_arg} | xcpretty -c ; exit ${PIPESTATUS[0]}")
        end
        
        XCTasks::TestReport.instance.add_result(self, options, success)
      end
    
      def xctool?
        runner == :xctool
      end

      def xcodebuild?
        runner == :xcodebuild
      end
    
      def xcpretty?
        runner == :xcpretty
      end
    end
    
    include ::Rake::DSL if defined?(::Rake::DSL)
    
    attr_reader :namespace_name, :prepare_dependency, :config, :subtasks
    extend Config::Delegations
    
    def initialize(namespace_name = :test)
      @namespace_name = namespace_name
      @config = Config.new
      @subtasks = []
      @namespace_name = namespace_name.kind_of?(Hash) ? namespace_name.keys.first : namespace_name
      @prepare_dependency = namespace_name.kind_of?(Hash) ? namespace_name.values.first : nil      
      
      yield self if block_given?
      raise "A workspace must be configured" unless workspace
      raise "At least one subtask must be configured" if subtasks.empty?
      define_rake_tasks
    end
    
    def subtasks=(subtasks)
      if subtasks.kind_of?(Hash)
        subtasks.each { |name, scheme| subtask(name => scheme) }
      else
        raise ArgumentError, "Cannot assign subtasks from a #{subtasks.class}"
      end
    end
    
    def subtask(name_options)
      subtask = Subtask.new(name_options, config)
      yield subtask if block_given?
      @subtasks << subtask
    end
    
    def define_rake_tasks
      namespace self.namespace_name do
        task (prepare_dependency ? { prepare: prepare_dependency} : :prepare ) do
          if schemes_dir
            FileUtils::Verbose.mkdir_p "#{workspace}/xcshareddata/xcschemes"
            FileUtils::Verbose.cp Dir.glob("#{schemes_dir}/*.xcscheme"), "#{workspace}/xcshareddata/xcschemes"
          end
        end
        
        subtasks.each { |subtask| subtask.define_rake_tasks }
        # 
        # # Iterate across the schemes and define a task for each version of iOS and an aggregate task
        # # schemes.each do |scheme_namespace, scheme_name|
        # #   namespace scheme_namespace do
        # #     ios_versions.each do |ios_version|
        # #       desc "Run #{scheme_namespace} tests against iOS Simulator #{ios_version} SDK"
        # #       task ios_version => :prepare do
        # #         test_scheme(scheme_name, namespace: scheme_namespace, ios_version: ios_version)
        # #       end
        # #     end
        # #   end
        #   
        #   desc "Run #{scheme_namespace} tests against iOS Simulator #{ios_versions.join(', ')}"
        #   task scheme_namespace => ios_versions.map { |ios_version| "#{scheme_namespace}:#{ios_version}" }
      end
      
      subtask_names = subtasks.map { |subtask| subtask.name }
      desc "Run all tests (#{subtask_names.join(', ')})"
      task namespace_name => subtask_names.map { |subtask_name| "#{namespace_name}:#{subtask_name}" } do
        XCTasks::TestReport.instance.report
      end
    end
  end
end
