# fixture job
class SetRedisKey
  NAME = "integration_test"
  @queue = :app
  def self.perform
    Resque.redis.set(NAME, "1")
  end
end
