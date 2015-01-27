require 5.000;
use strict;
$| = 1;
our ( $Scriptdir, $Scriptfile );

BEGIN {
    use File::Basename;
    $Scriptdir  = dirname(__FILE__) . "\\";
    $Scriptfile = basename(__FILE__);
}

#######
#
# This is a small utility script to list ACC vob types
#
#######

# Use clauses
use File::Basename;
use File::Temp;
use Getopt::Long;
use Cwd;
use lib "$Scriptdir../../praqma";
use trigger_helper;
use scriptlog;
use pcc 0.1011;
use acc;


chdir $ENV{SYSTEMDRIVE};

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;

# Initiate logging.
our $log = scriptlog->new;
my $pccObject = pcc->new;

#Define either environment variabel CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
#$log->enable(0);
#$log->set_verbose(1);

our $logfile = $log->get_logfile();
($logfile) && $log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.

#############################################  M A I N #####################################################

my ( @vobs, $vob, @vobtypes, $i );

# get a list of all vobs
@vobs = @{ $pccObject->get_vobtags() };
#@vobs = ( '\\bbComponent' );

# get vob acc types for each vob
foreach $vob (@vobs)
{
    @vobtypes = acc::get_vobtypes($vob);
    print "Vob ($vob) is of type(s): ";
	foreach $i (@vobtypes)
    {
	    print $i . " ";
	}
	print "\n";
}
