require 5.000;
use strict;
our ($Scriptdir, $Scriptfile);
BEGIN{
	$Scriptdir =".\\";$Scriptfile = $0;                                # Assume the script is called from 'current directory' (no leading path - $0 is the file)
	$Scriptfile =~/(.*\\)(.*)$/ &&  do{$Scriptdir=$1;$Scriptfile=$2;}  # Try to match on back-slashes (file path included) and correct mis-assumption if any found
}
use lib $Scriptdir."..";
use praqma::scriptlog;
use praqma::trigger_helper;

#Required if you call trigger_helper->enable_install
our $TRIGGER_NAME="ACC_RMEMPTYBR";                                             
our $TRIGGER_INSTALL="mktrtype -element -all -postop uncheckout,rmbranch,rmver vob:clientvob";   # vob: is on of clientvob | adminvob | both

# File version
our $VERSION = "1.0"; 
our $REVISION = "1";

my $verbose_mode=1;

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$REVISION                                      
#     This script is intended as trigger script for the 
#     $TRIGGER_NAME trigger.
#     The trigger runs after versions has beed removed from ClearCase 
#     (rmver, rmbranch and uncheckout) and checks if the removed version 
#     was the last on the branch, and if to removes the branch too.
#     This script supports self-install (execute with the -install 
#     switch to learn more).
#     Read the POD documentation in the script for more details
#     Date:       2009-08-17                                            '
#     Author:     Lars Kruse, lak\@praqma.net               
#     Copyright:  Praqma A/S
#     License:    GNU General Pulic License v3.0
#     Support:    http://launchpad.net/acc
#########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR  NOTE
----------  -------------  ---------------------------------------------------
2009-06-24  Lars Kruse     1st release prepared for Novo Nordisk (version 1.0.1)
------------------------------------------------------------------------------
ENDREVISION

#Enable the features in trigger_helper
our $thelp=trigger_helper->new;
$thelp->enable_install;
$thelp->require_trigger_context;
our $semaphore_file = $thelp->enable_semaphore_backdoor;

#Enable the features in scriptlog
our $log = scriptlog->new;
$log->conditional_enable(); #Define either environment variabel CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->set_verbose($verbose_mode);
our $logfile=$log->get_logfile;
($logfile) && $log->information("logfile is: $logfile\n");

#$log->dump_ccvars; # Run this statement to have the trigger dump the CLEARCASE variables

######### CHECK IF BRANCH IS EMPTY AND REMOVE IF NECESSARY ##############
if ( $ENV{CLEARCASE_OP_KIND} =~ /uncheckout|rmver/ ) { #Check that the events that fired the trigger is of the kind we support (rmbranch is dealt with later!)
	
	# Get out if brtype is 'main' even if it was empty we wouldn't attempt to delete it
	nice_exit(0) if ($ENV{CLEARCASE_BRTYPE} eq 'main');
	
	$ENV{'CLEARCASE_XPN'} =~ /(.*?)[\\\/](\d+)/; #split up to the element+branch part - and the the tailing integer;
	our $elem_br = $1;
	our $verno   = $2;
	  	
  # Get out if uncheckout isn't triggered by the zero-version
  if ($ENV{'CLEARCASE_OP_KIND'} eq "uncheckout"){
    nice_exit(0) if ($verno != 0); # If the version isn't the zero-version then the branch isn't empty - get out, do nothing!
  }

  # Get out if rmver doesn't leave an empty branch
  if ($ENV{'CLEARCASE_OP_KIND'} eq "rmver"){
     nice_exit(0) unless br_is_empty($elem_br);
   }
  
   nuke_br($elem_br);
   nice_exit(0);
}

######### CHECK IF BRANCH IS CASCADING OFF AN EMPTY BRANCH ##############
if ( $ENV{CLEARCASE_OP_KIND} =~ /rmbranch/ ) { #Check that the events that fired the trigger is of the kind we support

	# Get out if the parent branch is 'main'
	my @brs = split(/[\\\/]/,$ENV{CLEARCASE_ID_STR}); #split on delimers
	nice_exit(0) if ($brs[$#brs-1] eq 'main'); # check that our parent (the second-to-last) isn't main 
	
  $ENV{'CLEARCASE_XPN'} =~ /(.*)[\\\/].+/; #Get the XPN to the parent branch of the element;
  my $elem_br = $1;
  
  nuke_br($elem_br) if ( br_is_empty($elem_br) ); # nuke it if it's empty
	nice_exit(0);
}

$log->warning("This script is triggered by an event which it was not originally designed to handle\t\tMaybe it's not installed correct?");
exit 1;

####################################  SUBS   #################################################
sub br_is_empty($){
	my $elem_br = shift;
  my $cmd = "cleartool lsvtree -all \"$elem_br\"";
  my @vtree_elem_br = `$cmd`;
  if ($?){ # The lsvtree command failed!
    $log->error("The command: '$cmd' failed");
    nice_exit(1);
  }
  
  # An empty branch has two element in total:
  #   1: The branch itself
  #   2: The zero-version on the branch
  # Thus, if the highest valid index of the array should is larget than 1, then the branch isn't empty
  if ($#vtree_elem_br > 1){
  	return 0; # There are more versions on the branch - return false
  }  
  return 1; 
}

sub nuke_br($){
 	my $elem_br = shift;
	my $comment="Automatic removal of empty branch by trigger ($Scriptfile)";
	$log->information($comment."\n");
  my $cmd = "cleartool rmbranch -force -c \"$comment\" \"$elem_br\"";
  system($cmd);
  if ($?){ # The rmbranch command failed!
    $log->error("The command: '$cmd' failed\n\t\tUnable to determine state of ".$ENV{CLEARCASE_BRTYPE}."\n");
    nice_exit(1);
  }
  return 1;	
}

sub nice_exit($){
	my $retval = shift;
  system("cleartool update \"$ENV{'CLEARCASE_PN'}\"") if ($ENV{'CLEARCASE_VIEW_KIND'} eq 'snapshot' );
  exit $retval;
}