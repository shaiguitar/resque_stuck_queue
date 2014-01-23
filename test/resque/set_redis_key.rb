# fixture job
class SetRedisKey
  NAME = "integration_test"
  @queue = :app
  def self.perform
    # tests run on localhost
    Redis.new.set(NAME, "1")
  end
end
