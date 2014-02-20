#!/usr/bin/env ruby

require_relative 'qif'

module CostBasis

  # Cost basis calculator.
  class CostBasis

    # Share amounts below this are treated as zero.
    SHARETOL = 0.001

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
      cur_line = strlist.shift.to_s
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
        "#{fmt_date lot[:date]} #{form4 lot[:shares]}"
      }
      puts join_wrap(lot_strs, '  ', 78)
      puts
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
          "    Shares: #{@holdings[:totalshares]}  Total cost: #{cents @holdings[:totalbasis]}  Average cost: #{form4(@holdings[:totalbasis] / @holdings[:totalshares])}"
        end
      )
      puts
    end
    private :show_totals

    # Apply a buy transaction to our holdings.
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

    # Figure out the type of capital gain (long or short) given the buy and
    # sell dates.
    def capgain_term buydate, selldate
      buymon = buydate.year * 12 + buydate.mon
      sellmon = selldate.year * 12 + selldate.mon
      sellday = selldate.day
      if sellday < buydate.day
        # The length of the month doesn't matter here because we are just
        # comparing dates, not calculating calendar periods.
        sellday += 31
        sellmon -= 1
      end

      # The IRS considers a holding period to be one year long if it is the
      # day after in the next year. So March 5, 1997 to March 5, 1998 is
      # still considered short term. But March 5, 1997 to March 6, 1998 is
      # not.
      mondiff = sellmon - buymon
      mondiff += 1 if sellday > buydate.day

      mondiff <= 12 ? :S : :L
    end
    private :capgain_term

    def showbasis salelots
      basis = { L: 0, S: 0 }
      shares = { L: 0, S: 0 }

      salelots.each { |lot|
        price = yield lot
        amount = lot[:shares] * price
        term = lot[:term]
        puts "  #{fmt_date lot[:date]}: #{form4 lot[:shares]} * #{form4 price} = #{cents amount} #{term}"
        basis[term] += amount
        shares[term] += lot[:shares]
      }

      puts "  Totals: L=#{cents basis[:L]} (#{form4 shares[:L]} shares)  S=#{cents basis[:S]} (#{form4 shares[:S]} shares)"
      puts
    end
    private :showbasis

    # Apply a sell transaction to our holdings.
    def run_sell trans
      # We have to round down the average cost basis. It appears to be
      # standard practice at all mutual fund companies.
      avbasis = @holdings[:totalbasis] / @holdings[:totalshares]

      # This array holds all the share lots consumed in the sale
      # transaction.
      salelots = []

      # Number of shares to be sold.
      saleshares = trans[:shares]

      # Update the totals.
      @holdings[:totalbasis] -= avbasis * saleshares
      @holdings[:totalshares] -= saleshares

      # Regardless of the capital gains calculation method, we have to go
      # through the holdings lot by lot to determine the holding periods.
      @holdings[:lots].each { |lot|
        # Skip all lots that have already been zeroed out.
        next if lot[:shares] == 0

        if saleshares <= lot[:shares]
          # The remaining shares to be sold fit in this lot.
          salelots << {
            price: lot[:price],
            date: lot[:date],
            shares: saleshares,
            term: capgain_term(lot[:date], trans[:date])
          }
          lot[:shares] -= saleshares
          saleshares = 0
          break
        end

        # Otherwise, this entire lot is consumed.
        salelots << {
          price: lot[:price],
          date: lot[:date],
          shares: lot[:shares],
          term: capgain_term(lot[:date], trans[:date])
        }
        saleshares -= lot[:shares]
        lot[:shares] = 0
      }

      # The number of shares sold is greater than the number of shares
      # held. It would be very strange if this happened. The comparison
      # tests if the shares remaining to be "sold" from the current
      # holdings is greater than 0 after going through all of the holdings.
      fail 'Share balance below zero' if saleshares > SHARETOL

      puts "#{fmt_date trans[:date]}: SELL #{trans[:shares]} shares"

      @holdings[:totalshares] = 0 if @holdings[:totalshares].abs < SHARETOL
      @holdings[:totalbasis] = 0 if @holdings[:totalbasis].abs < SHARETOL
      show_totals

      puts '  FIFO:'
      showbasis(salelots) { |lot| lot[:price] }

      puts '  Average cost basis:'
      showbasis(salelots) { |lot| avbasis }
    end
    private :run_sell

    # Apply a stock split to our holdings.
    def run_split trans
      # For some reason, Quicken reports 10 times the split ratio rather than the
      # split ratio itself.
      mult = trans[:shares] / 10.0

      @holdings[:lots].each { |lot|
        lot[:shares] *= mult
        lot[:price] /= mult
      }

      @holdings[:totalshares] *= mult

      puts "#{fmt_date trans[:date]}: STOCK SPLIT #{mult} for 1"
      show_totals
    end
    private :run_split

    def run_transaction trans
      if buy_action? trans[:action]
        run_buy trans
      elsif sell_action? trans[:action]
        run_sell trans
      elsif trans[:action].downcase == 'stksplit'
        run_split trans
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
    CostBasis::Qif.new.read_qif file
  }

  trans_table.each { |security, translist|
    CostBasis::CostBasis.new.run_transactions security, translist
  }
end

__END__
