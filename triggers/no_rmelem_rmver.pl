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
our $TRIGGER_NAME="ACC_NO_RMELEM_RMVER";                                             
our $TRIGGER_INSTALL="mktrtype -element -all -preop rmver,rmelem vob:clientvob";   # vob: is on of clientvob | adminvob | both

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
#     The trigger prevent rmelem and rmver operations - unless you
#     are the VOB owner.
#     This script supports self-install (execute with the -install 
#     switch to learn more).
#     Read the POD documentation in the script for more details
#     Date:       2009-06-24                                            
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
$log->information("Searching valid semaphore file at '$semaphore_file'\n\t\t...but couldn't find any!\n");

#$log->dump_ccvars; # Run this statement to have the trigger dump the CLEARCASE variables

# Cache the vobowner
our ($domain, $vobowner) = split /\\/, `cleartool desc -fmt \"\%\[owner\]p\" vob:$ENV{CLEARCASE_VOB_PN}`;

######### PREVENT REMOVAL OF VERSIONS AND ELEMENTS ##############
unless ( lc($vobowner) eq lc($ENV{CLEARCASE_USER}) ){ # Do nothing if user is the vob owner

  if ( ( $ENV{CLEARCASE_OP_KIND} eq "rmver") ||  ($ENV{CLEARCASE_OP_KIND} eq "rmelem") ) { #Check that the events that fired the trigger are the ones we support
  	my $object = ($ENV{CLEARCASE_OP_KIND} eq "rmver")  # Cache what 'mode' we're runningto make a meaningful message
  	               ? "version" 
  	               : "element";
    my $msg = "The trigger $Scriptfile has refused the removal of the $object:\n".
              "\t\t$ENV{CLEARCASE_XPN}\n";
    $log->information($msg);
    exit 1;
  }
  $log->warning("This script is triggered by an event which it was not originally designed to handle\t\tMaybe it's not installed correct?");
}


exit 0; #Comment out this statement when debugging, and let the next take over
print "OK, since you are the vobwoner!, but exit=1 in debug mode to prevent destruction of element/version during test\n"; exit 1;
__END__

######################## DOCUMENTATION ##############################
=pod

=head1 NAME

no_rmelem_rmver - ClearCase trigger

Script:        F<no_rmelem_rmver.pl>

Trigger name:  C<NO_RMELEM_RMVER>

Used as a generic trigger which prevents rmelem and rmver (unless the user happens to be the vobowner).

=head1 SYNOPSIS

Runs as ClearCase trigger script installed on basevobs and ucmvobs (not adminvobs or pvobs)

The scripts installs itself correctly when executed outside a trigger context using:

  no_rmelem_rmver.pl -install -vob \thevob

To learn the full syntax simply execute the the script without the -vob switch:

  no_rmelem_rmver.pl -install

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

Elements and versions of elements can be removed by the users who owns them. This trigger prevents the 
operations all togeteher - with the vobowner as the built-in exception.




=head1 AUTHOR

Lars Kruse, E<lt>lak@praqma.netE<gt>.

=head1 BUGS

See the website below.

=head1 COPYRIGHT

This program is distributed under the GNU General Pulic License v3.0

Support:    http://launchpad.net/acc

=for html <a href="http://launchpad.net/acc">Project home at Launchpad</a>

=cut







