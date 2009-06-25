# Standard stuff
require 5.000;
use strict;
our ($Scriptdir, $Scriptfile);BEGIN{$Scriptdir =".\\";$Scriptfile = $0; $Scriptfile =~/(.*\\)(.*)$/ &&  do{$Scriptdir=$1;$Scriptfile=$2;}}
use lib $Scriptdir."..";


# Use clauses
use praqma::scriptlog;
use praqma::trigger_utils;

# Support trigger_utils::enable_install()
our $TRIGGER_NAME="NO_RMELEM_RMVER";                                             #Required if you call trigger_utils::enable_install()

# TODO: Review the TRIGGER_INSTALL string.
our $TRIGGER_INSTALL="mktrtype -type -lbtype -all -preop rmhlink vob:adminvob";   #Required if you call trigger_utils::enable_install()

# File version
our $VERSION = "1.0"; 
our $BUILD = "1";


my $verbose_mode=1;

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $Scriptfile  version $VERSION\.$BUILD                                      
#     This script is intended as trigger script for the 
#     $TRIGGER_NAME trigger.
#     The trigger prevent rmelem and rmver operations.
#     This script supports self-install (execute with the -install 
#     switch to learn more).
#     Read the POD documentation in the script for more details
#     Date:       2009-06-24                                            
#     Author:     Lars Kruse, lak\@praqma.net               
#     Copyright:  Lars Kruse
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

trigger_utils::enable_install();
trigger_utils::require_trigger_context();
enable_semaphore_backdoor();

our $log = scriptlog->new;
$log->conditional_enable();
$log->set_verbose($verbose_mode);
$log->dump_ccvars;

die;

######### PREVENT REMOVAL OF Restriction hlinks from LBTYPES ##############
#if (     ($ENV{CLEARCASE_HLTYPE} eq acc::HLTYPE_RESTRICTED) && 
#         ($ENV{CLEARCASE_OP_KIND} eq "rmhlink") &&
#         ($ENV{CLEARCASE_MTYPE} eq "label type")){
#   my $msg = "The trigger $Scriptfile has refused the removal of the ".acc::HLTYPE_RESTRICTED." attribute \n".
#             "\t\ton $ENV{CLEARCASE_MOD_TYPE}\@$ENV{CLEARCASE_VOB_PN} to proceed\n";
#   $log->information($msg);
#   exit 1;
#}

exit 0;

######################## DOCUMENTATION ##############################
=pod

=head1 NAME

Script:        F<no_rmelem_rmver.pl>

Trigger name:  C<NO_RMELEM_RMVER>

Used as a generic trigger which prevents rmelem and rmver (unless the version is a zero version).

=head1 SYNOPSIS

Runs as ClearCase trigger script installed on client VOBs both UCM and base ClearCase VOBs are supported

The scripts installs itself correctly when executed outside a trigger context using:

  no_rmelem_rmver.pl -install -vob \AdminVOB

The complete syntax is described in the POD for praqma::trigger_utils::enable_install()

=head2 Restrictions

The script is designed to install on Clients VOBs only - if you try to install this 
script on an Admin VOB it will fail.

During the install proicess, that script is supposed to run under the account which owns the VOB. The script will 
fail if that is not the case.

An exception is if you execute it in -preview mode)

=head1 DESCRIPTION

Elements and versions of elements can be removed by the users who owns them. This trigger prevents the 
operations all togeteher, regardless who owns the element or version. To bypass the script (force a rmelem or rmver 
operation) you must create the appropriate semaphor file first (see the POD documentation for 
praqma::trigger_utils::enable_semaphore_backdoor() ).

=head1 AUTHOR

Lars Kruse, E<lt>lak@praqma.netE<gt>.

=head1 BUGS

No known bugs.

=head1 COPYRIGHT

This program is distributed under the GNU General Pulic License v3.0

Support:    http://launchpad.net/acc

=for html <a href="http://launchpad.net/acc">Project home at Launchpad</a>


=cut







