require 5.000;
use strict;

our ( $Scriptdir, $Scriptfile );

BEGIN {
 $Scriptdir  = ".\\";
 $Scriptfile = $0;      # Assume the script is called from 'current directory' (no leading path - $0 is the file)
 $Scriptfile =~ /(.*\\)(.*)$/
   && do {
  $Scriptdir  = $1;
  $Scriptfile = $2;
   }                    # Try to match on back-slashes (file path included) and correct mis-assumption if any found
}

use lib $Scriptdir. "..";

use praqma::scriptlog;
use praqma::trigger_helper;

#Required if you call trigger_helper->enable_install
our $TRIGGER_NAME = "ACC_AUTO_RECOMMEND_NEWBL";

our %install_params = (
 "name"     => $TRIGGER_NAME,                               # The name og the trigger
 "mktrtype" => "-ucmobject -all -postop mkbl_complete ",    # The stripped-down mktrtype command
 "supports" => "pvob,autorec"                               # csv list of generic and/or custom VOB types (case insensetive)
);

# File version
our $VERSION = "1.0";
our $BUILD   = "2";

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#
#    $Scriptfile  version $VERSION\.$BUILD
#
#    This script is intended as ClearCase trigger script for the
#    $TRIGGER_NAME trigger.
#
#    The trigger enforces that instantly when a baseline is created
#    on an integration stream it's recommended baseline(s) are also updated. 
#
#    The trigger finds the baselines in the foundation, and then the components 
#    behind thes baselines. Then the latest baseline in each component is set 
#    as the recommended.
#
#    This script supports self-install (execute with the -install
#    switch to learn more).
#
#    Date:       2010-03-10
#    Author:     Lars Kruse, lak\@praqma.net
#    Copyright:  Praqma A/S
#    License:    GNU General Pulic License v3.0
#    Support:    http://launchpad.net/acc
#
#########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR         NOTE
----------  -------------  ----------------------------------------------
2011-01-12  Lars Kruse     1st release prepared for Novo (version 1.0.1)
-------------------------  ----------------------------------------------

ENDREVISION

my $verbose_mode =
  defined( $ENV{'CLEARCASE_TRIGGER_VERBOSE'} )
  ? $ENV{'CLEARCASE_TRIGGER_VERBOSE'}
  : undef;
my $debug_on =
  defined( $ENV{'CLEARCASE_TRIGGER_DEBUG'} )
  ? $ENV{'CLEARCASE_TRIGGER_DEBUG'}
  : undef;

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;
$thelp->enable_install( \%install_params );    #Pass a reference to the install-options
$thelp->require_trigger_context;

# Look for semaphore, respecting a local semaphore path via env. var.
our $semaphore_status = $thelp->enable_semaphore_backdoor();

#Enable the features in scriptlog
our $log = scriptlog->new;

#Define either environment variable CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->conditional_enable();

#Define either environment variable CLEARCASE_TRIGGER_VERBOSE=1 or SCRIPTLOG_VERBOSE=1 to start printing to STDOUT
$log->set_verbose();
our $logfile = $log->get_logfile;

# Logfile is null if logging isn't enabled.
($logfile) && $log->information("logfile is: $logfile\n");
($logfile) && $log->information($semaphore_status);

# Run this statement to have the trigger dump the CLEARCASE variables
($logfile) && $log->dump_ccvars;

########################### MAIN ###########################

# values from trigger environment
my $project = $ENV{'CLEARCASE_PROJECT'};
my $stream  = $ENV{'CLEARCASE_STREAM'};
my ( $short_stream, $pvob ) = split /\@/, $stream;

# find the integration stream
my $cmd                = 'cleartool desc -fmt %[istream]p project:' . $project . ' 2>&1';
my $project_int_stream = `$cmd`;
die "ERROR::$TRIGGER_NAME, [$cmd] returned [$project_int_stream]\n" if ($?);

#Leave quietly if we have nothing to do
exit 0 unless ( $short_stream eq $project_int_stream );

# Get the foundation baselines of the stream;

$cmd = 'cleartool  desc -fmt %[found_bls]Xp stream:' . $stream . ' 2>&1';
my $retval = `$cmd`;
die "ERROR::$TRIGGER_NAME, [$cmd] returned [$retval]\n" if ($?);

# Get the components behind the baselines

my @found_comps;
foreach ( split / /, $retval ) {
 $cmd = 'cleartool desc -fmt %[component]Xp ' . $_ . ' 2>&1';
 my $retval = `$cmd`;
 die "ERROR::$TRIGGER_NAME: [$cmd] returned [$retval]\n" if ($?);
 push @found_comps, $retval;
}

# find the LATEST baselines of the components in foundation of the stream
my @latest_bls;
foreach (@found_comps) {
 $cmd = 'cleartool lsbl -s -comp ' . $_ . ' -stream ' . $stream . ' -level INITIAL 2>&1';
 my $retval = `$cmd`;
 die "ERROR::$TRIGGER_NAME: $cmd returned $retval\n" if ($?);
 my @bls = split /\n/, $retval;
 push @latest_bls, pop @bls;
}

# Turn the list into a csv list
my $csv_bls = join ",", @latest_bls;

$cmd    = "cleartool chstream -c \"Trigger $TRIGGER_NAME is automatically recommending latest baselines\" -rec $csv_bls $stream";
$retval = `$cmd`;
die "ERROR::$TRIGGER_NAME: $cmd returned $retval\n" if ($?);
print "Trigger $TRIGGER_NAME recommend baseline(s) $csv_bls on stream $short_stream\n";
exit 0;
