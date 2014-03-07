# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'xctasks/version'

Gem::Specification.new do |spec|
  spec.name          = "xctasks"
  spec.version       = XCTasks::VERSION
  spec.authors       = ["Blake Watters"]
  spec.email         = ["blakewatters@gmail.com"]
  spec.description   = %q{Simple project automation for the sophisticated Xcode hacker}
  spec.summary       = %q{Provides a rich library of automation tasks for Xcode}
  spec.homepage      = "http://github.com/layerhq/xctasks"
  spec.license       = "Apache 2"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  
  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 2.14.0"
  spec.add_development_dependency "simplecov", "~> 0.7.1"
  spec.add_development_dependency "debugger", "~> 1.6.2"
  spec.add_development_dependency "webmock", "~> 1.13.0"
  spec.add_development_dependency "excon", "~> 0.26.0"
  spec.add_development_dependency "tomdoc", "~> 0.2.5"
end
