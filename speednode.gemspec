require './lib/speednode/version'

Gem::Specification.new do |s|
  s.name          = 'speednode'
  s.version       = Speednode::VERSION
  s.author        = 'Jan Biedermann'
  s.email         = 'jan@kursator.de'
  s.license       = 'MIT'
  s.summary       = 'A fast ExecJS runtime based on nodejs.'
  s.description   = 'A fast ExecJS runtime based on nodejs. As fast as mini_racer, but without the need to compile the js engine, because it uses the system provided nodejs.'
  s.homepage      = 'https://github.com/janbiedermann/speednode'
  s.files         = `git ls-files -- lib LICENSE README.md`.split("\n")
  s.require_paths = ['lib']

  s.add_dependency 'execjs', '~> 2.9.1'
  s.add_dependency 'oj', '>= 3.13.23', '< 3.17.0'
  s.add_dependency 'win32-pipe', '~> 0.4.0'
  s.add_development_dependency 'bundler'
  s.add_development_dependency 'minitest', '~> 5.22.0'
  s.add_development_dependency 'rake', '~> 13.2.0'
  s.add_development_dependency 'uglifier'
  s.required_ruby_version = '>= 3.1.0'
end
