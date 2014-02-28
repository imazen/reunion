require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs.push "lib"
  t.libs.push "test"
  t.pattern = "test/**/*.rb"
end

task :default => ['test']