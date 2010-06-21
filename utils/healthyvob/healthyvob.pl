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
use praqma::acc;
use praqma::scriptlog;
use Win32::TieRegistry( Delimiter => "#", ArrayValues => 0 );
my $pound = $Registry->Delimiter("/");

# File version
my $major = 1;
my $minor = 0;
my $build = 1;

die "Versioning failed\n" unless ( $build < 1000 );
our $VERSION = sprintf( "%.4f", $major + ( $minor / 10 ) + ( $build / 10000 ) );

sub run ($$); # forward declare, avoiding warnings.
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
# Usage information
my $usage = <<ENDUSAGE;
  $Scriptfile -vob <vobtag> | -allvobs [-checkdb ] [-debug]
  $Scriptfile -help


ENDUSAGE
# Online documentation
my $doc = <<ENDDOC;
Switch           Explanation
--------------   ---------------------------------------------------------------
-help            Get help with the script syntax etc. (you are watching it now)
-vob <vobtag>    The vobtag to check, check a single vob. Mandatory unless
                 -allvobs is specified
-allvobs         Boolean. Check all vobs, then you can not use -vob <vobtag>
-checkdb         Boolean. If set $Scriptfile will run an offline db-check on the
                 vob. The database will be locked while copying the db-files.
-checkvob        Boolean. If set $Scriptfile will run a cleartool checkvob on
                 the vob.
-debug           Even more information printed.

ENDDOC

### Global variables ###
$|=1; # synchronized output from cmds
our $log = scriptlog->new();

### switch variables
my ( $sw_help, $sw_vob, $sw_allvobs, $sw_checkdb, $sw_debug, $sw_checkvob );

### script variables
my ( %options, @voblist, $ccutils, $view, $logfolder, $vobunc );

validate_options();
initialize();

foreach my $lvob (@voblist) {

    $vobunc = run( "cleartool lsvob $lvob", 0 );
    $vobunc =~ s/(..)(\S+\s+)(\S+)(\s+.*)$/$3/;
    chomp($vobunc);

    mkdir "$logfolder$lvob" if (!-e "$logfolder$lvob");
    chdir "$logfolder$lvob";
    do_dbcheck($lvob) if $sw_checkdb;
    #
	do_checkvob($lvob, $vobunc) if $sw_checkvob;

	chdir "$Scriptdir";
}
# remove workview.
run ("cleartool rmview -tag $view",0) if ($sw_checkvob) ;

#############################   SUBS   #########################################

sub readoutput ($$) {
# Determine log folder. and report it
# Search summary for problems, report good or look further
	my $log = shift;
	my $vob = shift;





}

sub do_checkvob {
#Do a check vob on selected vob
#Various options exists depending on the vobtype, so vobtype is determined.

    my $vob = shift;
    my $vobunc = shift;
    my $checkvobcmd = "cleartool checkvob -view $view ";

    run ("cleartool mount $vob", 0);
    my $type = join ( ',', acc::get_vobtypes($vob));
    my $command = "cleartool checkvob " ;

    if ($type =~ /acc::VOBTYPE_ADMINVOB|acc::VOBTYPE_PVOB/) {
       my $cmd = "$command	-log .$vob//globaltypes -global vob:$vob";
       my @chkvobout= run ($cmd, 1);
       readoutput(\@chkvobout, $vob);

    }

#    todo check out put;
    # do last thing
    run ("cleartool umount $vob", 0);


}

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

   # Do offline dbcheck.
   # lock vob, copy db to offline, unlock
   # then run dbcheck

    my $vob = shift;
    $log->information("Starting dbcheck on $vob\n");
    # set vob's db dir
    my $dbdir = "$vobunc\\db" ; # Get vobstorage, append "db"

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
    $log->information("Succesfully completed dbcheck on $vob\n\n");
 }

sub run ($$) {

    # Generic sub for calling system and monitor return value

    my $cmd         = shift;
    my $aslist      = shift;
#    my $expecterror = shift; # optional
    my $cmdex       = $cmd . ' 2>&1';
    my @retval_list = qx($cmdex);


    my $retval_scl  = join '', @retval_list;

#    if ($expecterror)

    $? && do {
        $log->enable(1);
        $log->error("The command: $cmd failed!.\nIt returned:\n$retval_scl\n");
    };
    return @retval_list if $aslist;
    return $retval_scl;
}

sub initialize {
    # Set log folder
    $logfolder = "$Scriptdir\\Logs";
    mkdir $logfolder if (!-e $logfolder);

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

    # Create a workview, if we need to do checkvob
    if ($sw_checkvob) {
		$view = "$ENV{USERNAME}_checkvob_view";
        chomp (my $viewexist = run("cleartool lsview -s $view ",0));
        unless ($viewexist eq $view) {
        	run("cleartool mkview -tag $view -stgloc -auto",0);
        }
    }
 }

sub validate_options {

    my $msg;
    %options = (
        "help|?"  => \$sw_help, # make print help information
        "vob=s"   => \$sw_vob,  # string, a single vobtag
        "allvobs" => \$sw_allvobs, # bool, check all visible vobs
        "checkdb" => \$sw_checkdb,  # run dbcheck on selected vobs
        "debug"   => \$sw_debug, # Addtional output, prepended with string DEBUG
		"checkvob" => \$sw_checkvob # Bool, Run cleartool checkvob on selected  vob
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

    $msg = "No work request detected, please specify either checkdb and or checkvob\n";
	$log->assertion_failed($msg) unless ( $sw_checkvob | $sw_checkdb );

}



__END__


#$| = 1;
#my $logpath = "$ENV{TEMP}\\CHECKVOB";
#my $view = "$ENV{USERNAME}_CHECKING_VOB";

#my (@ucmvobber,@admvobber,@basevobber);

#my @lines = `cleartool mkview -tag $view -stgloc -auto`;
#`cleartool startview $view`; # Create view if it doesn't exist.

#addsep();

#my $logdir = "$logpath\\checkvob\\";
#!-e $logdir && do {
#        my @res = `md $logdir`;
#        push @lines, @res;
#};

#my $checkdir = "$ENV{TEMP}\\dbcheck\\";
#!-e $checkdir && do {
#        my @res = `md $checkdir`;
#        push @lines, @res;
#};

#my @rawvobs = `cleartool lsvob`; # Each line in array looks like '* \CCadm               \\SRVCHMVOB01\VOBS1\CCadm.vbs public'
#foreach (@rawvobs) { # remove 2 positions from each line, result looks like '\CCadm               \\SRVCHMVOB01\VOBS1\CCadm.vbs public'
#        $_ =~ s/(..)(.*)/$2/;   #
#}
#@allvobs = sort @rawvobs; # Sort the vobs, looks nicer

#foreach (@allvobs) { # Capture different parts of the line into variables, we need later.
#        $_ =~ /(\S+)(\s+)(\S+)(\s)(.*)/;
#        my $tag     = $1;
#        my $vobpath = $3;
#        my $ucm     = $5;

#        #print "$tag\t$vobpath\t$ucm\n";
#        my @lin;
##        dbcheck( $tag, $vobpath );
#        check( $tag, $vobpath, $ucm );
#        savelog($tag);
##        printvobtype( $tag, $vobpath, $ucm );

#}

##print "Basevobs\n\n";
## foreach (@basevobber) {
##        print "$_\n";
##}
##print "##############\n";
##print "UCMVOB\n\n";
##foreach (@ucmvobber) {
##        print "$_\n";
##}
##print "##############\n";
##print "adminvobs\n\n";
##foreach (@admvobber) {
##        print "$_\n";
##}
##

#my $logfile = "$logdir\\CheckAll.txt";
##
###  Save all the captured command output in a single file.
#open( FILE, "> $logfile " ) || die("can't open logfile:  $!");
#foreach (@lines) {
#        print FILE;
#}
#close(FILE);
################################################################3
#sub savelog {
#        $log = shift;
#        $log =~ s/(.)(.*)/$2/;
#        print "Entering sub savelog $vob\t$path\n";

#        my $logfile = "$logpath\\" . $log . "_CheckAll.txt";

#        open( LOG, "> $logfile " ) || die("can't open logfile:  $!");
#        foreach (@lin) {
#                print LOG;
#        }
#        close(LOG);
#        push @lines, @lin;

#        undef @lin;
#}

#sub addsep {
#        push( @lin, "\n\n" );
#}

#sub dbcheck {
#        my $vob  = shift;
#        my $path = shift;

#        print "Entering sub dbcheck $vob\t$path\n";

#        push( @lin, "#################################\n" );
#        push( @lin, "Start dbcheck on $vob\n" );
#        addsep();
#        push @lin, `del /Q \"$checkdir\\*.*\"`;
#        `copy \"$path\\db\\vob*.*\" \"$checkdir\\*.*\"`;
#        my $cmd ="\"D:\\Program Files\\Rational\\ClearCase\\etc\\utils\\dbcheck.exe\" -a -r -t -c \"c:\\Temp\\dbcheck\\vob_db\" 2>&1";
#        # print "[$cmd]\n";
#        push @lin, `"$cmd"`;
#        addsep();
#}

#sub check {
#        $vob  = shift;
#        $path = shift;
#        $kind = shift;

#        `cleartool mount $vob`; # mount the vob

#        my @admin = grep /^->/, qx(cleartool desc -s -ahl AdminVOB vob:$vob);   # look for AdminVOB link pointing "up"
#        addsep();
#        addsep();
#        addsep();
#        if ( $#admin == -1 ) {
#                my $cmd = "cleartool checkvob -view $view -global vob:$vob 2>&1";
#                print "Found Admin vob checking global types, command is [$cmd]\n";
#                push @lin, "\nFound Admin vob checking global types, command is [$cmd]";
#                push @lin, `$cmd`;

#                addsep();
#        }
#        elsif ( $kind =~ /ucm/ ) {
#                my $cmd = "cleartool checkvob -view $view -global vob:$vob 2>&1";
#        print "Found UCM vob checking global types, command is [$cmd]\n";
#                push @lin, "\nFound UCM vob checking global types, command is [$cmd]";
#                push @lin, `$cmd`;

#                addsep();



#                $cmd = "cleartool checkvob -view $view -ucm vob:$vob 2>&1";
#                print "Found UCM Vob check ucm structures, command is [$cmd]\n";
#                push @lin, "Found UCM Vob check ucm structures, command is [$cmd]";
#                push @lin, `$cmd`;

#                addsep();
#        }
#        else {
##                my $cmd =                  "cleartool checkvob -view $view -data -pool -source -protections $path 2>&1";
#                print "Found A basevob: [$vob], Ignoring for now\n]";
#                push @lin,          "Found A basevob: [$vob], Ignoring for now\n]";
##                push @lin, `$cmd`;
#                addsep();
#        }

#   `cleartool umount $vob`;
#}

#sub printvobtype {
#        $vob  = shift;
#        $path = shift;
#        $kind = shift;

#        `cleartool mount $vob`; # mount the vob
#        my (@ucm,@adm,@base);

#        my @admin = grep /^->/, qx(cleartool desc -s -ahl AdminVOB vob:$vob);   # look for AdminVOB link pointing "up"

#        if ( $#admin == -1 ) {
#      #print "Found Admin vob: $vob\n";
#    chomp $vob;
#        push @admvobber, $vob;

#        }

#        elsif ( $kind =~ /ucm/ ) {

#                #print "Found UCM Vob $vob\n";
#                      chomp $vob;
#                push @ucmvobber, $vob;

#        }
#        else {
#                #print "Found a Vob $vob\n";
#                chomp $vob;
#                push @basevobber, $vob;

#        }

#   `cleartool umount $vob`;
#}
