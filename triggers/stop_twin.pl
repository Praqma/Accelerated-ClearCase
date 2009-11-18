require 5.000;
use strict;

#REV lak: I've never seen a BEGIN END constuction used like this before. The $? is refering to "the result of he last system call"
#         What is "the last system call" when using this construction?
#         In plain: It cryptic what's going on here ;-)
BEGIN {

    # Ensure that the view-private file will get named back on rejection.
    END {
        rename( "$ENV{CLEARCASE_PN}.mkelem", $ENV{CLEARCASE_PN} )
          if $? && !-e $ENV{CLEARCASE_PN} && -e "$ENV{CLEARCASE_PN}.mkelem";
    }
}

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
our $TRIGGER_NAME = "ACC_STOP_TWIN";

our %install_params = (
  "name"        => $TRIGGER_NAME,                                         # The name og the trigger
  "mktrtype"    => "-preop lnname -element -all",                         # The stripped-down mktrtype command
  "supports"    => "bccvob,ucmvob",                                       # csv list of generic and/or custom VOB types (case insensetive)
);


# File version
our $VERSION  = "1.0";
our $REVISION = "22";

my $verbose_mode = 0;    # Setting the verbose mode to 1 will print the logging information to STDOUT/ERROUT ...even it the log-file isn't enabled

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

# Here starts the actual trigger code.
my $case_sensitive = 1;                                       # 0 means Case IN-Sensitive name matching

my ( $dir_delim, $possible_dupe, $dupver );
my $viewkind = $ENV{CLEARCASE_VIEW_KIND};
my $pathname = $ENV{CLEARCASE_XPN};
my $sfx      = $ENV{'CLEARCASE_XN_SFX'} ? $ENV{'CLEARCASE_XN_SFX'} : '@@';

if ( $ENV{'OS'} =~ /[Ww]indows/ ) {

    # Convert any "X:\view_tag\vob_tag\.\*" to "X:\view_tag\vob_tag\*"
    $pathname =~ s/\\.\\/\\/;
    $dir_delim = "\\";
} else {
    $dir_delim = "/";
}

# split element name in dir and leaf
my ( $parent, $element ) = acc::split_dir_file($pathname);

# Make parent directory DNA
#my $parent_dna = "$parent" . "$dir_delim" . ".$sfx";

my $parent_dna = "$parent.$sfx";

# Are we in a snapshot view?
my $snapview;
if ( exists( $ENV{'CLEARCASE_VIEW_KIND'} )
    && $ENV{'CLEARCASE_VIEW_KIND'} ne 'dynamic' )
{
    $snapview = 1;
} else {

    # The 2nd test is a special case for the vob root.
    $snapview = !-e "$parent$sfx/main" && !-e "$parent/$sfx/main";
}

$log->information("Snapview ? $snapview\n");

my $found = 0;
my $pattern;    # Casesensitive search pattern - or not

if ($case_sensitive) {
    $pattern = "$element";
} else {
    $pattern = "(?i)$element";
}

# get lines from lshist that begins with non-whitespace and ends with digit
my @lines =
  grep { /^\S.*\\\d+$/ } qx(cleartool lshist -nop -min -nco -dir -fmt "%Nc%Vn\\n" "$parent_dna");

#REV lak: It seems like you are only interested in lines starting with Added og Uncat.
#         It also seems the he new-line you are adding to output is used for nothing except chomping it again a few lines later
#         And even later your run another grep to see if the element is part of the Add/Uncat action)
#         So why no go:
#
# my @lines =
#   grep { /^Added.*?$element.*\\\d+$|^Uncat.*?$element.*\\\d+$/ } qx(cleartool lshist -nop -min -nco -dir -fmt "%Nc%Vn" "$parent_dna");
#
# HEY!!! I didn't actually test the reg-exp above ...might need adjustment, but point is it's possible to grep ONLY what actually interesting in one go!

# REV lak: If you @lines only hold what is truely interesting you don't need the two hashes
my %added        = ();    #  table of latest version where NAME was added
my %uncatalogued = ();    #  table of latest version where NAME was seen before uncatalog

foreach (@lines) {

    # REV lak: You could save yourself this reg exp match (see prev REV comment)
    next unless /^Added|^Uncat/i;

    # isolate elementname and branch version
    my ( $action, $name, $junk, $branch ) = /(.*")(.*)("\.)(.*)/;

    # Fill table of latest version where file was added
    if (/^Added/i) {
        $added{$name} = $branch unless $added{$name};
    }

    # Fill table of latest version where NAME was seen before uncatalog
    if (/^Uncat/i) {

        # chop branch and version number
        my ( $b, $v ) = ( $branch =~ /(.*)(\d+)/ );
        $v--;    # decrement version number
        my $lastknown = "$b$v";
        $uncatalogued{$name} = $lastknown unless $uncatalogued{$name};
    }
}

#  REV lak: You put the newline there in your -fmt switch to lshistory a few lines up
#           If you drop it, you won't need a chomp in the next line.
#           in fact you can drop the entire grep and check directly on @lines
chomp( my @match = grep /^$pattern$/, keys %added );
if (@match) {
    $dupver = $match[$#match];

    $found = $dupver;

}

# REV lak:
# I realize the if you implement the the 'improvement' I argued for then the code will be much harder to read, review and maintain
# BUT you save a lot a pattern matching and that is known to be fairly expensive.
# Performance ought to improve - which is our main goal ...everything else being equal ;-)
#
# All in all it looks neat - well done ...I have no more comments below this point

# No duplicate element is found on invisible branches
# Allow the creation of the element.
exit 0 unless $found;

$log->enable();
$log->set_verbose($verbose_mode);
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
    if ( !$pop_kind || ( $pop_kind eq "rmname" ) || ( $pop_kind eq "mkslink" ) ) {

        $log->information( "DEBUG\tLine " . __LINE__ . " Operation is not mkelem, but $pop_kind\n" );
        $prompt = "$prompt The element name [$element]\\n";

    }
}

$prompt = "$prompt ALREADY exists for the directory:\\n [$parent]\\n";
$prompt = "$prompt That name was added in branch version:\\n";
$prompt = "$prompt [$added{$element}].\\n";
$prompt = "$prompt \\n";

# check if it has been uncatogued
chomp( my @lastseen = grep /$pattern$/, keys %uncatalogued );

if (@lastseen) {
    $prompt = "$prompt The name has last been seen in: \\n";
    $prompt = "$prompt [$uncatalogued{$element}].\\n";
    $prompt = "$prompt \\n";
}

$prompt = "$prompt NOTE:  If you feel you really need to perform this action\\n";
$prompt = "$prompt e-mail the VOB_OWNER ($vob_owner).\\n\\n";

foreach ( split( /\\n/, $prompt ) ) {
    $log->warning("$_\n");
}

$prompt = "$prompt Action is logged in logfile:\\n " . $log->get_logfile;

`clearprompt yes_no -pro \"$prompt\" -type error -mask abort -default abort -newline -prefer_gui`;

# prevent the operation
exit 1;

__END__

######################## DOCUMENTATION ##############################

=pod

=head1 NAME

stop_twin - ClearCase trigger

Script:        F<stop_twin.pl>

Trigger name:  C<ACC_STOP_TWIN>

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
