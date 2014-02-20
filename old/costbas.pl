#!/usr/bin/perl -w
# Script for calculating the cost basis of sale transactions.
# Takes a QIF file as input and sends the cost basis report to stdout.

require 5.010;
use strict;
use Getopt::Std;
use FileHandle;

# Amounts below this are treated as zero.
my $SHARETOL = 0.001;

# If this is TRUE, verbose mode is on and all the share lots will be
# displayed after each transaction.
my $showlots = 0;

# If this is TRUE, the user has provided a supplemental info file.
my $gotsuppfile = 0;


# Parse a QIF format date.
sub parse_date {
    my $qifdate = shift;

# Date line. The second and third numbers can be space-padded.
    if ($qifdate =~ /(\d+)\/([ \d]+)\/([ \d]+)/) {
	return {
	    year => $3 + 1900,
	    month => $1,
	    day => $2
	};
    }
# Date format for year 2000 and beyond.
    elsif ($qifdate =~ /(\d+)\/([ \d]+)'([ \d]+)/) {
	return {
	    year => $3 + 2000,
	    month => $1,
	    day => $2
	};
    }
    else { 
	die "unrecognized date $qifdate\n";
    }
} # parse_date


sub date_equal {
    my $date1 = shift;
    my $date2 = shift;

    $date1->{year} == $date2->{year} and
	$date1->{month} == $date2->{month} and
	$date1->{day} == $date2->{day};
} # date_equal

sub is_buy_action {
    my $action = shift;

# All these transactions are treated as buys. For tax purposes, we treat
# all reinvestments as purchases on the date of reinvestment.

    $action eq "ShrsIn" or
	$action eq "ReinvDiv" or
	$action eq "ReinvInt" or
	$action eq "ReinvSh" or
	$action eq "ReinvMd" or
	$action eq "ReinvLg" or
	$action eq "Buy";
} # is_buy_action

sub is_sell_action {
    my $action = shift;

# All these transactions are treated as sells.
    $action eq "ShrsOut" or
	$action eq "Sell";
} # is_sell_action

sub new_trans {
    { 
	commission => 0, 
	washed => 0, 
	wash_basis_adjust => 0, 
	wash_price_adjust => 0 
    }
}

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

sub read_qif {
    my $fname = shift;
    my $g_trans = shift;
    my $curtrans = new_trans;
    my $security = '';
    local $_;

    my $fh = new FileHandle;
    $fh->open($fname, "r") or die "can't open $fname for reading: $!\n";

    $_ = <$fh>;
    chomp;

    # Check QIF file header.
    $_ eq "!Type:Invst" or die "Not an investment account\n";

    while (<$fh>) {
	chomp;

# First character on the line indicates the type of information on this
# line.
	my $cmdchar = substr($_, 0, 1);
	my $parm = substr($_, 1);

	if ($cmdchar eq '^') {
# End of transaction marker. Push current transaction onto the list and
# start a new transaction.

	    if ($security ne '') {
		if (defined $g_trans->{$security}) {
		    push @{$g_trans->{$security}}, $curtrans;
		}
		else {
		    $g_trans->{$security} = [ $curtrans ];
		}
	    }

	    $curtrans = new_trans;
	    $security = '';
	}
	
	elsif ($cmdchar eq 'D') {
	    $curtrans->{date} = parse_date $parm;
	}
	
	elsif ($cmdchar eq 'N') {
# The type of transaction.
	    $curtrans->{action} = $parm;
	}
	
	elsif ($cmdchar eq 'Y') {
# Name of the security.
	    $security = $parm;
	}
	
	elsif ($cmdchar eq 'I') {
# Price at which the trade was executed.
	    $parm =~ tr/,//d;
	    $curtrans->{price} = $parm + 0;
	}
	
	elsif ($cmdchar eq 'Q') {
# Number of shares.
	    $parm =~ tr/,//d;
	    $curtrans->{shares} = $parm + 0;
	}
	
	elsif ($cmdchar eq 'T') {
# Dollar amount of transaction.
	    $parm =~ tr/,//d;
	    $curtrans->{amount} = $parm + 0;
	}

	elsif ($cmdchar eq 'O') {
# Commission paid.
	    $parm =~ tr/,//d;
	    $curtrans->{commission} = $parm + 0;
	}
    }

    $fh->close;
} # read_qif

# Figure out the type of capital gain (long or short) given the buy and
# sell dates.
sub capgain_term {
    my($buydate, $selldate) = @_;

    my $buymon = $buydate->{year} * 12 + $buydate->{month};
    my $sellmon = $selldate->{year} * 12 + $selldate->{month};
    my $sellday = $selldate->{day};
    if ($sellday < $buydate->{day}) {
	$sellday += 31;
	--$sellmon;
    }

# The IRS considers a holding period to be one year long if it is the day
# after in the next year. So March 5, 1997 to March 5, 1998 is still
# considered short term. But March 5, 1997 to March 6, 1998 is not.

    my $mondiff = $sellmon - $buymon;
    if ($sellday > $buydate->{day}) {
	++$mondiff;
    }

    $mondiff <= 12 ? 'S' : 'L';
}

# From: http://hermetic.nofadz.com/cal_stud/jdn.htm
#           jd = ( 1461 * ( y + 4800 + ( m - 14 ) / 12 ) ) / 4 +
#                ( 367 * ( m - 2 - 12 * ( ( m - 14 ) / 12 ) ) ) / 12 -
#                ( 3 * ( ( y + 4900 + ( m - 14 ) / 12 ) / 100 ) ) / 4 +
#                d - 32075

sub julian_date {
    my $year = shift;
    my $month = shift;
    my $day = shift;

    int((1461 * ($year + 4800 + int(($month - 14) / 12))) / 4) +
    int((367 * ($month - 2 - 12 * int(($month - 14) / 12))) / 12) -
    int((3 * int(($year + 4900 + int(($month - 14) / 12)) / 100)) / 4) +
    $day - 32075;
}

# The modified julian date is the number of days since 1858-11-17.
sub mod_julian_date {
    my $year = shift;
    my $month = shift;
    my $day = shift;
    
    julian_date($year, $month, $day) - 2400001;
}

# Is the second date within 30 days of the first date?
sub thirty_days {
    my $date1 = shift;
    my $date2 = shift;

    my $mjd1 = mod_julian_date $date1->{year}, $date1->{month}, $date1->{day};
    my $mjd2 = mod_julian_date $date2->{year}, $date2->{month}, $date2->{day};

    abs($mjd2 - $mjd1) <= 30;
} # thirty_days

# Format a date.
sub datestr {
    my $date = shift;
    sprintf "%02d/%02d/%04d", $date->{month}, $date->{day}, $date->{year};
}

# Format a number to two decimal places.
sub cents {
    my $number = shift;
    sprintf "%.2f", $number;
}

# Round a number to two decimal places.
sub roundcents {
    my $number = shift;
    int($number * 100 + 0.5) / 100;
}

# Format a number to four decimal places.
sub form4 {
    my $number = shift;
    sprintf "%.4f", $number;
}

# Show all the stock lots.
sub showlots {

    if ($showlots) {

	print "  Lots:\n";
	my $str = "";
	my $addstr;
	for (@_) {
	    next if $_->{shares} == 0;
	    $addstr = datestr($_->{date}) . " $_->{shares}";
	    if (length($addstr) + 2 + length($str) > 78) {
		print "$str\n";
		$str = "";
	    }
	    $str = "$str  $addstr";
	}
	print "$str\n" if length $str;
	print "\n";
    }
}

# Display the cost basis and lots using the price calculation method in
# pricesub.
# Returns the total basis of the lots sold. This will be used for the
# wash sale calculations. (if any)
sub showbasis {
    my $salelots = shift;
    my $pricesub = shift;
    my %basis = ( L => 0, S => 0 );
    my %shares = ( L => 0, S => 0 );

    for (@$salelots) {
	my $price = &$pricesub($_);
	my $amount = $_->{shares} * $price;
	print "  ", datestr($_->{date}), ": ",
	    form4($_->{shares}), " * ", form4($price), 
	    " = ", cents($amount), " $_->{term}\n";
	$basis{$_->{term}} += $amount;
	$shares{$_->{term}} += $_ -> {shares};
    }
    print "  Totals: L=", cents($basis{L}), 
    	" (", form4($shares{L}), " shares)  ",
	"S=", cents($basis{S}), 
	" (", form4($shares{S}), " shares)\n\n";

    $basis{L} + $basis{S};
}

# Show share and cost totals
sub show_totals {
    my $holdings = shift;
    
    if ($holdings->{totalbasis} == 0 or $holdings->{totalshares} == 0) {
	print "    Shares: 0  Total Cost: 0\n\n";
    }
    else {
	print "    Shares: $holdings->{totalshares}  Total Cost: ",
	    cents($holdings->{totalbasis}), 
	    "  Average Cost: ",
	    form4($holdings->{totalbasis} / $holdings->{totalshares}), "\n\n";
    }
}

# Apply a buy transaction to our holdings.
sub run_buy {
    my $transaction = shift;
    my $holdings = shift;

    my $costbasis = ($transaction->{amount} // 0) + 
	$transaction->{commission};
#     my $costbasis = $transaction->{price} * $transaction->{shares} + 
# 	$transaction->{commission};
    
    my $lot = {
	price => $costbasis / $transaction->{shares},
	shares => $transaction->{shares},
	date => $transaction->{date},
	washed => 0
    };

# Just add a new lot to our holdings and update the totals.
    push @{$holdings->{lots}}, $lot;
    $holdings->{totalbasis} += $costbasis;
    $holdings->{totalshares} += $transaction->{shares};

# Apply wash sale adjustments that took effect on future transactions.
    $holdings->{washed} = $transaction->{washed};
    $holdings->{totalbasis} += $transaction->{wash_basis_adjust};
    $lot->{price} += $transaction->{wash_price_adjust};

# And report the transaction.
    print datestr($transaction->{date}), 
	": BUY $transaction->{shares} shares at @{[$transaction->{price} // 0]} ",
	"for @{[$transaction->{amount} // 0]}\n";

    show_totals $holdings;
} # run_buy

sub do_wash_sale_fifo {
    my $holdings = shift;
    my $remaining_transactions = shift;
    my $trans_date = shift;
    my $trans_shares = shift;
    my $trans_loss = shift;
    local $_;
    my $wash_total = 0;

    my $loss_per_share = $trans_loss / $trans_shares;

    for (@{$holdings->{lots}}) {
	
	next if $_->{shares} == 0;
	last if $trans_shares < $SHARETOL;
	
	if (thirty_days $_->{date}, $trans_date) {
	    
	    my $wash_shares = $_->{shares} - $_->{washed};

# skip if no shares left to wash
	    next if $wash_shares < $SHARETOL;

	    if ($wash_shares > $trans_shares) {
		$wash_shares = $trans_shares;
	    }

	    my $wash_amt = $wash_shares * $loss_per_share;

	    $wash_total += $wash_amt;
	    
	    print " ** Wash sale for lot ", datestr($_->{date}), 
		": ", cents($wash_amt), " ($wash_shares shares)\n";

# Adjust share prices upwards to account for the wash sale in future FIFO
# cost basis calculations. We assume the wash sale amount is spread out
# evenly over all the shares in that lot. The IRS publications do not
# specify how this is to be done.
	    $_->{price} += $wash_amt / $_->{shares};

	    $trans_shares -= $wash_shares;
	}
    }

    for (@$remaining_transactions) {

	last if $trans_shares < $SHARETOL;
	next unless is_buy_action $_->{action};

	if (thirty_days $_->{date}, $trans_date) {

	    my $wash_shares = $_->{shares} - $_->{washed};

# skip if no shares left to wash
	    next if $wash_shares < $SHARETOL;

	    if ($wash_shares > $trans_shares) {
		$wash_shares = $trans_shares;
	    }

	    my $wash_amt = $wash_shares * $loss_per_share;

	    $wash_total += $wash_amt;
	    
	    print " ** Wash sale for lot ", datestr($_->{date}), 
		": ", cents($wash_amt), " ($wash_shares shares)\n";

	    $_->{wash_price_adjust} += $wash_amt / $_->{shares};

	    $trans_shares -= $wash_shares;
	}
    }

    if ($wash_total > $SHARETOL) {
	print " *** Wash sale total: ", cents($wash_total), "\n\n";
    }	

} # do_wash_sale_fifo

# This differs from do_wash_sale_fifo in two ways:

# 1) The transaction loss may be different because of the average cost
# basis may be different from the FIFO cost basis.

# 2) The totalbasis is adjusted in do_wash_sale_avbasis rather than the
# share prices of the lots in holdings as in the case of do_wash_sale_fifo.

sub do_wash_sale_avbasis {
    my $holdings = shift;
    my $remaining_transactions = shift;
    my $trans_date = shift;
    my $trans_shares = shift;
    my $trans_loss = shift;
    local $_;
    my $wash_total = 0;

    my $loss_per_share = $trans_loss / $trans_shares;

    for (@{$holdings->{lots}}) {
	
	next if $_->{shares} == 0;
	last if $trans_shares < $SHARETOL;
	
	if (thirty_days $_->{date}, $trans_date) {
	    
	    my $wash_shares = $_->{shares} - $_->{washed};

# skip if no shares left to wash
	    next if $wash_shares < $SHARETOL;

	    if ($wash_shares > $trans_shares) {
		$wash_shares = $trans_shares;
	    }

	    my $wash_amt = $wash_shares * $loss_per_share;

	    $wash_total += $wash_amt;
	    
	    print " ** Wash sale for lot ", datestr($_->{date}), 
		": ", cents($wash_amt), " ($wash_shares shares)\n";

	    $trans_shares -= $wash_shares;
	}
    }

    $holdings->{totalbasis} += $wash_total;

    for (@$remaining_transactions) {

	last if $trans_shares < $SHARETOL;
	next unless is_buy_action $_->{action};

	if (thirty_days $_->{date}, $trans_date) {

	    my $wash_shares = $_->{shares} - $_->{washed};

# skip if no shares left to wash
	    next if $wash_shares < $SHARETOL;

	    if ($wash_shares > $trans_shares) {
		$wash_shares = $trans_shares;
	    }

	    my $wash_amt = $wash_shares * $loss_per_share;

	    $wash_total += $wash_amt;
	    
	    print " ** Wash sale for lot ", datestr($_->{date}), 
		": ", cents($wash_amt), " ($wash_shares shares)\n";

	    $_->{wash_basis_adjust} += $wash_amt;

	    $trans_shares -= $wash_shares;
	}
    }

    if ($wash_total > $SHARETOL) {
	print " *** Wash sale total: ", cents($wash_total), "\n\n";

# Adjust the total cost basis to account for the wash sale.
    }	

} # do_wash_sale_avbasis

sub adjust_washed {
    my $holdings = shift;
    my $remaining_transactions = shift;
    my $trans_date = shift;
    my $trans_shares = shift;
    local $_;

    for (@{$holdings->{lots}}) {
	
	next if $_->{shares} == 0;
	last if $trans_shares < $SHARETOL;
	
	if (thirty_days $_->{date}, $trans_date) {
	    
	    my $wash_shares = $_->{shares} - $_->{washed};

# skip if no shares left to wash
	    next if $wash_shares < $SHARETOL;

	    if ($wash_shares > $trans_shares) {
		$wash_shares = $trans_shares;
	    }

	    $_->{washed} += $wash_shares;
	    $trans_shares -= $wash_shares;
	}
    }

    for (@$remaining_transactions) {

	last if $trans_shares < $SHARETOL;
	next unless is_buy_action $_->{action};

	if (thirty_days $_->{date}, $trans_date) {

	    my $wash_shares = $_->{shares} - $_->{washed};

# skip if no shares left to wash
	    next if $wash_shares < $SHARETOL;

	    if ($wash_shares > $trans_shares) {
		$wash_shares = $trans_shares;
	    }

	    $_->{washed} += $wash_shares;
	    $trans_shares -= $wash_shares;
	}
    }

} # adjust_washed

# Apply a sell transaction to our holdings.
sub run_sell {
    my $transaction = shift;
    my $remaining_transactions = shift;
    my $holdings = shift;

# We have to round down the average cost basis. It appears to be standard
# practice at all mutual fund companies.
    my $avbasis = 
	($holdings->{totalbasis} / $holdings->{totalshares});

# This array holds all the share lots consumed in the sale transaction.
    my @salelots;

# Number of shares to be sold.
    my $saleshares = $transaction->{shares};

# Update the totals.
    $holdings->{totalbasis} -= $avbasis * $saleshares;
    $holdings->{totalshares} -= $saleshares;

# Regardless of the capital gains calculation method, we have to go
# through the holdings lot by lot to determine the holding periods.

    for (@{$holdings->{lots}}) {

# Skip all lots that have already been zeroed out.
	next if $_->{shares} == 0;

	if ($saleshares <= $_->{shares}) {
# The remaining shares to be sold fit in this lot.
	    my $lot = {
		price => $_->{price},
		date => $_->{date},
		shares => $saleshares,
		term => capgain_term($_->{date}, $transaction->{date})
	    };
	    push @salelots, $lot;
	    $_->{shares} -= $saleshares;
	    $saleshares = 0;
	    last;
	}

# Otherwise, this entire lot is consumed.
	my $lot = {
	    price => $_->{price},
	    date => $_->{date},
	    shares => $_->{shares},
	    term => capgain_term($_->{date}, $transaction->{date})
	};
	push @salelots, $lot;
	$saleshares -= $_->{shares};
	$_->{shares} = 0;
    }

# The number of shares sold is greater than the number of shares held. It
# would be very strange if this happened.
# The comparison tests if the shares remaining to be "sold" from the
# current holdings is greater than 0 after going through all of the
# holdings.
    die "share balance below zero\n" if $saleshares > $SHARETOL;

# Report the sale transaction.
    if ($gotsuppfile) {
	print datestr($transaction->{date}), 
	    ": SELL $transaction->{shares} shares at $transaction->{price} ",
	    "for $transaction->{amount}\n";
    }
    else {
	print datestr($transaction->{date}), 
	    ": SELL $transaction->{shares}\n";
    }

# Check if the number of shares has gone to zero or close enough.

    abs $holdings->{totalshares} < $SHARETOL and $holdings->{totalshares} = 0;
    abs $holdings->{totalbasis} < $SHARETOL and $holdings->{totalbasis} = 0;

    show_totals $holdings;

    print "  FIFO:\n";
    my $fifototalbasis = 
	showbasis \@salelots, sub { my $lot = shift; $lot->{price}; };

    my $gotloss = 0;

    if ($gotsuppfile) {
	
	my $loss = $fifototalbasis - $transaction->{amount};

	if ($loss > $SHARETOL) {

	    $gotloss = 1;

	    do_wash_sale_fifo $holdings, $remaining_transactions,
		$transaction->{date},
		$transaction->{shares}, $loss;
	}
    }
	
    print "  Average Cost Basis:\n";
    my $avtotalbasis =
	showbasis \@salelots, sub { $avbasis; };

    if ($gotsuppfile) {

	my $loss = $avtotalbasis - $transaction->{amount};

	if ($loss > $SHARETOL) {

	    $gotloss = 1;

	    do_wash_sale_avbasis $holdings, $remaining_transactions,
		$transaction->{date},
		$transaction->{shares}, $loss;
	}
    }

    if ($gotsuppfile and $gotloss) {
	adjust_washed $holdings, $remaining_transactions,
	    $transaction->{date}, 
	    $transaction->{shares};
    }

} # run_sell

# Apply a stock split to our holdings.
sub run_split {
    my $transaction = shift;
    my $holdings = shift;
    
# For some reason, Quicken reports 10 times the split ratio rather than the
# split ratio itself.

    for (@{$holdings->{lots}}) {
	$_->{shares} *= $transaction->{shares} / 10;
	$_->{price} /= $transaction->{shares} / 10;
    }

    $holdings->{totalshares} *= $transaction->{shares} / 10;

    print datestr($transaction->{date}), 
	": STOCK SPLIT ", $transaction->{shares} / 10, " for 1\n";

    show_totals $holdings;
    
} # run_split

sub run_transaction {
    my $transaction = shift;
    my $remaining_transactions = shift;
    my $holdings = shift;

    if (is_buy_action $transaction->{action}) {
	run_buy $transaction, $holdings;
    }

    elsif (is_sell_action $transaction->{action}) {
	run_sell $transaction, $remaining_transactions, $holdings;
    }

    elsif ($transaction->{action} eq "StkSplit") {
	run_split $transaction, $holdings;
    }

    else {
# Ignore transaction and don't show lots.
	return;
    }

    showlots @{$holdings->{lots}};
} # run_transaction

# Read supplemental information file.
#
# File format:
# Security security-name
#	Names the security with which the following transactions are
#	concerned. This must match the security name in the QIF file
#	exactly.
# Sale date price shares
#	States the price that the security was sold at on that date. For
#	now, if multiple sales occurred on that date, they are assumed to
#	have occurred at the same price.

sub read_supp {
    my $fname = shift;
    my $supp_trans = shift;
    local $_;
    my $security = '';

    my $fh = new FileHandle;
    $fh->open($fname, "r") or die "can't open $fname for reading: $!\n";

    while (<$fh>) {
	chomp;

	my ($cmd, $param) = split ' ', $_, 2;

	if (uc($cmd) eq "SECURITY") {
	    $security = $param;
	}
	elsif (uc($cmd) eq "SALE") {

	    my ($date, $price, $amount, $shares) = split ' ', $param;
	    my $curtrans = {};

	    $curtrans->{price} = $price;
	    $curtrans->{amount} = $amount;
	    $curtrans->{shares} = $shares;
	    $curtrans->{date} = parse_date $date;

# Add the record to the transaction array.
	    if ($security ne '') {
		if (defined $supp_trans->{$security}) {
		    push @{$supp_trans->{$security}}, $curtrans;
		}
		else {
		    $supp_trans->{$security} = [ $curtrans ];
		}
	    }
	}
    }

    $fh->close;

} # read_supp

sub merge_supp {
    my $main_trans = shift;
    my $supp_trans = shift;

# Try to find a match for each security.
    for my $security (keys %$supp_trans) {
	defined $main_trans->{$security} or
	    die "Security $security in supplemental file does not exist in QIF file\n";

# Try to find a match for each transaction in each security.
	for my $transaction (@{$supp_trans->{$security}}) {

	    my $match = 0;
	    
	    for my $findtrans (@{$main_trans->{$security}}) {
		if (date_equal($transaction->{date}, $findtrans->{date}) and
			$transaction->{shares} == $findtrans->{shares} and
			not defined $findtrans->{price}) {

		    $findtrans->{price} = $transaction->{price};
		    $findtrans->{amount} = $transaction->{amount};
		    $match = 1;
		    last;
		}
	    }

	    $match or die "can't find matching transaction for sale of " .
		$security . " on " . 
		datestr($transaction->{date}) . " for " .
		$transaction->{shares} . " shares\n";
	}
    }

} # merge_supp

# Make sure every sale transaction has a price.
sub check_trans {
    my $main_trans = shift;

    for my $security (keys %$main_trans) {
	for my $trans (@{$main_trans->{$security}}) {
	    defined $trans->{price} or
		die "No price for sale of $security on " .
		    datestr($trans->{date}) . " for " .
		    $trans->{shares} . " shares\n";
	}
    }
} # check_trans

my $USAGE = <<EOM;
Usage: $0 [-l] QIF-file [supp-file]
	-l: Show share lots after each transaction.
EOM

# The -l option shows the list of share lots after each transaction.
getopts('l') or die "$USAGE\n";
$showlots = 1 if defined $::opt_l and $::opt_l;

@ARGV >= 1 or die "$USAGE\n";

# Transactions grouped by security.
my %g_trans;
my %supp_trans;

my $infile = shift;

read_qif $infile, \%g_trans;

my $suppfile = shift;
if (defined $suppfile) {
    $gotsuppfile = 1;
    read_supp $suppfile, \%supp_trans;
    merge_supp \%g_trans, \%supp_trans;
    check_trans \%g_trans;
}

for my $security (keys %g_trans) {
    my %holdings;
    $holdings{totalbasis} = 0;
    $holdings{totalshares} = 0;

    print "Transactions for $security\n\n";

# Make a copy of the transaction list.
    my @transactions = ( @{$g_trans{$security}} );
    while (@transactions) {
	my $transaction = shift @transactions;
	run_transaction $transaction, \@transactions, \%holdings;
    }
}
    
# vim:sw=4 tw=75 fo=cq

__END__
