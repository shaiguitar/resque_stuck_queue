# encoding: utf-8
module Resque
  module StuckQueue
    module Signals
      extend self

      def enable!
        if Resque::StuckQueue.config[:enable_signals]

          trap("SIGUSR1") do
            ENV['SIGUSR1'] = "done be had"
            Resque::StuckQueue.logger.info("Inspecting StuckQueue config: #{Resque::StuckQueue.config.inspect}")
            Resque::StuckQueue.queues.each do |q| Resque::StuckQueue.log_watcher_info(q) end
            Resque::StuckQueue.logger.info("¯\_(ツ)_/¯ ...")
          end

          # do something meaningful
          #trap("SIGUSR2") do
          #  require 'pry'
          #  binding.pry
          #end

        end
      end
    end
  end
end
