# frozen_string_literal: true

require 'date'

module CostBasis
  # Reader for Quicken QIF files.
  class Qif
    def initialize
      @linenum = nil
    end

    # Parse a QIF format date.
    def parse_date(str)
      # Date line. The second and third numbers can be space-padded.
      %r{(\d+)/([ \d]+)/([ \d]+)}.match(str) { |mdata|
        year = mdata[3].to_i

        # Handle 2-digits years specially.
        if year < 100
          year += if year < 80
                    2000
                  else
                    1900
                  end
        end

        return Date.civil(year, mdata[1].to_i, mdata[2].to_i)
      }

      # Date format for year 2000 and beyond. (Quicken only?)
      %r{(\d+)/([ \d]+)'([ \d]+)}.match(str) { |mdata|
        return Date.civil(mdata[3].to_i + 2000, mdata[1].to_i, mdata[2].to_i)
      }

      raise "Unrecognized date on line #{@linenum}: #{str}"
    end
    private :parse_date

    # Dollar amounts can have comma separators.
    def parse_num(str)
      str.delete(',').to_f
    end
    private :parse_num

    # Reads a QIF file and generates a list of transactions.

    # Format of a QIF file is as follows:
    # Each transaction is specified on a number of lines. Each line provides
    # a detail of the transaction. Each line begins with a character denoting
    # the type of information provided on the line.

    # Lines can be as follows:

    # Dmm/dd/yy
    # Date of the transaction. The month can be one digit with no padding. The
    # day is space-padded if it is just a single digit. The year is two digits.

    # New for 2000: In the year 2000 and beyond, the format is Dmm/dd'yy

    # Naction
    # The type of transaction, e.g. ShrsIn, ShrsOut, ReinvDiv...

    # Ysecurity
    # The type of security. This is needed for brokerage accounts where many
    # types of securities can be traded in a single account.

    # Iprice
    # The price per share at which the trade was executed.

    # Qshares
    # The number of shares traded.

    # Tamount
    # The dollar amount of the transaction.

    # Ocommission
    # The commission paid. If this is a buy, the T amount plus the O commission
    # will be the cost basis.

    # This list is not complete. These are just the lines that we recognize. In
    # addition, each transaction in the QIF file ends with a line that begins
    # with a ^ character.

    def read_qif(io)
      trans = {}
      curtrans = {}

      # Skip everything except !type:invst sections.
      skip = true
      @linenum = 0

      io.each_line { |line|
        @linenum += 1

        if line.start_with?('!')
          skip = !line.strip.casecmp('!type:invst').zero?
          next
        end

        next if skip

        # First character on the line indicates the type of information on
        # this line.
        cmdchar, parm = line.chomp.split('', 2)

        case cmdchar
        when '^'
          # End of transaction marker. Add current transaction to the list
          # and start a new transaction.

          security = curtrans[:security]
          if security
            trans[security] ||= []
            trans[security] << curtrans
            curtrans = {}
          end

        when 'D'
          curtrans[:date] = parse_date parm

        when 'N'
          curtrans[:action] = parm

        when 'Y'
          curtrans[:security] = parm

        when 'I'
          # Price at which trade was executed.
          curtrans[:price] = parse_num parm

        when 'Q'
          # Quantity of shares.
          curtrans[:shares] = parse_num parm

        when 'U', '$' then 1
          # not used

        when 'L', 'M', 'P' then 2
          # Transaction memo.

        when 'T'
          # Dollar amount of transaction.
          curtrans[:amount] = parse_num parm

        when 'O'
          curtrans[:commission] = parse_num parm

        else
          raise "Unrecognized command code on line #{@linenum}: #{cmdchar}"

        end
      }

      trans
    end
  end
end
