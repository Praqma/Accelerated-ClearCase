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
our $TRIGGER_NAME="ACC_CHOW_ON_MKELEM";                                             

our %install_params = (
  "name"        => $TRIGGER_NAME,                                         # The name og the trigger
  "mktrtype"    => "-element -all -postop mkelem ",                       # The stripped-down mktrtype command
  "supports"    => "bccvob,ucmvob",                                       # csv list of generic and/or custom VOB types (case insensetive)
);

# File version
our $VERSION = "1.1"; 
our $REVISION = "2";

my $verbose_mode=1;

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$REVISION                                      
#     This script is intended as trigger script for the 
#     $TRIGGER_NAME trigger.
#     The trigger runs after elements has beed added to ClearCase and
#     changes the ownership of the element to the VOB owner account.
#     This script supports self-install (execute with the -install 
#     switch to learn more).
#     Read the POD documentation in the script for more details
#     Date:       2009-08-11                                            
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
2009-11-10  Lars Kruse     Made it compliant with the new enable_install method
------------------------------------------------------------------------------
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


# Cache the vobowner
our ($domain, $vobowner) = split /\\/, `cleartool desc -fmt \"\%\[owner\]p\" vob:$ENV{CLEARCASE_VOB_PN}`;

######### CHANGE THE OWNER OF THE ELEMENT ##############
  if ( $ENV{CLEARCASE_OP_KIND} eq "mkelem" ) { #Check that the events that fired the trigger is of the kind we support
  	
   my $cmd = "cleartool protect -chown $vobowner \"$ENV{CLEARCASE_PN}\" 2>&1";
   my $msg = "Changed the owner of element \"$ENV{CLEARCASE_PN}\" to '$vobowner'\n";
   $log->information($msg);
   my $output = `$cmd`;
   $log->warning("The attempt to protect the element failed with the message:\n\t\t$output") if $?;
   exit $?/256;
  }

$log->warning("This script is triggered by an event which it was not originally designed to handle\t\tMaybe it's not installed correct?");
exit 0;
__END__

######################## DOCUMENTATION ##############################
=pod

=head1 NAME

chow_on_mkelem - ClearCase trigger

Script:        F<chow_on_mkelem.pl>

Trigger name:  C<CHOW_ON_MKELEM>

Used as a trigger to change the ownership of newly added elemetns to be owned by the VOB owner.

=head1 SYNOPSIS

Runs as ClearCase trigger script installed on basevobs and ucmvobs (not adminvobs or pvobs)

The scripts installs itself correctly when executed outside a trigger context using:

  chow_on_mkelem.pl -install -vob \thevob

To learn the full syntax simply execute the the script without the -vob switch:

  chow_on_mkelem.pl -install

=head2 Restrictions

During the install process, that script is supposed to run under the account which owns the VOB. 
The script will fail if that is not the case.

An exception is if you execute it in -preview mode

To bypass the script you must create the appropriate semaphor file first 
(see the POD documentation for praqma::trigger_helper->enable_semaphore_backdoor).

It goes without saying, that to avoid misuse of this ability ClearCase administrators should make sure 
that triggers are executed - and semaphore files ar looked-up - at locations where common users only 
have read access. ...There! I said it anyway!

=head1 DESCRIPTION

Elements are per default owned by the user who creates them (adds them to source control) and element ownership 
means 'superpowers' ...superpowers which general users aren't supposed to have, so thererfor they are revoked 
instantly upon creation by this trigger.

=head1 AUTHOR

Lars Kruse, E<lt>lak@praqma.netE<gt>.

=head1 BUGS

See the website below.

=head1 COPYRIGHT

This program is distributed under the GNU General Pulic License v3.0

Support:    http://launchpad.net/acc

=for html <a href="http://launchpad.net/acc">Project home at Launchpad</a>

=cut