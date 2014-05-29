XCTasks
=======

**Simple project automation for the sophisticated Xcode hacker**

XCTasks provides a library of primitives and [Rake](http://rake.rubyforge.org/) tasks to 
simplify automation tasks that are faced by Cocoa developers. Xcode is a great UI for code editing & debugging, but a poor solution for all the other little things that make up day to day development activities. For testing, documentation, and build automation the command line still reigns supreme. The Cocoa community has done a fantastic job in providing simple, focused tools such as [xctool](https://github.com/facebook/xctool), [appledoc](http://gentlebytes.com/appledoc/), and [mogenerator](http://rentzsch.github.io/mogenerator/) to fill in gaps in the workflow, but each tool must then be scripted and integrated into the project. This has led to a world in which every Cocoa project has its own library of hastily written (or copied from Stack Overflow) automation scripts. XCTasks aims to fill in the gap by providing a library of simple, reusable tasks for automating your Xcode development workflow.

XCTasks is built in [Ruby](http://www.ruby-lang.org/en/) (like [CococaPods](http://cocoapods.org/)) and is designed to integrate neatly with the [Rake](http://rake.rubyforge.org/) build system. It is distributed as a [RubyGem](http://docs.rubygems.org/) and is released under the terms of the Apache 2 Open Source license.

## Features

### Test Automation

XCTasks provides an interface for executing Xcode tests in a few ways using a unified interface:

```ruby
require 'xctasks/test_task'
XCTasks::TestTask.new(test: 'server:autostart') do |t|
  t.workspace = 'LayerKit.xcworkspace'  
  t.schemes_dir = 'Tests/Schemes' # Location where you store your shared schemes, will copy into workspace
  t.runner = :xctool # or :xcodebuild/:xcpretty. Can also pass options as string, i.e. 'xcpretty -s'
  t.output_log = 'output.log' # Save the build log to a file. Export as Jenkins build artifact for CI build auditing
  
  t.subtask(unit: 'LayerKit Tests') do |s|
    s.ios_versions = %w{7.0 7.1}
  end
  t.schemes = { unit: 'LayerKit Tests' }    
end
```

This will synthesize one task for each Scheme and one task for each version of iOS under test:

```bash
$ rake -T

rake init           # Initialize the project for development and testing
rake test           # Run the unit tests
rake test:unit      # Run unit tests against iOS Simulator 6.0, 7.0
rake test:unit:6.0  # Run unit tests against iOS Simulator 6.0
rake test:unit:7.0  # Run unit tests against iOS Simulator 7.0
```

#### Kiwi on iOS and OS X Example

The following example is taken from [TransitionKit](http://github.com/blakewatters/TransitionKit) and executes a
[Kiwi](https://github.com/allending/Kiwi) test suite on OS X and iOS.

```ruby
require 'xctasks/test_task'

XCTasks::TestTask.new(:spec) do |t|
  t.workspace = 'TransitionKit.xcworkspace'
  t.schemes_dir = 'Specs/Schemes'
  t.runner = :xcpretty
  t.actions = %w{clean test}
  
  t.subtask(ios: 'iOS Specs') do |s|
    s.sdk = :iphonesimulator
  end
  
  t.subtask(osx: 'OS X Specs') do |s|
    s.sdk = :macosx
  end
end
```

#### Running Tests on Multiple Destinations

XCTasks supports a flexible syntax for specifying multiple destinations for your tests to execute on:

```ruby
XCTasks::TestTask.new(:spec) do |t|
  t.workspace = 'LayerKit.xcworkspace'
  t.runner = :xctool

  t.subtask :functional do |s|
    s.runner = :xcodebuild
    s.scheme = 'Functional Tests'
	
	# Run on iOS Simulator, iPad, latest iOS
    s.destination do |d|
      d.platform = :iossimulator
      d.name = 'iPad'
      d.os = :latest
    end
	
	# Specify a complete destination as a string
    s.destination('platform=iOS Simulator,OS=7.1,name=iPhone Retina (4-inch)')
	
	# Quickly specify a physical device destination
    s.destination platform: :ios, id: '437750527b43cff55a46f42ae86dbf870c7591b1'
  end
end
```

## Credits

Blake Watters

- http://github.com/blakewatters
- http://twitter.com/blakewatters
- blakewatters@gmail.com

## License

XCTasks is available under the Apache 2 License. See the LICENSE file for more info.
