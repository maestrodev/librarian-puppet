$:.push File.expand_path("../lib", __FILE__)

require 'librarian/puppet/version'

Gem::Specification.new do |s|
  s.name = 'librarian-puppet-maestrodev'
  s.version = Librarian::Puppet::VERSION
  s.platform = Gem::Platform::RUBY
  s.authors = ['Tim Sharpe']
  s.license = 'MIT'
  s.email = ['support@maestrodev.com']
  s.homepage = 'https://github.com/maestrodev/librarian-puppet'
  s.summary = 'Bundler for your Puppet modules'
  s.description = 'librarian-puppet-maestrodev gem is now deprecated in favor of librarian-puppet 0.9.11 and is no longer updated'

  s.files = [
    '.gitignore',
    'LICENSE',
    'README.md',
  ] + Dir['{bin,lib}/**/*']

  s.executables = ['librarian-puppet']

  s.add_dependency "librarian", ">=0.1.1"
  if RUBY_VERSION < '1.9'
    s.add_dependency "json"
    s.add_dependency "open3_backport"
  end

  s.add_development_dependency "rake"
  s.add_development_dependency "rspec"
  s.add_development_dependency "cucumber"
  s.add_development_dependency "aruba"
  s.add_development_dependency "puppet", ENV["PUPPET_VERSION"]
  s.add_development_dependency "minitest", "~> 5"
  s.add_development_dependency "mocha"
end
