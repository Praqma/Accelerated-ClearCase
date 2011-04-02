######################## STANDARD STUFF ##############################

require 5.001;
use strict;

=pod

=head1 NAME

locktype.pl is a perl script intended for use with Praqma's Troja Server.
The purpose is to lock a type in a multisite environment.

=head1 SYNOPSIS

Locking of clearcase object types in a multisite environment is subject to
mastership issues.

So in order to lock a type object successfully, the lock operation should be carried
out on the host mastering the type object.


=head1 DESCRIPTION

To avoid mastership issues, the script must be called twice. First time in -query
mode, that will determine, if the object exists, the master replica of the type,
and the master replica host.
The second call is in -lock mode, and this time the script is intended to run
on the replica master host.



=head1 Examples

=head2 Query mode

 ratlperl locktype.pl -query -object lbtype:SOMELABEL@\vobtag


=head2 Lock mode

 ratlperl locktype.pl -lock -object lbtype:SOMELABEL@\vobtag


=head2 Do something - fill it out


=head2 More


=head3 -


=head1 SUPPORT

Visit http://www.praqma.net to get help.

=cut

# Getting the script dir
our ( $Scriptdir, $Scriptfile );

BEGIN {
 if ( $0 =~ /(.*[\/\\])(.*)$/ ) {
  $Scriptdir  = $1;
  $Scriptfile = $2;
 }
 else {
  $Scriptdir  = "";
  $Scriptfile = $0;
 }
}

# Use clauses
use strict;

use lib "$Scriptdir..\\praqma";    # You may need to adjust this

use scriptlog;
use trojaclear;
use Getopt::Long;

# File version
my $major = 0;
my $minor = 1;
my $build = 9;

die "Versioning failed\n" unless ( $build < 1000 );
our $VERSION = sprintf( "%.4f", $major + ( $minor / 10 ) + ( $build / 10000 ) );

# Header history
my $header = <<ENDHEADER;

#########################################################################
#     $Scriptfile  version $VERSION
#     Date:       2009-03-25
#     Author:     Jens Brejner, jens.brejner\@praqma.net
#     Copyright:  Praqma A/S, Denmark
#     License:    GNU General Pubic License
#     Support:    http://www.praqma.info
#########################################################################

ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR  NOTE
----------  -------------  ----------------------------------------------
2010-03-24  Jens Brejner   1st release prepared, supports brtype and lbtype
----------  -------------  ----------------------------------------------
ENDREVISION

# Usage information
my $usage = <<ENDUSAGE;
Usage:

$Scriptfile -query -object object [-logfile \"path\"]
$Scriptfile -lock -object object -by_user login
            [-logfile\"path\"]
$Scriptfile -help

ENDUSAGE

# Switch documentation
my $doc = <<ENDDOC;
Switch        Usage
------------  ------------------------------------------------------------------
-query        Boolean. Required if not lock mode, see below. In this mode the
              the existance of the type-object is checked, and it's current state,
              master replica and the master replica host is determined. Then
              $Scriptfile will return the command that must be executed on the
              masterreplica host, in order to lock the type-object.
-lock         Boolean. Required if not query mode, see below. In this mode the
              the existance of the label type is checked, and it's current state,
              master replica and the master replica host is determined and re-
              turned
-object       Required string, object selector. i.e. lbtype:MYLABEL\@\\vobtag
-by_user      Required string with option -lock. The login id of the user
              requesting the lock.

-logfile      Optional. Select your own logfile.

-help         Get help with the script syntax etc. (you are watching it now)


ENDDOC

#########################    Define variables    #########################
# global variables
our $log = scriptlog->new;
my $clearobj;

# switch variables
my ( $sw_help, $sw_query, $sw_lock, $sw_logfile, $sw_object, $sw_byuser );

my %options = (
 "help"      => \$sw_help,       # Request help
 "query!"    => \$sw_query,      # Query mode
 "lock!"     => \$sw_lock,       # Lock mode
 "logfile=s" => \$sw_logfile,    # Your optional logfile
 "object=s"  => \$sw_object,     # object to work on i.e. brtype:mybranch@\vobtag
 "by_user=s" => \$sw_byuser      # the user that requests the locking of the object

);

#########################    MAIN    #########################

initialize();
conditionalexit();
$log->error("Couldn't create ClearObject\n") unless $clearobj = trojaclear->new( \$sw_object );
conditionalexit();
queryobject() if ($sw_query);
lockobject()  if ($sw_lock);
exit $log->get_accumulated_errorlevel;

#########################   SUBS     #########################

sub lockobject {
 my $returnvalue;
 $returnvalue = $clearobj->locktype($sw_byuser);    # Lock object
 if ($returnvalue) {
  $log->information("$returnvalue");
 }
}

sub queryobject {

 # querymode

 my @needed = ( 'QualifedName', 'ReplicaHost', 'MasterReplica' );
 $clearobj->get_masterreplica();                    # update the property $clearobj->{MasterReplica}
 $clearobj->get_replicahost();                      # update the property $clearobj->{ReplicaHost}

 #Return values is they are the needed ones

 foreach (@needed) {
  unless ( defined $clearobj->{$_} ) {
   $log->error("Required property $_ wasn't found defined, quitting\n");
   last;
  }
  $log->information("$_=$clearobj->{$_}\n");
 }

}

sub conditionalexit {

 # Set exit code if errors or warnings, and exit with that

 my $status = $log->get_accumulated_errorlevel();
 if ($status) {
  exit $status;
 }

}

sub initialize {
 my $msg;

 # Initialize and validate operation environment.

 die "\n$header\n\n$usage" unless GetOptions(%options);

 # Ensure consistent time formatting, see IBM Tech note 1249021
 $ENV{'CCASE_ISO_DATE_FMT'} = "1";

 # early out if help
 defined($sw_help) && do { print $header. $revision . $usage . $doc; exit 0; };

 $sw_logfile && $log->set_logfile($sw_logfile);

 # log enable
 $log->enable(1);

 # verbose logging
 $log->set_verbose(1);

 # Run only in either query or execute mode
 if ( defined($sw_query) || defined($sw_lock) ) {

  if ( !defined($sw_object) ) {
   $msg = "Fail: Object must be specified, i.e. mybranch\@\\vobtag.\n";
   $log->assertion_failed("$msg");
  }

  if ( defined($sw_lock) && !( defined($sw_byuser) ) ) {
   $msg = "Fail: Missing -by_user value, while attempting to lock object\n";
   $log->assertion_failed("$msg");
  }

  if ( $sw_object !~ /@/ ) {    # object must contain vob identifier
   $msg = "Fail: Object '$sw_object' does not seem to include a vobtag\n";
   $log->assertion_failed("$msg");
  }
  return;
 }
 else {
  $log->assertion_failed("$usage Must either lock or query\n");
 }

 # We should not have made it this far (neither return due to query or execute so let's quit
 $log->error("Error in usage ?\n$usage $doc\n");

}    # End sub initialize
