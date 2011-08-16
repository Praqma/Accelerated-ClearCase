require 5.000;
use strict;

BEGIN {

	# Ensure that the view-private file will get named back on rejection.
	END {
		rename( "$ENV{CLEARCASE_PN}.mkelem", $ENV{CLEARCASE_PN} )
		  if $? && !-e $ENV{CLEARCASE_PN} && -e "$ENV{CLEARCASE_PN}.mkelem";
	}
}

#Getting the script dir
our ( $Scriptdir, $Scriptfile );

BEGIN {
	if ( __FILE__ =~ /(.*[\/\\])(.*)$/ ) {
		$Scriptdir  = $1;
		$Scriptfile = $2;
	}
	else {
		$Scriptdir  = "";
		$Scriptfile = __FILE__;
	}
}
use File::Basename;
use lib $Scriptdir. "..";
use praqma::scriptlog;
use praqma::trigger_helper;

#Required if you call trigger_helper->enable_install
our $TRIGGER_NAME   = "ACC_RENAME_HISTORY";
our %install_params = (
	"name"     => $TRIGGER_NAME,    # The name og the trigger
	"mktrtype" =>
	  "-postop lnname -element -all",    # The stripped-down mktrtype command
	"supports" => "bccvob,ucmvob"
	,    # csv list of generic and/or custom VOB types (case insensetive)
);

# File version
our $VERSION  = "0.1";
our $REVISION = "1";
my $verbose_mode = 1
  ; # Setting the verbose mode to 1 will print the logging information to STDOUT/ERROUT ...even it the log-file isn't enabled
my $debug_on =
  defined( $ENV{'CLEARCASE_TRIGGER_DEBUG'} )
  ? $ENV{'CLEARCASE_TRIGGER_DEBUG'}
  : undef;

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$REVISION
#     This script is intended as ClearCase trigger script for the
#     $TRIGGER_NAME trigger.
#
#     The trigger adds history to renamed elements
#
#     This script supports self-install (execute with the -install
#     switch to learn more).
#
#     Read the POD documentation in the script for more details
#     Date:       2011-08-04
#     Author:     Jens Brejner, jbr\@praqma.net
#     Copyright:  Praqma A/S
#     License:    GNU General Public License v3.0
#     Support:    http://launchpad.net/acc
#########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR         		NOTE
----------  ------------   		----------------------------------------------

2011-08-04  Margit Bennetzen	Script created (based on evil twin)

------------------------   		----------------------------------------------

ENDREVISION

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;
$thelp->enable_install( \%install_params )
  ;    #Pass a reference to the install-options
$thelp->require_trigger_context;

# Look for semaphore, respecting a local semaphore path via env. var.
our $semaphore_status =
  $thelp->enable_semaphore_backdoor( $ENV{'CLEARCASE_USE_LOCAL_SEMAPHORE'} );

# Initiate logging.
our $log = scriptlog->new;

#Define either environment variabel CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->conditional_enable();
$log->enable(1);

#Define either environment variabel CLEARCASE_TRIGGER_VERBOSE=1 or SCRIPTLOG_VERBOSE=1 to start printing to STDOUT
$log->set_verbose($verbose_mode);
our $logfile = $log->get_logfile();
($logfile)
  && $log->information("logfile is: $logfile\n")
  ;    # Logfile is null if logging isn't enabled.
($logfile) && $log->information($semaphore_status);

#my $length = length($ENV{CLEARCASE_PN2});
#($logfile) && $log->information("length:"+$length);
# ($logfile) &&
$log->dump_ccvars
  ;    # Run this statement to have the trigger dump the CLEARCASE variables

#Finds renamed files
my $path  = dirname( $ENV{CLEARCASE_PN2} );
my @reply = `cleartool diff -pre  $path 2>&1`;

my @result;
my $on = 0;
foreach (@reply) {

	if ( $on == 0 ) {
		if ( $_ =~ /^-------------/ ) {
			$log->information($_);
			$on = 1;
			push( @result, $_ );
		}
	}
	else {

		$on = 0;
		push( @result, $_ );
	}

}

foreach (@result) {
	#use `cleartool chevent -c "added comment" . ` search for filename between | and whitespace 
	$log->information($_);
}
__END__

	
