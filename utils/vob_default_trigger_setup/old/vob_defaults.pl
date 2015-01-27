require 5.000;
use strict;
$| = 1;
our ( $Scriptdir, $Scriptfile );

BEGIN {
    use File::Basename;
    $Scriptdir  = dirname(__FILE__) . "\\";
    $Scriptfile = basename(__FILE__);
}

# Use clauses
use File::Basename;
use File::Temp;
use Getopt::Long;
use Cwd;
use lib "$Scriptdir../../praqma";
use trigger_helper;
use scriptlog;
use pcc 0.1011;

chdir $ENV{SYSTEMDRIVE};

#Enable the features in trigger_helper
our $thelp = trigger_helper->new;

# Initiate logging.
our $log = scriptlog->new;
my $pccObject = pcc->new;

#Define either environment variabel CLEARCASE_TRIGGER_DEBUG=1 or SCRIPTLOG_ENABLE=1 to start logging
$log->enable(1);
$log->set_verbose(1);

our $logfile = $log->get_logfile();
($logfile) && $log->information("logfile is: $logfile\n");    # Logfile is null if logging isn't enabled.

#############################################  M A I N #####################################################

my ( %bl_defaults,, @vobs, %trtypes, %trpaths, $replace );

init_globals();

foreach my $vobtag  (@vobs) {

    next unless ( $vobtag =~ m/bbComponent/);

	$log->information_always("Checking vob $vobtag");
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
			my $retval = qx($cmd);
			if ($?) {
				$log->error("Execution of [$cmd] failed: $retval");
			}
		}
	}
	else {
		$log->information("$vobtag is up-to-date ");
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
	$cmd       = "cleartool lstype -kind trtype -s -invob $parms{vobtag} 2>&1";
	@installed = sort qx($cmd);
	$log->assertion_failed(" Failed to get information about installed triggers in $parms{vobtag} ") if ($?);

	# Get supported triggers
	foreach my $vobtype ( @{ $parms{vobtypes} } ) {
		if ( exists $trtypes{$vobtype} ) {
			push @supported, @{ $trtypes{$vobtype} };
		}
	}

	# Exclude blacklisted triggers
	foreach my $trigger (@supported) {
		$wanted{$trigger}++ unless ( grep { /$trigger/ } @{ $parms{blacklist} } );
	}

	# Compare wanted to actual
	@missing = ();
	foreach my $trigger ( keys %wanted ) {
		unless ( grep { /$trigger/ } @installed ) {
			push @missing, $trpaths{$trigger};
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

	#	my %parms = @_;

	( my $root = $Scriptdir ) =~ s/(.*)(\/.*\/.*\/)$/$1\/triggers/;
	opendir( DIR, $root );
	my @files = grep { /\.pl$/i } readdir(DIR);
	closedir(DIR);

	foreach my $script (@files) {
		no strict 'vars';
		no warnings 'once';
		%install_params = ();
		$TRIGGER_NAME   = "";
		do "$root/$script";

		if ( $TRIGGER_NAME ne "" ) {
			foreach my $type ( split( ',', $install_params{"supports"} ) ) {

				# update hash with vobtype as key and array of triggernames as value
				push @{ $trtypes{$type} }, $TRIGGER_NAME;

				# update hash with triggername as key and path to script as value

				( my $path = "$root/$script" ) =~ tr#/#\\#;
				$trpaths{$TRIGGER_NAME} = $path;
			}
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
