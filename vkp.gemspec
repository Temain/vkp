# Ensure we require the local version and not one we might have installed already
require File.join([File.dirname(__FILE__),'lib','vkp','version.rb'])
spec = Gem::Specification.new do |s| 
  s.name = 'vkp'
  s.version = Vkp::VERSION
  s.author = 'Your Name Here'
  s.email = 'your@email.address.com'
  s.homepage = 'http://your.website.com'
  s.platform = Gem::Platform::RUBY
  s.summary = 'A description of your project'
  s.files = `git ls-files`.split("
")
  s.require_paths << 'lib'
  s.has_rdoc = false
  s.extra_rdoc_files = ['README.rdoc','vkp.rdoc']
  s.rdoc_options << '--title' << 'vkp' << '--main' << 'README.rdoc' << '-ri'
  s.bindir = 'bin'
  s.executables << 'vkp'
  s.add_development_dependency('rake')
  s.add_development_dependency('rdoc')
  s.add_development_dependency('aruba')
  s.add_runtime_dependency('gli','2.9.0')
  s.add_runtime_dependency('nokogiri')
  s.add_runtime_dependency('httpclient')
  s.add_runtime_dependency('terminal-table')
  s.add_runtime_dependency('highline')  
end
