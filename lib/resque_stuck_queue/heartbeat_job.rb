module Resque
  module StuckQueue
    class HeartbeatJob
      def self.perform(args)
        timestamp_key = args[0]
        host = args[1]
        port = args[2]
        new_time = Time.now.to_i
        r = Redis.new(:host => host, :port => port)
        r.set(timestamp_key, new_time)
      end
    end
  end
end
