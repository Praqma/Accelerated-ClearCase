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
our $TRIGGER_NAME = "ACC_NAMED_BRTYPES_ONLY";

# vob: is on of clientvob | adminvob | both
our $TRIGGER_INSTALL = "mktrtype -element -all -preop mkbranch vob:both";

# File version
our $VERSION  = "1.1";
our $REVISION = "3";

my $verbose_mode = 0;    # Setting the verbose mode to 1 will print the logging information to STDOUT/ERROUT ...even it the log-file isn't enabled

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$REVISION				
#     This script is intended as ClearCase trigger script for the       
#     $TRIGGER_NAME trigger.                                            
#                                                                       
#     This script is intended as trigger script (element -all)          
#     on the mkbranch event. It monitors a list of approved branches    
#     and requires that no branches are created except these.           #                                                                       
#     Date:       2009-10-07                                            
#     Author:     Mikael Jensen, mij\@praqma.net              		
#     License:    GNU General Pulic License v3.0                        
#     Support:    http://launchpad.net/acc                              
#########################################################################
ENDHEADER


# Revision information
#########################################################################
my $revision = <<ENDREVISION;
DATE        EDITOR  NOTE
----------  -------------  ----------------------------------------------
2006-10-26  Lars Kruse     1st release prepared for Novo Nordisk
                           (version 1.0.1)
2009-10-07  Mikael Jensen  ACC'ified (version 1.1.2)
-------------------------------------------------------------------------
ENDREVISION

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;
$thelp->enable_install;
$thelp->require_trigger_context;

our $semaphore_status = $thelp->enable_semaphore_backdoor;

#Enable the features in scriptlog
our $log = scriptlog->new;

# Define either environment variable CLEARCASE_TRIGGER_DEBUG=1 or
# SCRIPTLOG_ENABLE=1 to start logging
$log->conditional_enable();
$log->set_verbose($verbose_mode);

our $logfile = $log->get_logfile;
($logfile) && $log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.
$log->information($semaphore_status);


my $debug = 0; # Write more messages to the log file


if ($ENV{'CLEARCASE_TRIGGER_DEBUG'}) {
    $debug = 1;
}
($debug) && $log->dump_ccvars; # Dumps Clearcase variables if debug is defined

# End of standard stuff
# ------------------------------------
# Here starts the actual trigger code.
if ( ( $ENV{CLEARCASE_OP_KIND} eq "mkbranch") ) { #Check that the events that fired the trigger are the ones we support
	my $regexp = "main"; # list of branches that are allowed to create "brtype|brtype|..."
	unless ($ENV{'CLEARCASE_BRTYPE'}=~/$regexp/){
	    my $opkind =lc($ENV{'CLEARCASE_OP_KIND'});
	    my $brtype =  $ENV{'CLEARCASE_BRTYPE'};
	    $log->information(
	        "ERROR \n...triggered by a [$opkind $brtype] event.\n\n".
	        "You are about to create a branch that is not approved\n".
	        "The config spec of your view might be wrong!\n\n".
	        "Contact the Configuration Manager \n".
	        "or ClearCase Admin to get help!");
            exit 1;
	}
}
exit 0;

#################### sub functions #######################


__END__

######################## DOCUMENTATION ##############################

=pod

=head1 NAME

named_brtypes_only - ClearCase trigger

Script:        F<named_brtypes_only.pl>

Trigger name:  C<ACC_NAMED_BRTYPES_ONLY>


=head1 SYNOPSIS

Runs as ClearCase trigger script installed on all vobtypes and is supposed to run on mkbranch operations.

The scripts installs itself correctly when executed outside a trigger context using:

  (ratl)perl named_brtypes_only.pl -install -vob \thevob

To learn the full syntax simply execute the the script without the -vob switch:

  named_brtypes_only -install

=head2 Restrictions

During the install process, that script is supposed to run under the account which owns the VOB.
The script will fail if that is not the case.

An exception is if you execute it in -preview mode

=head1 DESCRIPTION

The triggerscript monitors a list of approved branches and requires that no branches are created except those listed in the $regexp variable. It supports several matchstrings seperated by "|" (vertical bar aka "or" in regex's), but the match pattern is hardcoded (currently as "main").

=head2 Bypassing the trigger.

To bypass the script you must create the appropriate semaphore file first
(see the POD documentation for praqma::trigger_helper->enable_semaphore_backdoor).

It goes without saying, that to avoid misuse of this ability ClearCase administrators should make sure
that triggers are executed - and semaphore files ar looked-up - at locations where common users only
have read access.

=head1 AUTHOR

Mikael Jensen, E<lt>mij@praqma.netE<gt>.

=head1 BUGS

See the website below.

=head1 COPYRIGHT

This program is distributed under the GNU General Pulic License v3.0

Support:    http://launchpad.net/acc

=for html <a href="http://launchpad.net/acc">Project home at Launchpad</a>

=cut

