#!/usr/bin/env ruby

module CostBasis

  class CostBasis

    def initialize
    end

    # All these transactions are treated as buys. For tax purposes, we
    # treat all reinvestments as purchases on the date of reinvestment.
    BUY_ACTIONS = %w(shrsin reinvdiv reinvint reinvsh reinvmd reinvlg buy)
    def buy_action? action
      BUY_ACTIONS.include? action.downcase
    end

    # All these transactions are treated as sells.
    SELL_ACTIONS = %w(shrsout sell)
    def sell_action? action
      SELL_ACTIONS.include? action.downcase
    end



  end

end

__END__
