#!/usr/bin/env ruby

require_relative 'qif'

module CostBasis

  class CostBasis

    def initialize
      @holdings = {
        lots: [],
        totalbasis: 0,
        totalshares: 0
      }
    end

    # All these transactions are treated as buys. For tax purposes, we
    # treat all reinvestments as purchases on the date of reinvestment.
    BUY_ACTIONS = %w(shrsin reinvdiv reinvint reinvsh reinvmd reinvlg buy)
    def buy_action? action
      BUY_ACTIONS.include? action.downcase
    end
    private :buy_action?

    # All these transactions are treated as sells.
    SELL_ACTIONS = %w(shrsout sell)
    def sell_action? action
      SELL_ACTIONS.include? action.downcase
    end
    private :sell_action?

    def fmt_date dt
      dt.strftime '%Y-%m-%d'
    end
    private :fmt_date

    def join_wrap strlist, sep, width
      strlist = strlist.dup
      str = ''
      cur_line = strlist.shift
      until strlist.empty?
        next_word = strlist.shift
        if cur_line.size + sep.size + next_word.size > width
          str += cur_line + "\n"
          cur_line = next_word
        else
          cur_line += sep + next_word
        end
      end
      str + cur_line
    end
    private :join_wrap

    def show_lots
      puts '  Lots:'
      lot_strs = @holdings[:lots].reject { |lot|
        lot[:shares] == 0
      }.map { |lot|
        "#{fmt_date lot[:date]} #{lot[:shares]}"
      }
      puts join_wrap(lot_strs, '  ', 78)
    end
    private :show_lots

    def cents num
      sprintf '%.2f', num
    end
    private :cents

    def form4 num
      sprintf '%.4f', num
    end
    private :form4

    def show_totals
      puts(
        if @holdings[:totalbasis] == 0 or @holdings[:totalshares] == 0
          '    Shares: 0  Total Cost: 0'
        else
          "    Shares: #{@holdings[:totalshares]}  Total cost: #{cents $holdings[:totalbasis]}  Average cost: #{form4($holdings[:totalbasis] / $holdings[:totalshares])}"
        end
      )
      puts
    end
    private :show_totals

    def run_buy trans
      costbasis = trans[:amount].to_f + trans[:commission].to_f
      lot = {
        price: costbasis / trans[:shares],
        shares: trans[:shares],
        date: trans[:date]
      }

      @holdings[:lots] << lot
      @holdings[:totalbasis] += costbasis
      @holdings[:totalshares] += trans[:shares]

      puts "#{fmt_date trans[:date]}: BUY #{trans[:shares]} shares at #{trans[:price]} for #{trans[:amount]}"
      show_totals
    end
    private :run_buy

    def run_transaction trans
      if buy_action? trans[:action]
        run_buy trans
      elsif sell_action? trans[:action]
      elsif trans[:action].downcase == 'stksplit'
      else
        # Ignore transaction and don't show lots.
        return
      end

      show_lots
    end
    private :run_transaction

    def run_transactions security, translist
      puts "Transactions for #{security}:"
      puts

      translist.each { |trans|
        run_transaction trans
      }
    end

  end
end

if __FILE__ == $PROGRAM_NAME
  progname = File.basename $PROGRAM_NAME
  USAGE = <<-EOS
Usage: #{progname} QIF-file
  EOS

  fname = ARGV.shift
  fname or die USAGE

  trans_table = File.open(fname, 'r') { |file|
    Qif.new.read_qif file
  }

  trans_table.each { |security, translist|
    CostBasis.new.run_transactions security, translist
  }
end

__END__
