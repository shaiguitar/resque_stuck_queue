# encoding: utf-8
module Resque
  module StuckQueue
    module Signals
      extend self

      def enable!
        if Resque::StuckQueue.config[:enable_signals]

          trap("SIGUSR1") do
            ENV['SIGUSR1'] = "done be had"
            Resque::StuckQueue.logger.info("¯\_(ツ)_/¯ ...")
          end

          trap("SIGUSR2") do
            require 'pry'
            binding.pry
          end

        end
      end
    end
  end
end
