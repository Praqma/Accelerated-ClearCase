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
our $TRIGGER_NAME="ACC_NAMED_BRTYPES_ONLY";

our %install_params = (
  "name"        => $TRIGGER_NAME,                                         # The name og the trigger
  "mktrtype"    => "-element -all -preop mkbranch",                       # The stripped-down mktrtype command
  "supports"    => "NovoNordiskDocVOB",                                   # csv list of generic and/or custom VOB types (case insensetive)
);

# File version
our $VERSION  = "1.1";
our $REVISION = "2";

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$REVISION
#     This script is intended as ClearCase trigger script for the
#     $TRIGGER_NAME trigger.
#
#     This script is intended as trigger script (element -all)
#     on the mkbranch event. It monitors a list of approved branches
#     and requires that no branches are created except these.           
#     Date:       2009-10-07
#     Author:     Lars Kruse, lak\@praqma.net
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
2009-11-12  Mikael Jensen+  
            Lars Kruse     ACC-ified (version 1.1.2)
-------------------------------------------------------------------------
ENDREVISION

#Enable the features in trigger_helper
our $thelp=trigger_helper->new;
$thelp->enable_install(\%install_params);  #Pass a reference to the install-options
$thelp->require_trigger_context;
our $semaphore_status = $thelp->enable_semaphore_backdoor;

#Enable the features in scriptlog
our $log = scriptlog->new;
$log->conditional_enable(); #Define either environment variabel CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->set_verbose();        #Define either environment variabel CLEARCASE_TRIGGER_VERBOSE=1 or SCRIPTLOG_VERBOSE=1 to start printing to STDOUT
our $logfile=$log->get_logfile;
($logfile) && $log->information("logfile is: $logfile\n"); # Logfile is null if logging isn't enabled.
$log->information($semaphore_status);
$log->dump_ccvars; # Run this statement to have the trigger dump the CLEARCASE variables


### Allow CHECKOUTS ON CERTAIN BRANCHES ONLY ###
if ( ( $ENV{CLEARCASE_OP_KIND} eq "mkbranch") ) { #Check that the events that fired the trigger are the ones we support
	my $regexp = "main"; # list of branches that are allowed to create "brtype|brtype|..."
    my $brtype =  $ENV{'CLEARCASE_BRTYPE'};
	unless ($brtype=~/$regexp/){
	    $log->error("ERROR \n...triggered by a [mkbranch $brtype] event.\n\n".
        "You are about to create a branch that is not approved\n".
        "The config spec of your view might be wrong!\n\n".
        "Contact the Configuration Manager or ClearCase Admin to get help!");
        exit 1;
	}
}
exit 0;

__END__

######################## DOCUMENTATION ##############################

=pod

=head1 NAME

named_brtypes_only - ClearCase trigger

Script:        F<named_brtypes_only.pl>

Trigger name:  C<ACC_NAMED_BRTYPES_ONLY>

=head1 SYNOPSIS

Runs as ClearCase trigger script installed on special VOB types ("NovoNordiskDocVOB")

The scripts installs itself correctly when executed outside a trigger context using:

  (ratl)perl named_brtypes_only.pl -install -vob \thevob

To learn the full syntax simply execute the the script without the -vob switch:

  named_brtypes_only -install

=head2 Restrictions

During the install process, that script is supposed to run under the account which owns the VOB.
The script will fail if that is not the case.

An exception is if you execute it in -preview mode

=head1 DESCRIPTION

The triggerscript monitors a list of approved branches and requires that no branches are created except 
those listed in the $regexp variable within the script itself. In the version released for NovoNordiskDocVOB 
types it only supports "main".

=head2 Bypassing the trigger.

To bypass the script you must create the appropriate semaphore file first
(see the POD documentation for praqma::trigger_helper->enable_semaphore_backdoor).

=head1 AUTHOR

Lars Kruse E<lt>lak@praqma.netE<gt>.

=head1 BUGS

See the website below.

=head1 COPYRIGHT

This program is distributed under the GNU General Pulic License v3.0

Support:    http://launchpad.net/acc

=for html <a href="http://launchpad.net/acc">Project home at Launchpad</a>

=cut
