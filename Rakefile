require 'rake/testtask'

task :default => :test
#task :test do
  ## forking and what not. keep containted in each own process?
  #Dir['./test/test_*.rb'].each do |file|
    #system("ruby -I. -I lib/ #{file}")
  #end
#end
Rake::TestTask.new do |t|
  t.pattern = "test/test_*rb"
end

require 'resque/tasks'

task :'resque:setup' do
  # https://github.com/resque/resque/issues/773
  # have the jobs loaded in memory
  Dir["./test/resque/*.rb"].each {|file| require file}
  # load project
  Dir["./lib/resque_stuck_queue.rb"].each {|file| require file}
end

require 'resque/scheduler/tasks'

task "resque:scheduler_setup"

