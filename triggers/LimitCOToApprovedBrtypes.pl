require 5.001;
# File version
$version::major= "1.0";
$version::minor= "0.0";
$0 =~ /([A-Za-z0-9-_\.]*$)/; $thisfile = $1; # Extract this file's name - without leading path
my $header = <<ENDHEADER;
#########################################################################
#     $thisfile                                       #
#     This script is intended as trigger script (element -all)          #
#     on the mkbranch event. It monitors a list of approved branches    #
#     and requires that no branches are created except these.           #
#     Date:       2006-10-26                                            #
#     Author:     Lars Kruse, lars.kruse\@krusecontrol.net               #
#     Copyright:  OPEN                                                  #
#########################################################################
ENDHEADER


# Revision information
#########################################################################
my $revision = <<ENDREVISION;
DATE        EDITOR  NOTE
----------  -------------  ----------------------------------------------
2006-10-26  Lars Kruse     1st release prepared for Novo Nordisk 
                           (version 1.0.0.0)
-------------------------------------------------------------------------
ENDREVISION

# Standard trigger stuff:
exit_if_not_executed_by_ccase_event();
enable_debug();
enable_semaphor_backdoor();

my $retval = 0;
$regexp = "main"; # list of branches that are allowed to create "brtype|brtype|..."
unless ($ENV{'CLEARCASE_BRTYPE'}=~/$regexp/){
	my $opkind =lc($ENV{'CLEARCASE_OP_KIND'});
	my $brtype =  $ENV{'CLEARCASE_BRTYPE'};
	$retval = abortmsg(
		"ERROR \\n...triggered by a [$opkind $brtype] event.\\n\\n".
		"You are about to create a branch that is not approved\\n".
		"The config spec of your view might be wrong!\\n\\n".
		"Contact the Configuration Manager \\n".
		"or ClearCase Admin to get help!"
	)
} 
        
$g_debug && print "Exit value:[$retval]\n";            
exit $retval;

#################### sub functions #######################
sub abortmsg{
  my $msg = shift;
  my $cmd= "clearprompt proceed -prompt \"$msg\" -type error -mask abort -default abort -newline -prefer_gui";
  $g_debug && print "Executing:\n$cmd\n";
  `$cmd`;
  my $retval = $?/256;
  $g_debug && print "...returncode was [$retval]\n";
  return $retval;
}

sub enable_debug{
  $g_debug=0; #Used for debugging
  # Initializes the global variable $g_debug 
  # 1) If the environamne variable "trace_subsys" contains the name of this script.
  # 2) If the environment variable ccdebug is defined
  $_ = lc($thisfile);
  if(lc($ENV{trace_subsys}) =~ /$_/){$g_debug=1;} #look for the name of the perl script in "trace_subsys"
  if ($ENV{'ccdebug'} ne ""){$g_debug=1;} # Look for the environment variable "ccdebug"
  if ($g_debug){
    my $log="$ENV{TEMP}\\".$thisfile.".debug.".$ENV{CLEARCASE_PPID}.".log"; # Create a log file
  	print STDERR "\nRunning in debug mode!\n".  # Notify that we're runing in debug mode
  	             "Triggerscript:\t\"$0\"\n".
  	              "Log of execution:\"$log\"\n";
    close(STDOUT); open(STDOUT,">>$log"); # Redirect STDOUT to the log
    close(ERROUT); open(ERROUT,">>$log");# Redirect STDERR to the log
    #Type a list of the instantiated CLEARCASE variables
    my $cmd = "set cle | sort";
    my $ccvariables = `$cmd`;
	  print "CLEARCASE Environment Variables:\n".
	        "-------------------------------------------------------------\n".
	        $ccvariables.
	        "-------------------------------------------------------------\n"; 
  }
}

sub enable_semaphor_backdoor{
  #If the semaphor file exists, the trigger will exit silently
  $semaphor_file="\\\\appdkhi008\\Triggers\\exclude\\".lc($ENV{'username'});
  $g_debug && print "Looking for semaphor file \"$semaphor_file\"\n";
  if (-e $semaphor_file){
  	my $msg ="Found semaphor file: $semaphor_file\nTHE TRIGGER SCRIPT IS CANCELED!\nEXIT CODE:0\n";
  	print $msg;
	  $g_debug && print STDERR $msg; # Make sure the message goes to STDERR even if we're in debug-mode
    exit 0;
  }
}

sub exit_if_not_executed_by_ccase_event{
	# look for the clearcase_vob_pn variable - it that does not exist then we are in a wrong scope
	$ENV{'CLEARCASE_VOB_PN'} || die $header."File version: $version::major.$version::minor\n".$revision; 
}
