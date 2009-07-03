require 5.001;
package trigger_helper;
use strict;
our ($scriptdir, $scriptfile);
BEGIN{
	$scriptdir =".\\";$scriptfile = $0;                                # Assume the module is called from 'current directory' (no leading path - $0 is the file)
	$scriptfile =~/(.*\\)(.*)$/ &&  do{$scriptdir=$1;$scriptfile=$2;}  # Try to match on back-slashes (file path included) and correct mis-assumption if any found
}
use lib "$scriptdir..";

use praqma::acc;
use Getopt::Long;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK $BUILD);

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(new);

use constant MAX_SEMAPHORE_FILE_AGE_DAYS        => 0.168;   # real (1 hr ~ 0.042 --> 4 hrs ~ 0.168)
use constant SEMAPHORE_DIR                      => './semaphores';    # Relative to the script location dir
                

# File version
$VERSION= "1.0";
$BUILD = "1";

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
-------------------------------------------------------------------------
ENDREVISION


sub new {
    my $class = shift;    #Cache the package name
    my $self = {};
    bless( $self, $class );
    return $self;
}



sub require_trigger_context(){
	defined($ENV{CLEARCASE_VOB_PN}) || die $main::header."File version: $main::VERSION\.$main::BUILD\n".$main::revision; 
}


sub enable_semaphore_backdoor(){
  # If the semaphor file exists and it´s not older than MAX_SEMAPHORE_FILE_AGE_DAYS
  # then the trigger will exit silently with 0 - allowing the event the trigger subscribed to, to carry on
  my ($scriptdir, $scriptfile) = acc::split_dir_file($0);

  my $semaphore_dir=$scriptdir.SEMAPHORE_DIR;
  my $semaphore_file=$semaphore_dir."/".lc($ENV{'username'});
  
 
  if (-e $semaphore_file ){
	 print "Found semaphore file: $semaphore_file\n";
	 if ((-M $semaphore_file) > MAX_SEMAPHORE_FILE_AGE_DAYS){
	   print "...but it's too old to stop the trigger\n!";
	 } else {
	 	 my ($mainpath, $mainscript) = acc::split_dir_file($main::0);
	 	 open(SEMAPHORE, $semaphore_file) || print "Failed to open the semaphore file for read\n" && return;
     my @sempahore = grep(/^\s*$mainscript\s*$/i,<SEMAPHORE>);
	 	 close(SEMAPHORE);
	 	 
	 	 if (scalar @sempahore) {
  	 	 print "Found the script '$mainscript' listed in the semphore file\nThe trigger script is canceled by semaphore!\n";
	   	 exit 0;
	   }
	 	 print "But it doesn't mention '$mainscript'.\nTrigger is allowed to continue\n";
    }
  }
  return $semaphore_file;
}


sub enable_install(){
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
   
  my ($sw_install, $sw_vob, $sw_script, $sw_trigger, $sw_preview);  
  my %options = ( "install"    => \$sw_install,         
                  "vob=s"      => \$sw_vob,             
                  "script=s"   => \$sw_script,          
                  "trigger=s"  => \$sw_trigger,         
                  "preview"    => \$sw_preview,);

  GetOptions(%options);

  return 0 unless defined($sw_install);
  
  #TODO: Refactory!: 
  # Consider passing $TRIGGER_NAME and $TRIGGER_INSTALL in a hash directly to enable_install - inspired of how
  # GetOptions is implemented in Getopt::Long
  # see https://praqma.fogbugz.com/?863
  # lak@praqma.net 2009-06-26

  #Assert $TRIGGER_NAME is defined in main package
  die "The trigger name should have been cached in \$TRIGGER_NAME in the script\n\n" 
  unless (defined ($::TRIGGER_NAME));

  #Assert $TRIGGER_INSTALLis defined in main package
  die "The trigger install command should have been cached in \$TRIGGER_INSTALL in the script, \n\n"
  unless defined ($::TRIGGER_INSTALL);
  
  #Assert -vob switch is applied
  die "ERROR -vob is required in -install mode.\n\n$usage\n" 
  unless defined ($sw_vob);
  
  #Assert VOB is available (test by querying the VOB owner)
  my $vobowner = lc(`cleartool desc -fmt \%[owner]p vob:$sw_vob`);
  die "ERROR $sw_vob is not accessible\n\n$usage\n"
  unless (not $?);
  
  #Assert current user is the VOB owner - or we're running in -preview mode
  my $current_user = lc($ENV{userdomain}."\\".$ENV{username});
  die "Ooooh! You ($current_user) aren't the VOB owner ($vobowner is) ...trying to hack you way in are you!\n\n$usage\n"
  unless (($vobowner eq $current_user) || defined($sw_preview));
  
  #Assert path to the trigger script is fully qualified
  my $trigger_pname = (defined $sw_script)? $sw_script : $::Scriptdir.$::Scriptfile;
  die "Only fully qualified paths are allowed: '$trigger_pname' is not valid.\n\n$usage\n"
  unless ($trigger_pname=~/^\\\\/) || ($trigger_pname=~/^[a-zA-Z]:\\/);
  
  #Assert the path to the trigger script is valid
  die "The script '$trigger_pname' is not accessible\n\n$usage\n"
  unless (-e $trigger_pname);
  
  #TODO:Improve
  #see https://praqma.fogbugz.com/?863

  #Assert the $TRIGGER_INSTALL string is compliant
  die "ERROR The trigger install string '$::TRIGGER_INSTALL' is not compliant\n"
  unless ( lc($::TRIGGER_INSTALL)=~/vob:(adminvob|clientvob|both)/ );
  my $allowed_vob_context = $1;
  
  ($allowed_vob_context eq "adminvob") && do{
    die "WARNING: This trigger '$::TRIGGER_NAME' can only be set on AdminVOBs (which $sw_vob is not)\n"
    unless acc::is_adminvob("vob:".$sw_vob);
  };

  ($allowed_vob_context eq "clientvob") && do{
    die "WARNING: This trigger '$::TRIGGER_NAME' can only be set on Client VOBs (which $sw_vob is not)\n"
    unless acc::is_clientvob("vob:".$sw_vob);
  };
  
  # Check if the trigger is already set (in which case we must use the -replace switch)
  my $trigger_tag = defined($sw_trigger)? $sw_trigger : $::TRIGGER_NAME;
  
  my $cmd= "cleartool desc trtype:$trigger_tag\@$sw_vob 2>&1";
  my $cmdexec = `$cmd`;
  my $replace = ($?/256)? "" : " -replace";

  #Compile the trigger installation command
  my $trig_inst_com = "\"Created using the -install switch of the scritpfile: $::Scriptfile\"";
  my $current_trigger_install = "cleartool ".$::TRIGGER_INSTALL;
  my $subst_str = "-c $trig_inst_com -exec \"".acc::TRIGGER_PERL." $trigger_pname\" $trigger_tag\@$sw_vob";
  $current_trigger_install =~ s/vob:(adminvob|clientvob|both)/$subst_str /;
  $current_trigger_install  =~ s/mktrtype/mktrtype$replace/;
  
  #If all the uses wanted was a preview it's time to get out
  defined($sw_preview) && do {
    print "Trigger install command:\n$current_trigger_install\n";
    exit 0;
  };
  #Else you do your thing
  exit system($current_trigger_install);
}


sub scalar_dump($){
   my $ref = shift;
   my ($package, $filename, $line) = caller;
   print STDERR "   ########   Dumping scalar   ########\n".
                "   Package:          \t$package '$filename'\n".
                "   Line:             \t$line\n".
                "   $ref: \t[".$$ref."]\n";
}

## The CLEARCASE_MTYPE variable tells which type is involved
## ...in clear text (%@\#$¤) we need it as a type prefix
sub mtype2cctype($$)
{
  my $mtyperef = shift;
  my $ccvarref = shift;
  my %types = ('branch type'    => 'brtype',
               'label type'     => 'lbtype',
               'attribute type' => 'attype',
               'element type'   => 'eltype',
               'trigger type'   => 'trtype',
               'hyperlink type' => 'hltype');
  return 0 unless defined ($types{$$mtyperef});  # Return as FALSE if the match was unsuccesful
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

Checks for the existence a semaphore file and if it exist the trigger execution is canceled

The semaphore file shall be in a folder called './semaphores' which is a relative path to the executing script.

The semaphore file itself is a file with the same name as the executing user (no file extension)

Sample:

  \\server\triggers
      script.pl
      \semaphores
          ycd
          vobadm

Will cause that the script.pl trigger doesn´t fire when ClearCase events are created by the users
ycd and vobadm

The location of the C<semaphores> directory can tweak by setting the constant C<trigger_utils::SEMAPHORE_DIR>.

The semaphore files are ignored (doesn´t stop the trigger) if they are more then 4 hrs old.

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
