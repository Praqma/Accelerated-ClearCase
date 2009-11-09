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
our $TRIGGER_NAME = "ACC_CHECKOUT_LATEST";


# vob: is on of clientvob | adminvob | both
our $TRIGGER_INSTALL = "mktrtype -preop checkout -element -all vob:clientvob";

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
#     On checkout the trigger checks if the element is the latest and 
#     prompts the user for action if the is a newer version of the element.
#
#     This script supports self-install (execute with the -install
#     switch to learn more).
#
#     Read the POD documentation in the script for more details
#     Date:       2009-09-21
#     Author:     Mikael Jensen, mij\@praqma.net
#     Copyright:  Praqma A/S
#     License:    GNU General Pulic License v3.0
#     Support:    http://launchpad.net/acc
#########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR         NOTE
----------  -------------  ----------------------------------------------
2009-09-21  Mikael Jensen  1st release prepared for Novo (version 0.1.1)

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

#mij HMM virker ikke overbevisende - hold øje...


if ($ENV{'CLEARCASE_TRIGGER_DEBUG'}) {
    $debug = 1;
    $log->dump_ccvars;                                        # Run this statement to have the trigger dump the CLEARCASE variables
}

# End of standard stuff
# ------------------------------------
# Here starts the actual trigger code.
my $cmd = "cleartool find \"$ENV{CLEARCASE_PN}\" -version version(\\$ENV{CLEARCASE_BRTYPE}\\LATEST) -print";
my $latest = `$cmd`;
chomp($latest);
if ($latest eq $ENV{CLEARCASE_XPN}) {
	$log->information("This element is latest version \n");
	exit 0;
} else {
	$log->information("Not latest element version. \n Enforcing trigger on $ENV{'CLEARCASE_PN'} \n");
}

#my ( $dir_delim, $possible_dupe, $dupver );
#my $viewkind = $ENV{CLEARCASE_VIEW_KIND};
#my $pathname = $ENV{CLEARCASE_XPN};
#my $sfx      = $ENV{'CLEARCASE_XN_SFX'} ? $ENV{'CLEARCASE_XN_SFX'} : '@@';
my $pathname = $ENV{CLEARCASE_XPN};
#my $sfx      = $ENV{'CLEARCASE_XN_SFX'} ? $ENV{'CLEARCASE_XN_SFX'} : '@@';

if ( $ENV{'OS'} =~ /[Ww]indows/ ) {
    # Convert any "X:\view_tag\vob_tag\.\*" to "X:\view_tag\vob_tag\*"
    $pathname =~ s/\\.\\/\\/;
    my $dir_delim = "\\";
} else {
    my $dir_delim = "/";
}

my $prompt = "This elemente is not the latest available. \\n";
my ( $parent, $element ) = acc::split_dir_file($pathname);
$prompt = "$prompt [-$parent-{$element}].\\n";
$prompt = "$prompt Would you like to update the element to LATEST before checkout?\\n";
$prompt = "$prompt yes = Update the element $parent to LATEST\\n";
$prompt = "$prompt no = Continue checkout of current version of $parent \\n";
$prompt = "$prompt abort = cancel checkout operation \\n \\n";
$prompt = "$prompt Action is logged in logfile:\\n " . $log->get_logfile;
$prompt = "$prompt \\n (if you expect/experience alot of these, you might want to abort and update the view)";

`clearprompt yes_no -pro \"$prompt\" -type error -mask yes,no,abort -default abort -newline -prefer_gui`;
my $result = $?;
# if "NO" is selected
if ($result == 256) {
	$log->information("Element $ENV{'CLEARCASE_PN'} is not latest available, but accepted by user");
	exit 0;
}
# if "YES" is selected
if ($result == 0) {
	# Do something to update the view
	# check the status of the update
	# if good update exit 0
	# if bad update exit 1 with explanation
	$log->information("You have YES to update the file");
	my $update = `cleartool update \"$ENV{'CLEARCASE_PN'}\"`;
	if ($?) {
		$log->error("Update of $ENV{'CLEARCASE_PN'} failed with $update");
		exit 1;
	}
	$log->information($update);
	exit 0;
}
if ($result == 512) {
	$log->information("You have chosen to abort");
	# prevent the operation
	exit 1;	
}

$log->error("Clearprompt returned an unexpected error");
exit 1;
__END__

######################## DOCUMENTATION ##############################

=pod

=head1 NAME

checkout_latest - ClearCase trigger

Script:        F<checkout_latest.pl>

Trigger name:  C<ACC_CHECKOUT_LATEST>

Used as a generic trigger which warns when trying to checkout an element that is not the latest - please see the Description

=head1 SYNOPSIS

Runs as ClearCase trigger script installed on any vob, but primaryly on basevobs and ucmvobs ( it less likely to create elements on adminvobs or pvobs).

The scripts installs itself correctly when executed outside a trigger context using:

  (ratl)perl stop_twin -install -vob \thevob

To learn the full syntax simply execute the the script without the -vob switch:

  stop_twin -install

=head2 Restrictions

During the install process, that script is supposed to run under the account which owns the VOB.
The script will fail if that is not the case.

An exception is if you execute it in -preview mode

=head1 DESCRIPTION

In ClearCase all files and directories are elements, and directory elements are versioned just like file elements are.
Every ClearCase element is identfied by an Object ID internally in ClearCase, and these Object ID's each have a name.
Each version of a Directory Element contains a list of file- or directory names which where contained by the directory
element - in that version, and a diff of two versions will display a change in the list of names contained by the directory
element. $sfx      = $ENV{'CLEARCASE_X

In a normal filesystem we delete files - or names - in order to remove them from the directory, but in ClearCase, because the names
actually are names of other elements, we can not accept that an entire element vanishes from Clearcase, just because we don't like or
need the name anymore.
So Clearcase does the only right thing - it removes the name from the directory element version.

Suppose that we at some time after removing the name foo.c from a directory version, ClearCase by itself does not stop us from creating
a brand new element, with the name foo.c, and have that recorded in the directory contents, but what ClearCase has created for us is 2
completely different element, with a history and contents of their own - but they look, by their name - like identical twins.
And they are evil. ClearCase can - and will not - merge what you see as one file, because it is 2 files.

That is the evil twin situation - and this trigger script, prevents the situation from happening, by looking in previous versions of the
directory if the name has been used. If the name have been used, you are not allowed to reuse it.

If you must reuse the name, you will need to merge a directory version that contains the name in question to the
directory version you are working with.

=head2 Case sensivity

By default the trigger operates in Case sensitive mode, so elements with for instance  CamelCase errors can be renamed
without involving the vob owner.

The case sensitive pattern matching can be changed to case insensitive if that is required, to do that, you will edit the
trigger script and change the line

        my $case_sensitive = 1;

to

        my $case_sensitive = 0;

=head2 Bypassing the trigger.

To bypass the script you must create the appropriate semaphore file first
(see the POD documentation for praqma::trigger_helper->enable_semaphore_backdoor).

It goes without saying, that to avoid misuse of this ability ClearCase administrators should make sure
that triggers are executed - and semaphore files ar looked-up - at locations where common users only
have read access.

=head1 AUTHOR

Jens Brejner, E<lt>jbr@praqma.netE<gt>.

=head1 BUGS

See the website below.

=head1 COPYRIGHT

This program is distributed under the GNU General Pulic License v3.0

Support:    http://launchpad.net/acc

=for html <a href="http://launchpad.net/acc">Project home at Launchpad</a>

=cut
