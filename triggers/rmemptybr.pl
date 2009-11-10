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

our $TRIGGER_NAME="ACC_RMEMPTYBR"; # The Trigger name is cached to it can be referenced in the header.

our %install_params = (
  "name"        => $TRIGGER_NAME,                                         # The name og the trigger
  "mktrtype"    => "-element -all -postop uncheckout,rmbranch,rmver ",    # The stripped-down mktrtype command
  "supports"    => "bccvob,ucmvob",                                       # csv list of generic and/or custom VOB types (case insensetive)
);

# File version
our $VERSION = "1.1"; 
our $REVISION = "2";

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$REVISION                                      
#     This script is intended as trigger script for the 
#     $TRIGGER_NAME trigger.
#     The trigger runs after versions, reserved checkouts or branches has 
#     beed removed from ClearCase (rmver, rmbranch and uncheckout) and 
#     checks if the operation left an empty branch and if so, removes the 
#     branch too. The trigger always updates the removed or uncheckedout 
#     element if the view is a snapshot view.
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
2009-11-09  Lars Kruse     Making it compliant with the new trigger_helper
                           (version 1.1.2)
------------------------------------------------------------------------------
ENDREVISION
fs
##################
snap_load();

######### CHECK IF BRANCH IS EMPTY AND REMOVE IF NECESSARY ##############
if ( $ENV{CLEARCASE_OP_KIND} =~ /uncheckout|rmver/ ) { #Check that the events that fired the trigger is of the kind we support (rmbranch is dealt with later!)
	
	# Get out if brtype is 'main' even if it was empty we wouldn't attempt to delete it
	exit 0  if ($ENV{CLEARCASE_BRTYPE} eq 'main');
	
	$ENV{'CLEARCASE_XPN'} =~ /(.*?)[\\\/](\d+)/; #split up to the element+branch part - and the the tailing integer;
	our $elem_br = $1;
	our $verno   = $2;
	  	
  # Get out if uncheckout isn't triggered by the zero-version
  if ($ENV{'CLEARCASE_OP_KIND'} eq "uncheckout"){
    exit 0  unless ($verno = 0); # Get out NOW - unless the version is the zero-version - then we'll nuke it.
  }

  # Get out if rmver doesn't leave an empty branch
  if ($ENV{'CLEARCASE_OP_KIND'} eq "rmver"){
     exit 0  unless br_is_empty($elem_br); # Get out NOW - unless the branch is empty - then we'll nuke it.
   }
  
  nuke_br($elem_br);
  exit 0 ;
}

######### CHECK IF BRANCH IS CASCADING OFF AN EMPTY BRANCH ##############
if ( $ENV{CLEARCASE_OP_KIND} =~ /rmbranch/ ) { #Check that the events that fired the trigger is of the kind we support

	# Get out if the parent branch is 'main'
	my @brs = split(/[\\\/]/,$ENV{CLEARCASE_ID_STR}); #split on delimers
	exit 0  if ($brs[$#brs-1] eq 'main'); # check that our parent (the second-to-last) isn't main 
	
  $ENV{'CLEARCASE_XPN'} =~ /(.*)[\\\/].+/; #Get the XPN to the parent branch of the element;
  my $elem_br = $1;
  
  nuke_br($elem_br) if ( br_is_empty($elem_br) ); # nuke it if it's empty
	exit 0;
}

# If the CLEARCASE_OP_KIND isn't recognized at this point, then we're off limits!
$log->warning("This script is triggered by an event which it was not originally designed to handle\t\tMaybe it's not installed correct?");
exit 1; # Error code 1 on a post-op trigger will automatically cause a warning.

####################################  SUBS   #################################################
sub br_is_empty($){
	my $elem_br = shift;
  my $cmd = "cleartool lsvtree -all \"$elem_br\"";
  my @vtree_elem_br = `$cmd`;
  if ($?){ # The lsvtree command failed!
  	my $output = join ",",@vtree_elem_br;
    $log->error("The command: '$cmd' failed\n");
    exit 1 ; 
  }
  # An empty branch has two element in total:
  #   1: The branch itself
  #   2: The zero-version on the branch
  # Thus, if the highest valid index of the array should is larget than 1, then the branch isn't empty
  if ($#vtree_elem_br > 1){
  	return 0; # There are more versions on the branch - return false
  }  
  return 1; #Else it's true - the branch is empty!
}

sub nuke_br($){
 	my $elem_br = shift;
 	$elem_br =~ /.*\@\@(.+)/;
  $log->information_always("Trigger script ($Scriptfile) is removing empty branch:\n  $1\n");
  my $cmd = "cleartool rmbranch -force -c \"Automatic removal of empty branch by trigger ($Scriptfile)\" \"$elem_br\"";
  $log->information("Executing: $cmd\n"); 
  my $output = `$cmd`;
  if ($?){ # The rmbranch command failed!
    $log->error("The command: '$cmd' failed:\n$output\nUnable to determine state of ".$ENV{CLEARCASE_BRTYPE}."\n");
    exit 1;
  }                  
  $log->information("Result was:\n\>\>\>\n$output\n\<\<\<\n");
  return 1;	
}

sub snap_load(){
	if ($ENV{'CLEARCASE_VIEW_KIND'} eq 'snapshot' ){ #update the element
	  my $cmd = "cleartool update -log nul \"$ENV{'CLEARCASE_PN'}\"";	  
	  $log->information("Executing: $cmd\n"); 
	  my $output = `$cmd`;
    if ($?){ # The update failed
      $log->error("The command: '$cmd' failed\n");
    }
    $log->information("Result was:\n\>\>\>\n$output\n\<\<\<\n");
    $ENV{CLEARCASE_XPN} =~ /.*\@\@(.+)/;
    $log->information_always("Loading the predecossor to the removed version:\n  $1\n");                    
	}; 
}


######################## DOCUMENTATION ##############################
=pod

=head1 NAME

rmemptybr - ClearCase trigger

Script:        F<rmemptybr.pl>

Trigger name:  C<ACC_RMEMPTYBR>

Used as a trigger to remove empty branches if necessary after versions or branches has been removed.

=head1 SYNOPSIS

Runs as ClearCase trigger script installed on VOBs that hold elements (everything but AdminVOBs and PVOBs)

The scripts installs itself correctly when executed outside a trigger context using:

  rmemptybr.pl -install -vob \thevob

To learn the full syntax simply execute the the script without the -vob switch:

  rmemptybr.pl -install
  
(...or consult the POD documentation for praqma::trigger_helper).

=head2 Restrictions

During the install process, that script is supposed to run under the account which owns the VOB. 
The script will fail if that is not the case.

An exception is if you execute it in -preview mode

To bypass (diable witoput uninstalling) the script the admin must create the appropriate semaphore file first 
(see the POD documentation for praqma::trigger_helper->enable_semaphore_backdoor).

=head1 DESCRIPTION

When a version is removed from a branch or a checkout is undone, then the predecessor becomes the new LATEST. 
But if the removed version is the only one on the branch except the zero version it means that the branch is 
left empty and it really ought to be removed.
    
Another situation that can lead to dangeling empty branches is if a config spec is set up to create "cascading 
branches". Then you have intentionally empty branches with no other purpose than to hold other branches coming 
off from it - but if the leaf branches are removed - then so should the in-between branches.

The trigger is fires post-op and in case og snapshort views it deals with the unpleasant side-effect that if 
you remove a version from a snapshot view then the element will have the status [not loaded]. This triggers 
will re-load the element.

=head1 AUTHOR

Lars Kruse, E<lt>lak@praqma.netE<gt>.

=head1 BUGS

See the website below.

=head1 COPYRIGHT

This program is distributed under the GNU General Pulic License v3.0

Support:    http://launchpad.net/acc

=for html <a href="http://launchpad.net/acc">Project home at Launchpad</a>

=cut