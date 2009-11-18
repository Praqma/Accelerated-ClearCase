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
our $TRIGGER_NAME = "ACC_RM_CONTRIBS";

our %install_params = (
  "name"        => $TRIGGER_NAME,                                         # The name og the trigger
  "mktrtype"    => "-element -all -postop uncheckout,checkin",            # The stripped-down mktrtype command
  "supports"    => "bccvob,ucmvob",                                       # csv list of generic and/or custom VOB types (case insensetive)
);

# File version
our $VERSION  = "1.1";
our $REVISION = "2";

my $verbose_mode = 0;    # Setting the verbose mode to 1 will print the logging information to STDOUT/ERROUT ...even it the log-file isn't enabled

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$REVISION
#     This script is intended as ClearCase trigger script for the
#     $TRIGGER_NAME trigger.
#
#     This script is intended as trigger script (element -all)
#     on the checkkout and unreserve events.
#     It removes associated ".contrib" files.
#
#     Date:       2009-10-07
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
2009-10-27  Mikael Jensen  Version 1.1.2
                           Added support for whitespaces in file path and name
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

#########################################

if ( ( $ENV{CLEARCASE_OP_KIND} eq "uncheckout") ||  ($ENV{CLEARCASE_OP_KIND} eq "checkin") ) { #Check that the events that fired the trigger are the ones we support

	if ("$ENV{'CLEARCASE_ELTYPE'}" eq "directory")
	   { exit 0; }

	my $ELEMENT = "$ENV{'CLEARCASE_PN'}";
    $ELEMENT =~ s/\\/\//g; # replaces backslash with forwardslash
    $ELEMENT =~ s/ /\\ /g; # replaces whitespaces with escaped whitespaces ("\ ")
    my @CONTRIBS = glob("$ELEMENT".".contrib*");
	foreach my $CONTRIB (@CONTRIBS)
	{
	   if ( ("$CONTRIB" =~ /\.contrib$/) or
	        ("$CONTRIB" =~ /\.contrib\.[0-9]+$/ ))
	   {
	      $log->error("Could not get objecttype for $CONTRIB")
	        unless my $ob_type=`cleartool desc -fmt %m "$CONTRIB"`;
	      if ("$ob_type" eq "view private object")
	      {
	         ######################################################
	         # Inform of and remove any associated .contrib files #
	         ######################################################
	         $log->information("Removing \".contrib\" file \"$CONTRIB\"...\n");
	         unlink ($CONTRIB);
	      }
	   }
	}
}
exit 0;


__END__

######################## DOCUMENTATION ##############################

=pod

=head1 NAME

rm_contribs - ClearCase trigger

Script:        F<rm_contribs.pl>

Trigger name:  C<ACC_RM_CONTRIBS>

=head1 SYNOPSIS

Runs as ClearCase trigger script installed on clientvobs (not adminvobs) and is supposed to run on checkin and uncheckout operations.

The scripts installs itself correctly when executed outside a trigger context using:

  (ratl)perl rm_contribs.pl -install -vob \thevob

To learn the full syntax simply execute the the script without the -vob switch:

  rm_contribs.pl -install

=head2 Restrictions

During the install process, that script is supposed to run under the account which owns the VOB.
The script will fail if that is not the case.

An exception is if you execute it in -preview mode

=head1 DESCRIPTION

On checkin and uncheckout, the trigger looks for and removes associated ".contrib" files.

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


