require 'spec_helper'
require 'xctasks/test_task'
require 'tempfile'

describe XCTasks::TestTask do
  before(:each) do
    @commands = []
    XCTasks::Command.stub(:run) do |command|
      @commands << command
    end
    FileUtils::Verbose.stub(:mkdir_p) do |path|
      @commands << "mkdir -p #{path}"
    end
    FileUtils::Verbose.stub(:cp) do |src, dst|
      @commands << "cp #{src} #{dst}"
    end

    Rake.application = rake

    Dir.mktmpdir.tap do |path|
      FileUtils.mkdir_p(path + '/LayerKit.xcworkspace/xcshareddata/xcschemes')
      FileUtils.mkdir_p(path + '/LayerKit.xcodeproj/xcshareddata/xcschemes')
      FileUtils.mkdir_p(path + '/Tests/Schemes')
      Dir.chdir(path)
    end
  end

  let(:rake) { Rake::Application.new }

  describe "test:prepare" do
    subject { Rake.application['test:prepare'] }

    context "when the given workspace does not exist" do
      let!(:task) do
        XCTasks::TestTask.new do |t|
          t.workspace = 'Invalid.xcworkspace'
          t.schemes_dir = 'Tests/Schemes'
          t.runner = :xcpretty
          t.subtasks = { unit: 'Unit Tests', functional: 'Functional Tests' }
        end
      end

      it "fails" do
        expect { subject.invoke }.to raise_error(RuntimeError, "No such workspace: Invalid.xcworkspace")
      end
    end

    context "when the given project does not exist" do
      let!(:task) do
        XCTasks::TestTask.new do |t|
          t.project = 'Invalid.xcodeproj'
          t.schemes_dir = 'Tests/Schemes'
          t.runner = :xcpretty
          t.subtasks = { unit: 'Unit Tests', functional: 'Functional Tests' }
        end
      end

      it "fails" do
        expect { subject.invoke }.to raise_error(RuntimeError, "No such project: Invalid.xcodeproj")
      end
    end

    context "when the given schemes_dir is nil" do
      let!(:task) do
        XCTasks::TestTask.new do |t|
          t.workspace = 'LayerKit.xcworkspace'
          t.schemes_dir = nil
          t.runner = :xcpretty
          t.subtasks = { unit: 'Unit Tests', functional: 'Functional Tests' }
        end
      end

      it "succeeds" do
        expect { subject.invoke }.not_to raise_error
      end
    end

    context "when the given schemes_dir does not exist" do
      let!(:task) do
        XCTasks::TestTask.new do |t|
          t.workspace = 'LayerKit.xcworkspace'
          t.schemes_dir = 'this/path/is/invalid'
          t.runner = :xcpretty
          t.subtasks = { unit: 'Unit Tests', functional: 'Functional Tests' }
        end
      end

      it "fails" do
        expect { subject.invoke }.to raise_error(RuntimeError, "Invalid schemes directory: this/path/is/invalid")
      end
    end
  end

  describe 'simple task with a project' do
    let!(:task) do
      XCTasks::TestTask.new do |t|
        t.project = 'LayerKit.xcodeproj'
        t.schemes_dir = 'Tests/Schemes'
        t.runner = :xcpretty
        t.redirect_stderr = true
        t.subtasks = { unit: 'Unit Tests' }
      end
    end

    it "configures the project" do
      task.project.should == 'LayerKit.xcodeproj'
    end

    describe 'tasks' do
      describe 'spec:unit' do
        subject { Rake.application['test:unit'] }

        it "executes the appropriate commands" do
          subject.invoke
          @commands.should == ["mkdir -p LayerKit.xcodeproj/xcshareddata/xcschemes",
                               "cp [] LayerKit.xcodeproj/xcshareddata/xcschemes",
                               "killall \"iPhone Simulator\"",
                               "/usr/bin/xcodebuild -project LayerKit.xcodeproj -scheme 'Unit Tests' -sdk iphonesimulator clean build test 2> /dev/null | xcpretty -c ; exit ${PIPESTATUS[0]}"]
        end
      end
    end
  end

  describe 'simple task with a workspace' do
    let!(:task) do
      XCTasks::TestTask.new do |t|
        t.workspace = 'LayerKit.xcworkspace'
        t.schemes_dir = 'Tests/Schemes'
        t.runner = :xcpretty
        t.redirect_stderr = true
        t.subtasks = { unit: 'Unit Tests', functional: 'Functional Tests' }
      end
    end

    it "configures the workspace" do
      task.workspace.should == 'LayerKit.xcworkspace'
    end

    it "configures the schemes dir" do
      task.schemes_dir.should == 'Tests/Schemes'
    end

    it "configures the runner" do
      task.runner.should == :xcpretty
    end

    it "configures the tasks" do
      expect(task.subtasks.count).to eq(2)
      task.subtasks.map { |t| t.name }.should == ["unit", "functional"]
    end

    it "configures xcpretty for all tasks" do
      task.subtasks.map { |t| t.runner }.should == [:xcpretty, :xcpretty]
    end

    describe 'tasks' do
      describe 'spec:unit' do
        subject { Rake.application['test:unit'] }

        it "executes the appropriate commands" do
          subject.invoke
          @commands.should == ["mkdir -p LayerKit.xcworkspace/xcshareddata/xcschemes",
                               "cp [] LayerKit.xcworkspace/xcshareddata/xcschemes",
                               "killall \"iPhone Simulator\"",
                               "/usr/bin/xcodebuild -workspace LayerKit.xcworkspace -scheme 'Unit Tests' -sdk iphonesimulator clean build test 2> /dev/null | xcpretty -c ; exit ${PIPESTATUS[0]}"]
        end
      end

      describe 'spec:functional' do
        subject { Rake.application['test:functional'] }

        it "executes the appropriate commands" do
          subject.invoke
          @commands.should == ["mkdir -p LayerKit.xcworkspace/xcshareddata/xcschemes",
                               "cp [] LayerKit.xcworkspace/xcshareddata/xcschemes",
                               "killall \"iPhone Simulator\"",
                               "/usr/bin/xcodebuild -workspace LayerKit.xcworkspace -scheme 'Functional Tests' -sdk iphonesimulator clean build test 2> /dev/null | xcpretty -c ; exit ${PIPESTATUS[0]}"]
        end
      end
    end
  end

  describe 'task with log' do
    let!(:task) do
      XCTasks::TestTask.new do |t|
        t.workspace = 'LayerKit.xcworkspace'
        t.schemes_dir = 'Tests/Schemes'
        t.runner = 'xcpretty -s'
        t.output_log = 'output.log'
        t.subtasks = { unit: 'Unit Tests', functional: 'Functional Tests' }
      end
    end

    describe 'tasks' do
      describe 'spec:unit' do
        subject { Rake.application['test:unit'] }

        it "executes the appropriate commands" do
          subject.invoke
          @commands.should == ["mkdir -p LayerKit.xcworkspace/xcshareddata/xcschemes",
                               "cp [] LayerKit.xcworkspace/xcshareddata/xcschemes",
                               "killall \"iPhone Simulator\"",
                               "/usr/bin/xcodebuild -workspace LayerKit.xcworkspace -scheme 'Unit Tests' -sdk iphonesimulator clean build test | tee -a output.log | xcpretty -s ; exit ${PIPESTATUS[0]}"]
        end
      end

      describe 'spec:functional' do
        subject { Rake.application['test:functional'] }

        it "executes the appropriate commands" do
          subject.invoke
          @commands.should == ["mkdir -p LayerKit.xcworkspace/xcshareddata/xcschemes",
                               "cp [] LayerKit.xcworkspace/xcshareddata/xcschemes",
                               "killall \"iPhone Simulator\"",
                               "/usr/bin/xcodebuild -workspace LayerKit.xcworkspace -scheme 'Functional Tests' -sdk iphonesimulator clean build test | tee -a output.log | xcpretty -s ; exit ${PIPESTATUS[0]}"]
        end
      end
    end
  end

  describe 'task with environment variables' do
    let!(:task) do
      XCTasks::TestTask.new do |t|
        t.workspace = 'LayerKit.xcworkspace'
        t.schemes_dir = 'Tests/Schemes'
        t.runner = 'xcpretty -s'
        t.output_log = 'output.log'
        t.env["LAYER_TEST_HOST"] = "10.66.0.35"
        t.subtasks = { unit: 'Unit Tests' }
      end
    end

    subject { Rake.application['test:unit'] }

    it "writes the environment variables into the scheme" do
      FileUtils.cp File.dirname(__FILE__) + '/Unit Tests.xcscheme', "LayerKit.xcworkspace/xcshareddata/xcschemes/"
      subject.invoke
      doc = Nokogiri::XML File.read("LayerKit.xcworkspace/xcshareddata/xcschemes/Unit Tests.xcscheme")
      node = doc.at('TestAction/EnvironmentVariables/EnvironmentVariable')
      expect(node).not_to be_nil
      attributes = node.attributes.inject({}) { |hash, pair| hash[pair[0]] = pair[1].to_s; hash }
      attributes.should == {"key"=>"LAYER_TEST_HOST", "value"=>"10.66.0.35", "isEnabled"=>"YES"}
    end
  end

  describe 'task with a project with environment variables' do
    let!(:task) do
      XCTasks::TestTask.new do |t|
        t.project = 'LayerKit.xcodeproj'
        t.schemes_dir = 'Tests/Schemes'
        t.runner = 'xcpretty -s'
        t.output_log = 'output.log'
        t.env["LAYER_TEST_HOST"] = "10.66.0.35"
        t.subtasks = { unit: 'Unit Tests' }
      end
    end

    subject { Rake.application['test:unit'] }

    it "writes the environment variables into the scheme" do
      FileUtils.cp File.dirname(__FILE__) + '/Unit Tests.xcscheme', "LayerKit.xcodeproj/xcshareddata/xcschemes/"
      subject.invoke
      doc = Nokogiri::XML File.read("LayerKit.xcodeproj/xcshareddata/xcschemes/Unit Tests.xcscheme")
      node = doc.at('TestAction/EnvironmentVariables/EnvironmentVariable')
      expect(node).not_to be_nil
      attributes = node.attributes.inject({}) { |hash, pair| hash[pair[0]] = pair[1].to_s; hash }
      attributes.should == {"key"=>"LAYER_TEST_HOST", "value"=>"10.66.0.35", "isEnabled"=>"YES"}
    end
  end

  describe 'simple xctool task with a reporter' do
    let!(:task) do
      XCTasks::TestTask.new do |t|
        t.workspace = 'LayerKit.xcworkspace'
        t.schemes_dir = 'Tests/Schemes'
        t.runner = 'xctool -reporter junit'
        t.subtasks = { unit: 'Unit Tests', functional: 'Functional Tests' }
      end
    end

    describe 'tasks' do
      describe 'spec:unit' do
        subject { Rake.application['test:unit'] }

        it "configures the runner" do
          subject.invoke
          @commands.should == ["mkdir -p LayerKit.xcworkspace/xcshareddata/xcschemes",
                               "cp [] LayerKit.xcworkspace/xcshareddata/xcschemes",
                               "killall \"iPhone Simulator\"",
                               "/usr/local/bin/xctool -reporter junit -workspace LayerKit.xcworkspace -scheme 'Unit Tests' -sdk iphonesimulator clean build test"]
        end
      end
    end
  end

  describe 'simple xctool task with multiple reporters' do
    let!(:task) do
      XCTasks::TestTask.new do |t|
        t.workspace = 'LayerKit.xcworkspace'
        t.schemes_dir = 'Tests/Schemes'
        t.runner = 'xctool -reporter junit -report pretty:pretty.txt'
        t.subtasks = { unit: 'Unit Tests', functional: 'Functional Tests' }
      end
    end

    describe 'tasks' do
      describe 'spec:unit' do
        subject { Rake.application['test:unit'] }

        it "configures the runner" do
          subject.invoke
          @commands.should == ["mkdir -p LayerKit.xcworkspace/xcshareddata/xcschemes",
                               "cp [] LayerKit.xcworkspace/xcshareddata/xcschemes",
                               "killall \"iPhone Simulator\"",
                               "/usr/local/bin/xctool -reporter junit -report pretty:pretty.txt -workspace LayerKit.xcworkspace -scheme 'Unit Tests' -sdk iphonesimulator clean build test"]
        end
      end
    end
  end

  describe 'advanced task' do
    let!(:task) do
      XCTasks::TestTask.new do |t|
        t.workspace = 'LayerKit.xcworkspace'
        t.runner = :xctool

        t.subtask(unit: 'Unit Tests') do |s|
          s.ios_versions = %w{7.0 7.1}
        end

        t.subtask :functional do |s|
          s.runner = :xcodebuild
          s.scheme = 'Functional Tests'
        end
      end
    end

    context "when the task overrides base options" do
      it "uses the original runner by default" do
        subtask = task.subtasks.detect { |t| t.name == 'unit' }
        subtask.runner.should == :xctool
      end

      it "respects the override" do
        subtask = task.subtasks.detect { |t| t.name == 'functional' }
        subtask.runner.should == :xcodebuild
      end
    end

    describe 'tasks' do
      describe 'test:unit' do
        subject { Rake.application['test:unit'] }

        it "executes the appropriate commands" do
          subject.invoke
          @commands.should == [
            "killall \"iPhone Simulator\"",
            "/usr/local/bin/xctool -workspace LayerKit.xcworkspace -scheme 'Unit Tests' -sdk iphonesimulator7.0 clean build test",
            "killall \"iPhone Simulator\"",
            "/usr/local/bin/xctool -workspace LayerKit.xcworkspace -scheme 'Unit Tests' -sdk iphonesimulator7.1 clean build test"
          ]
        end
      end

      describe 'test:functional' do
        subject { Rake.application['test:functional'] }

        it "executes the appropriate commands" do
          subject.invoke
          @commands.should == [
            "killall \"iPhone Simulator\"",
            "/usr/bin/xcodebuild -workspace LayerKit.xcworkspace -scheme 'Functional Tests' -sdk iphonesimulator clean build test"
          ]
        end
      end
    end
  end

  describe 'Destination Configuration' do
    let!(:task) do
      XCTasks::TestTask.new(:spec) do |t|
        t.workspace = 'LayerKit.xcworkspace'
        t.runner = :xctool

        t.subtask(unit: 'Unit Tests') do |s|
          s.ios_versions = %w{7.0 7.1}
        end

        t.subtask :functional do |s|
          s.runner = :xcodebuild
          s.scheme = 'Functional Tests'
          s.redirect_stderr = 'stderr.log'
          s.destination do |d|
            d.platform = :iossimulator
            d.name = 'iPad Retina'
            d.os = :latest
          end
          s.destination('platform=iOS Simulator,OS=7.1,name=iPhone Retina (4-inch)')
          s.destination platform: :ios, id: '437750527b43cff55a46f42ae86dbf870c7591b1'
        end
      end
    end

    describe 'spec:unit' do
      subject { Rake.application['spec:unit'] }

      it "executes the appropriate commands" do
        subject.invoke
        @commands.should == [
          "killall \"iPhone Simulator\"",
          "/usr/local/bin/xctool -workspace LayerKit.xcworkspace -scheme 'Unit Tests' -sdk iphonesimulator7.0 clean build test",
          "killall \"iPhone Simulator\"",
          "/usr/local/bin/xctool -workspace LayerKit.xcworkspace -scheme 'Unit Tests' -sdk iphonesimulator7.1 clean build test"
        ]
      end
    end

    describe 'spec:functional' do
      subject { Rake.application['spec:functional'] }

      it "executes the appropriate commands" do
        subject.invoke
        @commands.should == [
          "killall \"iPhone Simulator\"",
          "/usr/bin/xcodebuild -workspace LayerKit.xcworkspace -scheme 'Functional Tests' -sdk iphonesimulator -destination platform='iOS Simulator',name='iPad Retina',OS='latest' -destination platform\\=iOS\\ Simulator,OS\\=7.1,name\\=iPhone\\ Retina\\ \\(4-inch\\) -destination platform='iOS',id='437750527b43cff55a46f42ae86dbf870c7591b1' clean build test 2> stderr.log"]
      end
    end
  end

  describe 'SDK Configuration' do
    let!(:task) do
      XCTasks::TestTask.new(:spec) do |t|
        t.workspace = 'LayerKit.xcworkspace'
        t.runner = :xctool

        t.subtask(unit: 'Unit Tests') do |s|
          s.sdk = :macosx
        end
      end
    end

    subject { Rake.application['spec:unit'] }

    it "executes the appropriate commands" do
      subject.invoke
      @commands.should == ["/usr/local/bin/xctool -workspace LayerKit.xcworkspace -scheme 'Unit Tests' -sdk macosx clean build test"]
    end
  end

  describe 'validations' do
    it "raises an exception when an invalid value is assigned to the sdk" do
      expect do
        XCTasks::TestTask.new do |t|
          t.sdk = []
        end
      end.to raise_error(ArgumentError, "Can only assign sdk from a String or Symbol")
    end

    context "when an invalid runner is specified" do
      it "raises an exception" do
        expect do
          XCTasks::TestTask.new do |t|
            t.runner = 'phantomjs'
          end
        end.to raise_error(XCTasks::TestTask::ConfigurationError, "Must be :xcodebuild, :xctool or :xcpretty")
      end
    end

    context "when a workspace or project is not configured" do
      it "raises an exception" do
        expect do
          XCTasks::TestTask.new do |t|
            t.workspace = nil
            t.project = nil
          end
        end.to raise_error(XCTasks::TestTask::ConfigurationError, "A workspace or project must be configured")
      end
    end

    context "when an SDK of macosx and ios versions is specified" do
      it "raises an exception" do
        expect do
          XCTasks::TestTask.new do |t|
            t.workspace = 'Workspace.workspace'
            t.sdk = :macosx
            t.ios_versions = %w{7.0}
            t.subtasks = {unit: 'MyWorkspaceTests'}
          end
        end.to raise_error(XCTasks::TestTask::ConfigurationError, "Cannot specify iOS versions with an SDK of :macosx")
      end
    end
  end

  describe XCTasks::TestTask::Destination do
    let(:destination) { XCTasks::TestTask::Destination.new }

    describe '#platform=' do
      it "allows assignment of :osx" do
        destination.platform = :osx
        expect(destination.platform).to eq('OS X')
      end

      it "allows assignment of 'OS X'" do
        destination.platform = 'OS X'
        expect(destination.platform).to eq('OS X')
      end

      it "allows assignment of :ios" do
        destination.platform = :ios
        expect(destination.platform).to eq('iOS')
      end

      it "allows assignment of 'iOS'" do
        destination.platform = 'iOS'
        expect(destination.platform).to eq('iOS')
      end

      it "allows assignment of :iossimulator" do
        destination.platform = :iossimulator
        expect(destination.platform).to eq('iOS Simulator')
      end

      it "allows assignment of 'iOS Simulator'" do
        destination.platform = 'iOS Simulator'
        expect(destination.platform).to eq('iOS Simulator')
      end

      it "disallows other values" do
        expect { destination.platform = 'sdadsa' }.to raise_error(ArgumentError)
      end
    end

  end
end
