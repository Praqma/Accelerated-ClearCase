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
our $TRIGGER_NAME = "ACC_CO_LATEST_ONLY";

our %install_params = (
  "name"        => $TRIGGER_NAME,                                         # The name og the trigger
  "mktrtype"    => "-element -all -preop checkout",                       # The stripped-down mktrtype command
  "supports"    => "bccvob,ucmvob",                                       # csv list of generic and/or custom VOB types (case insensetive)
);

# File version
our $VERSION  = "1.0";
our $REVISION = "2";

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$REVISION
#     This script is intended as ClearCase trigger script for the
#     $TRIGGER_NAME trigger.
#
#     On checkout the trigger checks if the element is the latest and 
#     prompts the user for action if the is a newer version of the element.
#
#     This script supports self-install (execute with the -install
#     switch to learn more).
#
#     Read the POD documentation in the script for more details
#     Date:       2009-11-26
#     Author:     Lars Kruse, lak\@praqma.net
#     Copyright:  Praqma A/S
#     License:    GNU General Pulic License v3.0
#     Support:    http://launchpad.net/acc
#     Docs:       Goto http://wiki.praqma.net/acc 
#                 and search for "acc_co_latest_only"            
#########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR         NOTE
----------  -------------  ----------------------------------------------
2009-11-26  Lars Kruse     1st release prepared for Novo (version 0.1.1)
2009-12-02  Jens Brejner   1st Basic bug fixes (version 0.1.2)
-------------------------  ----------------------------------------------
ENDREVISION

#Enable the features in trigger_helper
our $thelp=trigger_helper->new;
$thelp->enable_install(\%install_params);  #Pass a reference to the install-options
$thelp->require_trigger_context;
our $semaphore_status = $thelp->enable_semaphore_backdoor;

#Enable the features in scriptlog
our $log = scriptlog->new;
$log->conditional_enable(); #Define either environment variabel CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->set_verbose;          #Define either environment variabel CLEARCASE_TRIGGER_VERBOSE=1 or SCRIPTLOG_VERBOSE=1 to start printing to STDOUT
our $logfile=$log->get_logfile;
($logfile) && $log->information("logfile is: $logfile\n"); # Logfile is null if logging isn't enabled.
$log->information($semaphore_status);
$log->dump_ccvars; # Run this statement to have the trigger dump the CLEARCASE variables

######### PREVENT CHECKOUT OF VERSIONS UNLESS THEY ARE LATEST ON THE BRANCH ##############

if ( ($ENV{CLEARCASE_VIEW_KIND} eq "snapshot") && ($ENV{CLEARCASE_OP_KIND} eq "checkout") )  {      #Check that the events that fired the trigger are the ones we support

  my $cmd = "cleartool find \"$ENV{CLEARCASE_PN}\" -version version(\\$ENV{CLEARCASE_BRTYPE}\\LATEST) -print 2>&1";
  my $latest = `$cmd`;
  
  print "\n\n[$latest]\n\n";
  
  
  ($? || ($latest eq "") ) && do{
  	$log->error("The result of the execution was unexpected please report to ClearCase Admin\n".
  	            "Execute:\n\>$cmd\n".
  	            "Return value was:\n$latest\n");
  	exit 1;
  };
  chomp($latest);
  if ($latest ne $ENV{CLEARCASE_XPN}) {
  	$log->error("THIS version is not the LATEST version on the branch. Update your snapshot view and try again\n".
  	            "   THIS   version: [$ENV{CLEARCASE_XPN}]\n".
  	            "   LATEST version: [$latest]\n");
    exit 1;	
  }
  exit 0;
}
__END__

######################## DOCUMENTATION ##############################

=pod

=head1 NAME

checkout_latest - ClearCase trigger

Script:        F<co_latest_only.pl>

Trigger name:  C<ACC_CO_LATEST_ONLY>

Used as a generic trigger which prevents checkouts in snapshot views of a version if that version is not the latest on it's branch.

=head1 SYNOPSIS

Runs as ClearCase trigger script installed on base ClearCase VOBs and UCM VOBs.

The script installs itself correctly when executed outside a trigger context using:

  co_latest_only.pl -install -vob \thevob

To learn the full syntax simply execute the the script without the -vob switch:

  co_latest_only.pl -install

=head2 Restrictions

During the install process, that script is supposed to run under the account which owns the VOB.
The script will fail if that is not the case.

An exception is if you execute it in -preview mode

=head1 DESCRIPTION

By default ClearCase allows any version to be checked out. But unless the version is the latest on it's branch it constitutes 
a rather odd case. And it's not typically a scenario you would want to end up in deliberately.

In snapshot views there is a tendency that this scenario occurs frequently because when a user checkes out a version, it's by 
default the one that is selected by the view, and if the view isn't updated and newer versions exists on the branch, then this trigger
will prevent it from happening, and the user is instructed to update the snapshot view and try againg.

The trigger has no effect if you are in a dynamic view. Assuming that if this scenario occurs in a dynamic view, it's because the user want it to happen.

=head2 Bypassing the trigger.

To bypass the script you must create the appropriate semaphore file first
(see the POD documentation for praqma::trigger_helper->enable_semaphore_backdoor).

It goes without saying, that to avoid misuse of this ability ClearCase administrators should make sure
that triggers are executed - and semaphore files ar looked-up - at locations where common users only
have read access.

=head1 AUTHOR

Lars Kruse, E<lt>lak@praqma.netE<gt>.

=head1 BUGS

See the website below.

=head1 COPYRIGHT

This program is distributed under the GNU General Pulic License v3.0

Support:    http://launchpad.net/acc

=for html <a href="http://launchpad.net/acc">Project home at Launchpad</a>

=cut
