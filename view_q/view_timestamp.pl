require 5.001;
use strict;

# get server log
# modify server log (get relevant entries)
# execute list of relevant view
# post to logfile

# Getting the script dir
our ( $scriptdir, $scriptfile );

BEGIN {
    if ( $0 =~ /(.*[\/\\])(.*)$/ ) {
        $scriptdir  = $1;
        $scriptfile = $2;
    }
    else {
        $scriptdir  = "";
        $scriptfile = $0;
    }
}

# Use clauses
use lib "$scriptdir..";
use Getopt::Long;
use praqma::scriptlog;

# Log and monitor default settings (overwriteable at execution)
my $debug        = 0;
my $verbose_mode = 0;
my $log_enabled  = 1;

# File version
our $VERSION = "0.1";
our $BUILD   = "3";

our $header = <<ENDHEADER;
#########################################################################
#     $scriptfile  version $VERSION\.$BUILD
#     It is a helper utility to view_q.pl
#
#     This script is supposed to run as a scheduled task
#     It's purpose is to register all views that has been used since last execution
#     and touch them so that the last accessed timestamp is updated.
#
#     It must run on the view-server, and will only process local, dynamic views.
#     Snapshot views are not supported.
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
2009-08-13  Jens Brejner   Bugfixes. Bumped major version. Updated doc-
                           mentation to explain that snapshot views are not sup-
                           ported.
2009-08-13  Jens Brejner   Remove -since switch, it was not implemented, not use-
                           full. Remove documentation too about -since too
                           Adding a new switch (-run).
                           Document that snapshot views are not supported.
-------------------------------------------------------------------------

ENDREVISION

my $usage = <<ENDUSAGE;

  $scriptfile -run [-help] [-[no]logfile pname] [-[no]verbose] [-[no]debug]

ENDUSAGE

my $doc = <<ENDDOC;

-run                    Required in order to execute. Help is displayed if omitted.
-help                   Get help with the script syntax etc. (you are watching it now)
                        --- Auxiliary switches (can be omitted or used on all functions)---
-[no]logfile pname      Sets whether or not to create a logfile.
                        May define the name [and location] of the logfile.
                        Default value is the temp dir (usually under users "doc&set") and "view_q.pl[PID].log"
-[no]verbose            Toggles verbose mode (log to STDOUT)
                        Default is off (for manual execution, verbose is recommended)
-[no]debug              Toggles debug mode (additional information + force logfile + verbose)
                        Default is off

ENDDOC

### Usual stuff ###
our $log = scriptlog->new;
my ( $verbose, $log_enable );

### Useable variables ###
my $log_file = $scriptdir . "view_timestamp.log";    # Default logfile

# REV_1_JBR This comment can be repeated a couple of times
# REV_1_JBR please comment each variable, what is it's purpose
# REV_1_JBR furthermore, you could have grouped all global variables in one place

my $prev_exe_datetime;
my $gotlog;

### Arrays for log processing ###
my ( @fulllog, @views );

### Switch arguments ###
our ( $sw_logfile, $sw_debug, $sw_verbose, $sw_help, $sw_run );

### Execution order ###
&validate_options();

unless ($sw_run) {    #stop running if -run is not on the command line
    print $header. $revision . $usage . $doc;
    exit 0;
}

&help_mode();
### Determin if previous logfiles exists ###

if ( -e $log_file ) {

    &getlastexecution();

    &enable_log();
    $log->information("Log found, last run time was $prev_exe_datetime \n");
}
else {

    &enable_log();
    $log->information("No previous log was found, defaulting to all\n");
}
### Log processing ###

&get_the_log();
&touch_views();

### Final line ###
$log->information("done");

=head1 NAME

view_timestamp.pl - view quarantine utilities

=head1 SYNOPSIS

Updates the last_accessed timestamp of views that are in use, but not written to.

=head1 DECRIPTION

view_timestamp.pl is a auxilary utility that supports the functionality of view_q.pl.
Reason is, that view_q.pl makes used of the "last_accessed" timestamp, with is only updated when an actual write is committed to the view.
view_timestamp.pl scans the ClearCase log for any views opened (read) and forces a recompilation of the configspec, 
which does nothing (as the configspec isn't changed) but updates the timestamp, which then tells view_q.pl that the view is still in use
and thus preventing that the view is quarantined in view_q.pl's scheduled runs.

=head1 SUPPORT

Visit http://wiki.praqma.net/acc/comp/view_q for more information.

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

sub validate_options() {
    my %options = (

        "help!"     => \$sw_help,       # Display help (
        "logfile=s" => \$sw_logfile,    # User supplied log file name.
        "debug!"    => \$sw_debug,      # Debug
        "verbose!"  => \$sw_verbose,    # Verbose output
        "run!"      => \$sw_run         # Do it flag, the script will only attempt to touch views if this switch is on
    );

    die "$usage" unless GetOptions(%options);
}

sub enable_log() {

=head3 enable_log( )

The sub-function overwrites the default settings for log, debug and verbose if set manually and enables the functionality in the logger.

debug:
- enables verbose, unless -noverbose is set in the script call.
- can be extended to give additional information during execution (not implemented)

verbose:
- enables log to STDOUT

logfile "filename":
- sets the logfilename (and path) if specified (default name [scriptdir]\view_check.log)

Checks for ARGV arguments (unreferenced values):
- if log is enabled, it dies if there is more then one (expect it to be filename or relative/absolute path AND filename)
- if log is disabled, it dies if there are any
- The logger module fails, if the specified log, can't be opened/created

Parameters:

  Non
  Uses -verbose, -debug and -logfile "filename"

Returns:

  nothing (unless it dies)

exit:

  Will kill the script exit 1 (die) on ARGV errors - printing the arguments

=cut

    # Overwrites the default logging setting, if set manually
    defined($sw_debug) && do { $debug = $sw_debug }
      && ( $verbose = 1 );
    defined($sw_verbose) && do { $verbose  = $sw_verbose };
    defined($sw_logfile) && do { $log_file = $sw_logfile };

    # Checks ARGV for consistency and enables the log
    if ( scalar(@ARGV) gt 0 ) {
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

sub help_mode() {

=head3 help_mode( )

Prints the help and exits

Returns:

  Header, revision and extended usage information

Exit:

  Always

=cut

    defined($sw_help) && do { print $header. $revision . $usage . $doc; exit 0; };
}

sub getlastexecution() {

=head3 getlastexecution( )

  Opens the previous logfil (if it exsists) and gets the last datetime-stamp in CC format or an error msg.

Returns:

  Last logentry in CC datetime format or textstring explaining it was not found (saved in global variable)

Exit:

  Dies if logfile can't be opened

=cut

    open PREV_LOG_FILE, "$log_file" or die "Couldn't open '$log_file'\n";
    my @previouslog = reverse <PREV_LOG_FILE>;
    foreach (@previouslog) {
        if (/(\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d\+\d\d)/) {

            # REV_1_JBR The regex above could be written as /(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2})/
            # REV_1_JBR which can be simpler to read, or even /([0-9-+T:]*)/
            # REV_1_JBR and it could have been assigned to a pattern, i.e.
            # REV_1_JBR my $pattern = "([0-9-+T:]*)";
            # REV_1_JBR if (/$pattern/) ...

            $prev_exe_datetime = $1;
            $gotlog            = 1;
            last;
        }
    }
    if ( !$prev_exe_datetime ) {
        $prev_exe_datetime = "not found. Defaulting to all";
    }
}

sub get_the_log() {

=head3 get_the_log( )

  Executes "cleartool getlog" based on returns from getlastexecution().
  If getlog is set, it only gets since the time found by getlastexecution().
  If gotlog is not set, it gets the entire log

Returns:

  Array of views found in the getlog execution (saved in global variable)

Exit:

  No

=cut

    if ($gotlog) {

        # CHG in Build 3, -host switch does not make sense, we are only working on view servers
        # @fulllog = `cleartool getlog -host %COMPUTERNAME% -since $prev_exe_datetime view`;
        @fulllog = `cleartool getlog -since $prev_exe_datetime view`;
    }
    else {

        # CHG in Build 3, -host switch does not make sense, we are only working on view servers
        # @fulllog = `cleartool getlog -host %COMPUTERNAME% -full view`;
        @fulllog = `cleartool getlog -full view`;
    }

    foreach (@fulllog) {
        /(\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d\+\d\d).*Using view (.*), on host/ && push @views, "$1 $2";
    }
}

sub touch_views() {

=head3 touch_views( )

  Touches (updates last access datetime-stamp) all views found in get_the_log()


Returns:

  Nothing

Exit:

  No (but last sub)

=cut

    # REV_1_JBR     This construction will be hard to maintain.
    # REV_1_JBR         I think you should have created a couple more minor functions

    foreach (@views) {
        /(\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d\+\d\d) (.*)/;
        my $viewdate = $1;
        my $viewloc  = $2;
        my ( $viewUNC, $viewnotstranded, $error );

        $debug && $log->information("processing $viewloc from $viewdate\n");

        # Skip views that are not dynamic
        my $dynview = grep { /dynamic/ } grep { /^Properties:/ } qx(cleartool lsview -region * -properties -full -storage $viewloc 2>&1);
        unless ($dynview) {
            $log->warning("snapshot view ? at least we did not find dynamic view at $viewloc - trying next view\n");
            next;
        }
        else {
            $debug && $log->information("Found dynamic view at $viewloc - continue\n");
        }

        #
        my $viewtag = `cleartool lsview -short -storage $viewloc 2>&1`;
        if ($?) {
            if ( $viewtag =~ /Unable to open file/ ) {
                $log->error("Could not find location $viewloc (deleted?)\n");
            }
            else {
                if ( $viewtag =~ /No view tags found/ ) {
                    $debug && $log->warning("viewtag not found\n");

                    # REV_1_JBR The next loop should have been a seperate sub
                    foreach my $region (`cleartool lsregion`) {
                        chomp($region);
                        $viewUNC = `cleartool lsview -region $region -storage $viewloc 2>&1`;
                        if ($?) {
                            $debug && $log->information("View was not found in $region\n");
                        }
                        else {
                            $log->information("View is in $region\n");
                            $viewUNC =~ /(\\\\.*)/;
                            $viewUNC = $1;
                            $debug && $log->information( $viewUNC . "\n" );
                            $viewnotstranded = 1;
                            last;    #breaks foreach
                        }    #end if/else (view found in region)
                    }    #end foreach
                    if ($viewnotstranded) {
                        $debug && $log->information("View is not stranded - processing\n");

                        # insert mktag, setcs and rmtag
                        my $mktagcmd = "cleartool mktag -view -tag VIEW_CHECK_TEMP_TAG $viewUNC 2>&1";
                        my $setcscmd = "cleartool setcs -tag VIEW_CHECK_TEMP_TAG -current 2>&1";
                        my $rmtagcmd = "cleartool rmtag -view VIEW_CHECK_TEMP_TAG 2>&1";

                        $debug && $log->information("$mktagcmd\n");
                        system("$mktagcmd");
                        if ($?) {
                            $log->error( "Make tag failed with exitcode: " . ( $? / 256 ) . "\n" );
                            next;    #Continues on next view
                        }
                        else {
                            $debug && $log->information("Make tag successful\n");
                        }
                        $debug && $log->information("$setcscmd\n");
                        system("$setcscmd");
                        if ($?) {
                            $log->error( "setcs failed with exitcode: " . ( $? / 256 ) . "\n" );
                            system("$rmtagcmd");
                            if ($?) {
                                $log->error( "rmtag failed with exitcode: " . ( $? / 256 ) . "\n" );    #/ #EPIC syntax highlight fixer

                            }
                            else {
                                $log->information("   but rmtag successful\n");
                            }
                            next;                                                                       #Continues on next view
                        }
                        else {
                            $log->information("setcs successful for $viewUNC\n");
                        }
                        $debug && $log->information("$rmtagcmd\n");
                        system("$rmtagcmd");
                        if ($?) {
                            $log->error( "rmtag failed with exitcode: " . ( $? / 256 ) . "\n" );        #/ #EPIC syntax highlight fixer
                            next;                                                                       #Continues on next view
                        }
                        else {
                            $debug && $log->information("rmtag successful\n");
                        }
                        $log->information("View $viewloc\'s last access have been updated from $viewdate\n");

                    }
                    else {
                        $log->warning("View is stranded (quarantined?) skipping\n");
                    }    #end if/else (viewnot stranded)
                }
                else {
                    $log->error("Unhandled error found:\n$viewtag ");
                }    #end if/else (viewtag not found)
            }    #end if/else (location found)
        }
        else {
            $viewtag =~ s/\s+$//;

            my @return = `cleartool setcs -tag $viewtag -current 2>&1`;
            if ($?) {
                $log->error("Touch view failed on $viewtag\n");
                foreach (@return) {
                    chomp;
                    $log->error("\t$_\n");

                }
            }
            else {
                $log->information("View $viewloc\'s last access have been updated from $viewdate\n");
            }    #end if/else (error setcs)
        }    #end if/else (viewtag found)
    }    #end foreach
}    #end sub


