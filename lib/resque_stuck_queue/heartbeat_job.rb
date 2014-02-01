module Resque
  module StuckQueue
    class HeartbeatJob
      class << self

        attr_accessor :redis

        def perform(*args)
          # TODO rm host, port, namespace hack from enqueue_to and here
          keyname,host,port,namespace,new_time = *args
          @redis = Resque::StuckQueue.redis
          @redis.set(keyname, new_time)
          Resque::StuckQueue.logger.info "successfully updated key #{keyname} to #{new_time} at #{Time.now} for #{@redis.inspect}"
        end

      end
    end
  end
end
