module Resque
  module StuckQueue
    class HeartbeatJob
      class << self

        attr_accessor :redis

        def perform(*args)
          keyname,host,port,namespace,new_time = *args
          @redis = Redis::Namespace.new(namespace, :redis => Redis.new(:host => host, :port => port))
          #raise "#{@redis.inspect} must be the same as #{Resque::StuckQueue.redis.inspect}"
          @redis.set(keyname, new_time)
          Resque::StuckQueue.logger.info "successfully updated key #{keyname} to #{new_time} at #{Time.now} for #{@redis.inspect}"
        end

      end
    end
  end
end
