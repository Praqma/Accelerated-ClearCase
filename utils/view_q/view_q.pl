######################## STANDARD STUFF ##############################

require 5.001;
use strict;

=head1 NAME

view_q.pl - View Quarantine Utilities

=head1 SYNOPSIS

A collection of features that enables quarantine, purge and recover of views based on
the view's 'last accessed' date.

Execute the script with -help switch to learn the syntax and usage.

=head1 DESCRIPTION

A fundamental concept to understand when working with view_q.pl is "Stranded views".

Stranded views are views that have valid (and registered) view storages, but haven't got any
view tags in any region.

Stranded views are unavailable for use, but can easily be brought back to availability by using:

  cleartool mktag -view ...

Clearcase has a feature called rgy_check (which is only available on ClearCase registry servers
though!). Rgy_check utility can report stranded views.

  rgy_check -views

Run cleartool man rgy_check to learn more.

When view_q.pl puts a view into quarantine, it removes all tags in all regions. This puts the
view into the state of being 'stranded'. An important difference between 'regular" stranded
and views put into quarantine by view_q.pl is the file called

  .view_quarantine

which view_q.pl created in the in the 'admin' subfolder in the view storage. This file contains the history
of tags in all regions from where they were deleted. and enables a complete restore of which can be done from
any machine with ClearCase installed.

View_q.pl can be run in a mode where it lists all views not accessed since a certain date. if you whish you
can even tell view_q.pl to automatically put these views into quarantine.

View_q.pl has a different mode which lists all views that are currently in quarantine (As you may have figured
out this is partly determined by the fact that views are stranded, so this mode only works when executed from
the ClearCase Registry server, which support rgy_check!)

When listing the quarantined views you can either automatically purge or recover the views.

Views can also be purged or recovered individually.

When view_q.pl purges a view it simply re-creates an intermediate view tag and runs a regular

  cleartool remove view

When a view is recovered by view_q.pl it simply restores all tags in all the regions where it was removed from.

Some views aren't supposed to be deleted even when they haven't been accessed for a long time. View_q.pl can
be instructed to disable quarantine of these views.

=head1 SUPPORT

Visit http://www.praqma.net to get help.

=cut

# Getting the script dir
our ( $Scriptdir, $Scriptfile );

BEGIN {
    if ( $0 =~ /(.*[\/\\])(.*)$/ ) {
        $Scriptdir  = $1;
        $Scriptfile = $2;
    } else {
        $Scriptdir  = ".";
        $Scriptfile = $0;
    }
}

use lib "$Scriptdir\\..\\..";

use Getopt::Long;
use praqma::scriptlog;

# File version
#rw2 What version are we on now?
our $VERSION = "0.4.0";
our $BUILD   = "4";

# Log and monitor default settings (overwriteable at execution)
my $debug        = 0;    # Set 1 for testing purpose
my $verbose_mode = 0;
my $log_enabled  = 1;

# Default setting 0-0-1 (script executio9n will generate NO output unless explicitly told to, but logs to default location [Temp dir]\view_q.pl.[PID].log

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$BUILD
#     This script is managing views based on their last accessed dates.
#     The script has several different features for taking views in and
#     out of quarantine.
#     Execute with -help switch to learn more
#
#     Date:       2009-03-25
#     Author:     Lars Kruse, lars.kruse\@praqma.net
#     Copyright:  Praqma A/S, Denmark
#     License:    GNU General Pulic License
#     Support:    http://www.praqma.info
#########################################################################

ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR  NOTE
----------  -------------  ----------------------------------------------
2009-03-25  Lars Kruse     1st release prepared for RUG-DK (version 0.1.1)
2009-05-18  Mikael Jensen  Beta for test
                           New: scriptlogger (logfile, verbose & debug)
                           New: Ignore split into ignore and noignore func
                           New: [no]ignore now take more params and semicolon-seperated lists
                           New: ARGV[0] is always logfile ARGV[1] fails
                           Doc: Usage, Help and POD doc updated to include new features
                           fixed: nasince
2009-06-12                 Initial test for production release
                           Lib added to parent folder
                           Perl module required praqma::scriptlog
2009-09-21  Jens Brejner   Chg. use lib statement to match reorganized module locations
                           Source formatting, minor syntax changes weeding out some warnings.


-------------------------------------------------------------------------

ENDREVISION

my $usage = <<ENDUSAGE;
  $Scriptfile -lsquarantine [-autopurge | -autorecover]
  $Scriptfile -nasince YYYY-MM-DD [-autoquarantine]
  $Scriptfile -quarantine stgloc
  $Scriptfile -recover stgloc
  $Scriptfile -purge stgloc
  $Scriptfile [-region region] -[no]ignore viewtag
  $Scriptfile -help
  Auxiliary switches [-[no]debug | -[no]verbose | -[no]logfile [location]

ENDUSAGE

my $doc = <<ENDDOC;

-help                   Get help with the script syntax etc. (you are watching it now)
-lsquarantine           List views that are currently in quarantine.
                        NOTE: This switch is only supporten when executed on
                        ClearCase Registry server.
-autopurge              Optional switch only valid together with -lsquarantine.
                        When -autopurge is applied the storages found by -lsquarantine
                        will automatically be purged (permanently deleted)
-autorecover            Optional switch only valid together with -lsquarantine.
                        When -autorecover is applied the storages found by -lsquarantine
                        will automatically be recovered.
-nasince date           Lists views that are not accessed since date. Date must
                        be in the format YYYY-MM-DD.
-autoquarantine         Optional swith only valid together with -nasince. When
                        -autoquarantine is applied the views found be -nasince will be
                        put into quarantine.
-quarantine stgloc      Will put the viewstg applied as stglog into quarantine. The format
                        of stgloc must be the global path (as listed with lsview).
-recover stgloc         Will recover the viewstg applied as stgloc out of quarantine. The
                        format of stgloc can be the global path (as listed with lsview).
                        or the local path (as listed by rgy_check, stranded views).
-purge stgloc           Will purge (rmview) the viewstg applied as stgloc. The
                        format of stgloc can be the global path (as listed with lsview).
                        or the local path (as listed by rgy_check, stranded views).
-[no]ignore viewtag     -ignore will make the view ignoring any attempt to put it into
                        quarantine until the ignore flag is removed using -noignore.
                        -nasince will still report he correct last accessed date.
                        multible viewtags can be use, by adding more -ignore option
                        or seperating with ";" eg. "... -ignore tag1;tag2 -ignore tag3"
-region region          Optional switch only valid together with -[no]ignore.
                        The region switch is used to qualify the viewtag applied with
                        -[un]ignore if necessary. if -region is omitted, the viewtag is
                        searched in the current region.

                        --- Auxiliary switches (can be omitted or used on all functions)---
-[no]logfile [location] Sets whether or not to create a logfile.
                        May define the name [and location] of the logfile.
                        Default value is the temp dir (usually under users "doc&set") and "view_q.pl[PID].log"
-[no]verbose            Toggles verbose mode (log to STDOUT)
                        Default is off (for manual execution, verbose is recommended)
-[no]debug              Toggles debug mode (additional information + force logfile + verbose)
                        Default is off


ENDDOC

### Global variables ###

our %stg_directory;
our $log                = scriptlog->new;
our $view_q_file        = ".view_quarantine";
our $view_q_ignore_file = ".view_q_ignore";
our (
    $sw_lsquarantine, $sw_recover, $sw_purge,    $sw_nasince,     $sw_quarantine, $sw_autoquarantine, $sw_autopurge, $sw_help,
    $sw_region,       @sw_ignore,  @sw_noignore, $sw_autorecover, $sw_logfile,    $sw_verbose,        $sw_debug
);
our $argstring;

if (@ARGV) {
    foreach (@ARGV) {
        $argstring = $argstring . "$_ ";
    }
}

&validate_options();

#### SWITCH ####
&help_mode();
&enable_log();
&lsquarantine_mode();
&purge_mode();
&nasince_mode();
&quarantine_mode();
&ignore_mode();
#### SWITCH ####
$log->assertion_failed( "Wrong syntax\n" . $usage );
###########################################################################################

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
        "autoquarantine" => \$sw_autoquarantine,
        "lsquarantine"   => \$sw_lsquarantine,
        "nasince=s"      => \$sw_nasince,
        "help"           => \$sw_help,
        "quarantine=s"   => \$sw_quarantine,
        "recover=s"      => \$sw_recover,
        "purge=s"        => \$sw_purge,
        "autopurge"      => \$sw_autopurge,
        "autorecover"    => \$sw_autorecover,
        "ignore=s"       => \@sw_ignore,
        "noignore=s"     => \@sw_noignore,
        "region=s"       => \$sw_region,
        "logfile!"       => \$sw_logfile,
        "debug!"         => \$sw_debug,
        "verbose!"       => \$sw_verbose
    );

    #  die "$usage" unless GetOptions(%options);
    GetOptions(%options);
}

=head3 enable_log( )


The sub-function overwrites the default settings for log, debug and verbose if set manually and enables the functionality in the logger.
Prefix option name with "no" for force disable (e.g. -nodebug)

Debug:
- enables verbose, unless -noverbose is set in the script call.
- enables the logfile
- gives some extra logging information (variable values, additional information, ect.)

Verbose:
- enables log to STDOUT

Logfile:
- enables the logfile
- sets the logfilename (and path) if specified
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

sub enable_log() {

    # Overwrites the default logging setting, if set manually
    defined($sw_debug) && do { $debug = $sw_debug }
      && ( $verbose_mode = 1 );
    defined($sw_verbose) && do { $verbose_mode = $sw_verbose };
    defined($sw_logfile) && do { $log_enabled  = $sw_logfile };

    my $argv_values;
    foreach (@ARGV) {
        $argv_values = $argv_values . "\"" . $_ . "\" ";    #rw2 use join

    }

    # Checks ARGV for consistency and enables the log
    if ($log_enabled) {
        if ( scalar(@ARGV) gt 1 ) {
            $log->assertion_failed(
                "You have more then one value with no defined reference,\nonly valid option is logfile location \nRecorded values are:$argv_values");
        }
        $log->set_logfile( $ARGV[0] );
        $log->enable();
    } else {
        if ( scalar(@ARGV) gt 0 ) {
            $log->assertion_failed("You have value(s) with no defined reference,\nRecorded values are: $argv_values");
        }    # end if scalar(argv)
        $log->conditional_enable();
    }    # end if logfile

    # Sets verbose
    $verbose_mode
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
        $log->information(
"Dumping all switch variables \n autoq = '$sw_autoquarantine' \n lsq = '$sw_lsquarantine' \n nas = '$sw_nasince' \n help = '$sw_help' \n quaran = '$sw_quarantine' \n recov = '$sw_recover' \n purge = '$sw_purge' \n autop = '$sw_autopurge' \n autor = '$sw_autorecover' \n igno = '@sw_ignore' \n reg = '$sw_region' \n noigno = '@sw_noignore' \n reg = '$sw_region' \n log = '$sw_logfile'+"
              . $log->get_logfile()
              . " \n debug = '$sw_debug' \n ver = '$sw_verbose' \n ARGV = $argv_values \n" );
        $log->information("ARGV value checks OK");
      };
    $log->information( "Called with " . $argstring . "\n" );
}

=head3 xxx_mode( )

The sub-functions named xxx_mode all work as switches.

They all start by checking the options and switches applied with the execution to see if the have any work
to do. if so, they take full responsibility over the remainder of the script execution and exits the script
with either 1 or 0;


Parameters:

  none

Returns:

  nothing

exit:

Will force the entire script to exit with 0 or 1

  1  =   Wrong set of switches applied
  0  =   Successful execution

=cut

sub help_mode() {
    defined($sw_help) && do { print $header. $revision . $usage . $doc; exit 0; };
}

sub recover_mode() {
    defined($sw_recover) && do {
        $log->information("recover\n");
        if (   defined($sw_lsquarantine)
            || defined($sw_purge)
            || defined($sw_nasince)
            || defined($sw_quarantine)
            || defined(@sw_ignore)
            || defined($sw_autoquarantine)
            || defined($sw_autopurge)
            || defined($sw_region)
            || defined($sw_autorecover) )
        {
            $log->assertion_failed( "Wrong syntax\n" . $usage );
        }
        chomp($sw_recover);
        if ( recover_stg($sw_recover) ) {
            $log->information("View \"$sw_recover\" was recovered succesfully\n");
        } else {
            $log->error("View \"$sw_recover\" was NOT recovered\n");
        }
        exit 0;
    };
}

sub lsquarantine_mode() {
    defined($sw_lsquarantine) && do {
        $log->information("lsquarantine\n");
        ( defined($sw_purge) || defined($sw_nasince) || defined($sw_quarantine) || defined(@sw_ignore) || defined($sw_autoquarantine) || defined($sw_region) )
          && do { $log->assertion_failed( "Wrong syntax\n" . $usage ); };
        ( defined($sw_autorecover) && defined($sw_autopurge) )
          && do { $log->assertion_failed( "-autopurge and -autorecover can't be used together\n" . $usage ); };
        foreach ( lsquarantined() ) {
            $log->information($_);
            defined($sw_autopurge) && do {
                purge_stg($_);
            };
            defined($sw_autorecover) && do {
                if ( recover_stg($_) ) {
                    $log->information("View was recovered succesfully\n");
                } else {
                    $log->error("View was NOT recovered\n");
                }
            };
        }
        exit 0;
    };
}

sub purge_mode() {
    defined($sw_purge) && do {
        $log->information("purge\n");
        (        defined($sw_nasince)
              || defined($sw_quarantine)
              || defined(@sw_ignore)
              || defined($sw_autoquarantine)
              || defined($sw_autopurge)
              || defined($sw_region)
              || defined($sw_autorecover) )
          && do { $log->assertion_failed( "Wrong syntax\n" . $usage ); };
        purge_stg($sw_purge);
        exit 0;
    };
}

sub nasince_mode() {
    defined($sw_nasince) && do {
        $log->information("nasince\n");
        ( defined($sw_quarantine) || defined(@sw_ignore) || defined($sw_autopurge) || defined($sw_region) || defined($sw_autorecover) )
          && do { $log->assertion_failed( "Wrong syntax\n" . $usage ); };

        my @views;
        $log->assertion_failed("ERROR: Wrong date format (use YYYY-DD-MM)\n") unless vwsstgs_nasince( $sw_nasince, \@views );
        foreach ( sort @views ) {
            $log->information($_);
            defined($sw_autoquarantine) && do {
                my ( $d, $stg ) = split( /\t/, $_ );
                if ( quarantine_stg($stg) ) {
                    $log->information("View was quarantined succesfully\n");
                } else {
                    $log->error("View was NOT quarantined\n");
                }
            };
        }
        exit 0;
    };
}

sub quarantine_mode() {
    defined($sw_quarantine) && do {
        $log->information("quarantine\n");
        ( defined(@sw_ignore) || defined($sw_autoquarantine) || defined($sw_autopurge) || defined($sw_region) || defined($sw_autorecover) )
          && do { $log->assertion_failed( "Wrong syntax\n" . $usage ); };
        if ( quarantine_stg($sw_quarantine) ) {
            $log->information("View \"$sw_quarantine\" was quarantined succesfully\n");
        } else {
            $log->error("View \"$sw_quarantine\" was NOT quarantined\n");
        }
        exit 0;
    };
}

sub ignore_mode() {
    defined(@sw_ignore) && do {
        ( defined(@sw_noignore) || defined($sw_autoquarantine) || defined($sw_autopurge) || defined($sw_autorecover) )
          && do { $log->assertion_failed( "Wrong syntax\n" . $usage ); };
        $log->information("ignore\n");

        #rw2 cleanup project reimplement ARGV (remember logfile uses it right now)
        @sw_ignore = split( /;/, join( ';', @sw_ignore ) );
        foreach (@sw_ignore) {
            my $viewtag = $_;
            my $region_switch = ( defined($sw_region) ) ? "-region $sw_region" : "";
            $_ = `cleartool lsview $region_switch $viewtag`;
            $? && $log->error( $? . $_ . "\nCould not find view $viewtag to ignore\n" );
            /^[\s\*]*(\S*)\s*(\S*)$/
              ; # Any number of whitespaces or * (if the view is started) followed by non-whitespace chars (the view tag) followed by some whitespaces and tne another set of non-whitespace chars (the view storage)
            print $2;    #rw2 debug??
            my $stg = $2;

            my $ignore_file_loc = $2 . "\\admin\\" . $view_q_ignore_file;

            open VIEW_Q_IGNORE_FILE, ">$ignore_file_loc" or $log->assertion_failed("Couldn't open '$ignore_file_loc'\n");
            print VIEW_Q_IGNORE_FILE "This view storage is ignored by $Scriptfile\nDelete this file to ";
            close VIEW_Q_IGNORE_FILE or $log->error("Couldn't close '$ignore_file_loc'\n");
            $log->information("Viewtag '$viewtag' has been set to ignored\n");
        }    # end foreach
        exit 0;
    };    # end ignore

    defined(@sw_noignore) && do {
        $log->information("noignore\n");
        @sw_noignore = split( /;/, join( ';', @sw_noignore ) );
        foreach (@sw_noignore) {
            my $viewtag = $_;
            my $region_switch = ( defined($sw_region) ) ? "-region $sw_region" : "";
            $_ = `cleartool lsview $region_switch $viewtag`;

            #rw2 error(view not found), not assertion
            $? && $log->assertion_failed( "\n" . $usage );

            # Any number of whitespaces or * (if the view is started) followed by non-whitespace chars
            # (the view tag) followed by some whitespaces and tne another set of non-whitespace chars (the view storage)
            /^[\s\*]*(\S*)\s*(\S*)$/;
            my $stg = $2;

            my $ignore_file_loc = $2 . "\\admin\\" . $view_q_ignore_file;
            unlink $ignore_file_loc;
            $log->information("Viewtag '$viewtag' has been unignored\n");
        }    # end foreach
        exit 0;
    };    # end noignore
}

#######################################

=head3 lsquarantined( )

NOTE: This function will only run on ClearCase registry servers!!!

This function lists all the quarantined views.

The format of the listing is the local view storage (as reported by lsview -age).

A quarantined view is defined as a view that is reported "stranded" by rgy_check and which has
a .view_quarantine file in the admin directory of the storage.

Parameters:

  none

Returns:

  @result    =    The list of quarantined storages.

=cut

sub lsquarantined( ) {
    my @result;
    foreach ( grep( /-local_path/, `rgy_check -views 2>&1` ) ) {
        /-local_path = \"(\S*)?\"/;
        push( @result, "$1\n" ) if ( -e "$1\\admin\\$view_q_file" );
    }
    return @result;
}

=head3 recover_stg( $stg )

This function recovers a view storage.

It will recreate all the tags in all regions where it was tagged at the time it was quarantined.

Parameters:

  $stg   = The storage to quarantine (the global one, as reported by a lsview command, or
           simply the local-path as reported by rgy_check)

Returns:

  1    =    Success
  0    =    The $stg does not contain a .view_quarantine file in the admin directory.

=cut

sub recover_stg( $ ) {
    my $stg = shift;
    chomp($stg);
    my $view_q_file_loc = "$stg\\admin\\$view_q_file";
    return 0 unless ( -e $view_q_file_loc );
    open VIEW_Q_FILE, "$view_q_file_loc" or die "Couldn't open '$view_q_file_loc'\n";
    foreach (<VIEW_Q_FILE>) { $log->information($_); system($_); $_ = ($?) ? "ERROR\n" : "Success\n"; $log->information($_); }
    close VIEW_Q_FILE or $log->error("Couldn't close '$view_q_file_loc'\n");

    # Something is delaying the close above, the file is not ready for deletion
    # I have to keep trying - I'll give it 40 shots and then I'll bail out
    # ...Need to improve this bit whne i get the time!
    $_ = 0;
    while ( $_ < 40 && !unlink $view_q_file_loc ) { $_++; }

    return 1;
}

=head3 purge_stg( $stg )

This function purges a view storage.

It will recreate one intermediate tag to the view stg and then do a regular
(safe) view removal.

Parameters:

  $stg   = The storage to purge (the global one, as reported by a lsview command, or
           simply the local-path as reported by rgy_check)

Returns:

  1    =    Success
  0    =    The $stg does not contain a .view_quarantine file or the $stg contains
            a .view_q_ignore file.

=cut

sub purge_stg($) {
    my $stg = shift;
    chomp($stg);    # Stg can be local or global so we only use it
    my $view_q_file_loc = "$stg\\admin\\$view_q_file";
    ( -e $view_q_file_loc ) || do {
        $log->error("ERROR: '$stg' is not a quarantined storage\n");
        return 0;
    };

    my $ignore_file_loc = $stg . "\\admin\\" . $view_q_ignore_file;
    ( -e $ignore_file_loc ) && do {
        $log->error("ERROR: '$stg' ignored for quarantine\n");
        return 0;
    };

    open VIEW_Q_FILE, "$view_q_file_loc" or die "Couldn't open '$view_q_file_loc'\n";
    @_ = <VIEW_Q_FILE>;
    close VIEW_Q_FILE or $log->error("Couldn't close '$view_q_file_loc'\n");
    $_ = $_[0];    # Cache the first entry (we really just need the global storage, so any entry will do)
    /\s(\S*)$/;    # The stg is the last part (whitespace separated) of the stream;

    my $mktagcmd   = "cleartool mktag -view -tag VIEW_Q_TEMP_TAG $1";
    my $endviewcmd = "cleartool endview -server VIEW_Q_TEMP_TAG";
    my $rmviewcmd  = "cleartool rmview $1";

    $log->information("$mktagcmd\n");
    system("$mktagcmd");
    if ($?) {
        $log->error( "Make tag failed with exitcode: " . ( $? / 256 ) . "\n" );    #/ #rw2 EPIC syntax highlight fixer
    } else {
        $log->information("Make tag successful\n");
    }

    $log->information("$endviewcmd\n");
    system("$endviewcmd");
    if ($?) {
        $log->error( "End view failed with exitcode: " . ( $? / 256 ) . "\n" );    #/ #rw2 EPIC syntax highlight fixer
    } else {
        $log->information("End view successful\n");
    }

    $log->information("$rmviewcmd\n");
    system("$rmviewcmd");
    if ($?) {
        $log->error( "Remove view failed with exitcode: " . ( $? / 256 ) . "\n" );    #/ #rw2 EPIC syntax highlight fixer
        $log->information( "Search for temptag VIEW_Q_TEMP_TAG returns " . `cleartool lsview -s VIEW_Q_TEMP_TAG` . "\n" );
        if ($?) {
            $log->information("VIEW_Q_TEMP_TAG was not found, continuing\n");
        } else {
            $log->error("VIEW_Q_TEMP_TAG found, removing it now\n");
            `cleartool rmtag -view VIEW_Q_TEMP_TAG`;
        }
    } else {
        $log->information("Remove view successful\n");
    }

    return 1;
}

=head3 quarantine_stg( $stg )

This function quarantines a view storage.

It will untag tags in all regions and record the reverse commands (the corresponding
mktag commands) in a file named .view_quarantine located in the admin directory of the
view storage.

Parameters:

  $stg   = The storage to quarantine (the global one, as reported by a lsview command)

Returns:

  1    =    Success
  0    =    The $stg parameter is invalid - nothing to do!

=cut

sub quarantine_stg( $ ) {
    my $stg = shift;
    chomp($stg);
    prepare_stg_directory();
    return 0 unless defined( $stg_directory{"$stg"} );    # Get out if the view storage has no entry in the directory

    my $ignore_file_loc = $stg . "\\admin\\" . $view_q_ignore_file;
    ( -e $ignore_file_loc ) && do {
        $log->error( $stg . " ignored for quarantine\n" );
        return 0;
    };

    # Only permit dynamic views
    @_ = split( /;/, $stg_directory{"$stg"} );            # Turn the semi-colon seprated list of tags into an array
    $_ = $_[0];                                           # Get a region/tag pair (anyone will do, so we just grab the first)
    s/-tag//;                                             # strip the -tag switch, it's not used in lsview

    if ( grep { /^Properties+.*dynamic/ } `cleartool lsview -pro -full $_` ) {
        $log->information("View \"$stg\" is a dynamic view\n");
    } else {
        $log->error("The view \"$stg\" is a snapshot view.\nSnapshotviews are currently not supported by view_q.pl\n");
        return 0;
    }

    my @rmtags;
    my @mktags;
    foreach ( split( /;/, $stg_directory{"$stg"} ) ) {
        push( @mktags, "cleartool mktag -view " . $_ . " " . $stg . "\n" );
        s/-tag//;    # strip the -tag switch which isn't used in rmtag
        push( @rmtags, "cleartool rmtag -view " . $_ );
    }
    my $view_q_file_loc = $stg . "\\admin\\" . $view_q_file;
    open VIEW_Q_FILE, ">$view_q_file_loc" or $log->assertion_failed("Couldn't open '$view_q_file_loc'\n");
    foreach (@mktags) { print VIEW_Q_FILE $_; }
    close VIEW_Q_FILE;
    foreach (@rmtags) { $log->information( $_ . "\n" ); system($_); }
    return 1;
}

=head3 vwsstgs_nasince( $cut_date, \@result )

This function pushes (global) view storage locations onto the result array
handed into the sub as a reference if they haven't been accessed since $cut_date.

The format of the resulting list entries are like this:

  <YYYY-MM-DD> <view_stg>

Where  view <YYYY-MM-DD> is the last accessed date, and <view_stg> is the global view storage location.

Parameters:

  $cut_date      =  The date to compare against. The scalar must be in the format YYYY-DD-MM
  \@result       =  An array reference passed into the sub function

Returns:

  1    =    The content of @result is trust worthy
  0    =    The $cut_date is in an unsupported format. The content of @result is crab!

=cut

sub vwsstgs_nasince($$) {
    my $cut_date = shift;
    my $result   = shift;
    return 0 unless ( $cut_date =~ /(\d\d\d\d-\d\d-\d\d)/ );
    prepare_stg_directory();
    foreach my $stg ( keys(%stg_directory) ) {
        @_ = split( /;/, $stg_directory{"$stg"} );    # Turn the semi-colon seprated list of tags into an array
        $_ = $_[0];                                   # Get a region/tag pair (anyone will do, so we just grab the first)
        s/-tag//;                                     # strip the -tag switch, it's not used in lsview
        @_ = split( /\n/, `cleartool lsview -age $_` );    # lsview with the -age switch return two lines
        $_ = $_[1];                                        # Grab the second line (where the relevant timestamp is listed)
        /(\d\d\d\d-\d\d-\d\d)/;                            # Get the date in the format YYYY-MM-DD

        push( @$result, $1 . "\t" . $stg . "\n" ) if $1 le $cut_date;    #If the last accessed date is prior to the cut_date, push it onto the result.
    }
    return 1;
}

=head3 sub prepare_stg_directory( )

This function is related to the global hash: %stg_directory.

%stg_directory is used be several sub functions as a common directory listing of view storages
and view tags.

After it has been prepared, the format of the hash entries are like this:

  keys                 = The global view storage location;
  values               = A semi-colon separated list of all region/tags pairs in the
                         format: -region <region> -tag <tag>

This function validates that the global hash containing all views across all regions is
loaded and trustworthy.

All operations querying the directory should call this sub function first.

Parameters:

  none

Returns:

  0      The %stg_directory is already prepared, it will be reused.
  1      The %stg_directory has been prepared.

=cut

sub prepare_stg_directory() {
    return 0 if keys(%stg_directory);    # Someone else already prepared the directory, reuse it! Let's get out.
    foreach my $region (`cleartool lsregion`) {
        chomp($region);
        foreach (`cleartool lsview -region $region`) {
            /^[\s\*]*(\S*)\s*(\S*)$/
              ; # Any number of whitespaces or * (if the view is started) followed by non-whitespace chars (the view tag) followed by some whitespaces and tne another set of non-whitespace chars (the view storage)
            $stg_directory{"$2"} =
              $stg_directory{"$2"} . "-region \"$region\" -tag \"$1\";";    #build a unique list of view storages containing the tags in all regions
        }
    }
    return 1;
}
