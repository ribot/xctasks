require 'rake'
require 'rake/tasklib'

module XCTasks
  class TestReport
    include Singleton
    
    def initialize
      @namespaces = {}
      @success = true
      
      at_exit do
        exit(-1) if failure?
      end
    end
    
    def add_result(namespace, ios_version, success)
      @namespaces[namespace] ||= {}
      @namespaces[namespace][ios_version] = success
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
      @namespaces.each do |namespace, version_status|
        version_status.each do |ios_version, success|
          puts "\033[0;31m!! #{namespace} tests failed under iOS #{ios_version}" unless success
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
    
    include ::Rake::DSL if defined?(::Rake::DSL)
    
    attr_reader :namespace_name, :prepare_dependency
    attr_accessor :workspace, :schemes_dir, :schemes, :ios_versions
    attr_accessor :runner, :xctool_path, :xcodebuild_path
    attr_accessor :ios_versions, :destination, :settings, :actions
    
    def initialize(namespace_name = :test)
      @namespace_name = namespace_name.is_a?(Hash) ? namespace_name.keys.first : namespace_name
      @prepare_dependency = namespace_name.is_a?(Hash) ? namespace_name.values.first : nil
      @schemes_dir = nil
      @ios_versions = %w{7.0}
      @xctool_path = '/usr/local/bin/xctool'
      @xcodebuild_path = '/usr/bin/xcodebuild'
      @runner = :xcodebuild
      @destination = "platform='iOS Simulator',name='iPhone Retina (4-inch)'"
      @settings = {}
      @platform = 'iOS Simulator'
      @destination = Destination.new
      @actions = %w{clean build test}
      
      yield self if block_given?
      raise "A workspace must be configured" unless workspace
      raise "At least one scheme must be configured" unless schemes
      define_tasks
    end
    
    def runner=(runner)
      raise ArgumentError, "Must be :xcodebuild, :xctool or :xcpretty" unless %w{xctool xcodebuild xcpretty}.include?(runner.to_s)
      @runner = runner.to_sym
    end
    
    def destination
      yield @destination if block_given?
      @destination
    end
    
    def define_tasks
      namespace self.namespace_name do
        task (prepare_dependency ? { prepare: prepare_dependency} : :prepare ) do
          if schemes_dir
            FileUtils::Verbose.mkdir_p "#{workspace}/xcshareddata/xcschemes"
            FileUtils::Verbose.cp Dir.glob("#{schemes_dir}/*.xcscheme"), "#{workspace}/xcshareddata/xcschemes"
          end
        end
        
        # Iterate across the schemes and define a task for each version of iOS and an aggregate task
        schemes.each do |scheme_namespace, scheme_name|
          namespace scheme_namespace do
            ios_versions.each do |ios_version|
              desc "Run #{scheme_namespace} tests against iOS Simulator #{ios_version} SDK"
              task ios_version => :prepare do
                test_scheme(scheme_name, namespace: scheme_namespace, ios_version: ios_version)
              end
            end                        
          end
          
          desc "Run #{scheme_namespace} tests against iOS Simulator #{ios_versions.join(', ')}"
          task scheme_namespace => ios_versions.map { |ios_version| "#{scheme_namespace}:#{ios_version}" }
        end                
      end
      
      desc "Run the #{schemes.keys.join(', ')} tests"
      task namespace_name => schemes.keys.map { |scheme| "#{namespace_name}:#{scheme}" } do
        XCTasks::TestReport.instance.report
      end
    end
    
  private
    def run(command)
      puts "Executing `#{command}`"
      system(command)
    end
    
    def test_scheme(scheme, options)
      system(%q{killall "iPhone Simulator"})
      namespace = options[:namespace]
      ios_version = options[:ios_version]
      test_sdk = "#{ios_version}"      
      
      settings_arg = settings.map { |k,v| "#{k}=#{v}"}.join(' ')
      destination_arg = destination.to_arg(ios_version)
      actions_arg = actions.join(' ')
      success = if xctool?
        run("#{xctool_path} -workspace #{workspace} -scheme '#{scheme}' -sdk iphonesimulator #{actions_arg} -freshSimulator -destination #{destination_arg} #{settings_arg}")
      elsif xcodebuild?
        run("#{xcodebuild_path} -workspace #{workspace} -scheme '#{scheme}' -sdk iphonesimulator #{actions_arg} -destination #{destination_arg} #{settings_arg}")
      elsif xcpretty?
        run("#{xcodebuild_path} -workspace #{workspace} -scheme '#{scheme}' -sdk iphonesimulator #{actions_arg} -destination #{destination_arg} #{settings_arg} | xcpretty -c ; exit ${PIPESTATUS[0]}")
      end      
      XCTasks::TestReport.instance.add_result(namespace, ios_version, success)
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
end
