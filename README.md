# Resque stuck queue

## Why?

This is to be used to satisfy an ops problem. There have been cases resque processes would stop processing jobs for unknown reasons. Other times resque wouldn't be running entirely due to deploy problems architecture/human error issues. Or on a different note, resque could be highly backed up and won't process jobs because it's too busy. This enables gaining a little insight into those issues.

## What is it?

If resque doesn't run jobs in specific queues (defaults to `@queue = :app`) within a certain timeframe, it will trigger a pre-defined handler of your choice. You can use this to send an email, pager duty, add more resque workers, restart resque, send you a txt...whatever suits you.

It will also fire a proc to notify you when it's recovered.

## How it works

When you call `start` you are essentially starting two threads that will continiously run until `stop` is called or until the process shuts down.

One thread is responsible for pushing a 'heartbeat' job to resque which will essentially refresh a specific key in redis every time that job is processed.

The other thread is a continious loop that will check redis (bypassing resque) for that key and check what the latest time the hearbeat job successfully updated that key.

StuckQueue will trigger a pre-defined proc if the queue is lagging according to the times you've configured (see below).

After firing the proc, it will continue to monitor the queue, but won't call the proc again until the queue is found to be good again (it will then call a different "recovered" handler). 

By calling the recovered proc, it will then complain again the next time the lag is found.

## Usage

Run this as a daemon somewhere alongside the app/in your setup. You'll need to configure it to your needs first:

Put something like this in `config/initializers/resque-stuck-queue.rb`:

<pre>
require 'resque_stuck_queue' # or require 'resque/stuck_queue'
require 'logger'

# change to decent values that make sense for you
Resque::StuckQueue.config[:heartbeat_interval]       = 10.seconds
Resque::StuckQueue.config[:watcher_interval]         = 1.seconds
Resque::StuckQueue.config[:trigger_timeout]          = 30.seconds

# which queues to monitor
Resque::StuckQueue.config[:queues]                   = [:app, :custom_queue]

# handler for when a resque queue is being problematic
Resque::StuckQueue.config[:triggered_handler]         = proc { |bad_queue, lagtime|
  msg = "[BAD] AWSM #{Rails.env}'s Resque #{bad_queue} queue lagging job execution by #{lagtime} seconds."
  send_email(msg)
}

# handler for when a resque queue recovers
Resque::StuckQueue.config[:recovered_handler]         = proc { |good_queue, lagtime|
  msg = "[GOOD] AWSM #{Rails.env}'s Resque #{good_queue} queue lagging job execution by #{lagtime} seconds."
  send_email(msg)
}

# create a sync/unbuffered log
logpath = Rails.root.join('log', 'resque_stuck_queue.log')
logfile = File.open(logpath, "a")
logfile.sync = true
logger = Logger.new(logfile)
logger.formatter = Logger::Formatter.new
Resque::StuckQueue.config[:logger]                    = logger

# your own redis
Resque::StuckQueue.config[:redis]                     = YOUR_REDIS

</pre>

Then create a task to run it as a daemon (similar to how the resque rake job is implemented):

<pre>

# put this in lib/tasks/resque_stuck_queue.rb

namespace :resque do
  desc "Start a Resque-stuck daemon"
  # :environment dep task should load the config via the initializer
  task :stuck_queue => :environment do
    Resque::StuckQueue.start
  end

end

</pre>

then run it via god, monit or whatever:

<pre>
$ bundle exec rake --trace resque:stuck_queue # outdated god config - https://gist.github.com/shaiguitar/298935953d91faa6bd4e
</pre>

## Configuration Options

Configuration settings are below. You'll most likely at the least want to tune `:triggered_handler`,`:heartbeat_interval` and `:trigger_timeout` settings.

<pre>

triggered_handler:
	set to what gets triggered when resque-stuck-queue will detect the latest heartbeat is older than the trigger_timeout time setting.
	Example:
	Resque::StuckQueue.config[:triggered_handler] = proc { |queue_name, lagtime| send_email('queue #{queue_name} isnt working, aaah the daemons') }

recovered_handler:
	set to what gets triggered when resque-stuck-queue has triggered a problem, but then detects the queue went back down to functioning well again(it wont trigger again until it has recovered).
	Example:
	Resque::StuckQueue.config[:recovered_handler] = proc { |queue_name, lagtime| send_email('phew, queue #{queue_name} is ok') }

heartbeat_interval:
	set to how often to push the 'heartbeat' job which will refresh the latest working time.
	Example:
	Resque::StuckQueue.config[:heartbeat_interval] = 5.minutes

watcher_interval:
	set to how often to check to see when the last time it worked was.
	Example:
	Resque::StuckQueue.config[:watcher_interval] = 1.minute

trigger_timeout:
	set to how much of a resque work lag you are willing to accept before being notified. note: take the :watcher_interval setting into account when setting this timeout.
	Example:
	Resque::StuckQueue.config[:trigger_timeout] = 9.minutes

redis:
	set the Redis StuckQueue will use. Either a Redis or Redis::Namespace instance.

heartbeat_key:
	optional, name of keys to keep track of the last good resque heartbeat time

triggered_key:
	optional, name of keys to keep track of the last trigger time

logger:
	optional, pass a Logger. Default a ruby logger will be instantiated. Needs to respond to that interface.

queues:
	optional, monitor specific queues you want to send a heartbeat/monitor to. default is [:app]

abort_on_exception:
	optional, if you want the resque-stuck-queue threads to explicitly raise, default is false

heartbeat_job:
	optional, your own custom refreshing job. if you are using something other than resque

enable_signals:
	optional, allow resque::stuck's signal_handlers which do mostly nothing at this point.

</pre>

To start it:

<pre>
Resque::StuckQueue.start                # blocking
Resque::StuckQueue.start_in_background  # sugar for Thread.new { Resque::StuckQueue.start }
</pre>

Stopping it consists of the same idea:

<pre>
Resque::StuckQueue.stop                 # this will block until the threads end their current iteration
Resque::StuckQueue.force_stop!          # force kill those threads and let's move on
</pre>

## Sidekiq/Other redis-based job queues

If you have trouble with other queues you can use this lib by setting your own custom refresh job (aka, the job that refreshes your queue specific heartbeat_key). The one thing you need to take care of is ensure whatever and however you enque your own custom job, it sets the heartbeat_key to Time.now:

<pre>

class CustomJob
  include Sidekiq::Worker
  def perform
    # ensure you're setting the key in the redis the job queue is using
    $redis.set(Resque::StuckQueue.heartbeat_key_for(queue_name), Time.now.to_i)
  end
end

Resque::StuckQueue.config[:heartbeat_job] = proc {
  # or however else you enque your custom job, Sidekiq::Client.enqueue(CustomJob), whatever, etc.
  CustomJob.perform_async
}
</pre>

## Tests

Run the tests:

`bundle; bundle exec rake`
`RESQUE_2=1 bundle exec rake # for resq 2 compat`
