# Resque stuck queue

## Why?

This is to be used to satisfy an ops problem. There have been cases resque processes would stop processing jobs for unknown reasons. Other times resque wouldn't be running entirely due to deploy problems architecture/human error issues. Or on a different note, resque could be highly backed up and won't process jobs because it's too busy. This enables gaining a little insight into those issues.

## What is it?

If resque doesn't run jobs in specific queues (defaults to `@queue = :app`) within a certain timeframe, it will trigger a pre-defined handler of your choice. You can use this to send an email, pager duty, add more resque workers, restart resque, send you a txt...whatever suits you.

## How it works

When you call `start` you are essentially starting two threads that will continiously run until `stop` is called or until the process shuts down.

One thread is responsible for pushing a 'heartbeat' job to resque which will essentially refresh a specific key in redis every time that job is processed.

The other thread is a continious loop that will check redis (bypassing resque) for that key and check what the latest time the hearbeat job successfully updated that key.

It will trigger a pre-defined proc (see below) if the last time the hearbeat job updated that key is older than the trigger_timeout setting (see below).

## Usage

Configure it first. Optional settings are below. You'll most likely at the least want to tune `:handler`,`:heartbeat` and `:trigger_timeout` settings.

<pre>
handler:
	set to what gets triggered when resque-stuck-queue will detect the latest heartbeat is older than the trigger_timeout time setting.
	Example:
	Resque::StuckQueue.config[:handler] = proc { |queue_name, lagtime| send_email('queue #{queue_name} isnt working, aaah the daemons') }

heartbeat:
	set to how often to push that 'heartbeat' job to refresh the latest time it worked.
	Example:
	Resque::StuckQueue.config[:heartbeat] = 5.minutes

trigger_timeout:
	set to how much of a resque work lag you are willing to accept before being notified. note: take the :heartbeat setting into account when setting this timeout.
	Example:
	Resque::StuckQueue.config[:trigger_timeout] = 55.minutes

redis:
	set the Redis instance StuckQueue will use

heartbeat_key:
	optional, name of keys to keep track of the last good resque heartbeat time

logger:
	optional, pass a Logger. Default a ruby logger will be instantiated. Needs to respond to that interface.

queues:
	optional, monitor specific queues you want to send a heartbeat/monitor to. default is :app

abort_on_exception:
	optional, if you want the resque-stuck-queue threads to explicitly raise, default is false

refresh_job:
	optional, your own custom refreshing job. if you are using something other than resque
</pre>

Then start it:

<pre>
Resque::StuckQueue.start                # blocking
Resque::StuckQueue.start_in_background  # sugar for Thread.new { Resque::StuckQueue.start }
</pre>

Stopping it consists of the same idea:

<pre>
Resque::StuckQueue.stop                 # this will block until the threads end their current iteration
Resque::StuckQueue.force_stop!          # force kill those threads and let's move on
</pre>

## Deployment/Integration

* Include this in the app in a config initializer of some sort.

Note though, the resque-stuck threads will live alongside the app server process so you will need to explicitely handle `start` _and_ `stop`. If you're deployed in a forking-server environment and the whatever process has this does not get restarted the threads will keep on going indefinitely.

* Run this as a daemon somewhere alongside the app/in your setup.

Contrived example:

<pre>

# put this in lib/tasks/resque_stuck_queue.rb

require 'resque_stuck_queue' # or require 'resque/stuck_queue'

namespace :resque do
  desc "Start a Resque-stuck daemon"
  task :stuck_queue do

    Resque::StuckQueue.config[:heartbeat] = 10.minutes
    Resque::StuckQueue.config[:trigger_timeout] = 1.hour
    Resque::StuckQueue.config[:handler] = proc { |queue_name| $stderr.puts("resque queue #{queue_name} wonky!") }

    Resque::StuckQueue.start # blocking operation, daemon running
  end
end

# then:

$ bundle exec rake --trace resque:stuck_queue

# you can run this under god for example @ https://gist.github.com/shaiguitar/298935953d91faa6bd4e

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

Resque::StuckQueue.config[:refresh_job] = proc {
  # or however else you enque your custom job, Sidekiq::Client.enqueue(CustomJob), whatever, etc.
  CustomJob.perform_async
}
</pre>

## Tests

Run the tests:

`bundle; bundle exec rake`
`RESQUE_2=1 bundle exec rake # for resq 2 compat`
