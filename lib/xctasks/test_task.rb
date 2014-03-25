require 'rake'
require 'rake/tasklib'

module XCTasks
  module Command
    def run(command, echo = true)
      puts "Executing `#{command}`" if echo
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
    
    class ConfigurationError < RuntimeError; end    
    class Configuration
      SETTINGS = [:workspace, :schemes_dir, :sdk, :runner, :xctool_path, 
                  :xcodebuild_path, :settings, :destination, :actions,
                  :scheme, :ios_versions]
      
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
        @sdk = :iphonesimulator
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
        raise ConfigurationError, "Must be :xcodebuild, :xctool or :xcpretty" unless %w{xctool xcodebuild xcpretty}.include?(runner.to_s)
        @runner = runner.to_sym
      end
      
      def sdk=(sdk)
        raise ArgumentError, "Can only assign sdk from a String or Symbol" unless sdk.kind_of?(String) || sdk.kind_of?(Symbol)
        @sdk = sdk.to_sym
      end
      
      def destination
        yield @destination if block_given?
        @destination
      end
      
      def validate!
        raise ConfigurationError, "Cannot specify iOS versions with an SDK of :macosx" if sdk == :macosx && ios_versions
      end
    end
    
    class Subtask
      extend Configuration::Delegations
      include ::Rake::DSL if defined?(::Rake::DSL)
      
      attr_reader :name, :config
      
      def initialize(name_options, config)
        @config = config.dup
        self.name = name_options.kind_of?(Hash) ? name_options.keys.first : name_options.to_s
        self.scheme = name_options.values.first if name_options.kind_of?(Hash)        
      end
      
      def name=(name)
        @name = name.to_s
      end
      
      def define_rake_tasks
        @config.validate!
        
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
        ios_versions && ios_versions.any?
      end            
    
      def run_tests(options = {})        
        ios_version = options[:ios_version]
        XCTasks::Command.run(%q{killall "iPhone Simulator"}, false) if sdk == :iphonesimulator
      
        settings_arg = " " << settings.map { |k,v| "#{k}=#{v}"}.join(' ')
        destination_arg = " -destination " << destination.to_arg(ios_version) if destination && ios_version
        actions_arg = actions.join(' ')
        success = if xctool?
          actions_arg << " -freshSimulator" if ios_version
          Command.run("#{xctool_path} -workspace #{workspace} -scheme '#{scheme}' -sdk #{sdk}#{ios_version} #{actions_arg}#{destination_arg}#{settings_arg}".strip)
        elsif xcodebuild?
          Command.run("#{xcodebuild_path} -workspace #{workspace} -scheme '#{scheme}' -sdk #{sdk}#{ios_version} #{actions_arg}#{destination_arg}#{settings_arg}".strip)
        elsif xcpretty?
          Command.run("#{xcodebuild_path} -workspace #{workspace} -scheme '#{scheme}' -sdk #{sdk}#{ios_version} #{actions_arg}#{destination_arg}#{settings_arg} | xcpretty -c ; exit ${PIPESTATUS[0]}".strip)
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
    extend Configuration::Delegations
    
    def initialize(namespace_name = :test)
      @namespace_name = namespace_name
      @config = Configuration.new
      @subtasks = []
      @namespace_name = namespace_name.kind_of?(Hash) ? namespace_name.keys.first : namespace_name
      @prepare_dependency = namespace_name.kind_of?(Hash) ? namespace_name.values.first : nil      
      
      yield self if block_given?
      raise ConfigurationError, "A workspace must be configured" unless workspace
      raise ConfigurationError, "At least one subtask must be configured" if subtasks.empty?
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
      end
      
      subtask_names = subtasks.map { |subtask| subtask.name }
      desc "Run all tests (#{subtask_names.join(', ')})"
      task namespace_name => subtask_names.map { |subtask_name| "#{namespace_name}:#{subtask_name}" } do
        XCTasks::TestReport.instance.report
      end
    end
  end
end
