require 'date'

module CostBasis

  class Qif

    def initialize
    end

    # Parse a QIF format date.
    def parse_date str
      # Date line. The second and third numbers can be space-padded.
      /(\d+)\/([ \d]+)\/([ \d]+)/.match(str) { |mdata|
        return Date.civil(mdata[3].to_i + 1900, mdata[1].to_i, mdata[2].to_i)
      }

      # Date format for year 2000 and beyond.
      /(\d+)\/([ \d]+)'([ \d]+)/.match(str) { |mdata|
        return Date.civil(mdata[3].to_i + 2000, mdata[1].to_i, mdata[2].to_i)
      }

      fail "Unrecognized date: #{str}"
    end
    private :parse_date

    # Dollar amounts can have comma separators.
    def parse_num str
      str.gsub(',', '').to_f
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

    def read_qif io
      trans = {}
      curtrans = {}

      # Check QIF file header.
      io.gets.strip.downcase == '!type:invst' or fail 'QIF data is not from an investment account'

      io.each_line { |line|
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

        when 'U'
        when '$'
          # not used

        when 'L'
        when 'M'
        when 'P'
          # Transaction memo.

        when 'T'
          # Dollar amount of transaction.
          curtrans[:amount] = parse_num parm

        when 'O'
          curtrans[:commission] = parse_num parm

        else
          fail "Unrecognized command code #{cmdchar}"

        end
      }

      trans
    end

  end
end
