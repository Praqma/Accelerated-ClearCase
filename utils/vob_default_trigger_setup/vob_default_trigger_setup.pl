require 5.000;
use strict;
$| = 1;
our ( $Scriptdir, $Scriptfile );

BEGIN {
    use File::Basename;
    $Scriptdir  = dirname(__FILE__) . "\\";
    $Scriptfile = basename(__FILE__);
}

# Module version
my $VERSION = '1.0.';
my $REVISION   = "1";

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#
#    $Scriptfile  version $VERSION.$REVISION
#
#    This script checks all available vobs for triggers and installs
#    missing triggers based on ACC vob type and trigger install_params
#    supported list
#
#    Copyright:  Praqma A/S
#    License:    GNU General Pulic License v3.0
#    Support:    mailto:support\@praqma.net
#
#########################################################################
ENDHEADER

# Revision information
#########################################################################
my $revision = <<ENDREVISION;
DATE        EDITOR  NOTE
----------  -------------  ----------------------------------------------
20xx-xx-xx  Lars Kruse     Initial version never taken into production
2015-01-26  Olof Aldin     Updated for production
-------------------------------------------------------------------------

ENDREVISION

## Use absolute paths or -install to trigger scripts will not work
my $cwd = cwd();
$Scriptdir = $cwd;

# Use clauses
use File::Basename;
use File::Temp;
use Getopt::Long;
use Cwd;
use lib "$Scriptdir../../praqma";
use trigger_helper;
use scriptlog;
use pcc 0.1011;
use Net::Domain qw(hostfqdn);

# Command line option parsing

# Prints help info and exits
sub print_usage($) {
  my $message = shift;
  print "\nERROR: $message\n\n" if ($message);
  print "\nUsage: $Scriptfile [-help] -shareHost <HOSTNAME> { -vob <vob tag> | -allvobs }\n";
  print "-help                   Prints this text\n";
  print "-vob <vob tag>          Installs triggers for this vob only\n";
  print "-allvobs                Installs triggers in all vobs\n";
  print "-shareHost <HOSTNAME>   Hostname where share CCUTILS exist with PRAQMA/Triggers\n";
  exit(1);
}
my ($p_help, $p_vob, $p_allvobs, $p_shareHost);
my $result = GetOptions ("vob=s"        => \$p_vob,
                         "allvobs"      => \$p_allvobs,
						 "shareHost=s"  => \$p_shareHost,
                         "help"         => \$p_help);
print_usage("") if defined($p_help);
print_usage("Must specify either -vob or -allvobs") unless (defined($p_vob) or defined($p_allvobs));
print_usage("Must specify -shareHost") unless defined($p_shareHost);

# should be passed with getopt
#my $sw_trpath = '\\\\' . uc("DKCLEARP11.EMEA.GROUP.GRUNDFOS.COM") . '\\CCUTILS\\PRAQMA\\Triggers';
my $sw_trpath = '\\\\' . uc($p_shareHost) . '\\CCUTILS\\PRAQMA\\Triggers';

chdir $ENV{SYSTEMDRIVE};

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;

# Initiate logging.
our $log = scriptlog->new;
my $pccObject = pcc->new;

#Define either environment variabel CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
#$log->enable(1);
#$log->set_verbose(1);

our $logfile = $log->get_logfile();
($logfile) && $log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.

#############################################  M A I N #####################################################

my ( %bl_defaults,, @vobs, %trtypes, %trpaths, $replace );

init_globals();

foreach my $vobtag  (@vobs) {

	next if (!$p_allvobs && !(("$p_vob" eq "$vobtag") || ("\\$p_vob" eq "$vobtag") || ("$p_vob" eq "\\$vobtag")));

	my @thisvobstypes = ();

	# Read current blacklist
	my @blacklisted = get_blacklist($vobtag);

	#  Verify or update blacklist values, the var @blacklisted will be updated
	check_bl_attr( vobtag => $vobtag, vobtypes => \@thisvobstypes, current_list => \@blacklisted );
	
	# Read installed triggers, install missing triggers (excluding those on blacklist)
	my @todo = get_missing_triggers( vobtag => $vobtag, blacklist => \@blacklisted, vobtypes => \@thisvobstypes );

	if ( scalar(@todo) ) {
		foreach my $path (@todo) {
			my $cmd    = "ratlperl $path -install -vob " . $vobtag . ' 2>&1';

			#my $retval = 0;
			#print "NOT RUNNING: $cmd \n";

			my $retval = qx($cmd);
			print "Installing missing trigger: $cmd \n";

			if ($?) {
				$log->error("Execution of [$cmd] failed: $retval");
			} else {
			  print "Trigger installation ok!\n";
			}
		}
	}
	else {
		#$log->information("$vobtag is up-to-date ");
		print "$vobtag is up-to-date \n";
	}
}

################################################ S U B S ####################################################

sub check_type {
	my %parms = @_;

	my $cmd    = 'cleartool lstype attype:' . acc::ATTYPE_TRIGGER_BLACKLIST . '@' . $parms{vobtag} . ' 2>&1';
	my $retval = qx($cmd);

	# if type not found, error is returned from system
	if ($?) {
		my $admin = acc::get_adminvob( $parms{vobtag} );
		$cmd    = 'cleartool mkattype -global -vtype string -nc ' . acc::ATTYPE_TRIGGER_BLACKLIST . '@' . $admin . ' 2>&1';
		$retval = qx($cmd);
		($?) && $log->assertion_failed("Failed creating attribute in AdminVOB $admin for the vob $parms{vobtag}");
	}
}

sub get_missing_triggers {
	my %parms = @_;

	my ( $cmd, @installed, @supported, %wanted, @missing );
	#$cmd       = "cleartool lstype -kind trtype -s -obsolete -invob $parms{vobtag} 2>&1";
	$cmd       = "cleartool lstype -kind trtype -fmt %n\\n -obsolete -invob $parms{vobtag} 2>&1";
	@installed = sort qx($cmd);
	$log->assertion_failed(" Failed to get information about installed triggers in $parms{vobtag} ") if ($?);
	
	# Get supported triggers
	foreach my $vobtype ( @{ $parms{vobtypes} } ) {
		if ( exists $trtypes{$vobtype} ) {
			push @supported, @{ $trtypes{$vobtype} };
		}
	}
	#print "Supported triggers: $parms{vobtag} @supported ::\n";

	# Exclude blacklisted triggers
	foreach my $trigger (@supported) {
		$wanted{$trigger}++ unless ( grep { /$trigger/ } @{ $parms{blacklist} } );
	}
	#print "Supported, non blacklisted, triggers: $parms{vobtag} @supported ::\n";
	
	# Compare wanted to actual
	@missing = ();
	foreach my $trigger ( keys %wanted ) {
		unless ( grep { /$trigger/ } @installed ) {
			push @missing, $trpaths{$trigger};
			#print "Missing trigger path: $trpaths{$trigger} ::+\n";
			$log->information("\tTrigger $trigger marked for installation on $parms{vobtag}");
		}
	}
	return @missing;

}

sub set_bllistattr {

	# create or replace blacklist attribute.
	my %parms = @_;
	my $cmd =
	  "cleartool mkattr $parms{replace} -nc " . acc::ATTYPE_TRIGGER_BLACKLIST . ' \"' . $parms{newvalue} . '\" ' . " vob:$parms{vobtag}" . ' 2>&1';
	my @retval = qx($cmd);
	if ($?) {
		$log->error( join( '\n', @retval ) );
	}
	else {
		$log->information( join( '\n', @retval ) );

	}

}

sub check_bl_attr {
	my %parms       = @_;
	my %entries     = ();
	my @defaultlist = ();
	# check attribute value is accessible
	check_type( vobtag => $parms{vobtag} );
	my @types = acc::get_vobtypes( $parms{vobtag} );
	#print "$parms{vobtag} :: @types ::\n";
	foreach my $type (@types) {

		push @defaultlist, @{ $bl_defaults{$type} };

		# update list we got from caller
		push @{ $parms{vobtypes} }, $type;

	}
	foreach ( @{ $parms{current_list} }, @defaultlist ) {
		next unless (length);
		$entries{$_}++ unless $entries{$_};
	}
	my $oldvalue = join( ',', @{ $parms{current_list} } );
	my $newvalue = join( ',', sort keys %entries );

	# Update attribute value if changed
	if ( $oldvalue ne $newvalue ) {
		set_bllistattr( replace => $replace, newvalue => $newvalue, vobtag => $parms{vobtag} );
		@{ $parms{current_list} } = split( ',', $newvalue );
	}

}

sub get_blacklist {

	# return sorted array of attribute list values
	my $sw_vob = shift;

	my $cmd               = 'cleartool describe -fmt %SN[' . acc::ATTYPE_TRIGGER_BLACKLIST . ']a vob:' . $sw_vob . ' 2>&1';
	my $raw_triggerblattr = qx($cmd);
	$? && $log->assertion_failed(" Execution of : [$cmd] failed ");    # assert success
	chomp($raw_triggerblattr);
	if ( $raw_triggerblattr =~ s/\"//g ) {

		# Attribute exists already, maybe even with empty value
		$replace = " -replace ";

	}
	else {
		$replace = "";
	}

	# $raw_triggerblattr =~ s/\"//g;    # get rid of the ' required ' quotes in CC string attributes
	my @blacklist = sort split( ', ', $raw_triggerblattr );    # make a list;
	return @blacklist

}

sub get_triggerinfo {
	# Open all trigger script files in the triggers directory.
	# Each of then contains a variable called $TRIGGERNAME

    my $root = $sw_trpath;
	
	opendir( DIR, $root );
	my @files = grep { /\.pl$/i } readdir(DIR);
	closedir(DIR);

	print "Using triggers from: $root : \n";
	
	print "\nFound triggers: " . join(" ", @files) . "\n\n";
	if (@files <= 0) {
	  print "ERROR: Found too few triggers\n";
	  exit 1;
	}

    my $TRIGGER_NAME;
	my %install_params;
	
	foreach my $script (@files) {
	
      ### Ugly way of finding out TRIGGER_NAME and install_params
      ### Feel free to improve this...
      my $filename = $root . '\\' . $script;
	  #print "DEBUG: filename: $filename\n";
      open(my $fh, '<:encoding(UTF-8)', $filename)
        or die "Could not open file '$filename' $!";
		
      my $trigger_name_code = "";
      my $install_params_code = "";
      while (my $row = <$fh>) {
        chomp $row;

        if (!$trigger_name_code && $row =~ m/^[^#]*(\$TRIGGER_NAME\s.*=.*)$/) {
          $trigger_name_code = $1 ;
	      next;
        }

        if ($install_params_code) {
	      if ($row =~ m/^(.*\;).*/) {
	        $install_params_code = $install_params_code . $1;
	        last;
	      } else {
	        if ($row =~ m/^(.*)#/) {
	          $install_params_code = $install_params_code . $1;
	        } else {
	          $install_params_code = $install_params_code . $row;
	        }
	      }
        } else {
          if ($row =~ m/^[^#]*(%install_params\s.*=.*)$/) {
            $install_params_code = $1;
          }
        }
      }
      close($fh);
      eval($trigger_name_code);
      eval($install_params_code);
	  #print "DEBUG: trigger_name_code: $trigger_name_code :\n";
	  #print "DEBUG: install_params_code: " . $install_params_code . "\n";
      #print "DEBUG: TRIGGER_NAME: $TRIGGER_NAME ::+\n";
	  #foreach my $key (keys %install_params) {
	  #  print "DEBUG: install_params{$key} = $install_params{$key} ::\n";
	  #}
      ### End of finding out TRIGGER_NAME and install_params

# Old implementation to get TRIGGER_NAME and install_params doesn'nt work
#	    no strict 'vars';
#		no warnings 'once';
#		%install_params = ();
#		$TRIGGER_NAME   = "";
#		do "$root/$script";

	  if ( $TRIGGER_NAME ne "" && (keys %install_params) ) {
			foreach my $type ( split( ',', $install_params{"supports"} ) ) {
			
				# update hash with vobtype as key and array of triggernames as value
				push @{ $trtypes{$type} }, $TRIGGER_NAME;

				# update hash with triggername as key and path to script as value

				( my $path = "$root/$script" ) =~ tr#/#\\#;
				$trpaths{$TRIGGER_NAME} = $path;
			}
	  } else {
	    print "ERROR: Unable to find TRIGGER_NAME and/or install_params for trigger in $filename. Ignoring this trigger\n";
		print "ERROR: TRIGGER_NAME: $TRIGGER_NAME \n";
		print "ERROR: Keys of install_params that were found will be printed below:\n";
        foreach my $key (keys %install_params) {
	      print "ERROR: install_params{$key} = $install_params{$key} ::\n";
	    }
		print "ERROR: Done printing install_params keys\n";
	  }
	}
	foreach my $vobtype ( keys %trtypes ) {
		my @list = sort @{ $trtypes{$vobtype} };
		@{ $trtypes{$vobtype} } = @list;

	}
}

sub init_globals {

	push @{ $bl_defaults{acc::VOBTYPE_PVOB} },       ("ACC_PRE_SETACT");
	push @{ $bl_defaults{acc::VOBTYPE_BCC_CLIENT} }, ("");
	push @{ $bl_defaults{acc::VOBTYPE_UCM_CLIENT} }, ("");
	push @{ $bl_defaults{acc::VOBTYPE_ADMINVOB} },   ("");
	
    @vobs = @{ $pccObject->get_vobtags() };

	# retrieve information about available trigger scripts
	get_triggerinfo();
}
