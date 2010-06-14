require 5.001;
use strict;

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
use lib "$Scriptdir..//..";
use Getopt::Long;
use praqma::scriptlog;
use Win32::TieRegistry( Delimiter => "#", ArrayValues => 0 );
my $pound = $Registry->Delimiter("/");

#use praqma::acc;

# File version
my $major = 1;
my $minor = 0;
my $build = 1;

die "Versioning failed\n" unless ( $build < 1000 );
our $VERSION = sprintf( "%.4f", $major + ( $minor / 10 ) + ( $build / 10000 ) );

# Header history
our $header = <<ENDHEADER;
################################################################################
#     $Scriptfile  version $VERSION
#
#
#     Date:       2010-06-09
#     Author:     Jens Brejner, jens.brejner\@praqma.net
#     Copyright:  Praqma A/S, Denmark
#     License:    GNU General Pulic License
#     Support:    http://www.praqma.info
################################################################################

ENDHEADER

# Revision information
################################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR         NOTE
----------  -------------  -----------------------------------------------------
2010-06-09  Jens Brejner   1st release prepared for RUG-DK (version 0.1.1)

--------------------------------------------------------------------------------

ENDREVISION

my $usage = <<ENDUSAGE;
  $Scriptfile -vob <vobtag> | -allvobs [-checkdb ] [-debug]
  $Scriptfile -help


ENDUSAGE

my $doc = <<ENDDOC;
Switch           Explanation
--------------   ---------------------------------------------------------------
-help            Get help with the script syntax etc. (you are watching it now)
-vob <vobtag>    The vobtag to check, check a single vob. Mandatory unless
                 -allvobs is specified
-allvobs         Boolean. Check all vobs, then you can not use -vob <vobtag>
-checkdb         Boolean. If set $Scriptfile vil run an offline db-check on the
                 vob. The database will be locked while copying the db-files.
-debug           Even more information printed.

ENDDOC

### Global variables ###
our $log = scriptlog->new(1);

### switch variables
my ( $sw_help, $sw_vob, $sw_allvobs, $sw_checkdb, $sw_debug );

### script variables
my ( %options, @voblist, $ccutils );

validate_options();
initialize();

foreach my $lvob (@voblist) {
    do_dbcheck($lvob) if $sw_checkdb;

}


#############################   SUBS   #########################################

sub findutils {

    #Look in registry to find ClearCase installation directory, then look for utils dir
    #die if we fail else return the path of the utils directory

    my $homekey = 'LMachine/SOFTWARE/Atria/ClearCase/CurrentVersion//ProductHome';
    my $home    = $Registry->{"$homekey"}
      or die "Can't read $homekey key: $^E\n";
    $home = "$home\\etc\\utils";
    -d $home or die "Can't locate $home\n";
    $sw_debug && $log->information("DEBUG: Found ClearCase Utilities in $home\n");
    return $home;

}

sub do_dbcheck {

    my $vob = shift;
    $log->information("Running dbcheck on $vob\n");
    # Find vob's db dir
    chomp (my $dbdir = run( "cleartool lsvob $vob", 0 ));
    $dbdir =~ s/^(.*\s+)(\\\\\S+)(\s+.*)$/$2\\db/; # Get vobstorage, append "db"

    $sw_debug && $log->information("DEBUG: Found this UNC path [$dbdir]\n");
    # Set temp dir
    my $dbtempdir = "$ENV{TEMP}\\_checkdb";
	if (-e  $dbtempdir) {
	    $sw_debug && $log->information("DEBUG: Deleting directory \"$dbtempdir\"\n");
    	run ("rmdir /S /Q \"$dbtempdir\"",0);
	}

    if (!-e $dbtempdir)  {
    	$sw_debug && $log->information("DEBUG: Creating directory \"$dbtempdir\"\n");
    	mkdir $dbtempdir;
    }

    # Lock vob if unlocked, set flag
    my $lockedstate = run ("cleartool desc -fmt \%[locked]p vob:$vob",0);
	if ($lockedstate =~ /unlocked/i) {
    	$sw_debug && $log->information("DEBUG: $vob is unlocked, locking it now\n");
    	run("cleartool lock -c \"Locked by $Scriptfile for copy of database\" vob:$vob",0);
    }

    # Copy db to tempdir

    my @cpyres = run ("copy \"$dbdir\\vob_db*.*\" \"$dbtempdir\"" ,1);
   	$sw_debug && $log->information("DEBUG: Copying datbase to temp folder\n");
   	$sw_debug && do {
   		foreach(@cpyres) {
   			$log->information("DEBUG: \t\t$_");
   		}
    };
    # Unlock unless flag

	if ($lockedstate =~ /unlocked/i) {
    	$sw_debug && $log->information("DEBUG: $vob was unlocked, unlocking it now\n");
    	run("cleartool unlock vob:$vob",0);
	}

    # do check
	my $chkcmd =  "\"$ccutils\\dbcheck.exe\" -a -r -t -c \"$dbtempdir\\vob_db\"";    # build command
   	$sw_debug && $log->information("DEBUG: dbcheck command looks like [$chkcmd]\n");
	my @chkoutput = run("$chkcmd",1);                                                # run command
	# look for string in output, all is good if it is found
    my $okresult = grep {  /0 errors were encountered in 0 records\/nodes/ } @chkoutput;
    if ($okresult) {
    	$log->information("Dbcheck on $vob completed succesfully\n");
    } else
    {
        my $vobdbout = $ENV{TEMP} . $vob . "_checkdb.log";
        $sw_debug && $log->information("Attempting to open output file for dbcheck errors\n");
        open DBOUT, ">$vobdbout" or $log->warning("Couldn't open \"$vobdbout\"\n");
        print DBOUT @chkoutput;
        close( DBOUT);
        my $errmsg = "Found errors in $vob database.\nLog is saved in  $vobdbout\ncontact Rational Support Immediately\n";
	    $log->enable(1);
    	$log->error($errmsg);
    	exit 1;
    }
    $sw_debug && $log->information("Completed dbcheck on $vob\n");
 }



#sub dbcheck {
#    my $vob  = shift;
#    my $path = shift;

#    print "Entering sub dbcheck $vob\t$path\n";

#    push( @lin, "#################################\n" );
#    push( @lin, "Start dbcheck on $vob\n" );
#    addsep();
#    push @lin, `del /Q \"$checkdir\\*.*\"`;
#    `copy \"$path\\db\\vob*.*\" \"$checkdir\\*.*\"`;
#    $ccutils;
#    my $cmd ="\"$ccutils\\dbcheck.exe\" -a -r -t -c \"c:\\Temp\\dbcheck\\vob_db\" 2>&1";
#    # print "[$cmd]\n";
#    push @lin, `"$cmd"`;
#    addsep();
#}

sub run ($$) {

    # Generic sub for calling system and monitor return value

    my $cmd         = shift;
    my $aslist      = shift;
    my $cmdex       = $cmd . ' 2>&1';
    my @retval_list = qx($cmdex);
    my $retval_scl  = join '', @retval_list;

    $? && do {
        $log->enable(1);
        $log->error("The command: $cmd failed!.\nIt returned:\n$retval_scl\n");
    };
    return @retval_list if $aslist;
    return $retval_scl;
}

sub initialize {

	$log->enable(1);
	$log->set_verbose(1);

    if ($sw_vob) {
        push @voblist, $sw_vob;
    } else {
        @voblist = sort( run( "cleartool lsvob -s", 1 ) );
        chomp(@voblist);
    }

    # Get ClearCase utils dir
    $ccutils = findutils();

    print "Done initializing\n";
}

sub validate_options {
    my $msg;
    %options = (
        "help|?"  => \$sw_help, # make print help information
        "vob=s"   => \$sw_vob,  # string, a single vobtag
        "allvobs" => \$sw_allvobs, # bool, check all visible vobs
        "checkdb" => \$sw_checkdb,  # run dbcheck on selected vobs
        "debug"   => \$sw_debug

    );

    GetOptions(%options);

    defined($sw_help) && do { print $header. $revision . $usage . $doc; exit 0; };

    # Either vobtag or allvobs
    $msg = "Missing parameter, use either -vob <vobtag> OR -allvobs\n";
    $log->assertion_failed($msg) unless ( $sw_vob | $sw_allvobs );

    # vobtag or allvobs, only one
    $msg = "Use either -vob <vobtag> OR -allvobs, can't use both\n";
    $log->assertion_failed($msg) if ( $sw_vob && $sw_allvobs );

    # Only one vobtag
    $msg = "Did not find a single backslash in -vob value [$sw_vob], that is not supported\n";
    if ($sw_vob) {
        my $count = 0;
        $count++ while $sw_vob =~ /\\/g;    # Count backslashes
        $log->assertion_failed($msg) unless ( $count == 1 );

    }

}

=head1 NAME

view_q.pl - View Quarantine Utilities

=head1 SYNOPSIS

A collection of features that enables quarantine, purge and recover of views based on
the view's 'last accessed' date.

Execute the script with -help switch to learn the syntax and usage.

=head1 DESCRIPTION

A fundamental concept to understand when working with view_q.pl is "Stranded views".

Stranded views are views that have valid (and registered) view storages, but haven't got any
view tags in any region.

Stranded views are unavailable for use, but can easily be brought back to availability by using:

  cleartool mktag -view ...

Clearcase has a feature called rgy_check which can report stranded views.

  rgy_check -views

Run cleartool man rgy_check to learn more.

When view_q.pl puts a view into quarantine, it removes all tags in all regions. This puts the
view into the state of being 'stranded'. An important difference between 'regular" stranded
and views put into quarantine by view_q.pl is the file called

  .view_quarantine

which view_q.pl creates in the the 'admin' subfolder in the view storage. This file contains the history
of tags in all regions from where they were deleted. and enables a complete restore.

View_q.pl can be run in a mode where it lists all views not accessed since a certain date. if you whish you
can even tell view_q.pl to automatically put these views into quarantine.

View_q.pl has a different mode which lists all views that are currently in quarantine (As you may have figured
out this is partly determined by the fact that views are stranded, so this mode only works when executed from
the ClearCase Registry server, which support rgy_check!)

When listing the quarantined views you can either automatically purge or recover the views.

Views can also be purged or recovered individually.

When view_q.pl purges a view it runs the sequence, rmtag, unregister, rmview by uuid, and it will attempt to
delete the view storage too.

When a view is recovered by view_q.pl it simply restores all tags in all the regions where it was removed from.

Some views aren't supposed to be deleted even when they haven't been accessed for a long time. View_q.pl can
be instructed to disable quarantine of these views.

View_q.pl will only process views hosted on the machine where the script is being executed.


=head1 Examples

=head2 Putting a view in Quarantine

 ratlperl view_p.pl -quarantine \\server\share\views\viewstorage

The view storage can in either Local File Path notation (d:\views\...) or UNC style

=head2 Listing view that have not been used since ...

This operation is achieved by the swithc -nasince. The argument to -nasince can either be
a date in the form YYYY-MM-DD or a number of days. In the latter case the number of days
will be subtracted from the current date. This feature adresses the possibility to
set-up scheduled jobs. So if you call

 ratlperl view_q.pl -nasince 90

all views that have not been used for 90 dayss or more will be listed. You can add -autoquarantine
to the command to have all these views quarantined in one operation.

=head3 - and putting them in quarantine

 ratlperl view_q.pl -nasince 90 -autoquaratine

=head2 Listing views in quarantine

So you have used view_q.pl to put views in quarantine. How to know which views are in quarantine ?
Simple, used the -lsquarantine:

 ratlperl view_q.pl -lsquarantine

=head3 -have all quarantined views purged (deleted ...)

Use -autopurge:

 ratlperl view_q.pl -lsq -autopurge

Any view in quarantine will be removed.


=head3 purge only views that have been for long enough

add the -days switch which is only valid together with -lsq -autopurge (or -autorecover )
With -autopurge the days switch will filter the quarantined views and only purge those
that have been in quarantine for MORE than I<days>

 ratlperl view_q.pl -lsq -autopurge -days 180

will remove views that have been in quarantine for more than 180 days

=head3 or autorecover quarantined views

Use the -autorecover switch with -lsquarantine. When autorecovering the meaning of
the -days switch is changed to mean less than, I<days>. So

 ratlperl view_q.pl -lsq -autorecover -days 30

Will recover quarantined views that have been quarantined less than 30 days

=head2 One view at a time

Views can be processed one at a time with:

=head3 quarantine:

 ratlperl view_q.pl  -quarantine stgloc

=head3 recover:

 ratlperl view_q.pl -recover stgloc

=head3 purge:

 ratlperl view_q.pl  -purge stgloc

Where B<stgloc> can be in eiter UNC style or local file system notation.

=head2 Ignoring views

Some views are not accessed - but should however not be quarantined, they build-views
or have some other purpose for the organization.

 ratlperl view_q.pl  -ignore I<viewtag>

as the view may not be in the current region, the switch -region is supported

 ratlperl view_q.pl  -ignore I<viewtag> -region I<region>


=head2 Un-ignoring views

To remove the ignore flag from a view, just run

  ratlperl view_q.pl  -noignore I<viewtag> -region I<region>

-and that view will be back in consideration for view_q.pl



=head1 SUPPORT

Visit http://www.praqma.net to get help.

=cut

__END__


$| = 1;
my $logpath = "$ENV{TEMP}\\CHECKVOB";
my $view = "$ENV{USERNAME}_CHECKING_VOB";

my (@ucmvobber,@admvobber,@basevobber);

my @lines = `cleartool mkview -tag $view -stgloc -auto`;
`cleartool startview $view`; # Create view if it doesn't exist.

addsep();

my $logdir = "$logpath\\checkvob\\";
!-e $logdir && do {
        my @res = `md $logdir`;
        push @lines, @res;
};

my $checkdir = "$ENV{TEMP}\\dbcheck\\";
!-e $checkdir && do {
        my @res = `md $checkdir`;
        push @lines, @res;
};

my @rawvobs = `cleartool lsvob`; # Each line in array looks like '* \CCadm               \\SRVCHMVOB01\VOBS1\CCadm.vbs public'
foreach (@rawvobs) { # remove 2 positions from each line, result looks like '\CCadm               \\SRVCHMVOB01\VOBS1\CCadm.vbs public'
        $_ =~ s/(..)(.*)/$2/;   #
}
@allvobs = sort @rawvobs; # Sort the vobs, looks nicer

foreach (@allvobs) { # Capture different parts of the line into variables, we need later.
        $_ =~ /(\S+)(\s+)(\S+)(\s)(.*)/;
        my $tag     = $1;
        my $vobpath = $3;
        my $ucm     = $5;

        #print "$tag\t$vobpath\t$ucm\n";
        my @lin;
#        dbcheck( $tag, $vobpath );
        check( $tag, $vobpath, $ucm );
        savelog($tag);
#        printvobtype( $tag, $vobpath, $ucm );

}

#print "Basevobs\n\n";
# foreach (@basevobber) {
#        print "$_\n";
#}
#print "##############\n";
#print "UCMVOB\n\n";
#foreach (@ucmvobber) {
#        print "$_\n";
#}
#print "##############\n";
#print "adminvobs\n\n";
#foreach (@admvobber) {
#        print "$_\n";
#}
#




my $logfile = "$logdir\\CheckAll.txt";
#
##  Save all the captured command output in a single file.
open( FILE, "> $logfile " ) || die("can't open logfile:  $!");
foreach (@lines) {
        print FILE;
}
close(FILE);


###############################################################3
sub savelog {
        $log = shift;
        $log =~ s/(.)(.*)/$2/;
        print "Entering sub savelog $vob\t$path\n";

        my $logfile = "$logpath\\" . $log . "_CheckAll.txt";

        open( LOG, "> $logfile " ) || die("can't open logfile:  $!");
        foreach (@lin) {
                print LOG;
        }
        close(LOG);
        push @lines, @lin;

        undef @lin;
}

sub addsep {
        push( @lin, "\n\n" );
}

sub dbcheck {
        my $vob  = shift;
        my $path = shift;

        print "Entering sub dbcheck $vob\t$path\n";

        push( @lin, "#################################\n" );
        push( @lin, "Start dbcheck on $vob\n" );
        addsep();
        push @lin, `del /Q \"$checkdir\\*.*\"`;
        `copy \"$path\\db\\vob*.*\" \"$checkdir\\*.*\"`;
        my $cmd ="\"D:\\Program Files\\Rational\\ClearCase\\etc\\utils\\dbcheck.exe\" -a -r -t -c \"c:\\Temp\\dbcheck\\vob_db\" 2>&1";
        # print "[$cmd]\n";
        push @lin, `"$cmd"`;
        addsep();
}


sub check {
        $vob  = shift;
        $path = shift;
        $kind = shift;

        `cleartool mount $vob`; # mount the vob

        my @admin = grep /^->/, qx(cleartool desc -s -ahl AdminVOB vob:$vob);   # look for AdminVOB link pointing "up"
        addsep();
        addsep();
        addsep();
        if ( $#admin == -1 ) {
                my $cmd = "cleartool checkvob -view $view -global vob:$vob 2>&1";
        print "Found Admin vob checking global types, command is [$cmd]\n";
                push @lin, "\nFound Admin vob checking global types, command is [$cmd]";
                push @lin, `$cmd`;

                addsep();
        }
        elsif ( $kind =~ /ucm/ ) {
                my $cmd = "cleartool checkvob -view $view -global vob:$vob 2>&1";
        print "Found UCM vob checking global types, command is [$cmd]\n";
                push @lin, "\nFound UCM vob checking global types, command is [$cmd]";
                push @lin, `$cmd`;

                addsep();



                $cmd = "cleartool checkvob -view $view -ucm vob:$vob 2>&1";
                print "Found UCM Vob check ucm structures, command is [$cmd]\n";
                push @lin, "Found UCM Vob check ucm structures, command is [$cmd]";
                push @lin, `$cmd`;

                addsep();
        }
        else {
#                my $cmd =                  "cleartool checkvob -view $view -data -pool -source -protections $path 2>&1";
                print "Found A basevob: [$vob], Ignoring for now\n]";
                push @lin,          "Found A basevob: [$vob], Ignoring for now\n]";
#                push @lin, `$cmd`;
                addsep();
        }

   `cleartool umount $vob`;
}



sub printvobtype {
        $vob  = shift;
        $path = shift;
        $kind = shift;

        `cleartool mount $vob`; # mount the vob
        my (@ucm,@adm,@base);

        my @admin = grep /^->/, qx(cleartool desc -s -ahl AdminVOB vob:$vob);   # look for AdminVOB link pointing "up"

        if ( $#admin == -1 ) {
      #print "Found Admin vob: $vob\n";
    chomp $vob;
        push @admvobber, $vob;

        }

        elsif ( $kind =~ /ucm/ ) {

                #print "Found UCM Vob $vob\n";
                      chomp $vob;
                push @ucmvobber, $vob;

        }
        else {
                #print "Found a Vob $vob\n";
                chomp $vob;
                push @basevobber, $vob;

        }

   `cleartool umount $vob`;
}
