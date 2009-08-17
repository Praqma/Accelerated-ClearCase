package scriptlogccbackup;
use strict;
our( $Scriptdir, $Scriptfile );
=head1 NAME

 Package: scriptlog
 Class:   scriptlog
 Module:  scriptlog.pm

Used to ease the logging of perl scripts.
...With some sugar added to those who writes ClearCase triggers

=head1 SYNOPSIS

=head2 Setters

 set_logfile( pname )
 set_verbose( 0|1 )

=head2 Getters

 get_information_count( )
 get_warning_count( )
 get_error_count( )
 get_logfile( )

=head2 Methods

 enable( )
 conditional_enable( [flag] )
 disable( ) 
 information( msg )
 warning( msg )
 error( msg )
 assertion_failed( msg )
 dump_array( array )
 dump_ccavars( ) 
 get_accumulated_errorlevel( )


=head1 DESCRIPTION

Creating the log object is straight forward:

  our $log = scriptlog->new;

The log is not enabled directly upon creation, you need to 
make a call to the enable metode first:

  $log->enable;

Using the class like this will generate the logfile automatically.
the log file will be in the directory of your TEMP environment variable
and named after the executing perl script suffixed with the process ID 
of the  running process and a .log extention

Sample:

F<maintainfrozen.pl> ...will create a log file: F<c:\temp\maintainforzen.pl.PID2354.log>

The logfile is always opened in concatenate mode.

If you want to control the location of the log file youself you simply 
make a call to the set_logfile method before you enable it:

  $log->set_logfile("c:\\mydir\\test.log");
  $log->enable;

Be aware that the logfile class is not very forgiven on no-good 
file pathnames - The assumption is that if you are using the scriptlog 
class it's because you want a log to be created. Thus if the log 
creation fails then the executing script is dragged into the fall - and dies!

There is and alternative enable method you can use. It's called conditional_enable

  $log->conditional_enable

It enables the log if one of the following conditions apply:

=over 4

=item Parameter controlled

The method can be called with an optional parameter, if so it will be
be evaluated in a boolean context and if TRUE logging is enabled

=item TRACE_SUBSYS

An environment variable named TRACE_SUBSYS contains the name of the 
executing perlscript

E.g. TRACE_SUBSYS=maintainfrozen.pl;evil_twin.pl
will turn on logging in maintainfrozen.pl and evil_twin.pl 

=item SCRIPTLOG_ENABLE

An Environment variable SCRIPTLOG_ENABLE is defined
This will effectively turn on logging in all executing script that used conditional_enable

=item CLEARCASE_TRIGGER_DEBUG

An environment variable named CLEARCASE_TRIGGER_DEBUG is defined
This has the exact same effect as define the variable SCRIPTLOG_ENABLE, it's only 
added as a twist of syntactical sugar for the Clearcase trigger programmers

=back

Writing to to log is done through one of the three methods information, warning or error

  $log->information("Hey!\n");
  $log->warning("Watch out!\n");
  $log->error("WRONG!!!!\n");

These loggings will turn up in the log prefixed with the a time stamp and a letter code to 
inform of the information level:

  10.43:35 [I]:   Hey!
  10.43:35 [W]:   Watch out!
  10.43:35 [E]:   WRONG!!!!

Dumping arrays or CLEARCASE_* environment variables is alwas done at the information level:

  $log->dump_ccvars

Will produce a log entry like:

  10.43:35 [I]:   Dumping CLEARCASE environment variables:
          CLEARCASE_PRIMARY_GROUP=CHM_Users

The assertion_failed method will be the death of the executing script!!!
The message is printed to the log before the kill:

  $_ = `cleartool describe vob:\ThePVOB`;
  $? && $log->assertion_failed("where's the PVOB? Can't live without it! ...Arrrrrrgh!\n");

The information,warning and error counts come in handy if you want to exit you scripts
based on the severity level;

  $retval = ($log->get_error_count)?2:($log->get_warning_count)?1:0;

Actually, if you go with the idea of the following exit codes

 2=You have logged errors
 1=You have logged warnings
 0=You have only logged informations or nothing at all

The you can use the get_accumulated_errorlevel method:

  exit $log->get_accumulated_errorlevel;

The verbose mode is turned off at class instantiation if you enable it, the messages are also 
written to STDOUT (informations) or STDERR (warnings, errors and assertion_fails)

=head1 AUTHOR

Lars Kruse, E<lt>lars.kruse@praqma.netE<gt>.

=head1 BUGS

None registered

=head1 COPYRIGHT

This program is distributed under the Friends Of Praqma license


=for html <a href="http://www.praqma.infoi">Visit Friends Of praqma</a>

=cut




BEGIN {
    $Scriptdir  = ".\\";
    $Scriptfile = $0;
    $Scriptfile =~ /(.*\\)(.*)$/ && do { $Scriptdir = $1; $Scriptfile = $2; }
}
use lib $Scriptdir. "/../modules";

#        use acc;
require 5.001;
require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(new);

my $Info_count = 0;    #Increased by one every time an information is issued
my $Warn_count = 0;    #Increased by one every time a warning is issued
my $Err_count  = 0;    #Increased by one every time an error is issued
my $Enabled    = 0;    #When logging is only done when it's enabled;
my $Verbose    = 0;    #When verbose is on messages are wittten to console as well as logfile
my $Logfile    =
  "";    #Updated with the logfile pname once log is enabled os set manually using set_logfile
my $LogIsOpen = 0;    #Flag indicating wether the log is succesfully open or not.

#        $Scriptfile="";

# Module version
our $VERSION = "0.1";
# BUILD is SVN revision number!
our $BUILD   = "152";
our $header  = <<ENDHEADER;
#########################################################################
#     This module contains a class which enables easy script logging
#     Date:       2007-08-27
#     Author:     Lars Kruse, lars.kruse\@praqma.net
#     Copyright:  Friends Of Praqma
#                 http://www.praqma.info
##########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR  NOTE
----------  -------------  ----------------------------------------------
2008-09-17  Lars Kruse     1st release 0.1.152
-------------------------------------------------------------------------
ENDREVISION



sub new {
	
    my $class = shift;    #Cache the package name
    $Enabled && openlog();
    ( $_, $Scriptfile ) = split_dir_file($0);
    my $self = {};
    bless( $self, $class );
    return $self;
}

sub get_information_count      { return $Info_count; }
sub get_warning_count          { return $Warn_count; }
sub get_error_count            { return $Err_count; }
sub get_logfile                { return $Logfile; }
sub get_accumulated_errorlevel { return ($Err_count) ? 2 : ($Warn_count) ? 1 : 0; }

######## Setters #############

sub set_verbose() {
    my $self = shift;
    $Verbose = shift;
}

sub set_logfile() {
    my $self = shift;
    $Logfile = shift;
}

####### Methods #############

sub enable {
    $Enabled = 1;
    openlog() unless $LogIsOpen;
}

sub conditional_enable {
    my $self   = shift;
    my $switch = shift;
    my $flag   = 0;

    if ($switch) { $flag = 1; }
    if ( lc( $ENV{trace_subsys} ) =~ /$Scriptfile/ ) { $flag = 1; }
    if ( defined( $ENV{SCRIPTLOG_ENABLED} ) || defined( $ENV{CLEARCASE_TRIGGER_DEBUG} ) ) {
        $flag = 1;
    }
    if ($flag) { $self->enable; }
}

sub disable {
    $Enabled = 0;
}

sub information($$) {
    ( $Enabled || $Verbose ) && do {
        my $self     = shift;
        my $msg      = $self->timestamp() . " [I]:\t" . shift;
        my $g_notify = shift;
        push @$g_notify, $msg;
        $Enabled && print LOGFILE $msg . "\n";
        $Verbose && print STDOUT $msg . "\n";
        $Info_count++;
      }
}

sub warning($$) {
    ( $Enabled || $Verbose ) && do {
        my $self     = shift;
        my $msg      = $self->timestamp() . " [W]:\t" . shift;
        my $g_notify = shift;
        push @$g_notify, $msg;
        $Enabled && print LOGFILE $msg . "\n";
        $Verbose && print STDERR $msg . "\n";
        $Warn_count++;
      }
}

sub error($$) {
    ( $Enabled || $Verbose ) && do {
        my $self     = shift;
        my $msg      = $self->timestamp() . " [E]:\t" . shift;
        my $g_notify = shift;
        push @$g_notify, $msg;
        $Enabled && print LOGFILE $msg . "\n";
        $Verbose && print STDERR $msg . "\n";
        $Err_count++;
      }
}

sub assertion_failed($) {
#    my $self = shift;
    my $in = shift;
    my $msg  = timestamp() . " [LOG ASSERTION FAILED]:" . $in;
    $LogIsOpen && print LOGFILE $msg;
    die $msg;
}

sub dump_array() {
    ( $Enabled || $Verbose ) && do {
        my $self = shift;
        my $arr  = shift;
        foreach (@$arr) {
            chomp($_);
            my $msg = "\t\t" . $_ . "\n";
            $Enabled && print LOGFILE $msg;
            $Verbose && print $msg;
        }
      }
}

sub dump_ccvars {
    ( $Enabled || $Verbose ) && do {
        my $self = shift;
        @_ = `set CLEARCASE`;
        $Enabled
          && $self->information( "Dumping " . scalar(@_) . " CLEARCASE environments variables:\n" );
        $Enabled && $self->dump_array( \@_ );

        $Verbose
          && $self->information( "Dumping " . scalar(@_) . " CLEARCASE environments variables:\n" );
        $Verbose && $self->dump_array( \@_ );
      }
}

######## (...designed to be) Private ###########

sub timestamp {
    my $retval;
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime;

    # my @mon_names = qw (JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC);
    $year = $year + 1900;

    # my $mon_name = $mon_names[$mon];
    $mon++;

    if ( $mon < 10 )  { $mon  = "0" . $mon }
    if ( $mday < 10 ) { $mday = "0" . $mday }
    if ( $hour < 10 ) { $hour = "0" . $hour }
    if ( $min < 10 )  { $min  = "0" . $min }
    if ( $sec < 10 )  { $sec  = "0" . $sec }

    return "$hour:$min:$sec";
}

sub datestamp {
    my $retval;
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime;
    $year = $year + 1900;
    $mon++;
    if ( $mon < 10 )  { $mon  = "0" . $mon }
    if ( $mday < 10 ) { $mday = "0$mday" }
    return "$year-$mon-$mday";
}

sub openlog() {
    my $self = shift;
    if ( $Logfile eq "" ) {
        $Logfile = "$ENV{TEMP}\\" . $Scriptfile . ".PID$$.log";    # Create a log file
    }

    # open LOGFILE, ">>$Logfile" or assertion_failed("Couldn't open '$Logfile'");
    open LOGFILE, ">>$Logfile" or return 0;
    $LogIsOpen = 1;
    print LOGFILE "\n#######################################################\n"
      . "This log is created (or appended) on "
      . datestamp() . " \@ "
      . timestamp() . "\n"
      . "Executing script:\t"
      . $Scriptfile . "\n"
      . "Process ID (PID):\t"
      . $$ . "\n"
      . "Executing user:  \t"
      . $ENV{USERNAME} . "\n\n";
    print STDOUT "Log of execution:\"$Logfile\"\n";
    return 1;
}

sub DESTROY {

    close LOGFILE;
}

##########  Chopped from acc.pm in order to remove dependecy to that module.  ############

sub debug_print($) {
    shift;
    my $str = shift;
    chomp $str;
    my $msg = "\t    DEBUG::  $str\n";
    print STDERR $msg;
}

sub verbose_print ($) {
    print STDERR shift;
}

sub split_dir_file($) {

    my ( $dir, $file );
    $file = shift;
    $dir  = ".\\";
    $file =~ /(.*\\)(.*)$/ && do {
        $dir  = $1;
        $file = $2;
    };
    return ( $dir, $file );
}
