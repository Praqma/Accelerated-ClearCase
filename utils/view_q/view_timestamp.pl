require 5.001;

# Getting the script dir
our ( $Scriptdir, $Scriptfile );

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
use lib "$Scriptdir..//..";
use Getopt::Long;
use praqma::scriptlog;

# File version
our $VERSION = "0.2";
our $BUILD   = "5";

# Header info
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$BUILD
#     It is a helper utility to view_q.pl
#
#     This script is supposed to run as a scheduled task
#     It's purpose is to register all views that has been used since last
#     execution
#     and touch them so that the last accessed timestamp is updated.
#
#     It must run on the view-server, and it will only process local views.
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
2009-11-09  Jens Brejner   Version 0.2.4 Add support for snapshot views, some
                           rewriting.

-------------------------------------------------------------------------

ENDREVISION

# Usage information
my $usage = <<ENDUSAGE;

  $Scriptfile -run [-help] [-logfile pname] [-[no]verbose] [-[no]debug]

ENDUSAGE

# Documentation for prompt information
my $doc = <<ENDDOC;

-run              Required in order to execute. Help is displayed if omitted.
-help             Get help with the script syntax etc. (you are watching it now)
                  --- Auxiliary switches (can be omitted or used on all functions)---
-logfile pname    Overwrite log file name which defaults to view_timestamp.log
-[no]verbose      Toggles verbose mode (log is also printed to STDOUT)
                  Default is no (for manual execution, verbose is recommended)
-[no]debug        Toggles debug mode (additional information + force logfile + verbose)
                  Default is no.

ENDDOC

=pod

=head1 NAME

view_timestamp.pl - view quarantine utilities

=head1 SYNOPSIS

Updates the last_accessed timestamp of views that are in use, but not written to.

=head1 DECRIPTION

view_timestamp.pl is a auxilary utility that supports the functionality of
view_q.pl. Reason is, that view_q.pl makes used of the "last_accessed"
timestamp, with is only updated when an actual write is committed to the view.

view_timestamp.pl scans the ClearCase log for any views opened (started) and
forces a recompilation of the config spec, which does nothing (as the config
spec isn't changed) but updates the timestamp, which then tells view_q.pl
that the view has been used recently and thus preventing that the view is
quarantined in view_q.pl's scheduled runs.

=head1 SUPPORT

Visit http://wiki.praqma.net/acc/comp/view_q for more information.

=head1 Script Implementation

=head2 Internal subfunctions

=cut

### Usual stuff ###

my ( $log, $verbose, $log_enable, $prev_exe_datetime, $gotlog, $log_file );

### Switch arguments ###
our ( $sw_logfile, $sw_debug, $sw_verbose, $sw_help, $sw_run );

### Arrays for log processing ###
my ( @fulllog, @views );

### Execution order ###

validate_options();    # Check all is good
enable_log();
get_views();
touchviews();
$log->information("done");
exit $log->get_accumulated_errorlevel();

###################  SUBS  ###################
sub getviewunc ($$) {

=pod

=head3 getviewunc (\$localpath, \$uncpath)

Loop through regions in search of a view's unc path.
The input parameters are references, where the \$uncpath will be updated
by the function.

=over

=item Parameters

=item *
1'st is reference to local view storage

=item *
2'nd is reference to a view's UNC path

=back

=over

=item Returns

=item *
0 on success

=item *
non-zero on failure

=back

=cut

    my $localpath = shift;
    my $uncpath   = shift;

    foreach my $region (`cleartool lsregion`) {
        chomp $region;
        my $ret = `cleartool lsview -region $region -storage $$localpath 2>&1`;
        if ( $ret =~ m/error/i ) {
            $sw_debug && $log->information("No view registered for view path $$localpath in region $region\n");
            next;
        } else {

            # Any number of whitespaces or * (if the view is started) followed by non-whitespace chars (the view tag)
            # followed by some whitespaces and tne another set of non-whitespace chars (the view storage UNC)
            ( $$uncpath = $ret ) =~ s/^[\s\*]*(\S*)\s*(\S*)$/$2/;
            chomp $$uncpath;
            $log->information("View path $$localpath in region $region maps to $2\n");
            return 0;    # found the unc, exit happy.
        }
        return 1;        # No way we should have made it this far...
    }

}

sub stampdynamic ($) {

=pod

=head3 stampdynamic ($viewtag)

Set dynamic view's config spec to current, (using C<cleartool setcs -current VIEWTAG> )
because that will update the view's Last Accessed time stamp.

=over

=item Parameters:

=item *
1'st is the viewtag to update

=back

=over

=item Returns:

=item *
0 on Success

=item *
non-zero on failure

=back

=cut

    my $tag = shift;
    my $cmd = "cleartool setcs -current -tag $tag 2>&1";
    $sw_debug && $log->information("DEBUG: SetCS command: [$cmd]\n");
    my @retval = `$cmd`;
    if ($?) {
        $log->warning("Could set config spec on $tag:\n");
        foreach (@retval) { $log->warning("$_"); }
        $log->information("\n");
        return 1;
    }
    $log->information("OK. Last access stamp on dynamic view [$tag] is now current\n");
    return 0;
}

sub stampsnapshot ($$) {

=pod

=head stampsnapshot ($$)

Remove the file .access_info that resides in the local view-storage directory.
We can not use C<cleartool setcs -current VIEWTAG> on snapshot views, without modifying the
actual view contents. As a minimum, all files in the view will become hijacked,
and the user will start complaining quite rapidly.

But if we just shut down that view's view-server process, and remove the file, it
will automatically be recreated next time a view-server is started for that view -
and the file creation or modification date is used by ClearCase to report the Last
Accessed timestamp

=over

=item Paramters

=item *
1'st the the local view storage location to look in

=item *
2'nd is the viewtag

=back

=over

=item Returns:

=item *
0 on Success

=item *
non-zero on failure

=back

=cut

    my $lpath = shift;
    my $tag   = shift;

    my $cmd = "cleartool endview -server -tag $tag 2>&1";
    $sw_debug && $log->information("DEBUG: End snapshot view command: [$cmd]\n");
    my @retval = `$cmd`;

    my $infofile = "$lpath\\.access_info";
    $sw_debug && $log->information("DEBUG: Access info file is named [$infofile]\n");
    if ( -e $infofile ) {    # expected file exists ?
        if ( unlink $infofile ) {    # unlink returns Number of files deleted
            $sw_verbose && $log->information("Succesfully deleted [$infofile]\n");
            $log->information("OK. Last access stamp on snapshot at [$lpath] is now current\n");
            return 0;
        } else {
            $log->warning("Could not delete $infofile\n");
            return 1;
        }

    } else {
        $log->information("File $infofile not found, so can not delete\n");
        return 1;
    }
}

sub rmtemptag ($) {

=pod

=head3 rmtemptag ($viewtag)

In order to have this script do what we want, we may have created at temporary
view tag (see L<mktemptag|mktemptag ($viewtag, $uncpath)"> ) for touching a view. So we need to clean up.

=over

=item Parameters:

=item *
1'st    the view tag to remove

=back

=over

=item Returns:

=item *
0 for success

=item *
non-zero for failure

=back

=cut

    my $tag = shift;

    # stop the view server process
    my $cmd = "cleartool endview -server $tag 2>&1";
    $sw_debug && $log->information("DEBUG: Endview command: [$cmd]\n");
    my @retval = `$cmd`;    # No output is expected from command
                            # remove the tag
    $cmd = "cleartool rmtag -view $tag 2>&1";
    $sw_debug && $log->information("DEBUG: rmtag command: [$cmd]\n");
    @retval = `$cmd`;

    if ($?) {
        $log->error("Trouble removing the temporary tag: [$tag]\n");
        foreach (@retval) { $log->error("$_"); }
        $log->information("\n");
        return 1;
    }
    $log->information("Viewtag [$tag] has been removed\n");
    return 0;

}

sub mktemptag ($$) {

=pod

=head3 mktemptag ($viewtag, $uncpath)

Tag a view temporarily. In order to create a view tag, we need at tag name
and an global-storage path which is in UNC format.

=over

=item Parameters:

=item *
1. the view tag

=item *
2. the view's uncpath

=back

=over

=item Returns:

=item *
0 on Success

=item *
non-zero on failure

=back

=cut

    my $tag = shift;
    my $unc = shift;
    my $cmd = "cleartool mktag -view -tag $tag -nstart $unc 2>&1";
    $sw_debug && $log->information("DEBUG: Tag command: [$cmd]\n");
    my @retval = `$cmd`;
    if ($?) {
        $log->warning("Could not create tag :\n");
        foreach (@retval) { $log->warning("$_"); }
        $log->information("\n");
        return 1;
    }
    $log->information("Viewtag [$tag] has been created on $unc\n");
    return 0;
}

sub touchviews {

=pod

=head3 touchviews

Loops through the local views storages we isolated in @fulllog array

If clearcase can't resolve the storage to a registered view, it is
probably tagged in a different region. So we will find that region
so the unc path can be determined, by calling L<getviewunc|"getviewunc (\$localpath, \$uncpath)">

Then we will temporarily create a tag for the view in this region, and
remove the tag after the view have been touched.

=over

=item Parameters:

=item *
None

=back

=over

=item Returns:

=item *
None

=back

=cut

    my ( $viewlocal, $viewunc, $is_temptag, $viewtag, $reply, $i );

    foreach $viewlocal (@fulllog) {

        $is_temptag = 0;
        $reply      = `cleartool lsview -s -storage $viewlocal 2>&1`;

        # not tagged here, find where and tag it
        if ( $reply =~ m/error:/i ) {

            # get view's uncpath
            unless ( getviewunc( \$viewlocal, \$viewunc ) ) {
                $log->warning("Failed getting UNC path for storage [$viewlocal], skipping.\n");
                next;
            }

            # generate a temp tag
            $viewtag = "_RMTAG_ONLY_" . $i++;

            # tag that view here
            unless ( mktemptag( $viewtag, $viewunc ) ) {
                $log->warning("Failed setting local view tag on [$viewunc] , skipping [$viewlocal]\n");
                next;
            }
            $is_temptag = 1;    # Cache that we made that tag
        } else {                # that view is tagged in current region, isolate viewtag
            chomp $reply;
            $viewtag = $reply;

        }

        my @cmd = grep { /^Properties:/i } `cleartool lsview -properties -full -storage $viewlocal 2>&1`;

        if ( $cmd[0] =~ m/dynamic/i ) {
            $sw_debug && $log->information("Found dynamic view [$viewtag] at [$viewlocal], calling stampdynamic\n");
            stampdynamic($viewtag);

        } elsif ( $cmd[0] =~ m/snapshot/i ) {
            $sw_debug && $log->information("Found snapshot view [$viewtag] at [$viewlocal], calling stampsnapshot\n");
            stampsnapshot( $viewlocal, $viewtag );
        } else {
            $log->warning("View type at [$viewlocal] not recognized, view not processed\n");
        }

        # Stop the view-server process

        `cleartool endview -server $viewtag`;

        if ($is_temptag) {
            rmtemptag($viewtag);
        }
    }
}

sub get_views {

=pod

=head get_views()

This function retrieves the contents of the clearcase log I<view>. If no this script
does not find it's own log file, the entire log will be processed, if it's logfile does
exist, we will use the last modification time of that at file and only get the view log
since that time.

After retrieval, the we will isolate only the unique local view storage path's that have
been used, and add them to the internal array @fulllog.

The initial retrieval only selects the lines that contains "Using View", which all will be
looking like this:

 2006-11-09T14:03:32+01 view_server(1172): Using view C:\ccstorage\views\CCCQ7\student\student_view3.vws, on host: CCCQ7

=over

=item Parameters:

=item *
None

=back

=over

=item Returns:

=item *
None

=back

=cut

    my @loggedviews;
    my %seen = ();
    my @lines = grep { /Using view/i } `cleartool getlog $prev_exe_datetime view`;

    if ($sw_debug) {
        $log->information("DEBUG: Lines in \@lines:\n");
        foreach (@lines) {
            $log->information("DEBUG: $_");
        }
        $log->information("DEBUG: No more lines in \@lines\n");
    }

    # Isolate log timestamp and view-storage path
    foreach (@lines) {
        my @arr = split / /, $_;

        # magic ehh!, nah it is only the 4'th element that is interesting
        chop $arr[4];    # 4'th element has an unwanted comma at the end
                         # the lines in @loggedviews looks like this:
                         # "C:\ccstorage\views\CCCQ7\student\student_view3.vws"
        push @loggedviews, "$arr[4]";
    }

    if ($sw_debug) {
        $log->information("DEBUG: Lines in \@loggedviews before isolation\n");
        foreach (@loggedviews) {
            $log->information("DEBUG: $_\n");
        }
        $log->information("DEBUG: No more lines in \@loggedviews\n");
    }

    # isolate unique entries.
    my @unique = grep { !$seen{$_}++ } @loggedviews;

    # isolate existing path's

    foreach ( sort @unique ) {
        if ( -e $_ ) {
            push @fulllog, "$_";
        } else {
            $log->information("Ignoring listed view storage at [$_], it has probabably been deleted\n");
        }
    }

    if ($sw_debug) {
        $log->information("DEBUG: Lines in \@fulllog after isolation\n");
        foreach (@fulllog) {
            $log->information("DEBUG: $_\n");
        }
        $log->information("DEBUG: No more lines in \@fulllog\n");
    }
}

sub getlastexecution ($) {

=pod

=head3 getlastexecution (\$lasttime)

Get last modification time stamp from logfile if one exists.

If it does not exist, the $lasttime is set to C< -full>, because $lasttime is
used by the call to C<cleartool getlog >, and if we have never been in action before
we want to consider all views.

If on the other hand this script's logfile exist, we will set $lasttime to a string looking
like this C< -since yyyy-mm-ddThh:mm:ss>, the Format that is suitable for
cleartool getlog -since format.

=over

=item Parameters:

=item *
1'st: Reference to scalar meant for use with cleartool getlog

=back

=over

=item Returns:

=item *
0 for success

=item *
non-zero for failure

=back


=cut

    my $lasttime = shift;

    if ( -e $log_file ) {

        # get last modification time for log file in UTC time
        my $mtime = ( stat($log_file) )[9];
        my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime($mtime);
        $year = $year + 1900;
        $mon  = $mon + 1;       # january is month 0, so have to add 1

        # format it after "2006-11-09T09:31:33 UTC"
        my $startstamp = sprintf( "%04d-%02d-%02dT%02d:%02d:%02d", $year, $mon, $mday, $hour, $min, $sec );
        $sw_debug && print " Formatted time is : $startstamp\n ";
        $$lasttime = " -since $startstamp";
        return 0;
    } else {
        $$lasttime = " -full";
        return 0;
    }
    return 1;                   # something went wrong
}

sub enable_log {

=pod

=head3 enable_log ()

Enables the log, and start logging to the logfile.

Will kill the script exit on ARGV errors - printing the arguments

=item Parameters:

=item *
None

=back

=over

=item Returns:

=item *
None

=back

=cut

    $log = scriptlog->new;
    $log->set_logfile($log_file);
    $log->set_verbose($sw_verbose);
    $log->enable();

    # Checks ARGV for consistency, exit 1 if there unknown options
    if ( scalar(@ARGV) gt 0 ) {
        $log->set_verbose(1);
        $log->assertion_failed("You have value(s) (@ARGV) with no defined reference,\n$usage");
        exit $log->get_accumulated_errorlevel();
    }

    $sw_verbose && $log->information("Verbose is ON\n");
    $sw_debug   && $log->information("Debug is ON\n");

    if ( $prev_exe_datetime =~ /-full/ ) {
        $log->information("Didn't find previous executions, defaulting to search entire log\n");

    } else {
        $log->information("Will search log $prev_exe_datetime\n");
    }
}

sub validate_options {

=pod

=head3 validate_options ()

Reads and validate the command line options, as well as establish default values

=item Parameters:

=item *
None

=back

=over

=item Returns:

=item *
None

=back

=cut

    #        Check command line options, assign defaults

    ## Only tested on windows
    unless ( $ENV{'OS'} =~ /^Windows/i ) {
        die "$Scriptfile has only been written for use on Windows platform, which we did not seem to find\n";
    }

    my %options = (

        "help!"     => \$sw_help,       # Display help (
        "logfile=s" => \$sw_logfile,    # User supplied log file name.
        "debug!"    => \$sw_debug,      # Debug
        "verbose!"  => \$sw_verbose,    # Verbose output
        "run!"      => \$sw_run         # Do it flag, the script will only attempt to touch views if this switch is on
    );

    die "$usage" unless GetOptions(%options);

    # close with help
    defined($sw_help) && do {
        print $header. $revision . $usage . $doc;
        exit 1;
    };

    !defined($sw_run) && do {
        print "Won't process anything unless -run is on specified\n";
        exit 1;
    };

    # seems we are good to go
    # overwrite logfile name if defined
    $log_file   = defined($sw_logfile) ? "$sw_logfile" : $Scriptdir . "view_timestamp.log";
    $sw_verbose = defined($sw_debug)   ? $sw_debug     : $sw_verbose;

    getlastexecution( \$prev_exe_datetime );    # look for last execution

	# Ensure consistent time formatting, see IBM Tech note 1249021
    $ENV{'CCASE_ISO_DATE_FMT'} = "1";


}

###################  END OF ALL SUBS  ###################

__END__

=pod

=head1 Bugs

None known at this time, but there may be a problem with running the script from
a network location, if the 2 machines are not time synchronized from the same source.

That is because we rely on the modification time stamp on our logfile, but that timestamp
will be set by the remote filesystem, so there may be a discrepancy. To overcome that you
should use the -logfile parameter and define a local logfile.

=head1 To Do

Only dynamic views and snapshot views are supported. CCRC and other webviews are
not supporteed yet but that may come in the future.

Add support for ClearCase LT, on LT views are tagged a bit differently.


=cut


