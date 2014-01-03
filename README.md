## Resque stuck queue

Ever run into that? Sucks, eh?

This should enable a way to fire some handler when jobs aren't occurring within a certain timeframe.

## How it works

When you call `start` you are essentially starting two threads that will continiously run until `stop` is called or until the process shuts down.

One thread is responsible for pushing a 'heartbeat' job to resque which will essentially refresh a specific key in redis every time that job is processed.

The other thread is a continious loop that will check redis (bypassing resque) for that key and check what the latest time the hearbeat job successfully updated that key.

It will trigger a pre-defined proc (see below) if the last time the hearbeat job updated that key is older than the trigger_timeout setting (see below).

## Usage

Add this to wherever you're setting up resque (config/initializers or wherever).

Configure it first:

<pre>
# how often to push that 'heartbeat' job to refresh the latest time it worked.
Resque::StuckQueue.config[:heartbeat] = 5.minutes

# since there is an realistic and acceptable lag for job queues, set this to how much you're
# willing to accept between the current time and when the last hearbeat job went through.
#
# obviously, take the heartbeat into consideration when setting this
Resque::StuckQueue.config[:trigger_timeout] = 10.hours

# what gets triggered when resque-stuck-queue will detect the latest heartbeat is older than the trigger_timeout time set above.
Resque::StuckQueue.config[:handler] = proc { send_email }

# optional, in case you want to set your own name for the key that will be used as the last good hearbeat time
Resque::StuckQueue.config[:global_key] = "name-the-refresh-key-as-you-please"

# optional, if you want the resque-stuck-queue threads to explicitly raise, default is false
Resque::StuckQueue.config[:abort_on_exception] = true
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

## Tests

Run the tests:

`bundle; bundle exec rake`
