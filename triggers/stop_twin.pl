require 5.000;
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
      && do { $Scriptdir = $1; $Scriptfile = $2; }    # Try to match on back-slashes (file path included) and correct mis-assumption if any found
}

use lib $Scriptdir. "..";

use praqma::scriptlog;
use praqma::trigger_helper;

#Required if you call trigger_helper->enable_install
our $TRIGGER_NAME    = "STOP_TWIN";
our $TRIGGER_INSTALL = "mktrtype -preop lnname -element -all vob:both";    # vob: is on of clientvob | adminvob | both

# File version
our $VERSION  = "1.0";
our $REVISION = "19";

my $verbose_mode = 1;

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$REVISION
#     This script is intended as ClearCase trigger script for the
#     $TRIGGER_NAME trigger.
#
#     The trigger prevents creation of evil twins in ClearCase.
#
#     This script supports self-install (execute with the -install
#     switch to learn more).
#
#     Read the POD documentation in the script for more details
#     Date:       2009-07-28
#     Author:     Jens Brejner, jbr\@praqma.net
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
2008-10-24  Jens Brejner   1st release prepared for Novo (version 0.1.1)
2009-01-16  Jens Brejner   2st release prepared for Novo (version 1.0.18)
                           Minor edits and cleanup after Novo internal
                           review.
-------------------------  ----------------------------------------------
ENDREVISION

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;
$thelp->enable_install;

print "HEY ! Need to remove here, before releasing\n";

#        $thelp->require_trigger_context;

our $semaphore_file = $thelp->enable_semaphore_backdoor;

#Enable the features in scriptlog
our $log = scriptlog->new;
$log->conditional_enable();    #Define either environment variable CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->set_verbose($verbose_mode);
our $logfile = $log->get_logfile;
($logfile) && $log->information("logfile is: $logfile\n");
$log->information("Searching valid semaphore file at '$semaphore_file'\n\t\t...but couldn't find any!\n");

my $debug = 0;                 # Write more messages to the log file
$ENV{'CLEARCASE_TRIGGER_DEBUG'} && do {
    $log->dump_ccvars;         # Run this statement to have the trigger dump the CLEARCASE variables
    $debug = 1;
};

## Here starts the actual evil twin searching code.

my $case_sensitive = 0;        # 1 means Case Sensitive name matching

my ( $dir_delim, $possible_dupe, $dupver );
my $viewkind = $ENV{CLEARCASE_VIEW_KIND};
my $pathname = $ENV{CLEARCASE_PN};
my $sfx      = $ENV{'CLEARCASE_XN_SFX'} ? $ENV{'CLEARCASE_XN_SFX'} : '@@';

if ( $ENV{'OS'} =~ /[Ww]indows*/ ) {

    # Convert any "X:\view_tag\vob_tag\.\*" to "X:\view_tag\vob_tag\*"
    $pathname =~ s/\\.\\/\\/;
    $dir_delim = "\\";
} else {
    $dir_delim = "/";
}
$debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$pathname is now [$pathname]\n" );

# split element name in dir and leaf
$pathname =~ /(.*)([\/\\])(.*)$/;
my $parent  = $1;
my $element = $3;

$debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$parent is now [$parent]\n" );
$debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$element is now [$element]\n" );

# Make parent directory DNA
my $parent_dna = "$parent" . "$dir_delim" . ".$sfx";
$debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$parent_dna is now [$parent_dna]\n" );

# Are we in a snapshot view?
my $snapview;
if ( exists( $ENV{'CLEARCASE_VIEW_KIND'} ) && $ENV{'CLEARCASE_VIEW_KIND'} ne 'dynamic' ) {
    $snapview = 1;
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " Viewtype is SNAPSHOT\n" );
} else {
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " Viewtype is DYNAMIC\n" );

    # The 2nd test is a special case for the vob root.
    $snapview = !-e "$parent$sfx/main" && !-e "$parent/$sfx/main";
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " Value of \$snapview after vob root test is [$snapview]\n" );
}

# Now search for evil twin
my $found = 0;
my $pattern;
if ($case_sensitive) {
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " Case sensitive matching is performed\n" );
    $pattern = "$element$sfx";
} else {
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " Case INSENSITIVE matching is performed\n" );
    $pattern = "(?i)$element$sfx";
}

$debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$pattern is [$pattern]\n" );

foreach my $branchversion ( reverse qx(cleartool lsvtree -a -s -obs -nco "$parent_dna") ) {
    chomp $branchversion;
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " Looking at \$branchversion: $branchversion\n" );
    chomp( my @match = grep /$pattern$/, `cleartool ls -s \"$branchversion\"` );
    if (@match) {
        $dupver = $match[$#match];
        $debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$dupver before = [$dupver]\n" );
        $dupver =~ s/\\/\//g;    # normalize path sep
        $debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$dupver normalized = [$dupver]\n" );
        $dupver =~ s/(.*)($sfx)$/$1/;    # strip directory part
        $found = $dupver;
        $debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$dupver after = [$dupver]\n" );
        last;
    }
}

# No duplicate element is found on invisible branches
# Allow the creation of the element.
exit 0 unless $found;

# Possible duplicate element is found - start logging.
$log->enable();
my $user      = "$ENV{'CLEARCASE_USER'}";
my $pop_kind  = "$ENV{'CLEARCASE_POP_KIND'}";
my $vob_owner = `cleartool desc -fmt %u vob:$ENV{'CLEARCASE_VOB_PN'}`;

my $prompt = " Trigger $TRIGGER_NAME prevented operation [$pop_kind]\\n";
$prompt = "$prompt because an evil twin possibility was detected:\\n\\n";

if ( $pop_kind eq "mkelem" ) {

    # From a mkelem command
    $prompt = "$prompt The name: [$element]\\n";

} else {

    # From a "ln", "ln -s" or "mv" command
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " Operation is not mkelem, but $pop_kind\n" );
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$ENV{'CLEARCASE_PN2'} is [$ENV{'CLEARCASE_PN2'}]\n" );
    $ENV{'CLEARCASE_PN2'} =~ /(.*[\/\\])(.*)$/;
    my $old_path_name = $1;
    chomp( my $old_element_name = $2 );

    #        Rev 18 take out
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$old_path_name = [$old_path_name]\n" );
    $debug && $log->information( "DEBUG\tLine " . __LINE__ . " \$old_element_name = [$old_element_name]\n" );

    if ( !$pop_kind || ( $pop_kind eq "rmname" ) || ( $pop_kind eq "mkslink" ) ) {

        $debug && $log->information( "DEBUG\tLine " . __LINE__ . " Operation is not mkelem, but $pop_kind\n" );
        $prompt = "$prompt The element name [$element]\\n";

    }
}

$prompt = "$prompt ALREADY exists for the directory:\\n [$parent]\\n";
$prompt = "$prompt in another branch as:\\n";
$prompt = "$prompt [$found].\\n";
$prompt = "$prompt \\n";
$prompt = "$prompt NOTE:  If you feel you really need to perform this action\\n";
$prompt = "$prompt e-mail the VOB_OWNER ($vob_owner).\\n\\n";

foreach ( split ( /\\n/, $prompt ) ) {
    $log->warning("$_\n");
}

$prompt = "$prompt Action is logged in logfile:\\n " . $log->get_logfile;

`clearprompt yes_no -pro \"$prompt\" -type error -mask abort -default abort -newline -prefer_gui`;
$log->DESTROY();

# Stop operation
exit 1;

__END__

######################## DOCUMENTATION ##############################

=pod

=head1 NAME

stop_twin - ClearCase trigger

Script:        F<stop_twin.pl>

Trigger name:  C<STOP_TWIN>

Used as a generic trigger which prevents creation of evil twins in ClearCase - please see the Description

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

To bypass the script you must create the appropriate semaphore file first
(see the POD documentation for praqma::trigger_helper->enable_semaphore_backdoor).

It goes without saying, that to avoid misuse of this ability ClearCase administrators should make sure
that triggers are executed - and semaphore files ar looked-up - at locations where common users only
have read access. ...There! I said it anyway!

=head1 DESCRIPTION

In ClearCase all files and directories are elements, and directory elements are versioned just like file elements are.
Every ClearCase element is identfied by an Object ID internally in ClearCase, and these Object ID's each have a name.
Each version of a Directory Element contains a list of file- or directory names which where contained by the directory
element - in that version, and a diff of two versions will display a change in the list of names contained by the directory
element.

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



=head1 AUTHOR

Jens Brejner, E<lt>jbr@praqma.netE<gt>.

=head1 BUGS

See the website below.

=head1 COPYRIGHT

This program is distributed under the GNU General Pulic License v3.0

Support:    http://launchpad.net/acc

=for html <a href="http://launchpad.net/acc">Project home at Launchpad</a>

=cut
