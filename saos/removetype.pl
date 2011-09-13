######################## STANDARD STUFF ##############################

require 5.001;
use strict;

=pod

=head1 NAME

removetype.pl is a perl script intended for use with Praqma's Troja Server.
The purpose is to remove a type in a multisite environment.

=head1 SYNOPSIS

Removal of clearcase type objects in multisite environment is subject to
mastership issues.

So in order to remove a type object successfully, the remove operation should be carried
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

# Use clauses
use strict;

use lib "$Scriptdir..\\praqma";    # You may need to adjust this

use scriptlog;
use trojaclear 0.1007;

use Getopt::Long;
use Time::Local;

# File version
my $major = 0;
my $minor = 1;
my $build = 5;

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

$Scriptfile -query -object object  [-logfile \"path\"]
$Scriptfile -remove -object object -by_user login -max_age hours [-logfile\"path\"]
$Scriptfile -help

ENDUSAGE

# Switch documentation
my $doc = <<ENDDOC;
Switch        Usage
------------  ------------------------------------------------------------------
-query        Boolean. Required if not remove mode, see below. In this mode the
              the existance of the type-object is checked, and it's current state,
              master replica and the master replica host is determined. Returns
              Mastership host, Mastership replica, and object.
-remove       Boolean. Required if not query mode, In this mode the
              the existance of the type is checked, it's age in hours is checked
              against -max_age. If all is well the object is deleted.
-object       Required string, object selector. i.e. lbtype:MYLABEL\@\\vobtag
-by_user      Required string with option -remove. The login id of the user
              requesting the lock.
-max_age      Integer. Required in -remove mode. A number indicating hours, the
              object age in hours must be less than this number.

-verbose      Optional. Spam STDOUT with various values. Usefull for debugging.
-logfile      Optional. Select your own logfile.

-help         Get help with the script syntax etc. (you are watching it now)


ENDDOC

my $diemsg = "This script should not be used without serious consideration\n\n";
$diemsg = $diemsg . "The reason is that removal of types could cause a lot of \n";
$diemsg = $diemsg . "undesired results. If for instance you remove a branch type \n";
$diemsg = $diemsg . "then any version which are on branches created from the type \n";
$diemsg = $diemsg . "will end up in lost+found - at the best. \n";
$diemsg = $diemsg . "The reason is that removal of types could cause a lot of \n";

#	die "$diemsg";

#########################    Define variables    #########################
# global variables
our $log = scriptlog->new;
my $clearobj;

# switch variables
my ( $sw_help, $sw_verbose, $sw_query, $sw_remove, $sw_logfile, $sw_object, $sw_byuser, $sw_max_age );

my %options = (
 "help"      => \$sw_help,       # Request help
 "query!"    => \$sw_query,      # Query mode
 "remove!"   => \$sw_remove,     # Remove type mode
 "logfile=s" => \$sw_logfile,    # Your optional logfile
 "object=s"  => \$sw_object,     # object to work on i.e. brtype:mybranch@\vobtag
 "by_user=s" => \$sw_byuser,     # the user that requests the locking of the object
 "max_age=i" => \$sw_max_age,    # Integer, maximum object age in hours 
 "verbose!"  => \$sw_verbose     # verbose output 
	
);

#########################    MAIN    #########################

initialize();
conditionalexit();
$log->error("Couldn't create ClearObject\n") unless $clearobj = trojaclear->new( \$sw_object );
conditionalexit();
queryobject()  if ($sw_query);
removeobject() if ($sw_remove);
exit $log->get_accumulated_errorlevel;

#########################   SUBS     #########################

sub removeobject {

 my ( $epoch_created, $maxseconds );

 # $sw_max_age is in hours, find number of seconds
 $maxseconds = $sw_max_age * 60 * 60;

 if ( $clearobj->get_creationdate() ) {

  my $timenow = time();    # current time
  $epoch_created = $clearobj->{ObjectCreatedInEpoch};
  my $epoch_elapsed = $timenow - $epoch_created;
  if ( $maxseconds > $epoch_elapsed ) {
   $log->information( "$clearobj->{QualifedName} is " . sprintf ("%02d:%02d", (localtime($epoch_elapsed))[2,1]) . " hours old\n" );
   $log->information("so $clearobj->{QualifedName} can be removed, attempting now...\n");
   $log->information( $clearobj->{Removed} ) if ( $clearobj->removetype($sw_byuser) );
  }
  else {
   $log->warning("$clearobj->{QualifedName} is too old for removal by this tool\n");
  }

 }

}

sub queryobject {

 # querymode

 my @needed = ( 'QualifedName', 'ReplicaHost', 'MasterReplica' );
 $clearobj->get_masterreplica();    # update the property $clearobj->{MasterReplica}
 $clearobj->get_replicahost();      # update the property $clearobj->{ReplicaHost}

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
 if ( defined($sw_query) || defined($sw_remove) ) {

  unless ( defined($sw_object) ) {
   $msg = "Fail: Object must be specified, i.e. mybranch\@\\vobtag.\n";
   $log->assertion_failed("$msg");
  }

  unless ( $sw_object =~ /@/ ) {    # object must contain vob identifier
   $msg = "Fail: Object '$sw_object' does not seem to include a vobtag\n";
   $log->assertion_failed("$msg");
  }

  if ( defined($sw_remove) ) {

   # some switches are required in remove mode
   unless ( defined($sw_byuser) ) {
    $msg = "Fail: Missing -by_user value, while attempting to remove object\n";
    $log->assertion_failed("$msg");
   }
   unless ( defined($sw_max_age) ) {
    $msg = "Fail: Missing -max_age value, while attempting to remove object\n";
    $log->assertion_failed("$msg");
   }

  }
  return;
 }
 else {
  $log->assertion_failed("$usage Must either -remove or -query\n");
  return;
 }

 # We should not have made it this far (neither return due to query or execute so let's quit
 $log->error("Error in usage ?\n$usage $doc\n");

}    # End sub initialize

