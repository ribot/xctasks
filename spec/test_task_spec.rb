require 'spec_helper'
require 'xctasks/test_task'

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
  end
  
  describe 'simple task' do
    let!(:task) do
      XCTasks::TestTask.new do |t|
        t.workspace = 'LayerKit.xcworkspace'    
        t.schemes_dir = 'Tests/Schemes'    
        t.runner = :xcpretty
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
                               "/usr/bin/xcodebuild -workspace LayerKit.xcworkspace -scheme 'Unit Tests' -sdk iphonesimulator clean build test  | xcpretty -c ; exit ${PIPESTATUS[0]}"]
        end
      end
      
      describe 'spec:functional' do
        subject { Rake.application['test:functional'] }
        
        it "executes the appropriate commands" do
          subject.invoke
          @commands.should == ["mkdir -p LayerKit.xcworkspace/xcshareddata/xcschemes", 
                               "cp [] LayerKit.xcworkspace/xcshareddata/xcschemes", 
                               "/usr/bin/xcodebuild -workspace LayerKit.xcworkspace -scheme 'Functional Tests' -sdk iphonesimulator clean build test  | xcpretty -c ; exit ${PIPESTATUS[0]}"]
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
            
        t.subtask :functional do |t|
          t.runner = :xcodebuild
          t.scheme = 'Functional Tests'
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
          @commands.should == ["/usr/local/bin/xctool -workspace LayerKit.xcworkspace -scheme 'Unit Tests' -sdk iphonesimulator clean build test -freshSimulator -destination platform='iOS Simulator',OS=7.0,name='iPhone Retina (4-inch)' ", 
                               "/usr/local/bin/xctool -workspace LayerKit.xcworkspace -scheme 'Unit Tests' -sdk iphonesimulator clean build test -freshSimulator -destination platform='iOS Simulator',OS=7.1,name='iPhone Retina (4-inch)' "]
        end
      end
      
      describe 'test:functional' do
        subject { Rake.application['test:functional'] }
        
        it "executes the appropriate commands" do
          subject.invoke
          @commands.should == ["/usr/bin/xcodebuild -workspace LayerKit.xcworkspace -scheme 'Functional Tests' -sdk iphonesimulator clean build test "]
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
          s.destination = nil
        end
            
        t.subtask :functional do |t|
          t.runner = :xcodebuild
          t.scheme = 'Functional Tests'
          t.destination do |dst|
            # TODO: Fill this in
          end
        end
      end
    end
  end
  
  describe 'validations' do
    context "when an invalid runner is specified" do
      it "raises an expection" do
        expect do
          XCTasks::TestTask.new do |t|
            t.runner = 'phantomjs'
          end
        end.to raise_error(ArgumentError, "Must be :xcodebuild, :xctool or :xcpretty")
      end
    end
  end
end
