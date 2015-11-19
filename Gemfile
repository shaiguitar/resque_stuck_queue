source 'https://rubygems.org'

gemspec

if ENV['RESQUE_2']
# resque 2
  gem 'resque', :git => "https://github.com/engineyard/resque.git"
else
  gem 'resque'
end

gem 'redis-mutex'
gem 'redis-classy'

# TEST
gem 'minitest'
gem 'mocha'
gem 'pry'
gem 'm'
gem 'resque-scheduler'
