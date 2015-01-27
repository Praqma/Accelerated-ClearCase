require 5.000;
use strict;
our( $Scriptdir, $Scriptfile );

BEGIN {
    $Scriptdir  = ".\\";
    $Scriptfile = $0;      # Assume the script is called from 'current directory' (no leading path - $0 is the file)
    $Scriptfile =~ /(.*\\)(.*)$/
      && do { $Scriptdir = $1; $Scriptfile = $2; }    # Try to match on back-slashes (file path included) and correct mis-assumption if any found
}
use lib $Scriptdir. "..";
use praqma::scriptlog;
use praqma::trigger_helper;

our $TRIGGER_NAME = "ACC_LOCK_UCM_PROJECT";    # The Trigger name is cached to it can be referenced in the header.
our %install_params = (
    "name"     => $TRIGGER_NAME,                                                     # The name og the trigger
    "mktrtype" => "-ucmobject -all -stream -all -project -all -postop lock,unlock",  # The stripped-down mktrtype command
    "supports" => "pvob",                                                   # csv list of generic and/or custom VOB types (case insensitive)
);

# File version
our $VERSION  = "1.0";
our $REVISION = "1";

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#
#    $Scriptfile  version $VERSION.$REVISION
#
#    This script is intended as ClearCase trigger script for the
#    $TRIGGER_NAME trigger.
#
#    Triggers (post op) on lock/unlock for projects and streams
#    For projects it locks the integration stream
#    For streams it locks the corresponding branch type and all child streams
#
#    This script supports self-install (execute with the -install
#    switch to learn more).
#
#    Date:       2014-12-17
#    Author:     Olof Aldin
#    Copyright:  Praqma A/S
#    License:    GNU General Pulic License v3.0
#    Support:    mailto:support\@praqma.net
#
#########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR  NOTE
----------  -------------  ---------------------------------------------------
2014-12-17  Olof Aldin     Initial version
------------------------------------------------------------------------------
ENDREVISION

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;
$thelp->enable_install( \%install_params );    #Pass a reference to the install-options
$thelp->require_trigger_context;
our $semaphore_status = $thelp->enable_semaphore_backdoor;

#Enable the features in scriptlog
our $log = scriptlog->new;
$log->conditional_enable();                    #Define either environment variabel CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->set_verbose;                             #Define either environment variabel CLEARCASE_TRIGGER_VERBOSE=1 or SCRIPTLOG_VERBOSE=1 to start printing to STDOUT
our $logfile = $log->get_logfile;
($logfile) && $log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.
$log->information($semaphore_status);
$log->dump_ccvars;                                            # Run this statement to have the trigger dump the CLEARCASE variables

###

my $op_kind = $ENV{CLEARCASE_OP_KIND};
die "Trigger shouldn't fire ($0) for anything else than lock/unlock on projects, streams and branches (1)" if ($op_kind != "lock" and $op_kind != "unlock");

# Match on stuff like: project:ProjMan@\tstPVOB::
my $ucmObject = $ENV{CLEARCASE_UCM_OBJECT};
$ucmObject =~ /^(project|stream):([^@]+)@(\\.+)$/;
my $ucmType = $1;
my $ucmTypeName = $2;
my $ucmTypeVob = $3;

my $cmd = "";

die "Trigger shouldn't fire ($0) for anything else than lock/unlock on projects, streams and branches (2)" if ($ucmType != "project" and $ucmType != "stream");

if ($ucmType eq "project") {

  # get name of integration stream
  $cmd = "cleartool describe -fmt '%[istream]p' $ucmObject";
  my $ucmIntegStream = `$cmd`;
  $ucmIntegStream =~ s/'//g;

  # a project can exist without an integration stream
  if ($ucmIntegStream ne "") {
    # lock integration stream
    $cmd = "cleartool $op_kind stream:$ucmIntegStream\@$ucmTypeVob";
    #print $cmd . "\n";
    system($cmd);
  }

} elsif ($ucmType eq "stream") {

  my $ucmStreamBranch;
  $cmd = "cleartool describe stream:$ucmTypeName\@$ucmTypeVob";
  open(BRANCH, "$cmd |");
  my $tmp;
  while ($tmp=<BRANCH>) {
    chomp($tmp);
    # trim both ends of output for whitespace
    $tmp =~ s/^\s+|\s+$//g;
    if ($tmp =~ /^Guarding: brtype:([^@]+)@.*$/) {
      $ucmStreamBranch = $1;
      last;
    }
  }

  # lock/unlock branch type
  if ($ucmStreamBranch ne "") {
    $cmd = "cleartool $op_kind brtype:$ucmStreamBranch\@$ucmTypeVob";
    #print $cmd . "\n";
    system($cmd);
  }

  # get a list of child streams
  $cmd = "cleartool describe -fmt '%[dstreams]p' stream:$ucmTypeName\@$ucmTypeVob";
  #my $ucmChildStreams = `$cmd`;

  open(CHILD, "$cmd |");
  my $ucmChildStreams = <CHILD>;
  close(CHILD);

  # remove any ' outputted by cleartool
  $ucmChildStreams =~ s/'//g;
  # trim both ends of output for whitespace
  $ucmChildStreams =~ s/^\s+|\s+$//g;

  my @childStreams = split(' ', $ucmChildStreams);
  foreach my $childStream (@childStreams) {
    # trim both ends for whitespace
    $childStream =~ s/'//g;
	  $cmd = "cleartool $op_kind stream:$childStream\@$ucmTypeVob";
    #print $cmd . "\n";
    system($cmd);
  }
} else {
  die "This should never happen from trigger ($0)";
}
