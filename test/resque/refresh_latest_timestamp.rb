class RefreshLatestTimestamp
  @queue = :app
  def self.perform(args)
    timestamp_key, host, port = args[0], args[1], args[2]
    r = Redis.new(:host => host, :port => port)
    r.set(timestamp_key, Time.now.to_i)
  end
end
