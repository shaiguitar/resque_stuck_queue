# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'resque_stuck_queue/version'

Gem::Specification.new do |spec|
  spec.name          = "resque_stuck_queue"
  spec.version       = Resque::StuckQueue::VERSION
  spec.authors       = ["Shai Rosenfeld"]
  spec.email         = ["srosenfeld@engineyard.com"]
  spec.summary       = %q{fire a handler when your queues are wonky}
  spec.description   = %q{where the wild things are. err, when resque gets stuck}
  spec.homepage      = "https://github.com/shaiguitar/resque_stuck_queue/"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "redis-mutex" # TODO rm this

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "redis-namespace"
end
