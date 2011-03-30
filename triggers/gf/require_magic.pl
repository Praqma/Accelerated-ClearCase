require 5.004;
use strict;

BEGIN {

    # Ensure that the view-private file will get named back on rejection.
    END {
        rename( "$ENV{CLEARCASE_PN}.mkelem", $ENV{CLEARCASE_PN} )
          if $? && !-e $ENV{CLEARCASE_PN} && -e "$ENV{CLEARCASE_PN}.mkelem";
    }
}

our( $Scriptdir, $Scriptfile );

BEGIN {
    $Scriptdir  = ".\\";
    $Scriptfile = $0;      # Assume the script is called from 'current directory' (no leading path - $0 is the file)
    $Scriptfile =~ /(.*\\)(.*)$/
      && do {
        $Scriptdir  = $1;
        $Scriptfile = $2;
      }                    # Try to match on back-slashes (file path included) and correct mis-assumption if any found
}

use lib $Scriptdir. "..\\..";

use praqma::scriptlog;
use praqma::trigger_helper;

#Required if you call trigger_helper->enable_install
our $TRIGGER_NAME = "ACC_REQ_MAGIC";

our %install_params = (
    "name"     => $TRIGGER_NAME,                    # The name og the trigger
    "mktrtype" => "-preop mkelem -element -all",    # The stripped-down mktrtype command
    "supports" => "bccvob,ucmvob",                  # csv list of generic and/or custom VOB types (case insensetive)
);

# File version
our $VERSION  = "1.0";
our $REVISION = "2";

# This trigger won't be feasible on CC Remote Clients, they will use the magic file on the CCRC Server.
# - please see http://www-01.ibm.com/support/docview.wss?uid=swg21417790
exit 0 if $ENV{'ATRIA_WEB_GUI'};

my $verbose_mode = 0;                               # Setting the verbose mode to 1 will print the logging information to STDOUT/ERROUT ...even it the log-file isn't enabled
my $debug_on     =
  defined( $ENV{'CLEARCASE_TRIGGER_DEBUG'} )
  ? $ENV{'CLEARCASE_TRIGGER_DEBUG'}
  : undef;

# Header and revision history
our $header = <<ENDHEADER;
################################################################################
    $Scriptfile  version $VERSION\.$REVISION
    This script is intended as ClearCase trigger script for the
    $TRIGGER_NAME trigger.

    The trigger prevents creation of new element if the User Environment
    Variable MAGIC_PATH has not been set to a net work share containing .magic
    files

    run cleartool man cc.magic for more information about .magic files.

    This script supports self-install (execute with the -install
    switch to learn more).

    Read the POD documentation in the script for more details
    Date:       2010-07-08
    Author:     Jens Brejner, jbr\@praqma.net
    Copyright:  Praqma A/S
    License:    GNU General Pulic License v3.0
    Support:    http://launchpad.net/acc
################################################################################
ENDHEADER

# Revision information
################################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR         NOTE
----------  -------------  ----------------------------------------------
2010-07-08  Jens Brejner   1st release prepared for Grundfos (v1.0.1)
2010-10-02  Jens Brejner   Add silent exit for CC Remote clients (v1.0.2)
----------  -------------  ----------------------------------------------
ENDREVISION

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;
$thelp->enable_install( \%install_params );    #Pass a reference to the install-options
$thelp->require_trigger_context;

# Look for semaphore, respecting a local semaphore path via env. var.
our $semaphore_status = $thelp->enable_semaphore_backdoor();

#Enable the features in scriptlog
our $log = scriptlog->new;
$log->conditional_enable();                    #Define either environment variabel CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->set_verbose;                             #Define either environment variabel CLEARCASE_TRIGGER_VERBOSE=1 or SCRIPTLOG_VERBOSE=1 to start printing to STDOUT
our $logfile = $log->get_logfile;
($logfile) && $log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.
($logfile) && $log->information($semaphore_status);
($logfile) && $log->dump_ccvars;                              # Run this statement to have the trigger dump the CLEARCASE variables

my $helphere = "http://dkclearp04.emea.group.grundfos.com/CCHelp";

if ( lc( $ENV{'CLEARCASE_OP_KIND'} ) eq "mkelem" ) {          # continue only if operation type is what we are intended for..

    if ( $ENV{MAGIC_PATH} ) {
        $log->information("Found env var MAGIC_PATH\n");

        # Valid MAGIC_PATH is a semi-colon seperated list of directories, let's look at each
        my @locations = split /;/, $ENV{MAGIC_PATH};
        foreach my $dir (@locations) {
            $log->information("MAGIC_PATH lists $dir\n");
            foreach my $file (qx(dir "$dir\\*.magic" /b 2>&1)) {
                last if $?;                                   #  if "File not found"
                chomp($file);
                my $magic = "$dir\\$file";
                $log->information("Found magic file called $magic\n");
                if ( -r $magic ) {
                    exit 0;                                   # found readable magic file, we are done.
                } else {
                    $log->information(" - but $magic is not readable\n");
                }    # end if ( -r $magic ) {
            }    # end foreach my $file
        }    # end foreach my $dir

        fail();    # didn't find any readable magic files, complain about it
    } else {
        fail();    # didn't find the MAGIC_PATH environment variable
    }
}    #

################################# SUBS #########################################

sub fail {

    #        exit while complaining...

    print "Missing or incorrect MAGIC_PATH User environment variable\n";
    print "Please follow the instructins at $helphere\n";
    qx(start $helphere 2>&1);    # blind attempt to open the web page for the user.

    # prevent the operation
    exit 1;

}

$log->enable(1);                 # force enable
$log->dump_ccvars();             # print variables
$log->error( "Trigger script $Scriptfile file should never have ended here in line " . __LINE__ . "\n" );
exit 1;

__END__

######################## DOCUMENTATION ##############################
=pod

=head1 NAME

require_magic.pl is intended as a ClearCase Trigger script.

Script:        F<require_magic.pl>


=head1 SYNOPSIS

If a client attempts to create a new element in ClearCase this trigger will
require the environment variable MAGIC_PATH to exist and the location must contain
at least one readable .magic file. "cleartool man cc.magic" for more information
about ClearCase Magic file.

=head1 DESCRIPTION

The trigger is useable if you have customized element types, and want to have new
elements typed correctly (to you custom element types) when they are added to source
control.

When adding a new element types to a vob, the magic file must be changed if the
file-typing should work. The default magic file exists on each client, and it is
error-prone to try update or modify the magic file in each client. You can how-ever
make every client see the same magic file by having each client create the
MAGIC_PATH environment variable. Search Rational ClearCase support site for more
information about the MAGIC_PATH environment variable.


=head2 Restrictions

ClearCase Remote Clients doesn't support usage of MAGIC_PATH environment variable. So
the trigger exits silently if a CCRC is detected (ATRIA_WEB_GUI environment variable exists).

=head2 Dependencies

praqma::scriptlog;
praqma::trigger_helper;

=head1 AUTHOR

Jens Brejner, E<lt>jbrejner@praqma.netE<gt>.

=head1 BUGS

See the website below.

=head1 COPYRIGHT

This program is distributed under the GNU General Pulic License v3.0

Support:    http://launchpad.net/acc

=for html <a href="http://launchpad.net/acc">Project home at Launchpad</a>

=cut


