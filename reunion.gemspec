# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)


Gem::Specification.new do |s|
  s.name        = "reunion"
  s.version     = '0.0.1'
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Nathanael Jones"]
  s.email       = ["nathanael.jones@gmail.com"]
  s.homepage    = "http://github.com/nathanaeljones/reunion"
  s.summary     = %q{Evidenced-based, repeatable accounting library and webapp}
  s.description = <<-EOF
Reunion takes your exported, overlapping, transaction records (.ofx, .qfx, .csv, .txt, etc) and merges them into a single, normalized file per account.
It then detects transfers and provides a DSL for rule-based accounting. 
EOF

  s.rubyforge_project = "reunion"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]


  s.add_dependency('tilt')
  s.add_dependency('nokogiri')
  s.add_dependency('sinatra', '>= 1.3.3')

  
  # Test libraries
  s.add_development_dependency('minitest')
  s.add_development_dependency('rack-test')
end
