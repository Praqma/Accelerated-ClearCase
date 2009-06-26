package acc_pro;
use strict;
our ($Scriptdir, $Scriptfile);BEGIN{$Scriptdir =".\\";$Scriptfile = $0; $Scriptfile =~/(.*\\)(.*)$/ &&  do{$Scriptdir=$1;$Scriptfile=$2;}}
use lib $Scriptdir."..";
use praqma::acc;
require 5.001;



use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
$VERSION = "3.2";

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(new);

# File version
our $VERSION= "0.1";
our $BULILD = "1";

our $header = <<ENDHEADER;
#########################################################################
#     This module contains subs that are used to  support the      
#     ACC process
#     Date:       #
#     Author:     
#     Copyright:  GNU GPL v3.0
#########################################################################
ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE         EDITOR        NOTE
-----------  ------------- ----------------------------------------------
2009-06-26   Lars Kruse    Pulling stuff out of trigger_utils.pm, 
                           that was misplaced. Had nowhere else to put it!
                           (version 0.1.1)
-------------------------------------------------------------------------
ENDREVISION


sub new {
    my $class = shift;    #Cache the package name
    my $self = {};
    bless( $self, $class );
    return $self;
}

sub lbtype_is_frozen($){
  my $ccobj = shift;
  my $cmd = "cleartool desc -fmt \%[".acc::ATTYPE_FROZEN."]Na $ccobj";
  # print "lbtype_is_frozen()\t\$cmd:\t$cmd\n";
  my $retval = `$cmd`;
  # print "lbtype_is_frozen()\t\$retval:\t$retval\n";
  return ($retval ne "")? 1 :0;
}

sub version_has_frozen_label($$){
  my $cc_pn = shift;                                       # The version to examine
  my $return_lbtype_ref = shift;                           # The lbtype to return

  my $cmd = "cleartool desc -fmt \%Nl $cc_pn";             # Get the labels of the version 
  my @labels_on_version = split / /,`$cmd`;
  foreach my $label (@labels_on_version){
    if (lbtype_is_frozen("lbtype:$label\@$ENV{CLEARCASE_VOB_PN}")){
      $$return_lbtype_ref = $label;
      return 1;
    }
  }
  return 0;
}

sub version_has_subtree_with_frozen_label($$$){
  my $cc_pn = shift;
  my $return_label_ref = shift;
  my $return_ccpn_ref = shift;

  my @vtree;
  get_versiontree_below_version($cc_pn, \@vtree) && return 1; # return an error if the sub fails;
  print "\@vtree:\n"; foreach (@vtree){print "\t$_"}
  return 0;
}

sub get_versiontree_below_version($$){
  my $cc_pn = shift;                                       
  my $return_array_ref = shift;
  
  my $cmd = "cleartool desc -fmt \%Vn $cc_pn";             # Get the version id
  my $versionid = `$cmd`; 
  my $escvid = quotemeta($versionid);   
  return 0 unless ($versionid =~ /(.+?)\\(\d+)/);            # exit as FALSE if you don't have a valid version id
  my $br = $1;                                             # ...the branch is part of the match
  my $rev = $_= $2;                                        # ...and so it the revision number
  my $expected_successor = "$br\\".++$_;                   # construct the id of the next successor
  $cmd = "cleartool lsvtree -all -branch $br $cc_pn"; 
  @$return_array_ref = `$cmd`;                             # Get the version tree - below the branch of the version 

  return 0 unless not $?;                                    # Exit as FALSE if the cleartool command failed
  my $continue =1;                                         # A flag the allows us to exit the while loop when we've shifted'ed the uninteresting versions
  $_ = shift @$return_array_ref;                           # shift the first value
  while ($continue && defined($_)) {                       # Continued is set to 0 when we find what we're looking for - $_ is undefined when we pop from an empty array
    if ($_ =~ /($escvid)/){                                # Look for the (escaped) versionid
      $continue=0;                                         # We're done shifting
      unshift @$return_array_ref, $_;                      # We've shifted one to many - put it back!
    } else {
      $_ = shift @$return_array_ref;                       # Carry on!
    }
  }
  scalar(@$return_array_ref) eq 1 && return 0;             # If the version tree is empty (only the $cc_pn version)- return 0;
  return 1 unless grep $expected_successor,@$return_array_ref; # Exis as TRUE if the $expected_successor isn't in the version tree
  # OK - So the version tree is still too big - (Found: $expected_successor)
  my $iterator = scalar(@$return_array_ref);
  $escvid = quotemeta($expected_successor);
  $continue = 1;
  $_ = pop @$return_array_ref;
  while ($continue && defined($_)){
    if ($_ =~ /($escvid)/){                                # Look for the (escaped) successor versionid
      $continue=0;                                         # We're done poping
    } else {
      $_ = pop @$return_array_ref;                         # Carry on!
    }
  }
  return 1;                                                # We're done, Exit as TRUE
}

sub frozen_label_in_version_tree(@$@){
  my $debug = 0;
  my $version_tree_ref = shift; # a reference to an array generated with cleartool lsvtree
  my $vob              = shift; # The VOB to check lbtypes against;
  my $return_arr_ref   = shift; # a reference to an ($lbtype, $version_pn) style array where we can put the search results
  # print "frozen_label_in_version_tree()\n";
  my ($lbtype, $version_pn);
  foreach my $ln (@$version_tree_ref){
    if ($ln =~ /(.*?)\s(\(.*\))$/){                      # Look for a string the has a paranthesis proceeded by a whitespace in the end e.g. "xxxx (xxx xxx)"
      $version_pn = $1;                                  # The version string is the first match
      $_ = $2;                                           # The paranthesis is the second match
      $_ =~ s/\(|\)|\,//g;                               # Ret rid of the paranthesis and the commas (turning it into a white-space separated list of lbtypes)
      $debug && scalar_dump(\$version_pn);
      foreach my $lb ( split / /){
        $lbtype = "lbtype:".$lb."\@$vob";
        $debug && scalar_dump(\$lbtype); 
        lbtype_is_frozen($lbtype) && do {
           @$return_arr_ref[0] = $lbtype;
           @$return_arr_ref[1] = $version_pn;
           return 1;                                     # Exit as TRUE;
        }
      }
    }
  }
  return 0;                                              # Exit as FALSE 
}

sub scalar_dump($){
   my $ref = shift;
   my ($package, $filename, $line) = caller;
   print STDERR "   ########   Dumping scalar   ########\n".
                "   Package:          \t$package '$filename'\n".
                "   Line:             \t$line\n".
                "   $ref: \t[".$$ref."]\n";
}



sub DESTROY {
}

__END__

=head1 NAME

ACC - process module

=head1 SYNOPSIS

package: C<acc_pro>

Module:  C<acc_pro.pm>

###TODO:
###We need to review the POD 

The trigger_utils package contains various functions that will come in handy when you write ClearCase triggers.

It enables you to turn logging on and off after you have installet the triggers in the production environment, it 
enables you to make triggers that doesn´t execute if semaphores have been set, and it makes you triggers install
automatically.

=head1 DESCRIPTION

To ease the use of the trigger_utils.pm module it´s recommended that you keep your scripts and trigger_utils.pm 
close together and include the directory that contains the trigger_utils.pm module using a relative path.

Example file structure:

 root
   triggers
   utils
   modules

In order to use a relative path, you´ll obviously need to determine the location of your running script in a pre-compiled block.

You can achive that using a regulare BEGIN statement; below is an example on how you can set it up:

 our ($Scriptdir, $Scriptfile); 
 BEGIN
 {
   $Scriptdir =".\\"; # Assume $0 only contain the script, not a fully qualified path. In this case the Scriptdir is set to ".\" (CD)
   $Scriptfile = $0;  # Assume $0 only contain the script, not a fully qualified path. In this case the Scriptfile to $0  
   $Scriptfile =~/(.*\\)(.*)$/ &&  do{$Scriptdir=$1;$Scriptfile=$2;} # If $0 contains backslashes - it's split on the last occurence
 }
 use lib $Scriptdir."/../modules"; # From here it's up to the parent (..) and then down into modules
 use acc;

if you have other modules that are located in the modules folder that should also use the current directory  you simply go:

 ...
 use lib $Scriptdir; # Include current directory
 use trigger_utils;

The recommended use is that you add the following to your ClearCase trigger scripts:

  use trigger_utils;
  our $TRIGGER_NAME="MAINTAIN_FROZEN";                                             #Example only - your name here!
  our $TRIGGER_INSTALL="mktrtype -type -lbtype -all -preop rmattr vob:adminvob";   #Example only - your install command here!

B<NOTE:>

The use of the variables C<$TRIGGER_NAME> and C<$TRIGGER_INSTALL> er described in more detail in the documentation 
of the sub function C<install_trigger( )>

And hereafter, but before you actually start doing any work in you script you add the following statements;

  enable_install();
  require_trigger_context();
  enable_semaphore_backdoor();

  # Your trigger functionality begins here

Good luck

B<NOTE:>

C<trigger_utils> uses the perl module C<acc>!

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
