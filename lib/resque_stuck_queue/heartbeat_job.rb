module Resque
  module StuckQueue
    class HeartbeatJob
      class << self

        attr_accessor :redis

        def perform(*args)
          keyname,host,port,namespace = args
          Redis::Namespace.new(namespace, :redis => Redis.new(:host => host, :port => port))
          @redis.set(keyname, Time.now.to_i)
        end

      end
    end
  end
end
