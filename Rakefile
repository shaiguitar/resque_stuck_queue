
task :default => 'resque:setup'

require 'resque/tasks'

task :'resque:setup' do
  # https://github.com/resque/resque/issues/773
  # have the jobs loaded in memory
  Dir["./test/resque/*.rb"].each {|file| require file}
end

require 'resque_scheduler/tasks'
task "resque:scheduler_setup"

