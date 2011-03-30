######################## STANDARD STUFF ##############################

require 5.001;
use strict;

=pod

=head1 NAME

removeversion.pl is a perl script intended for use with Praqma's Troja Server
The purpose is to remove a specified a version in a multisite environment.

=head1 SYNOPSIS

Locking of clearcase object types in a multisite environment is subject to
mastership issues.

So in order to remove a specified version of an element the operation must be carried
out in the replica that is mastering the branch.

=head1 DESCRIPTION

To avoid mastership issues, the script must be called twice. First time in -query
mode, it will determine, if the object exists, the master replica of the type,
and the master replica host.
The second call is in -remove mode, and this time the script is intended to run
on the replica master host.
During the remove version operation, the script will create a dynamic view, mount
the required vob, run the rmver operation, then unmount the vob, and remove the
temporary view.

The script will not remove a version which is "interesting" which means that the
version has any kind of metadata, i.e. another branch starts off the version or
the version is labelled, has hyperlinks or the like.

=head2 Specifying the version to remove.

You should create a view that selects the branch where the version to delete is visible.

So if your version is located at branch a_branch, you should add

 element * .../a_branch/LATEST

to the view's config spec

Then you must find the fully extended path to the version, but exclude the view information.

So if your version extended path is

  m:\student_view\base\aspexec\aspcopy.asp@@\main\g_branch_keep\l_branch\4

(you want to remove version 4 of aspcopy.asp on branch l_branch), then you must be
passing the string

 \base\aspexec\aspcopy.asp@@\main\g_branch_keep\l_branch\4

to the script. What happens inside the script is that first this string is chopped up
and the first part - "base" in the example, is consisedered the vob tag.
The second last part, is considered the branch, and naturally the last part is the version
to remove.


=head1 Examples

=head2 Query mode

 ratlperl removeversion.pl -query -object \base\aspexec\aspcopy.asp@@\main\g_branch_keep\l_branch\4

This will print something like this to STDOUT

 QualifedName=brtype:l_branch@\base
 ReplicaHost=cccq7
 MasterReplica=replica:original@\base

So now you now which server - and replica that is keeping the mastership.

=head2 Remove mode

 ratlperl removeversion.pl -remove -object lbtype:SOMELABEL@\vobtag -by_user LOGIN


=head2 Return Code

 Removeversion will return 0 zero - if everything went fine
 Removeversion will return 1 zero - if there are warnings - then you investigate the logfile.
 Removeversion will return 2 zero - if there are errors - then you must investigate the logfile.


=head1 SUPPORT

Visit http://www.praqma.net to get help.

=cut

# Getting the script dir
our( $Scriptdir, $Scriptfile );

BEGIN {
    if ( $0 =~ /(.*[\/\\])(.*)$/ ) {
        $Scriptdir  = $1;
        $Scriptfile = $2;
    } else {
        $Scriptdir  = "";
        $Scriptfile = $0;
    }
}

# Use clauses
use strict;

use lib "$Scriptdir..\\praqma";    # You may need to adjust this

use scriptlog;
use trojaclear  0.1007;

use Getopt::Long;
use Time::Local;


# File version
my $major = 0;
my $minor = 1;
my $build = 1;

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
$Scriptfile -remove -object object -by_user login [-logfile\"path\"]
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

-verbose      Optional. Spam STDOUT with various values. Usefull for debugging.
-logfile      Optional. Select your own logfile.

-help         Get help with the script syntax etc. (you are watching it now)


ENDDOC

#########################    Define variables    #########################
# global variables
our $log = scriptlog->new;

my ( $clearobj, $branch, $brtype, $vobtag );
my $viewtag = "$ENV{USERNAME}_" . time();    # used to create a temporary view

# switch variables
my ( $sw_help, $sw_verbose, $sw_query, $sw_remove, $sw_logfile, $sw_object, $sw_byuser);

my %options = (
    "help"      => \$sw_help,                # Request help
    "query!"    => \$sw_query,               # Query mode
    "remove!"   => \$sw_remove,              # Lock mode
    "logfile=s" => \$sw_logfile,             # Your optional logfile
    "object=s"  => \$sw_object,              # object to work on i.e. brtype:mybranch@\vobtag
    "by_user=s" => \$sw_byuser               # the user that requests the locking of the object
);

#########################    MAIN    #########################

initialize();

conditionalexit();
if ($sw_query) {
    queryobject();
}

if ($sw_remove) {
    manageviewview("make");
    setcs() unless ( $branch eq "main" );
    removeversion();
    manageviewview("remove");
}

$log->information("Script is done\n");
exit $log->get_accumulated_errorlevel;

#########################   SUBS     #########################
sub setcs {

    # adjust config spec if we are not branch main

    # write new config_spec to a file
    ## open the file
    my $csfile = "$ENV{TEMP}\\$viewtag.txt";
    open( CS, "> $csfile" ) or $log->error("can't open $csfile for writing $!");
    print CS "element * CHECKEDOUT\n";
    print CS "element * .../$branch/LATEST\n";
    print CS "element * /main/LATEST\n";
    close(CS);

    my @reply = qx(cleartool setcs -tag $viewtag  -force \"$csfile\");

    if ($?) {
        foreach (@reply) {
            $log->error("$_");
        }
    } else {
        $log->information("The config spec of the workview has been set to include \"element * .../$branch/LATEST\"\n");
        unlink $csfile;
    }

}

sub manageviewview {
    my $mode = shift;

    # manage a temporary work view for the version removal
    my @reply;
    if ( $mode eq "make" ) {
        $log->information("Attempting to create view $viewtag\n");
        @reply = qx(cleartool mkview -tag $viewtag -tcomment "Delete me, I should not have been left behind" -stgloc -auto 2>&1);

    } elsif ( $mode eq "remove" ) {
        $log->information("Attempting to remove view $viewtag\n");
        @reply = qx(cleartool rmview -force -tag $viewtag  2>&1);
    }

    if ($?) {
        foreach (@reply) {
            $log->error($_);
        }
        conditionalexit();
    } else {
        foreach (@reply) {
            $log->information($_);
        }
    }
    return;
}

sub removeversion {

    my (@reply, $b_umount) ;
    my $version = "\\\\view\\$viewtag$sw_object";

    if ( !-e $version ) {
        $b_umount = 1; # the vob was not mounted (Well we couldn't find the the version to remove, so now we mount the vob
        $log->information("Mounting vob $vobtag\n");
        @reply = qx(cleartool mount $vobtag 2>&1);
    }
    $log->information("Attempting to remove version: $version \n");
    @reply = qx(cleartool rmver -force -c "Removed via Troja webservice on request made by $sw_byuser" $version 2>&1);
    if ($?) {

        $log->warning("Trouble removing version $version\n");
        foreach (@reply) {
            $log->warning($_);
        }

    } else {
        foreach (@reply) {
            $log->information("$_");
        }
    }

    # unmount vob again, if we where mounting it.
    ($b_umount) && $log->information(qx(cleartool umount $vobtag 2>&1));

}

sub queryobject {

    # querymode

    my @needed = ( 'QualifedName', 'ReplicaHost', 'MasterReplica' );
    $log->error("Couldn't create ClearObject\n") unless $clearobj = trojaclear->new(\$brtype);

    $clearobj->get_masterreplica();    # update the property $clearobj->{MasterReplica}
    $clearobj->get_replicahost();      # update the property $clearobj->{ReplicaHost}

    foreach (@needed) {
    #Return values is they are the needed ones
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
        $log->information("$Scriptfile is exiting with exit code $status\n");
        exit $status;
    }

}

sub initialize {
    my $msg;

    # Initialize and validate operating    environment.

    die "\n$header\n\n$usage" unless GetOptions(%options);

    # Ensure consistent time formatting, see IBM Tech note 1249021
    $ENV{'CCASE_ISO_DATE_FMT'} = "1";

    # early out if help
    defined($sw_help) && do { print $header. $revision . $usage . $doc; exit 0; };

    $sw_logfile && $log->set_logfile($sw_logfile);

    # log enable - always , alldays
    $log->enable(1);

    # verbose logging  - always, alldays
    $log->set_verbose(1);

    # Run only in either query or execute mode
    if ( defined($sw_query) || defined($sw_remove) ) {

        unless ( defined($sw_object) ) {
            $msg = "Fail: Object must be specified\n";
            $log->assertion_failed("$msg");
        }

        # with remove version the object is identified in a string
        # formatted like this '\vobtag\dir\element@@\branch1\version'
        #
        my @stringparts = split /\\/, $sw_object;
        $vobtag = "\\" . $stringparts[1];              # result should be like vobtag
        $branch = $stringparts[ $#stringparts - 1 ];   # name of the branch for the version is the second last in the array
        $brtype = "brtype:$branch\@$vobtag";           # branch type selector

        # valicate that vob and brtype can be found:

        foreach ( "vob:$vobtag", "$brtype" ) {
            my @reply = qx(cleartool des $_ 2>&1);
            if ($?) {
                $log->error("Trouble identifying $_\n");
                foreach (@reply) { $log->error($_); }
                conditionalexit();
            }
        }

        if ( defined($sw_remove) ) {

            unless ( defined($sw_byuser) ) {
                $msg = "Fail: Missing -by_user value, while attempting to remove object\n";
                $log->assertion_failed("$msg");
            }

        }
        return;
    } else {
        $log->assertion_failed("$usage Must either -remove or -query\n");
        return;
    }

    # We should not have made it this far (neither return due to query or remove so let's quit
    $log->error("Error in usage ?\n$usage $doc\n");

}    # End sub initialize
