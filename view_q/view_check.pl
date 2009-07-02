require 5.001;
use strict;

# get server log
# modify server log (get relevant entries)
# execute list of relevant view
# post to logfile

# Getting the script dir
our ( $scriptdir, $scriptfile );
BEGIN { if ($0 =~ /(.*[\/\\])(.*)$/){
  $scriptdir = $1; $scriptfile = $2; } else {
  $scriptdir = ""; $scriptfile = $0; }
}

# Use clauses
use lib "$scriptdir..";
use Getopt::Long;
use praqma::scriptlog;

# Log and monitor default settings (overwriteable at execution)
my $debug = 0; 
my $verbose_mode=0;
my $log_enabled=1;

# File version
our $VERSION      = "0.0.1";
our $BUILD        = "0";

our $header = <<ENDHEADER;
#########################################################################
#     $scriptfile  version $VERSION\.$BUILD
#     This script is supposed to run as a scheduled task
#     It's purpose is to register all views in use and touch them
#     so that the last accessed timestamp is updated.
#
#     Used with the view cleanup script view_q.pl
#
#     Date:       2009-06-29
#     Author:     Mikael Jensen MIJ\@praqma.net
#     Copyright:  Praqma A/S, Denmark
#     License:    GNU General Pulic License
#     Support:    http://www.praqma.info
#########################################################################

ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR         NOTE
----------  -------------  ----------------------------------------------
2009-03-25  Mikael Jensen  Initial development version

-------------------------------------------------------------------------

ENDREVISION

my $usage = <<ENDUSAGE;
  
  $scriptfile [switches]
  --- Switches ---
  -since YYYY-MM-DD
  -logfile [logfilename]
  -verbose

ENDUSAGE

my $doc = <<ENDDOC;

-help                   Get help with the script syntax etc. (you are watching it now)

                        --- Auxiliary switches (can be omitted or used on all functions)---
-[no]logfile [location] Sets whether or not to create a logfile.
                        May define the name [and location] of the logfile.
                        Default value is the temp dir (usually under users "doc&set") and "view_q.pl[PID].log"
-[no]verbose            Toggles verbose mode (log to STDOUT)
                        Default is off (for manual execution, verbose is recommended)
-[no]debug              Toggles debug mode (additional information + force logfile + verbose)
                        Default is off


ENDDOC

### Usual stuff ###
our $log = scriptlog->new;
my ($debug, $verbose, $log_enable);

### Useable variables ###
my $log_file=$scriptdir."view_check.log";
my $prev_exe_datetime;
my $gotlog;

### Arrays for log processing ###
my (@fulllog, @views);

### Switch arguments ###
our ($sw_since, $sw_logfile, $sw_debug, $sw_verbose, $sw_help);

### Execution order ###
validate_options();
help_mode();
### Determin if previous logfiles exists ### 
if (-e $log_file) {
	getlastexecution();
	enable_log();
	$log->information("Log found, last run time was $prev_exe_datetime \n");
} else {
	enable_log();
	$log->information("No previous log was found, defaulting to all\n");
}
### Log processing ###
get_the_log();
touch_views();

### Final line ###
$log->information("done");




=head1 Script Implementation

=head2 Internal subfunctions

=head3 validate_options( )

The sub-functions read the options and switches applied with the execution into
the global variables that are defined to cache them.

The function will kill the script execution if unknown switches are used.

Parameters:

  none

Returns:

  nothing

=cut

sub validate_options(){
  my %options = ( "since=s"            => \$sw_since,
                  "help!"              => \$sw_help,
                  "logfile=s"          => \$sw_logfile,
                  "debug!"             => \$sw_debug,
                  "verbose!"           => \$sw_verbose);

  die "$usage" unless GetOptions(%options);
#  GetOptions(%options);
};

sub enable_log(){
=head3 enable_log( )

The sub-function overwrites the default settings for log, debug and verbose if set manually and enables the functionality in the logger.

debug:
- enables verbose, unless -noverbose is set in the script call.
- enables the logfile
- gives some extra logging information (variable values, additional information, ect.)

verbose:
- enables log to STDOUT

logfile [filename]:
- enables the logfile (default on)
- sets the logfilename (and path) if specified (default name [scriptdir]\view_check.log)
- the environment variables SCRIPTLOG_ENABLED or CLEARCASE_TRIGGER_DEBUG forces the logfile to enable, not matter what

Checks for ARGV arguments (unreferenced values):
- if log is enabled, it dies if there is more then one (expect it to be filename or relative/absolute path AND filename)
- if log is disabled, it dies if there are any
- The logger module fails, if the specified log, can't be opened/created

Parameters:

  Non
  Uses -verbose, -debug and -logfile

Returns:

  nothing (unless it dies)

exit:

  Will kill the script exit 1 (die) on ARGV errors - printing the arguments

=cut
    # Overwrites the default logging setting, if set manually
    defined($sw_debug) && do {$debug=$sw_debug} && ($verbose=1);
    defined($sw_verbose) && do {$verbose=$sw_verbose};
    defined($sw_logfile) && do {$log_file=$sw_logfile};

    # Checks ARGV for consistency and enables the log
    if (scalar(@ARGV) gt 0) {
        $log->assertion_failed("You have value(s) (@ARGV) with no defined reference,\n$usage");
    }
    $log->set_logfile($log_file);
    $log->enable();

    # Sets verbose
    $verbose
      && do {
        $log->set_verbose(1);
        $log->information("Verbose is ON\n");
      };

    # Sets debug
    $debug
      && do {
        $log->enable();
        $log->set_verbose(1);
        $log->information("DEBUG is ON\n");
        #rw2 subject for revision: dynamic dump of sw_options (for each key in %options)
      };
}

sub help_mode(){
  defined($sw_help) && do {print $header.$revision.$usage.$doc; exit 0;};
};


sub getlastexecution(){
    open PREV_LOG_FILE ,"$log_file"  or die "Couldn't open '$log_file'\n";
    my @previouslog = reverse <PREV_LOG_FILE>;
    foreach (@previouslog) {
    	if (/(\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d\+\d\d)/) {
    		$prev_exe_datetime = $1; 
    		$gotlog = 1;
    		last;
    	}
    }
    if (!$prev_exe_datetime) {
    	$prev_exe_datetime = "not found. Defaulting to all";
    }
}	

sub get_the_log(){
	if ($gotlog) {
		@fulllog = `cleartool getlog -host %COMPUTERNAME% -since $prev_exe_datetime view`;
	} else {
		@fulllog = `cleartool getlog -host %COMPUTERNAME% -full view`;
	}
    
    foreach (@fulllog){
     /(\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d\+\d\d).*Using view (.*), on host/ && push @views, "$1 $2";
    }
}

sub touch_views() {
	foreach (@views) {
		/(\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d\+\d\d) (.*)/;
		my $viewtag = `cleartool lsview -short -storage $2`;
		my $viewloc = $2;
		my $viewdate = $1;
		$viewtag =~ s/\s+$//;
	    if ($?) {
	      $log->error("Could not find view at $2\n"); 
	    } else {
	       # insert age validation here
	       `cleartool setcs -tag $viewtag -current`;
	        if ($?) {
	          $log->error("Touch view failed on $viewtag\n"); 
	        } else {
	           $log->information("View $viewloc\'s last access have been updated from $viewdate\n");
	        }
	    }
	}
}
