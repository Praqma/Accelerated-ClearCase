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

Clearcase has a feature called rgy_check which can report stranded views.

  rgy_check -views

Run cleartool man rgy_check to learn more.

When view_q.pl puts a view into quarantine, it removes all tags in all regions. This puts the
view into the state of being 'stranded'. An important difference between 'regular" stranded
and views put into quarantine by view_q.pl is the file called

  .view_quarantine

which view_q.pl creates in the the 'admin' subfolder in the view storage. This file contains the history
of tags in all regions from where they were deleted. and enables a complete restore.

View_q.pl can be run in a mode where it lists all views not accessed since a certain date. if you whish you
can even tell view_q.pl to automatically put these views into quarantine.

View_q.pl has a different mode which lists all views that are currently in quarantine (As you may have figured
out this is partly determined by the fact that views are stranded, so this mode only works when executed from
the ClearCase Registry server, which support rgy_check!)

When listing the quarantined views you can either automatically purge or recover the views.

Views can also be purged or recovered individually.

When view_q.pl purges a view it runs the sequence, rmtag, unregister, rmview by uuid, and it will attempt to
delete the view storage too.

When a view is recovered by view_q.pl it simply restores all tags in all the regions where it was removed from.

Some views aren't supposed to be deleted even when they haven't been accessed for a long time. View_q.pl can
be instructed to disable quarantine of these views.

View_q.pl will only process views hosted on the machine where the script is being executed.


=head1 Examples

=head2 Putting a view in Quarantine

 ratlperl view_p.pl -quarantine \\server\share\views\viewstorage

The view storage can in either Local File Path notation (d:\views\...) or UNC style

=head2 Listing view that have not been used since ...

This operation is achieved by the swithc -nasince. The argument to -nasince can either be
a date in the form YYYY-MM-DD or a number of days. In the latter case the number of days
will be subtracted from the current date. This feature adresses the possibility to
set-up scheduled jobs. So if you call

 ratlperl view_q.pl -nasince 90

all views that have not been used for 90 dayss or more will be listed. You can add -autoquarantine
to the command to have all these views quarantined in one operation.

=head3 - and putting them in quarantine

 ratlperl view_q.pl -nasince 90 -autoquaratine

=head2 Listing views in quarantine

So you have used view_q.pl to put views in quarantine. How to know which views are in quarantine ?
Simple, used the -lsquarantine:

 ratlperl view_q.pl -lsquarantine

=head3 -have all quarantined views purged (deleted ...)

Use -autopurge:

 ratlperl view_q.pl -lsq -autopurge

Any view in quarantine will be removed.


=head3 purge only views that have been for long enough

add the -days switch which is only valid together with -lsq -autopurge (or -autorecover )
With -autopurge the days switch will filter the quarantined views and only purge those
that have been in quarantine for MORE than I<days>

 ratlperl view_q.pl -lsq -autopurge -days 180

will remove views that have been in quarantine for more than 180 days

=head3 or autorecover quarantined views

Use the -autorecover switch with -lsquarantine. When autorecovering the meaning of
the -days switch is changed to mean less than, I<days>. So

 ratlperl view_q.pl -lsq -autorecover -days 30

Will recover quarantined views that have been quarantined less than 30 days

=head2 One view at a time

Views can be processed one at a time with:

=head3 quarantine:

 ratlperl view_q.pl  -quarantine stgloc

=head3 recover:

 ratlperl view_q.pl -recover stgloc

=head3 purge:

 ratlperl view_q.pl  -purge stgloc

Where B<stgloc> can be in eiter UNC style or local file system notation.

=head2 Ignoring views

Some views are not accessed - but should however not be quarantined, they build-views
or have some other purpose for the organization.

 ratlperl view_q.pl  -ignore I<viewtag>

as the view may not be in the current region, the switch -region is supported

 ratlperl view_q.pl  -ignore I<viewtag> -region I<region>


=head2 Un-ignoring views

To remove the ignore flag from a view, just run

  ratlperl view_q.pl  -noignore I<viewtag> -region I<region>

-and that view will be back in consideration for view_q.pl



=head1 SUPPORT

Visit http://www.praqma.net to get help.

=cut

# Getting the script dir
our( $Scriptdir, $Scriptfile );

BEGIN {
    if ( $0 =~ /(.*[\/\\])(.*)$/ ) {
        $Scriptdir  = $1;
        $Scriptfile = $2;
    } else {
        $Scriptdir  = "";
        $Scriptfile = $0;
    }
}

# Use clauses
use strict;
use lib "$Scriptdir..\\..";
use Getopt::Long;
use praqma::scriptlog;
use praqma::acc;

use constant BLATEXE => "$Scriptdir..\\..\\praqma\\Blat\\Blat.exe";

# File version
our $VERSION = " 0.7 ";
our $BUILD   = " 13 ";

# Log and monitor default settings (overwriteable at execution)
my $debug        = 0;                    # Set 1 for testing purpose
my $verbose_mode = 1;
my $log_enabled  = 1;
my $mailfilename = "$Scriptdir/mailtexts.pl";

# Header history
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
################################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR         NOTE
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
2009-11-16  Jens Brejner   Version 0.5.6: Add support for snapshot views
2009-11-18  Jens Brejner   Version 0.5.7: Add support for ClearCase LT
2009-12-10  Jens Brejner   Version 0.5.10: Add support for web-views
2009-12-10  Jens Brejner   Version 0.6.11: Interface changed. Adding for support
                           number of days, see option -days
2010-03-04  Jens Brejner   Version 0.6.12: bugfix, snapshot views with missing access date
                           will now be ignored, but a warning will be printed
2010-07-09  Jens Brejner   Version 0.7.13: Enable mail sending.

-------------------------------------------------------------------------

ENDREVISION

my $usage = <<ENDUSAGE;
  $Scriptfile -lsquarantine [-days DD] [-autopurge [-sendmail] | -autorecover]
  $Scriptfile -nasince YYYY-MM-DD | -nasince number [-autoquarantine] [-sendmail]
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

-days NUMBER            Optional Switch, think " age in days " Valid with -lsquarantine
                        together with -autopurge or -autorecover
                        If -days is used with -autopurge, only views that have
                        been quarantined for more than -days NUMBER will be listed
                        and only those views will be available for -autopurge.
                        If used together with -autorecover the opposite occurs,
                        only views that have been in quarantine less than -days will
                        be recovered.

-nasince date|number    Lists views that are not accessed since date. Date must
                        either be in the format YYYY-MM-DD or a positive integer.
                        If a number is used is meant as a number of days since, and
                        the number of days will be subtracted from todays date and
                        the resulting date will be used.

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
                        or seperating with ";
" eg. " ... -ignore tag1;
tag2 -ignore tag3 "

-region region          Optional switch only valid together with -[no]ignore.
                        The region switch is used to qualify the viewtag applied with
                        -[un]ignore if necessary. if -region is omitted, the viewtag is
                        searched in the current region.

-sendmail               Optional. Sends mails to view owners  and administrator.
                        Requires the a file called $mailfilename to exist in the
                        same directory as $Scriptfile. You must copy the supplied
                        file tmpl.pl, and modify it to you needs.

--- Auxiliary switches (can be omitted or used on all functions)---

-[no]logfile [location] Sets whether or not to create a logfile.
                        May define the name [and location] of the logfile.
                        Default value is the temp dir (usually under
                        users " doc &set ") and " view_q . pl [PID] . log "

-[no]verbose            Toggles verbose mode (log to STDOUT)
                        Default is on (for manual execution, verbose is recommended)

-[no]debug              Toggles debug mode (additional information + force logfile + verbose)
                        Default is off

ENDDOC

### Global variables ###

our %stg_directory;
our %views_per_user;    # key is view owner, value is array of views owned by user
our $log                = scriptlog->new;
our $view_q_file        = " . view_quarantine ";
our $view_q_ignore_file = " . view_q_ignore ";
our(
    $sw_lsquarantine, $sw_recover,  $sw_purge,       $sw_nasince, $sw_quarantine, $sw_autoquarantine, $sw_autopurge, $sw_help, $sw_region,
    @sw_ignore,       @sw_noignore, $sw_autorecover, $sw_logfile, $sw_verbose,    $sw_debug,          $sw_days,      %options, $sw_sendmail
);

&validate_options();

#### SWITCH ####
&help_mode();
&enable_log();
&lsquarantine_mode();
&recover_mode();
&purge_mode();
&nasince_mode();
&quarantine_mode();
&ignore_mode();
#### SWITCH ####
$log->assertion_failed( " Wrong syntax \n " . $usage );
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

sub isolatepath ($) {

    #Isolate the path part of lsview output
    #input is the output from cleartool lsview, which looks like
    #returns the filesystem path  or
    # 0 for failure

    my $lsview_reply = shift;

    if ( $lsview_reply =~ /$ENV{'COMPUTERNAME'}:/i ) {    # CC LT and WebView format
        $lsview_reply =~ /^[\s\*]*(\S*)\s*\S*:([a-zA-Z]:\\\S*)$/;
        $sw_debug && $log->information(" \tlsview reply [$lsview_reply], path isolatede to [$2] \n ");
        return $2 if ( -e $2 );
    } elsif ( $lsview_reply =~ /\\\\$ENV{'COMPUTERNAME'}\\/i ) {    # Base CC format

        $lsview_reply =~ /^[\s\*]*(\S*)\s*(\S*)$/;
        $sw_debug && $log->information(" \tlsview reply [$lsview_reply], path isolatede to [$2] \n ");
        return $2 if ( -e $2 );

    } else {

        return 0;
    }

}

sub validate_options () {

    %options = (
        "autoquarantine" => \$sw_autoquarantine,
        "lsquarantine"   => \$sw_lsquarantine,
        "days=i"         => \$sw_days,
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
        "verbose!"       => \$sw_verbose,
        "sendmail!"      => \$sw_sendmail

    );

    #  die "$usage" unless GetOptions(%options);
    GetOptions(%options);

}

=head3 enable_log ()


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

sub enable_log () {

    # Overwrites the default logging setting, if set manually
    defined($sw_debug) && do { $debug = $sw_debug }
      && ( $verbose_mode = 1 );
    defined($sw_verbose) && do { $verbose_mode = $sw_verbose };
    defined($sw_logfile) && do { $log_enabled  = $sw_logfile };

    my $argv_values;
    foreach (@ARGV) {
        $argv_values = $argv_values . "\"" . $_ . "\" ";    #rw2 use join

    }

    # Ensure consistent time formatting, see IBM Tech note 1249021
    $ENV{'CCASE_ISO_DATE_FMT'} = "1";

    # Checks ARGV for consistency and enables the log
    if ($log_enabled) {
        if ( scalar(@ARGV) gt 1 ) {
            $log->assertion_failed("You have more then one value with no defined reference,\nonly valid option is logfile location \nRecorded values are:$argv_values");
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
      };

    # Region not allowed on ClearCase LT
    if ( (acc::is_cclt) && defined($sw_region) ) {
        $log->assertion_failed("ClearCase LT detected, -region switch is not allowed\n");
    }

    if ($sw_sendmail) {

        my $msg = "-sendmail can only be used together with -nasince or -lsquarantine\n";
        $log->assertion_failed($msg) unless ( $sw_lsquarantine || $sw_nasince );
        $msg = "Can't find required file called \"$mailfilename\"\n\n";
        do "$mailfilename" || $log->assertion_failed($msg);    # read the template file
    }

}

=head3 xxx_mode ()

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

sub help_mode () {
    defined($sw_help) && do { print $header. $revision . $usage . $doc; exit 0; };
}

sub recover_mode () {
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

sub lsquarantine_mode () {
    defined($sw_lsquarantine) && do {
        $log->information("lsquarantine\n");
        ( defined($sw_purge) || defined($sw_nasince) || defined($sw_quarantine) || defined(@sw_ignore) || defined($sw_autoquarantine) || defined($sw_region) )
          && do { $log->assertion_failed( "Wrong syntax\n" . $usage ); };
        ( defined($sw_autorecover) && defined($sw_autopurge) )
          && do { $log->assertion_failed( "-autopurge and -autorecover can't be used together\n" . $usage ); };

        ( defined($sw_days) && !( defined($sw_autorecover) || defined($sw_autopurge) ) )

          && do { $log->assertion_failed( "Using -days requires either -autopurge or -autorecover\n" . $usage ); };

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
        do_mail();
        exit 0;
    };
}

sub purge_mode () {
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

sub nasince_mode () {
    defined($sw_nasince) && do {
        $log->information("nasince\n");
        ( defined($sw_quarantine) || defined(@sw_ignore) || defined($sw_autopurge) || defined($sw_region) || defined($sw_autorecover) )
          && do { $log->assertion_failed( "Wrong syntax\n" . $usage ); };

        if ( $sw_nasince =~ /^\d+$/ ) {

            # change meaning of nasince date

            my $cutdays = int($sw_nasince);    # only integers accepted

            $log->error("Number of days $cutdays is not valid\n") unless ( $cutdays gt 0 );
            my $offset    = $cutdays * 60 * 60 * 24;    # Convert to epoch by multiply with seconds per days
            my $timesince = time() - $offset;

            # slice date, month, year of time since
            my ( $day, $month, $year ) = ( localtime($timesince) )[ 3, 4, 5 ];
            $sw_nasince = sprintf( "%04d-%02d-%02d", $year + 1900, $month + 1, $day );
            $debug && $log->information("Calculated cutdate is [$sw_nasince]\n");
        }
        my @views;
        $log->assertion_failed("ERROR: Wrong date format (use YYYY-DD-MM)\n")
          unless vwsstgs_nasince( $sw_nasince, \@views );
        foreach ( sort @views ) {
            $log->information($_);

            if ( defined($sw_autoquarantine) ) {
                my ( $d, $stg ) = split ( /\t/, $_ );
                if ( quarantine_stg($stg) ) {
                    $log->information("View was quarantined succesfully\n");
                } else {
                    $log->error("View was NOT quarantined\n");
                }
            }


        }
        do_mail();
        exit 0;
    };
}

sub quarantine_mode () {
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

sub ignore_mode () {
    defined(@sw_ignore) && do {
        ( defined(@sw_noignore) || defined($sw_autoquarantine) || defined($sw_autopurge) || defined($sw_autorecover) )
          && do { $log->assertion_failed( "Wrong syntax\n" . $usage ); };
        $log->information("ignore\n");

        #rw2 cleanup project reimplement ARGV (remember logfile uses it right now)
        @sw_ignore = split ( /;/, join ( ';', @sw_ignore ) );
        foreach (@sw_ignore) {
            my $stg           = "";
            my $viewtag       = $_;
            my $region_switch = ( defined($sw_region) ) ? "-region $sw_region" : "";
            $_ = `cleartool lsview $region_switch $viewtag`;
            $? && $log->error( $? . $_ . "\nCould not find view $viewtag to ignore\n" );

            $stg = isolatepath($_);
            unless ($stg) {    #
                $log->warning("Could determine storage for viewtag [$region_switch $viewtag], skipping it\n");
                next;
            }

            my $ignore_file_loc = $stg . "\\admin\\" . $view_q_ignore_file;

            open VIEW_Q_IGNORE_FILE, ">$ignore_file_loc"
              or $log->assertion_failed("Couldn't open '$ignore_file_loc'\n");
            print VIEW_Q_IGNORE_FILE "This view storage is ignored by $Scriptfile\nDelete this file to reenable this storage for view_q.pl considerations\n";
            close VIEW_Q_IGNORE_FILE or $log->error("Couldn't close '$ignore_file_loc'\n");
            $log->information("Storage '$stg' has been set to ignored\n");
        }    # end foreach
        exit 0;
    };    # end ignore

    defined(@sw_noignore) && do {
        $log->information("noignore\n");
        @sw_noignore = split ( /;/, join ( ';', @sw_noignore ) );
        foreach (@sw_noignore) {
            my $stg           = "";
            my $viewtag       = $_;
            my $region_switch = ( defined($sw_region) ) ? "-region $sw_region" : "";
            $_ = `cleartool lsview $region_switch $viewtag`;

            $? && $log->assertion_failed( "\n" . $usage );

            $stg = isolatepath($_);
            unless ($stg) {    #
                $log->warning("Could determine storage for viewtag [$region_switch $viewtag], skipping it\n");
                next;
            }

            my $ignore_file_loc = $stg . "\\admin\\" . $view_q_ignore_file;
            unlink $ignore_file_loc;
            $log->information("Viewtag '$viewtag' has been unignored\n");
        }    # end foreach
        exit 0;
    };    # end noignore
}

=head3 lsquarantined ()

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

sub lsquarantined () {
    my @result;
    foreach ( grep( /-local_path/, `rgy_check -views 2>&1` ) ) {
        /-local_path = \"(\S*)?\"/;
        push ( @result, "$1\n" ) if ( -e "$1\\admin\\$view_q_file" );
    }
    return @result;
}

=head3 recover_stg ($stg)

This function recovers a view storage.

It will recreate all the tags in all regions where it was tagged at the time it was quarantined.

Parameters:

  $stg   = The storage to quarantine (the global one, as reported by a lsview command, or
           simply the local-path as reported by rgy_check)

Returns:

  1    =    Success
  0    =    The $stg does not contain a .view_quarantine file in the admin directory.

=cut

sub recover_stg ($) {
    my $stg = shift;
    chomp($stg);
    my $view_q_file_loc = "$stg\\admin\\$view_q_file";
    return 0 unless ( -e $view_q_file_loc );

    if ($sw_days) {
        my $age = int( sprintf "%f", -C $view_q_file_loc );

        if ( $age ge $sw_days ) {    # too old to recover (given number of days)
            $log->information("Too old '$stg' has been quarantined for $age days, igoring for recovering\n");
            return 0;
        }
    }

    open VIEW_Q_FILE, "$view_q_file_loc" or die "Couldn't open '$view_q_file_loc'\n";
    foreach (<VIEW_Q_FILE>) {
        $log->information($_);
        system($_);
        $_ = ($?) ? "ERROR\n" : "Success\n";
        $log->information($_);
    }
    close VIEW_Q_FILE or $log->error("Couldn't close '$view_q_file_loc'\n");

    # Something is delaying the close above, the file is not ready for deletion
    # I have to keep trying - I'll give it 40 shots and then I'll bail out
    # ...Need to improve this bit whne i get the time!
    $_ = 0;
    while ( $_ < 10 && !unlink $view_q_file_loc ) { sleep 1; $_++; }

    return 1;
}

=head3 purge_stg ($stg)

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

sub purge_stg ($) {
    my $stg = shift;
    chomp($stg);    # Stg can be local or global so we only use it
    my $view_q_file_loc = "$stg\\admin\\$view_q_file";
    ( -e $view_q_file_loc ) || do {
        $log->error("ERROR: '$stg' is not a quarantined storage\n");
        return 0;
    };

    if ($sw_days) {
        my $age = int( sprintf "%f", -C $view_q_file_loc );

        if ( $age le $sw_days ) {    # too young to purge
            $log->information("Too new; '$stg' has only been quarantined for $age days, igoring for purge\n");
            return 1;
        }

    }

    my $ignore_file_loc = $stg . "\\admin\\" . $view_q_ignore_file;
    ( -e $ignore_file_loc ) && do {
        $log->error("ERROR: '$stg' ignored for quarantine\n");
        return 0;
    };

    open VIEW_Q_FILE, "$view_q_file_loc" or die "Couldn't open '$view_q_file_loc'\n";
    @_ = <VIEW_Q_FILE>;
    close VIEW_Q_FILE or $log->error("Couldn't close '$view_q_file_loc'\n");
    $_ = $_[0];    # Cache the first entry (we really just need the global storage, so any entry will do)
    my $ngpath = ( $_ =~ /-ngpath/ ) ? "-ngpath " : "";
    /\s(\S*)$/;    # The stg is the last part (whitespace separated) of the stream;

    my $temptag    = "VIEW_Q_TEMP_TAG";
    my $mktagcmd   = "cleartool mktag -view -nstart $ngpath -tag $temptag $1";
    my $endviewcmd = "cleartool endview -server $temptag";
    my $rmtagcmd   = "cleartool rmtag -view $temptag";

    # create temptag so we can get view's properties
    $log->information("$mktagcmd\n");
    system("$mktagcmd");
    if ($?) {
        $log->error( "Make tag failed with exitcode: " . ( $? / 256 ) . "\n" );
    } else {
        $log->information("Make tag successful\n");
    }

    # get view properties into hash
    my %viewprops;
    foreach (`cleartool lsview -l $temptag`) {
        /^(.*):\s(.*)$/;
        $viewprops{$1} = $2;
    }

    # end the view again
    $log->information("$endviewcmd\n");
    system("$endviewcmd");
    if ($?) {
        $log->error( "End view failed with exitcode: " . ( $? / 256 ) . "\n" );
        my $i = 0;
        while ( $i < 11 ) {
            $log->information("Waiting a sec before trying to end that view...\n");
            sleep 1;
            system("$endviewcmd");
            if ($?) { $i++; }
            else { $i = 12; }
        }

        $log->error( "End view failed with exitcode: " . ( $? / 256 ) . "\n" );
    } else {
        $log->information("End view successful\n");
    }

    # remove the temp tag again
    $log->information("$rmtagcmd\n");
    system("$rmtagcmd");
    if ($?) {
        $log->error( "Removal of temp tag failed with exitcode: " . ( $? / 256 ) . "\n" );
        $log->information( "Search for temptag $temptag returns " . `cleartool lsview -s $temptag` . "\n" );
        if ($?) {
            $log->information("$temptag was not found, continuing\n");
        } else {
            $log->error("$temptag found, removing it now\n");
            `cleartool rmtag -view $temptag`;
        }
    } else {
        $log->information("Remove temp tag successful\n");
    }

    # using the properties we found, unregister the view by uuid
    my $viewuuid = $viewprops{"View uuid"};
    my $unregcmd = "cleartool unregister -view -uuid $viewuuid 2>&1";
    system("$unregcmd");
    if ($?) {
        $log->error( "Unregister view failed with exitcode: " . ( $? / 256 ) . "\n" );
    } else {
        $log->information("Unregister view successful\n");
    }

    # rmview by UUID
    my $rmviewcmd = "cleartool rmview -force -all -uuid $viewuuid 2>&1";
    $log->information("$rmviewcmd\n");
    system("$rmviewcmd");
    if ($?) {
        $log->error( "Remove view failed with exitcode: " . ( $? / 256 ) . "\n" );
    } else {
        push ( @{ $views_per_user{'PURGED:'} }, "$stg" ); # save the list of views that was purged
        $log->information("Remove view successful\n");
    }

    # something is holding on the old storage, wait a bit before continuing
    sleep 2;

    # attempt to kill the storage
    my $localstorage = $viewprops{"View server access path"};
    my $rmstgcmd     = "rmdir /s /q \"$localstorage\"";
    if ( -e $localstorage ) {
        system("$rmstgcmd");
        if ($?) {
            $log->error( "Removal of old view storage at $localstorage failed with exitcode: " . ( $? / 256 ) . "\n" );
        } else {
            $log->information("Removal of old view storage at $localstorage successful\n");
        }
    }

    return 1;
}

=head3 quarantine_stg ($stg)

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

sub quarantine_stg ($) {
    my $stg = shift;
    chomp($stg);
    prepare_stg_directory();
    return 0 unless defined( $stg_directory{"$stg"} );    # Get out if the view storage has no entry in the directory

    my $ignore_file_loc = $stg . "\\admin\\" . $view_q_ignore_file;
    ( -e $ignore_file_loc ) && do {
        $log->error( $stg . " ignored for quarantine\n" );
        return 0;
    };

    @_ = split ( /;/, $stg_directory{"$stg"} );           # Turn the semi-colon seprated list of tags into an array
    $_ = $_[0];                                           # Get a region/tag pair (anyone will do, so we just grab the first)
    s/-tag//;                                             # strip the -tag switch, it's not used in lsview

    my @rmtags;
    my @mktags;
    foreach ( split ( /;/, $stg_directory{"$stg"} ) ) {
        push ( @mktags, "cleartool mktag -view -nstart " . $_ . " " . $stg . "\n" );
        s/-tag //;                                        # strip the -tag which isn't used in rmtag
        s/-ngpath //;                                     # strip the -ngpath which isn't used in rmtag
        push ( @rmtags, "cleartool rmtag -view " . $_ );
    }
    my $view_q_file_loc = $stg . "\\admin\\" . $view_q_file;
    open VIEW_Q_FILE, ">$view_q_file_loc" or $log->assertion_failed("Couldn't open '$view_q_file_loc'\n");
    foreach (@mktags) { print VIEW_Q_FILE $_; }
    close VIEW_Q_FILE;
    foreach (@rmtags) { $log->information( $_ . "\n" ); system($_); }
    return 1;
}

=head3 vwsstgs_nasince ( $cut_date, \@result)

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

sub vwsstgs_nasince ($$$) {
    my $cut_date = shift;
    my $result   = shift;
    return 0 unless ( $cut_date =~ /(\d\d\d\d-\d\d-\d\d)/ );
    prepare_stg_directory();
    foreach my $stg ( sort keys(%stg_directory) ) {
        @_ = split ( /;/, $stg_directory{"$stg"} );    # Turn the semi-colon seprated list of tags into an array
        $_ = $_[0];                                    # Get a region/tag pair (anyone will do, so we just grab the first)
        s/-tag//;                                      # strip the -tag switch, it's not used in lsview
        s/-ngpath//;                                   # strip the -ngpath switch, it's not used in lsview

        my @viewdetails = split ( /\n/, `cleartool lsview -properties $_` );    # lsview with the -age switch return two lines
        my $accessed = $viewdetails[3];                                         # Grab fourth line (where the relevant timestamp is listed)
        $accessed =~ s/.*(\d\d\d\d-\d\d-\d\d).*/$1/;                            # Get the date in the format YYYY-MM-DD
        my $owner = $viewdetails[4];                                            # Grab 5'th line - owner information
        $owner =~ s/.*\\(\S+).*/$1/;                                            # Isolate owner (the login ID)

        if ( ( $accessed ne "" ) && ( $accessed le $cut_date ) ) {

            #If the last accessed date is prior to the cut_date, push it onto the result tables.
            my $info = "$accessed\t$stg\n";
            push ( @$result,                     $info );
            push ( @{ $views_per_user{$owner} }, $info );                       # save the list of views per owner
        } else {

            # Snapshot views that have lost their .access_info can not tell when they where used last so $accessed will be empty
            $log->warning("Warning, consider manual removal of the view at $stg, we have no accessed date\n");
        }
    }
    return 1;
}

=head3 sub prepare_stg_directory ( )

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

sub prepare_stg_directory () {
    return 0 if keys(%stg_directory);    # Someone else already prepared the directory, reuse it! Let's get out.

    # build a unique list of view storages containing the tags in all regions
    # syntax is different whether on ClearCase LT or not.
    # The view storage is key in the hash
    if (acc::is_cclt) {                  # report syntax is different on LT versus Base CC

        # This is ClearCase LT
        foreach (`cleartool lsview `) {

            # Any number of whitespaces or * (if the view is started)
            # followed by non-whitespace chars (the view tag) followed
            # by some whitespaces and non-whitespace ending with a colon and
            # then another set of non-whitespace chars that starts with a letter, a colon and a backslash (the view storage)
            /^[\s\*]*(\S*)\s*\S*:([a-zA-Z]:\\\S*)$/;

            #build a unique list of view storages containing the tags
            $stg_directory{"$2"} = $stg_directory{"$2"} . "-tag \"$1\";";
        }

    } else {

        #  Base ClearCase
        foreach my $region (`cleartool lsregion`) {
            chomp($region);

            # Build hash table
            foreach (`cleartool lsview -host $ENV{'COMPUTERNAME'} -region $region`) {

                # Cleartool lsview reports in different formats, web-views are reported differently than
                # snapshot views and dynamic views. Actually the format is like CC LT reports views ...
                #  see below for example

                #    * student_view         \\cccq7\ccstorage\views\CCCQ7\student\student_view.vws
                #      student_snap         \\cccq7\ccstorage\views\CCCQ7\student\student_snap.vws
                #      student_web          CCCQ7:C:\ccweb\student\student_web\view.stg

                if (/$ENV{'COMPUTERNAME'}:/i) {    # think it is is web-view
                    /^[\s\*]*(\S*)\s*$ENV{'COMPUTERNAME'}:(\S*)$/i;
                    $stg_directory{"$2"} = $stg_directory{"$2"} . "-ngpath -region \"$region\" -tag \"$1\";";
                } else {                           # normal snap dynamic view, not on CC LT
                                                   # Any number of whitespaces or * (if the view is started)
                                                   # followed by non-whitespace chars (the view tag) followed
                                                   # by some whitespaces and tne another set of non-whitespace chars (the view storage)

                    /^[\s\*]*(\S*)\s*(\S*)$/;
                    $stg_directory{"$2"} = $stg_directory{"$2"} . "-region \"$region\" -tag \"$1\";";
                }
            }
        }

    }
    $log->assertion_failed("No views are hosted on this machine [$ENV{'COMPUTERNAME'}]\n.") unless keys(%stg_directory);
    return 1;
}

sub do_mail {
    return unless $sw_sendmail;
    no strict;

    my %envelope = (
        -f      => $_fromadress,         # FROM:
        -server => $_smtpserver,         # specify the SMTP server to use
        -q      => " ",                  # silent operation
        -debug  => " ",                  # run Blat with debuging output
        -log    => "\"$0.blat.log\"",    # dump screen output to a file instead.
    );

    my @noaddres;                        # Collect login's without email adress
    my @warnlist;                        # list of processed views

    # send warning mails to users
    my $key;
    foreach $key ( sort keys %views_per_user ) {

        # add to list for admin's summary mail.
        push @warnlist, "\n$key\n";
        foreach ( sort @{ $views_per_user{$key} } ) { push @warnlist, "\t$_"; }

        unless ( defined($sw_autoquarantine) || defined($sw_autopurge) ) {

            # We are in warning mode, inform each user
            # Build per-user mail
            my $usermailbody = $_warnofquarantine;

            # Set recipient mail adress
            if ($_maildomain ne "") { # $_maildomain has a value, email adress is login ($key) plus this value
	            $envelope{'-to'} = $key . $_maildomain;
				$log->information("Using default domain, recipient was set to $envelope{'-to'}.\n");
            }else{
	            # get email of login ID, by asking the active directory, so we... kind of depend on that :-(
	            $envelope{'-to'} = qx(dsquery user forestroot -name $key  2>&1 | dsget user -email 2>&1 | findstr @ 2>&1 );
				$log->information("Using dsquery domain, recipient was set to $envelope{'-to'}.\n");
            }
            # debug
            if ( $ENV{COMPUTERNAME} eq "CCCQ7" ) {
	            #	print STDERR "Hey - remove line " . ( __LINE__ + 1 ) . "\n";
	            $envelope{'-to'} = 'jbr@praqma.net';
            }
            ( push @noaddres, "$key\n" and next ) if ($envelope{'-to'} !~ m/\@/);    # can't find email of login, try the next

            $envelope{'-subject'} = "\"$_warnsubject\"";                 # SUBJECT:
            # some substitutions in the text read from the template file $mailfilename
            $usermailbody =~ s/===USER===/$key/g;
            $usermailbody =~ s/===CUTDATE===/$sw_nasince/g;
            $usermailbody =~ s/===VIEWLIST===/\n@{ $views_per_user{$key} }/g;

            sendthemail( $usermailbody, %envelope );
        }
    }    # end foreach my $key
    # Summary mail
    my ( $adminmailbody, $adminsubject );
    $envelope{'-to'} = $_fromadress;    # TO:
    # debug
    if ( $ENV{COMPUTERNAME} eq "CCCQ7" ) {
        #	print STDERR "Hey - remove line " . ( __LINE__ + 1 ) . "\n";
        $envelope{'-to'} = 'jbr@praqma.net';
    }

    # select subject and mail body
    if ( defined($sw_autoquarantine) || defined($sw_autopurge) ) {
        $envelope{'-subject'} = "\"$_adminsubj\"";    # SUBJECT:

        $adminmailbody = $_actionsummary;
        my $action = defined($sw_autoquarantine) ? "quarantined" : "removed";
        $adminmailbody =~ s/===ACTION===/$action/g;

    } else {
        $envelope{'-subject'} = "\"$_adminwarnsubj\"";    # SUBJECT
        $adminmailbody = $_warnsummary;
        $adminmailbody =~ s/===CUTDATE===/$sw_nasince/g;    # set since date
        my $nomail = "";
        if ( scalar(@noaddres) ) {
            $nomail = join ( '\n\t', @noaddres );
            $nomail = "We couldn't retrieve the email adresse for the login(s):\n$nomail";
        }
        $adminmailbody =~ s/===NOEMAIL===/$nomail/g;

    }

    $adminmailbody =~ s/===WARNVIEWS===/@warnlist/g;
    sendthemail( $adminmailbody, %envelope );

}

sub sendthemail {

    my $blatcmd = BLATEXE;    # the Blat binary

    -e BLATEXE || die $!;
    my $body = shift @_;      # get the msg body
    $blatcmd .= " - @_";      # add all the parms

    open( MAIL, "| $blatcmd" ) ||  $log->error("$!\nFailed opening blat.exe to send this mail\n$body\n");    # start Blat with all it's parms
    print MAIL $body;                        # now put in the msg body (bigger this way than CL)
    close(MAIL);
}


__END__
