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
our $TRIGGER_NAME = ""; # MISSING: Must have name


# vob: is on of clientvob | adminvob | both
our $TRIGGER_INSTALL = ""; # MISSING: examp: mktrtype -preop checkout -element -all vob:clientvob

# File version
our $VERSION  = "0.1";
our $REVISION = "1";

my $verbose_mode = 0;    # Setting the verbose mode to 1 will print the logging information to STDOUT/ERROUT ...even it the log-file isn't enabled

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$REVISION
#     This script is intended as ClearCase trigger script for the
#     $TRIGGER_NAME trigger.
#
#
#
#
#
#
#
#     Read the POD documentation in the script for more details
#     Date:       Not started
#     Author:     Mikael Jensen, mij\@praqma.net
#     License:    GNU General Public License v3.0
#     Support:    http://launchpad.net/acc
#########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR         NOTE
----------  -------------  ----------------------------------------------
YYYY-MM-DD  Mikael Jensen  1st release prepared for Customer (version 0.1.1)

-------------------------  ----------------------------------------------
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
$log->enable();


#$log->conditional_enable();
#$log->set_verbose($verbose_mode);
$log->set_verbose(1);
our $logfile = $log->get_logfile;
($logfile) && $log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.
$log->information($semaphore_status);


my $debug = 0;                                                # Write more messages to the log file


if ($ENV{'CLEARCASE_TRIGGER_DEBUG'}) {
    $debug = 1;
    $log->dump_ccvars;                                        # Run this statement to have the trigger dump the CLEARCASE variables
}

# End of standard stuff
# ------------------------------------
# Here starts the actual trigger code.

__END__

######################## DOCUMENTATION ##############################

=pod

=head1 NAME

Somename - ClearCase trigger

Script:        F<Somename.pl>

Trigger name:  C<Somename>


=head1 SYNOPSIS

Runs as ClearCase trigger script installed on

The scripts installs itself correctly when executed outside a trigger context using:

  (ratl)perl Somename -install -vob \thevob

To learn the full syntax simply execute the the script without the -vob switch:

  stop_twin -install

=head2 Restrictions

During the install process, that script is supposed to run under the account which owns the VOB.
The script will fail if that is not the case.

An exception is if you execute it in -preview mode

=head1 DESCRIPTION



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
