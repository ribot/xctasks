require 'rake'
require 'rake/tasklib'
require 'forwardable'
require 'nokogiri'

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
          puts "\033[0;31m!! #{subtask.name} tests failed with options #{options}\033[0m" unless success
        end
      end
      puts "\033[0;32m** All tests executed successfully\033[0m" if success?
    end
  end

  class TestTask < Rake::TaskLib
    class Destination
      # Common Keys
      attr_accessor :platform, :name

      # OS X attributes
      attr_accessor :arch

      # iOS keys
      attr_accessor :id

      # iOS Simulator keys
      attr_accessor :os

      def initialize(options = {})
        options.each { |k,v| self[k] = v }
      end

      def platform=(platform)
        valid_platforms = {osx: 'OS X', ios: 'iOS', iossimulator: 'iOS Simulator'}
        raise ArgumentError, "Platform must be one of :osx, :ios, or :iossimulator" if platform.kind_of?(Symbol) && !valid_platforms.keys.include?(platform)
        raise ArgumentError, "Platform must be one of 'OS X', 'iOS', or 'iOS Simulator'" if platform.kind_of?(String) && !valid_platforms.values.include?(platform)
        @platform = platform.kind_of?(Symbol) ? valid_platforms[platform] : platform
      end

      def [](key)
        send(key)
      end

      def []=(key, value)
        send("#{key}=", value)
      end

      def to_s
        keys = [:platform, :name, :arch, :id, :os].reject { |k| self[k].nil? }
        keys.map { |k| "#{key_name(k)}='#{self[k].to_s}'" }.join(',')
      end

      private
      def key_name(attr)
        attr == :os ? 'OS' : attr.to_s
      end
    end

    class ConfigurationError < RuntimeError; end
    class Configuration
      SETTINGS = [:workspace, :schemes_dir, :sdk, :runner, :xctool_path,
                  :xcodebuild_path, :settings, :destinations, :actions,
                  :scheme, :ios_versions, :output_log, :env]
      HELPERS = [:destination, :xctool?, :xcpretty?, :xcodebuild?]

      # Configures delegations to pass through configuration accessor when extended
      module Delegations
        def self.extended(base)
          base.extend Forwardable
          accessors = SETTINGS.map { |attr| [attr, "#{attr}=".to_sym] }.flatten
          base.def_delegators :@config, *accessors
          base.def_delegators :@config, *HELPERS
        end
      end
      attr_accessor(*SETTINGS)

      def initialize
        @sdk = :iphonesimulator
        @schemes_dir = nil
        @xctool_path = '/usr/local/bin/xctool'
        @xcodebuild_path = '/usr/bin/xcodebuild'
        @runner = :xcodebuild
        @settings = {}
        @platform = 'iOS Simulator'
        @destinations = []
        @actions = %w{clean build test}
        @env = {}
      end

      def runner=(runner)
        runner_bin = runner.to_s.split(' ')[0]
        raise ConfigurationError, "Must be :xcodebuild, :xctool or :xcpretty" unless %w{xctool xcodebuild xcpretty}.include?(runner_bin)
        @runner = runner
      end

      def sdk=(sdk)
        raise ArgumentError, "Can only assign sdk from a String or Symbol" unless sdk.kind_of?(String) || sdk.kind_of?(Symbol)
        @sdk = sdk.to_sym
      end

      def destination(specifier = {})
        if specifier.kind_of?(String)
          raise ArgumentError, "Cannot configure a destination via a block when a complete String specifier is provided" if block_given?
          @destinations << specifier.shellescape
        elsif specifier.kind_of?(Hash)
          destination = Destination.new(specifier)
          yield destination if block_given?
          @destinations << destination
        else
          raise ArgumentError, "Cannot configure a destination with a #{specifier}"
        end
      end

      def validate!
        raise ConfigurationError, "Cannot specify iOS versions with an SDK of :macosx" if sdk == :macosx && ios_versions
      end

      def xctool?
        runner =~ /^xctool/
      end

      def xcodebuild?
        runner =~ /^xcodebuild/
      end

      def xcpretty?
        runner =~ /^xcpretty/
      end

      # Deep copy any nested structures
      def dup
        copy = super
        copy.settings = settings.dup
        copy.destinations = destinations.dup
        return copy
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

      def prepare
        write_environment_variables_to_scheme
      end

      private

      def namespaced?
        ios_versions && ios_versions.any?
      end

      def run_tests(options = {})
        ios_version = options[:ios_version]
        XCTasks::Command.run(%q{killall "iPhone Simulator"}, false) if sdk == :iphonesimulator

        output_log_command = output_log ? " | tee -a #{output_log} " : ' '
        success = if xctool?
          actions_arg << " -freshSimulator" if ios_version
          Command.run("#{xctool_path} -workspace #{workspace} -scheme '#{scheme}' -sdk #{sdk}#{ios_version}#{destination_arg}#{actions_arg}#{settings_arg}#{output_log_command}".strip)
        elsif xcodebuild?
          Command.run("#{xcodebuild_path} -workspace #{workspace} -scheme '#{scheme}' -sdk #{sdk}#{ios_version}#{destination_arg}#{actions_arg}#{settings_arg}#{output_log_command}".strip)
        elsif xcpretty?
          xcpretty_bin = runner.is_a?(String) ? runner : "xcpretty -c"
          Command.run("#{xcodebuild_path} -workspace #{workspace} -scheme '#{scheme}' -sdk #{sdk}#{ios_version}#{destination_arg}#{actions_arg}#{settings_arg}#{output_log_command}| #{xcpretty_bin} ; exit ${PIPESTATUS[0]}".strip)
        end

        XCTasks::TestReport.instance.add_result(self, options, success)
      end

      def settings_arg
        if settings.any?
          " " << settings.map { |k,v| "#{k}=#{v}"}.join(' ')
        else
          nil
        end
      end

      def actions_arg
        " " << actions.join(' ')
      end

      def destination_arg
        if destinations.any?
          " " << destinations.map { |d| "-destination #{d}" }.join(' ')
        else
          nil
        end
      end

      def write_environment_variables_to_scheme
        if env.any?
          path = "#{workspace}/xcshareddata/xcschemes/#{scheme}.xcscheme"
          doc = Nokogiri::XML(File.read(path))
          testable_node = doc.at('TestAction')
          env_variables_node = Nokogiri::XML::Node.new "EnvironmentVariables", doc
          env.each do |key, value|
            node = Nokogiri::XML::Node.new "EnvironmentVariable", doc
            node.set_attribute "key", key
            node.set_attribute "value", value
            node.set_attribute "isEnabled", "YES"
            env_variables_node << node
          end
          testable_node << env_variables_node
          File.open(path, 'w') { |f| f << doc.to_s }
        end
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
          fail "No such workspace: #{workspace}" unless File.exists?(workspace)
          fail "Invalid schemes directory: #{schemes_dir}" unless schemes_dir.nil? || File.exists?(schemes_dir)
          File.truncate(output_log, 0) if output_log && File.exists?(output_log)
          if schemes_dir
            FileUtils::Verbose.mkdir_p "#{workspace}/xcshareddata/xcschemes"
            FileUtils::Verbose.cp Dir.glob("#{schemes_dir}/*.xcscheme"), "#{workspace}/xcshareddata/xcschemes"
          end
          subtasks.each { |subtask| subtask.prepare }
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
