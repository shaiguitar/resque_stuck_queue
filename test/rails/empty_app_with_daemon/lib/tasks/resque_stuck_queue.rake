require 'logger'
require 'resque_stuck_queue'

namespace :resque do
  desc "Start a Resque-stuck daemon"
  task :stuck_queue => :environment do

    logpath = Rails.root.join('log', 'resque_stuck_queue.log')
    logfile = File.open(logpath, "a")
    logfile.sync = true
    logger = Logger.new(logfile)
    logger.formatter = Logger::Formatter.new

    Resque::StuckQueue.config[:logger] = logger
    Resque::StuckQueue.config[:redis]  = Redis.new
    Resque::StuckQueue.config[:queues] = [:app]

    # change me to decent values
    Resque::StuckQueue.config[:heartbeat]           = 5.seconds
    Resque::StuckQueue.config[:trigger_timeout]     = 10.seconds
    Resque::StuckQueue.config[:abort_on_exception]  = true # staging

    Resque::StuckQueue.config[:triggered_handler] = proc { |bad_queue, lagtime|
      msg = "[BAD] #{Rails.env}'s Resque #{bad_queue} queue lagging job execution by #{lagtime} seconds."
      Resque::StuckQueue.logger.info msg
    }

    Resque::StuckQueue.config[:recovered_handler] = proc { |good_queue, lagtime|
      msg = "[GOOD] #{Rails.env}'s Resque #{good_queue} queue lagging job execution by #{lagtime} seconds."
      Resque::StuckQueue.logger.info msg
    }

    require 'pry'
      binding.pry
    Resque::StuckQueue.start
  end
end

