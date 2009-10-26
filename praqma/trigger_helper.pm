require 5.001;

package trigger_helper;
use strict;
our( $scriptdir, $scriptfile );

BEGIN {
    $scriptdir  = ".\\";
    $scriptfile = $0;      # Assume the module is called from 'current directory' (no leading path - $0 is the file)
    $scriptfile =~ /(.*\\)(.*)$/
      && do { $scriptdir = $1; $scriptfile = $2; }    # Try to match on back-slashes (file path included) and correct mis-assumption if any found
}
use lib "$scriptdir..";

use praqma::acc;
use Getopt::Long;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK $BUILD);

require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw(new);

use constant MAX_SEMAPHORE_FILE_AGE_DAYS => 0.168;             # real (1 hr ~ 0.042 --> 4 hrs ~ 0.168)
use constant SEMAPHORE_DIR               => '\\semaphores';    # Relative to the script location dir

# File version
$VERSION = "1.0";
$BUILD   = "4";

our $header = <<ENDHEADER;
#########################################################################
#     This module contains subs that come in handy in when
#     you write triggers in ClearCase
#     Date:       2009-06-26
#     Author:     Lars Kruse, lak\@praqma.net
#     Copyright:  Praqma A/S
#     License:    GNU GPL v3.0
#########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE         EDITOR        NOTE
-----------  ------------- ----------------------------------------------
2009-06-26   Lars Kruse    First release of the module prepared for
                           Novo Nordisk A/s. It´s based on the old
                           trigger_utils module (version 1.0.1)
2009-08-11   Lars Kruse    Changed path to the semaphore file to use
                           back-slashes (version 1.0.2)
2009-08-25	Lars Kruse		 Changed the return value of enable_semaphore()
                           to be the status of the semaphore look-up.
                           (version 1.0.3)
-------------------------------------------------------------------------
ENDREVISION

sub new {
    my $class = shift;    #Cache the package name
    my $self  = {};
    bless( $self, $class );
    return $self;
}

sub require_trigger_context() {
    defined( $ENV{CLEARCASE_VOB_PN} ) || die $main::header . "File version: $main::VERSION\.$main::BUILD\n" . $main::revision;
}

sub enable_semaphore_backdoor($) {
	  my $msg = ""; #The status level of the semphore file.

    # If the semaphor file exists and it´s not older than MAX_SEMAPHORE_FILE_AGE_DAYS
    # then the trigger will exit silently with 0 - allowing the event the trigger subscribed to, to carry on

    my $semaphore_dir  = $scriptdir . SEMAPHORE_DIR;
    my $semaphore_file = $semaphore_dir . "\\" . lc( $ENV{'username'} );

    my ( $mainpath, $mainscript ) = acc::split_dir_file($main::0);
    if ( -e $semaphore_file ) {
    	  $msg = "Script '$mainscript' found semaphore file at '$semaphore_file'\n";
        if ( ( -M $semaphore_file ) > MAX_SEMAPHORE_FILE_AGE_DAYS ) {
            $msg = $msg."...but it's too old to stop us!";
        } else {
            open( SEMAPHORE, $semaphore_file ) || print $msg = $msg. "...Failed to open the semaphore file for read\n" && return;
            my @sempahore = grep( /^\s*$mainscript\s*$/i, <SEMAPHORE> );
            close(SEMAPHORE);

            if ( scalar @sempahore ) {
                $msg = $msg."...and found the script '$mainscript' listed in the semphore file\nThe trigger script is canceled by semaphore!\n";
                print $msg;
                exit 0;
            }
            $msg=$msg."...but it doesn't mention '$mainscript' so the trigger is allowed to continue\n";
        }
    } else {
    	$msg = "Script '$mainscript' looked for semaphore file at '$semaphore_file'\n...but there wasn't any\n";
    }
    return $msg;
}

sub enable_install() {
    my $usage = <<ENDUSAGE;
$::Scriptfile -install -vob vob_tag [-script script_pname]
            [-trigger trigger_name] [-preview]

-install                Required to run the script in install mode
-vob vob_tag            The VOB where the trigger should be installed
-script script_pname    The fully qualified path to the script (must be a
                        UNC path or a drive that is mapped).
                        If this is omitted then script pname will be the one
                        used to execute it (this too must be a fully qualified
                        path either using UNC or a mapped drive).
                        If the script pname does not exist the trigger installation
                        fails.
-trigger trigger_name   The name of the trigger. This is only used if you wish to
                        override the triggers default name (which is already cached
                        in the script).
-preview                Displays the cleartool command that installs the trigger,
                        but does not actually execute it. This switch allows you to
                        run the script even if you are not the VOB owner

ENDUSAGE

    my ( $sw_install, $sw_vob, $sw_script, $sw_trigger, $sw_preview );
    my %options = (
        "install"   => \$sw_install,
        "vob=s"     => \$sw_vob,
        "script=s"  => \$sw_script,
        "trigger=s" => \$sw_trigger,
        "preview"   => \$sw_preview,
    );

    GetOptions(%options);

    return 0 unless defined($sw_install);

    #TODO: Refactory!:
    # Consider passing $TRIGGER_NAME and $TRIGGER_INSTALL in a hash directly to enable_install - inspired of how
    # GetOptions is implemented in Getopt::Long
    # see https://praqma.fogbugz.com/?863
    # lak@praqma.net 2009-06-26

    #Assert $TRIGGER_NAME is defined in main package
    die "The trigger name should have been cached in \$TRIGGER_NAME in the script\n\n"
      unless ( defined($::TRIGGER_NAME) );

    #Assert $TRIGGER_INSTALLis defined in main package
    die "The trigger install command should have been cached in \$TRIGGER_INSTALL in the script, \n\n"
      unless defined($::TRIGGER_INSTALL);

    #Assert -vob switch is applied
    die "ERROR -vob is required in -install mode.\n\n$usage\n"
      unless defined($sw_vob);

    #Assert VOB is available (test by querying the VOB owner)
    my $vobowner = lc(`cleartool desc -fmt \%[owner]p vob:$sw_vob`);
    die "ERROR $sw_vob is not accessible\n\n$usage\n"
      unless ( not $? );

    #Assert current user is the VOB owner - or we're running in -preview mode
    my $current_user = lc( $ENV{userdomain} . "\\" . $ENV{username} );
    die "Ooooh! You ($current_user) aren't the VOB owner ($vobowner is) ...trying to hack you way in are you!\n\n$usage\n"
      unless ( ( $vobowner eq $current_user ) || defined($sw_preview) );

    #Assert path to the trigger script is fully qualified
    my $trigger_pname = ( defined $sw_script ) ? $sw_script : $::Scriptdir . $::Scriptfile;
    die "Only fully qualified paths are allowed: '$trigger_pname' is not valid.\n\n$usage\n"
      unless ( $trigger_pname =~ /^\\\\/ ) || ( $trigger_pname =~ /^[a-zA-Z]:\\/ );

    #Assert the path to the trigger script is valid
    die "The script '$trigger_pname' is not accessible\n\n$usage\n"
      unless ( -e $trigger_pname );

    #TODO:Improve
    #see https://praqma.fogbugz.com/?863

    # What is the target vobs of the trigger
    # What is the VOB type
	my $allowed_vob_context = acc::get_vobtype($sw_vob);

	$::TRIGGER_INSTALL =~ /vob:(.*)/;
    my @target_vobs = split(',', $1);
	my $tentativemsg;
    my $errormsg;
    my $install_allowed;
    foreach my $current_type (@target_vobs) {
	    # Valid VOB types for installation can be added here following the layedout semantic
	    # All valid VOBtypes must be matched as "$_ eq ["name"]"
	    # Note the difference between "must be" VOBtypes (prefixed with "+") which writes directly to $errormsg
	    # and "could be" VOBtypes which writes to $tentativemsg and only disallows installation if $install_allowed remains unset
	    #
	    # Psudo example:
        # if ($current_type eq [VOBtype to match]) { # Validation of VOBtype
        #     if ([match clause]) { # what to match
        #         $install_allowed = 1; # allows installation unless an asserted VOBtype failes
        #     } else { # What to do if match failes
        #         $tentativemsg = $tentativemsg."Warning message"
        #             or
        #         $errormsg = $errormsg."error message"
        # NOTE: Writing to errormsg will always result in installtion fail
        #       Writing to tentativmsg will copy to errormsg, unless VOBtype is matched in another iteration
        #     } # end of "what to match"
        #
        # } elsif { # Next type to match

        if ($current_type eq "both") {
			if ($allowed_vob_context ge 1) {
                $install_allowed = 1;
			} else {
                $tentativemsg = $tentativemsg."Warning: The specified VOBtype could not be identified (No AdminVOB tag)"
			}

    	} elsif ($current_type eq "adminvob") {
			if (($allowed_vob_context == 3) || ($allowed_vob_context == 4)) {
				$install_allowed = 1;
			} else {
            	$tentativemsg = $tentativemsg."Warning: The VOB $sw_vob is not a adminvob\n"
            }

    	} elsif ($current_type eq "clientvob") {
            if (($allowed_vob_context == 1) || ($allowed_vob_context == 2)) {
				$install_allowed = 1;
			} else {
             	$tentativemsg = $tentativemsg."Warning: The VOB $sw_vob is not a clientvob)\n"
           	}

        # Define "MUST BE" VOB types under here
    	} elsif ($current_type eq "+adminvob") {
            if (($allowed_vob_context == 3) || ($allowed_vob_context == 4)) {
				$install_allowed = 1;
			} else {
				$errormsg = $errormsg."ERROR: This trigger '$::TRIGGER_NAME' can only be set on AdminVOBs (which $sw_vob is not)\n"
    		}

    	} elsif ($current_type eq "+clientvob") {
            if (($allowed_vob_context == 1) || ($allowed_vob_context == 2)) {
                $install_allowed = 1;
            } else {
        		$errormsg = $errormsg."ERROR: This trigger '$::TRIGGER_NAME' can only be set on ClientVOBs (which $sw_vob is not)\n"
        	}

    	# If $current_type is not known above, it is checked agains the ACC meta type attribute "AccVOBType"
    	} else {
    		my $AccVOBType_res = `cleartool desc -aattr AccVOBType vob:$sw_vob`;
            if ($current_type =~ s/^\+(.*)/$1/) { # identifies and removes the plussign, if any
                if ($AccVOBType_res =~ /AccVOBType.*$current_type/) {
                    $install_allowed = 1;
                } else {
					$errormsg = $errormsg."ERROR: This trigger '$::TRIGGER_NAME' can only be set on custom VOBtype \"$current_type\" (which $sw_vob is not)\n";
				} # End if $AccVOBType_res
			} else {
	            if ($AccVOBType_res =~ /AccVOBType.*$current_type/) {
                    $install_allowed = 1;
                } else {
					$tentativemsg = $tentativemsg."Warning: AccVOBType \"$current_type\" is not set on $sw_vob\n";
				} # End if $AccVOBType_res
	        } # End "case" + match on $current_type
    	} # End "case" VOBtype
    } # End foreach VOBtype
    $errormsg = $errormsg.$tentativemsg."ERROR: No valid VOB type was found\n"
      unless (($install_allowed == 1) || ($errormsg));
	#debug defined($sw_preview) && do {print "Errormsg = $errormsg \nInstall allowed?: $install_allowed\ntentativmsg: $tentativemsg\n";};
    if ($errormsg) {die $errormsg;};




#   # Old Install helper - To be replaced by above
#    #Assert the $TRIGGER_INSTALL string is compliant
#    die "ERROR The trigger install string '$::TRIGGER_INSTALL' is not compliant\n"
#      unless ( lc($::TRIGGER_INSTALL) =~ /vob:(adminvob|clientvob|both)/ );
#    my $allowed_vob_context = $1;

#    ( $allowed_vob_context eq "adminvob" ) && do {
#        die "WARNING: This trigger '$::TRIGGER_NAME' can only be set on AdminVOBs (which $sw_vob is not)\n"
#          unless acc::is_adminvob( "vob:" . $sw_vob );
#    };

#    ( $allowed_vob_context eq "clientvob" ) && do {
#        die "WARNING: This trigger '$::TRIGGER_NAME' can only be set on Client VOBs (which $sw_vob is not)\n"
#          unless acc::is_clientvob( "vob:" . $sw_vob );
#    };

    # Check if the trigger is already set (in which case we must use the -replace switch)
    my $trigger_tag = defined($sw_trigger) ? $sw_trigger : $::TRIGGER_NAME;

    my $cmd     = "cleartool desc trtype:$trigger_tag\@$sw_vob 2>&1";
    my $cmdexec = `$cmd`;
    my $replace = ( $? / 256 ) ? "" : " -replace";

    #Compile the trigger installation command
    my $trig_inst_com           = "\"Created using the -install switch of the scriptfile: $::Scriptfile\"";
    my $current_trigger_install = "cleartool " . $::TRIGGER_INSTALL;
    my $subst_str               = "-c $trig_inst_com -exec \"" . acc::TRIGGER_PERL . " $trigger_pname\" $trigger_tag\@$sw_vob";
    $current_trigger_install =~ s/vob:(adminvob|clientvob|both)/$subst_str /;
    $current_trigger_install =~ s/mktrtype/mktrtype$replace/;

    #If all the uses wanted was a preview it's time to get out
    defined($sw_preview) && do {
        print "Trigger install command:\n$current_trigger_install\n";
        exit 0;
    };

    #Else you do your thing
    exit system($current_trigger_install);
}

sub scalar_dump($) {
    my $ref = shift;
    my ( $package, $filename, $line ) = caller;
    print STDERR "   ########   Dumping scalar   ########\n"
      . "   Package:          \t$package '$filename'\n"
      . "   Line:             \t$line\n"
      . "   $ref: \t["
      . $$ref . "]\n";
}

## The CLEARCASE_MTYPE variable tells which type is involved
## ...in clear text (%@\#$¤) we need it as a type prefix
sub mtype2cctype($$) {
    my $mtyperef = shift;
    my $ccvarref = shift;
    my %types    = (
        'branch type'    => 'brtype',
        'label type'     => 'lbtype',
        'attribute type' => 'attype',
        'element type'   => 'eltype',
        'trigger type'   => 'trtype',
        'hyperlink type' => 'hltype'
    );
    return 0 unless defined( $types{$$mtyperef} );    # Return as FALSE if the match was unsuccesful
    $$ccvarref = $types{$$mtyperef};
    return 1;
}

sub DESTROY {
}

__END__

=head1 NAME

ACC - trigger utility module

=head1 SYNOPSIS

package: C<trigger_helper>

Module:  C<trigger_helper.pm>
The trigger_utils package contains various functions that will come in handy when you write ClearCase triggers.

it enables you to make triggers that doesn´t execute if semaphores have been set, and it makes you triggers install
automatically.

=head1 DESCRIPTION

To ease the use of the trigger_helper.pm module it´s recommended that you keep your scripts and trigger_helper.pm
close together and include the directory that contains the trigger_utils.pm module using a relative path.

Example file structure:

 root
   triggers
   praqma
   utils

In order to use a relative path, you´ll obviously need to determine the location of your running script in a pre-compiled block.

our ($Scriptdir, $Scriptfile);BEGIN{$Scriptdir =".\\";$Scriptfile = $0; $Scriptfile =~/(.*\\)(.*)$/ &&  do{$Scriptdir=$1;$Scriptfile=$2;}}
use lib $Scriptdir."..";
use praqma::trigger_helper;

The recommended use is that you add the following to your ClearCase trigger scripts:

  our $TRIGGER_NAME="MAINTAIN_FROZEN";                                             #Example only - your name here!
  our $TRIGGER_INSTALL="mktrtype -type -lbtype -all -preop rmattr vob:adminvob";   #Example only - your install command here!

B<NOTE:>

The use of the variables C<$TRIGGER_NAME> and C<$TRIGGER_INSTALL> er described in more detail in the documentation
of the sub function C<install_trigger( )>

And hereafter, but before you actually start doing any work in you script you add the following statements;

  our $thelp=trigger_helper->new;
  $thelp->enable_install;
  $thelp->require_trigger_context;
  $thelp->enable_semaphore_backdoor;

  # Your trigger functionality begins here

Good luck

B<NOTE:>

=head1 CONSTANTS

The module defines the following constants which you might consider to give different values:

C<MAX_SEMAPHORE_FILE_AGE_DAYS>        = C<0.168>

Tha value  of C<MAX_SEMAPHORE_FILE_AGE_DAYS> determins how long time a semaphore file is valid. The value is given
as number of days (1 hr ~ 0.042 --> 4 hrs ~ 0.168).

C<SEMAPHORE_DIR>                      = C<'./semaphores'>

The value of C<SEMAPHORE_DIR> is the relative to the script location directory where the semaphore file will be
searched for.

=head1 FUNCTIONS

The following functions are defined in the module. they migh not all be exported. Have a look in the
module script so find out which ones that are.

=cut

=head2 require_trigger_context( )

Looks for the CLEARCASE_VOB_PN variable which is always (but only) instantiatied if the scritp is
executed from at trigger context.

Returns:
   void

The method doesn´t return anything but it simply dies if not in a trigger context. The sub function
assumes that the caller ($main) has defined the following fore variabels:

  $header
  $revision
  $VERSION
  $BUILD

=head2 sub enable_semaphore_backdoor( )

Checks for the existence of a valid semaphore.

The semaphore enables triggers to exit silently and let the ClearCase event processed - as if the trigger had
not been executed at all.

To create a valid semaphore for a trigger script the following conditions will have to be met:

=over

=item *

A semaphore file must be created, The semaphore file must be named after the user account - no file extension (e.g lsku, g91551, ycd)

=item *

The semaphore file must be located in a subfolder of the actual trigger loctaion named "semaphores" (defined by a constant in the module)

=item *

The semaphore file must have been created (not accessed, or updated, but CREATED) within the last 4 hours (defined by a constant in the module)

=item *

The semaphore file must contain a line stating the name of the perl script it is supposed to detronize (eg. no_rmelem_rmver.pl), the
same semaphore file can list many scritps.

=back
If a valid semaphore exist the trigger execution is canceled.

The location of the C<semaphores> directory can tweak by setting the constant C<trigger_utils::SEMAPHORE_DIR>.

Note that the semaphore files are ignored (doesn´t stop the trigger) if they are more then 4 hrs old.

This setting can be tweaked by setting the constant C<trigger_utils::MAX_SEMAPHORE_FILE_AGE_DAYS>.

One hour is apx 0.042 days, thus 0.168 ~ 4 hrs.

=head2 sub enable_install( )

Supports help installing the trigger using the following syntax:

  Scriptfile -install -vob vob_tag [-script script_pname]
              [-trigger trigger_name] [-preview]

  -install                Required to run the script in install mode
  -vob vob_tag            The VOB where the trigger should be installed
  -script script_pname    The fully qualified path to the script (must be a
                          UNC path or a drive that is mapped).
                          If this is omitted then script pname will be the one
                          used to execute it (this too must be a fully qualified
                          path either using UNC or a mapped drive).
                          If the script pname does not exist the trigger installation
                          fails.
  -trigger trigger_name   The name of the trigger. This is only used if you wish to
                          override the triggers default name (which is already cached
                          in the script).
  -preview                Displays the cleartool command that installs the trigger,
                          but does not actually execute it.

Prequsites are that the script file defines the following two variables (using our):

  our $TRIGGER_NAME
  our $TRIGGER_INSTALL

The $TRIGGER_NAME shall contain the default name of the trigger

The $TRIGGER_INSTALL shall contain a formalized version of the mktrtype command using the
following approach:

=over

=item *

Use the syntax for mktrtype

=item *

Don't apply the -exec (or -execwin or -execunix for that matter)

=item *

Don't apply the trigger name

=item *

At the end of the string apply one of the following three keywords:

  vob:adminvob
  vob:clientvob
  vob:both

To indicate wether the trigger can be installed only on AdminVOBs, only on Client VOBs or on both types

=back

Heres and example:

  our $TRIGGER_NAME="MAINTAIN_FROZEN";
  our $TRIGGER_INSTALL="mktrtype -type -lbtype -all -preop rmattr vob:adminvob";

Executing the script like this:

  ratlperl \\server\triggers\maintainfrozen.pl -install -vob \Adm

Will install like this:

  cleartool cleartool mktrtype -type -lbtype -all -preop rmattr -exec "ratlperl \\server\triggers\maintainfrozen.pl" MAINTAIN_FROZEN@\Adm

...but only if you are the vob owner and the \Adm vob is an AdminVOB.

The install utility will examine if the trigger is already installed, and put a C<-replace> switch inthere i necessary.


=head2 get_versiontree_below_version( $cc_pn, \@result_array )

This function returns a version tree below a certain version. The point is that
A version tree is normally retrived for an element, not a particular version of
an element. The function retrives the version tree of the element and starts
shifting the version in the list until it finds the $cc_pn version - and then returns
the rest.

Parameters:

 $cc_pn                = The version to use as off-set standard version extended syntax:
                         element-pname@@branch-id
 $result_array         = The result

Returns:
  1 = Success
  0 = Some error occured - content of @result_array is not to be trusted.



=cut

=head1 AUTHOR

Lars Kruse, E<lt>lak@praqma.netE<gt>.

=head1 BUGS

See the Accelerated ClearCase project on Launchpad.net

=for html <a href="http://launchpad.net/acc">Accelerated ClearCase</a>


=head1 COPYRIGHT

This program is distributed under GNU GPL v3.0

=cut
