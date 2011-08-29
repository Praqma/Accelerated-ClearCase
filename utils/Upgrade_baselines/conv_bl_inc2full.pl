use strict;
our ( $_packagedir, $_packagefile );

BEGIN {
  use File::Basename;
  ( $_packagefile, $_packagedir ) = fileparse(__FILE__);
}

# File version
our $VERSION = "0.7";
our $BUILD   = "15";

# Header history
our $header = <<ENDHEADER;
#########################################################################
#     $_packagefile version $VERSION\.$BUILD
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
2011-03-27  Jens Brejner   Version 0.7.14: Improved reporting fo views with no last access date
2011-06-15  Jens Brejner   Version 0.7.15: List ignored views, and optionally report by mail.
 
-------------------------------------------------------------------------
 
ENDREVISION

my $usage = <<ENDUSAGE;
$_packagefile -lsquarantine [-days DD] [-autopurge [-sendmail] | -autorecover]
$_packagefile -nasince YYYY-MM-DD | -nasince number [-autoquarantine] [-sendmail]
$_packagefile -quarantine stgloc
$_packagefile -recover stgloc
$_packagefile -purge stgloc
$_packagefile [-region region] -[no]ignore viewtag
$_packagefile -lsignored [-sendmail]
$_packagefile -help
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
                        or seperating with "; " eg. " ... -ignore tag1; tag2 -ignore tag3 "
                        
-lsignore               List views in ignore state.                         
 
-region region          Optional switch only valid together with -[no]ignore.
                        The region switch is used to qualify the viewtag applied with
                        -[un]ignore if necessary. if -region is omitted, the viewtag is
                        searched in the current region.
 
-sendmail               Optional. Sends mails to view owners  and administrator.
                        Requires the a file called to exist in the
                        same directory as $_packagefile. You must copy the supplied
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

# $_packagedir was defined in BEGIN block

use lib "$_packagedir";
use lib "$_packagedir\\..\\..";

use praqma::pcc;

# Store start time
my $t_begin = time();

# Get reference to Praqma ClearCase object
my $pccobj = pcc->new();

# Get
my (@comps);
foreach ( @{ $pccobj->get_pvobs() } ) {
  push @comps, @{ $pccobj->get_components() };
}

# my @comps = `cleartool lscomp -s  -invob $pvob`;

#
if ( $ARGV[0] ne "" ) {
  print "Filter: '$ARGV[0]'\n";
  @comps = grep( /$ARGV[0]/, @comps );
}

print "Found " . scalar(@comps) . " components that matched the filter\n";

foreach (@comps) {
  print "\t$_";
}

print "Processing " . scalar(@comps) . " components\n";

our $t_elapsed = time() - $t_begin;
print "Elapsed time (sec): $t_elapsed\n";

foreach (@comps) {
  chomp($_);
  my $comp = "component:$_\@$pvob";
  my $dot;
  print "############################################\n" . "Getting baselines in $comp\n";
  my @bls = `cleartool lsbl -s -component $comp`;
  my @inc_bls;

  $t_elapsed = time() - $t_begin;
  print "Elapsed time (sec): $t_elapsed\n";

  print "Processing " . scalar(@bls) . " baselines\n";

  print "Looking for those which are incrementally labeled\n";
  foreach (@bls) {
    chomp($_);
    my $bl = "baseline:$_\@$pvob";
    our $cmd = "cleartool desc -fmt \"[%[label_status]p] %n\\n\" $bl";
    $_ = `$cmd`;

    $dot = ".";
    (/\[Incrementally Labeled\]/) && do {
      push @inc_bls, $bl;
      $dot = "+";
    };
    print $dot;

  }

  print "\n";
  $t_elapsed = time() - $t_begin;
  print "Elapsed time (sec): $t_elapsed\n";

  print "Processing " . scalar(@inc_bls) . " incrementally labeled baselines\n";

  foreach (@inc_bls) {
    my $cmd = "cleartool chbl -full $_ >nul";
    print $_. "\n";
    system($cmd);
  }
  $t_elapsed = time() - $t_begin;
  print "Elapsed time (sec): $t_elapsed\n";

}

