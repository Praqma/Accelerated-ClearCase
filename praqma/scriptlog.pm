package scriptlog;

require 5.001;
require Exporter;
use strict;

our ( $scriptdir, $scriptfile );

BEGIN {
	$scriptdir  = ".\\";
	$scriptfile = $0;      # Assume the module is called from 'current directory' (no leading path - $0 is the file)
	$scriptfile =~ /(.*\\)(.*)$/
	  && do {
		$scriptdir  = $1;
		$scriptfile = $2;
	  }                    # Try to match on back-slashes (file path included) and correct mis-assumption if any found
}
use lib "$scriptdir..";

our @ISA    = qw(Exporter);
our @EXPORT = qw(new);        #Export only the constructor

my $Info_count = 0;           #Increased by one every time an information is issued
my $Warn_count = 0;           #Increased by one every time a warning is issued
my $Err_count  = 0;           #Increased by one every time an error is issued
my $Enabled    = 0;           #When logging is only done when it's enabled;
my $Verbose    = 0;           #When verbose is on messages are wittten to console as well as logfile
my $Logfile    = "";          #Updated with the logfile pname once log is enabled os set manually using set_logfile
my $LogIsOpen  = 0;           #Flag indicating wether the log is succesfully open or not.

# Module version
our $VERSION = "1.0";
our $BUILD   = "6";
our $header  = <<ENDHEADER;
#########################################################################
#     This module contains a class which enables easy script logging
#     Date:       2009-07-02
#     Author:     Lars Kruse, lak\@praqma.net
#     Copyright:  GNU GLP v3.0
#     Support:    http://launchpad.net/acc
##########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR  NOTE
----------  -------------  ----------------------------------------------
2007-08-27  Lars Kruse     1st release prepared for Novo (version 1.0)
                           https://svn.praqma.net/svn/acc/dock revision 76
2009-07-02  Lars Kruse     Prepared for Novo Nordisk (version 1.0.4)
2009-08-19  Lars Kruse     Changed the printing subs (i+w+e) so they only
                           print the timestamp to the log - not STDOUT.
                           Added information_always() (version 1.0.5)
2009-11-10  Lars Kruse     Changed the behaviour of the set_verbose.
                           It now check for environment variables
                           SCRIPTLOG_VERBOSE or CLEARCASE_TRIGGER_VERBOSE
                           (version 1.0.6)
-------------------------------------------------------------------------
ENDREVISION

sub new {
	my $class = shift;    #Cache the package name
	$Enabled && openlog();
	my $self = {};
	bless( $self, $class );
	return $self;
}

sub get_information_count { return $Info_count; }
sub get_warning_count     { return $Warn_count; }
sub get_error_count       { return $Err_count; }
sub get_logfile           { return $Logfile; }

sub get_accumulated_errorlevel {
	return ($Err_count) ? 2 : ($Warn_count) ? 1 : 0;
}

######## Setters #############

sub set_verbose() {
	my $self = shift;
	$Verbose = shift;    # boolean
	$Verbose && return;
	if (   defined( $ENV{SCRIPTLOG_VERBOSE} )
		|| defined( $ENV{CLEARCASE_TRIGGER_VERBOSE} ) )
	{
		$Verbose = 1;
	}
}

sub set_logfile() {
	my $self = shift;
	$Logfile = shift;    # valid path+file
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
	if ( lc( $ENV{trace_subsys} ) =~ /$scriptfile/ ) { $flag = 1; }
	if (   defined( $ENV{SCRIPTLOG_ENABLED} )
		|| defined( $ENV{CLEARCASE_TRIGGER_DEBUG} ) )
	{
		$flag = 1;
	}
	if ($flag) { $self->enable; }
}

sub disable {
	$Enabled = 0;
}

sub information() {
	( $Enabled || $Verbose ) && do {
		my $self   = shift;
		my $msg    = shift;
		my $prefix = $self->timestamp . " [I]:\t";
		$Enabled && print LOGFILE $prefix . indent_msg($msg);
		$Verbose && print STDOUT "$msg\n";
		$Info_count++;
		return $Verbose;
	  }
}

sub information_always() {
	my $self   = shift;
	my $msg    = shift;
	my $prefix = $self->timestamp . " [I]:\t";
	$Enabled && print LOGFILE $prefix . indent_msg($msg);
	print STDERR $msg;    #unconditional print
	$Info_count++;
	return $Verbose;
}

sub warning($) {
	( $Enabled || $Verbose ) && do {
		my $self   = shift;
		my $msg    = shift;
		my $prefix = $self->timestamp . " [W]:\t";
		$Enabled && print LOGFILE $prefix . indent_msg($msg);
		print STDERR $msg;
		$Warn_count++;
		return $Verbose;
	  }
}

sub error($) {
	my $self   = shift;
	my $msg    = shift;
	my $prefix = $self->timestamp . " [E]:\t";
	$Enabled && print LOGFILE $prefix . indent_msg($msg);
	print STDERR "$msg\n";
	$Err_count++;
	return $Verbose;

}

sub indent_msg() {
	my $msg = shift;
	chomp($msg);
	$msg =~ s/\n/\n\t\t/g;
	return $msg . "\n";
}

sub assertion_failed($) {
	my $self   = shift;
	my $msg    = shift;
	my $prefix = $self->timestamp . " [ASSERTION FAILED]:\n";
	print LOGFILE "$prefix$msg";
	#$LogIsOpen && print LOGFILE $prefix . $msg;
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
		$self->information( "Dumping " . scalar(@_) . " CLEARCASE environments variables:\n" );
		$self->dump_array( \@_ );
	  }
}

######## (...designed to be) Private ###########

sub timestamp {

	return sprintf( "%02d.%02d:%02d", (localtime)[ 2, 1, 0 ] );
}

sub datestamp {
	my ( $year, $mon, $mday ) = (localtime)[ 5, 4, 3 ];
	return sprintf( "%04d-%02d-%02d", $year + 1900, $mon + 1, $mday );
}

sub openlog() {
	my $self = shift;
	if ( $Logfile eq "" ) {
		$Logfile = "$ENV{TEMP}\\$main::Scriptfile" . "PID$$" . ".log";    # Create a log file
	}

	open LOGFILE, ">>$Logfile"
	  or assertion_failed("Couldn't open \"$Logfile\"\n");
	$LogIsOpen = 1;
	print LOGFILE "\n#######################################################\n"
	  . "This log is created (or appended) on "
	  . datestamp() . " \@ "
	  . timestamp() . "\n"
	  . "Executing script:\t"
	  . $main::Scriptfile . "\n"
	  . "Process ID (PID):\t"
	  . $$ . "\n"
	  . "Executing user:  \t"
	  . $ENV{USERNAME} . "\n\n";
	print STDOUT "Log of execution:\"$Logfile\"\n";
}

sub DESTROY {
	close LOGFILE;
}

__END__


=pod

=head1 NAME

Scriptlog - logging module for ClearCase scripts

 Package: scriptlog
 Class:   scriptlog
 Module:  scriptlog.pm

=head1 SYNOPSIS

Used to ease the logging of perl scripts.
...With some sugar added to those who writes ClearCase triggers

=head2 Setters

 set_logfile(pname)
 set_verbose(0|1)  (reads environment variables SCRIPTLOG_VERBOSE and CLEARCASE_TRIGGER_VERBOSE)

=head2 Getters

 get_information_count
 get_accumulated_errorlevel
 get_warning_count
 get_error_count
 get_logfile

=head2 Methods

 enable
 conditional_enable([boolean]) (reads environment variables SCRIPTLOG_ENABLE and CLEARCASE_TRIGGER_DEBUG)
 disable
 information(msg)
 information_always(msg)
 warning(msg)
 error(msg)
 assertion_failed(msg)
 dump_array(array)
 dump_ccvars
 get_accumulated_errorlevel

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

There is and alternative enable method you can use. It's called C<conditional_enable>

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

Writing to to log is done through one of the four methods:

  $log->information("Hey!\n");
  $log->information_always("Hey - again!\n");
  $log->warning("Watch out!\n");
  $log->error("WRONG!!!!\n");

These loggings will turn up in the log prefixed with the a time stamp and a letter code to
inform of the information level:

  10.43:35 [I]:   Hey!
  10.43:35 [I]:   Hey - again!
  10.43:35 [W]:   Watch out!
  10.43:35 [E]:   WRONG!!!!

If the Log is in verbose mode, then the informations will be printet to STDOUT (informations and warnings)
or STDOUT (errors) as well (but without the timestamp prefix).

information_always() will always print to STDOUT - even if the log isn't in verbose mode. It's convenient
when you want to provide a 'service outut' regardless if the user chose verbose mode or not.

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

Lars Kruse, E<lt>lak@praqma.netE<gt>.

=head1 BUGS

No known bugs.

=head1 SUPPORT

See the website for the Accelerated ClearCase project at http://launchpad.net/acc

=for html <a href="http://launchpad.net/acc">Accelerated ClearCase</a>

=head1 COPYRIGHT

This program is distributed under the GNU GPL v3.0 license

=cut

