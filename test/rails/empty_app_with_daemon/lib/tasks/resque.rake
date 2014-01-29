require 'resque/tasks'
task "resque:setup" => :environment do
  ENV['QUEUES'] ||= "*"
  ENV['INTERVAL'] ||= '1'
end

