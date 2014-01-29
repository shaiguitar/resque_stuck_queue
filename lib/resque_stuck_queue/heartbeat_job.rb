module Resque
  module StuckQueue
    class HeartbeatJob
      class << self

        attr_accessor :redis

        def perform(keyname)
          @redis.set(keyname, Time.now.to_i)
        end

      end
    end
  end
end
