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
  t.ios_versions = %w{6.0 7.0}
  t.schemes = { unit: 'LayerKit Tests' }
  t.schemes_dir = 'Tests/Schemes' # Location where you store your shared schemes, will copy into workspace
  t.runner = :xctool # or :xcodebuild/:xcpretty
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

## Credits

Blake Watters

- http://github.com/blakewatters
- http://twitter.com/blakewatters
- blakewatters@gmail.com

## License

XCTasks is available under the Apache 2 License. See the LICENSE file for more info.
