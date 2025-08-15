# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'standalone_typograf/version'

Gem::Specification.new do |spec|
  spec.name          = 'standalone_typograf'
  spec.version       = StandaloneTypograf::VERSION
  spec.authors       = 'Alex Shilov'
  spec.email         = 'sashapashamasha@gmail.com'
  spec.description   = "Standalone (offline) client of the ArtLebedev's Studio Typograf service. http://typograf.herokuapp.com"
  spec.summary       = 'Very Fast&Simple Typograf fot the Russian text.'
  spec.homepage      = 'https://github.com/shlima/standalone_typograf'
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.3'
  spec.add_development_dependency 'pry-byebug'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'simplecov'

  spec.add_runtime_dependency 'activesupport'
end
