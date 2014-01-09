# Resque stuck queue

## Why?

This is to be used to satisfy an ops problem. There have been cases resque processes would stop processing jobs for unknown reasons. Other times resque wouldn't be running entirely due to deploy problems architecture/human error issues. Or on a different note, resque could be highly backed up and won't process jobs because it's too busy. This enables gaining a little insight into those issues.

## What is it?

If resque doesn't run jobs within a certain timeframe, it will trigger a pre-defined handler of your choice. You can use this to send an email, pager duty, add more resque workers, restart resque, send you a txt...whatever suits you.

## How it works

When you call `start` you are essentially starting two threads that will continiously run until `stop` is called or until the process shuts down.

One thread is responsible for pushing a 'heartbeat' job to resque which will essentially refresh a specific key in redis every time that job is processed.

The other thread is a continious loop that will check redis (bypassing resque) for that key and check what the latest time the hearbeat job successfully updated that key.

It will trigger a pre-defined proc (see below) if the last time the hearbeat job updated that key is older than the trigger_timeout setting (see below).

## Usage

Configure it first:

<pre>
# how often to push that 'heartbeat' job to refresh the latest time it worked.
Resque::StuckQueue.config[:heartbeat] = 5.minutes

# since there is an realistic and acceptable lag for job queues, set this to how much you're
# willing to accept between the current time and when the last hearbeat job went through.
#
# take the heartbeat into consideration when setting this (it will fire 10 hours + 5 minutes with above heartbeat).
Resque::StuckQueue.config[:trigger_timeout] = 10.hours

# what gets triggered when resque-stuck-queue will detect the latest heartbeat is older than the trigger_timeout time set above.
#
# triggering will update the key, so you'll have to wait the trigger_timeout again
# in order for it to trigger again even if workers are still stale.
Resque::StuckQueue.config[:handler] = proc { send_email }

# optional, in case you want to set your own name for the key that will be used as the last good hearbeat time
Resque::StuckQueue.config[:global_key] = "name-the-refresh-key-as-you-please"

# optional, if you want the resque-stuck-queue threads to explicitly raise, default is false
Resque::StuckQueue.config[:abort_on_exception] = true

# optional, pass a logger. Default a ruby logger will be instantiated. Needs to respond to that interface.
Resque::StuckQueue.config[:logger] = Logger.new($stdout)

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
    Resque::StuckQueue.config[:handler] = proc { $stderr.puts("resque wonky!") }

    Resque::StuckQueue.start # blocking operation, daemon running
  end
end

# then:

$ bundle exec rake --trace resque:stuck_queue

# you can run this under god for example @ https://gist.github.com/shaiguitar/298935953d91faa6bd4e

</pre>

## Sidekiq/Other job queues

If you have trouble with other queues the ideas here can be applied there. The only difference would be to swap out the method of enqueing the refresh job. The rough idea would be swap:

`Resque.enqueue(RefreshLatestTimestamp, global_key)`

With:

`Sidekiq::Client.enqueue(RefreshLatestTimestamp, 'bob', 1) # or however you enque that job`

The idea holds.

## Tests

Run the tests:

`bundle; bundle exec rake`
