class RefreshLatestTimestamp
  @queue = :app
  def self.perform(timestamp_key)
    Resque.redis.set(timestamp_key, Time.now.to_i)
  end
end
