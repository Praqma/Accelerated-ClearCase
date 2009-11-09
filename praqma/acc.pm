package acc;
require 5.001;
require Exporter;
@ISA = qw(Exporter);
our @EXPORT = qw( get_adminvob
  get_hlinks
  get_to_hlinks
  get_from_hlinks
  is_adminvob
  is_clientvob
  get_vobtype
  split_dir_file
  mkrestriction
  get_composite
  validate_lbtype
);

=head1 NAME

ACC - Accelerated ClearCase, library functions

=head1 SYNOPSIS

To ease the deployment of the acc.pm module it's recommended that you keep your scripts and acc.pm
close together and include the directory that contains the acc.pm module using a relative path.

Example file structure:

 acc
   triggers
   utils
   modules

In order to use a relative path, you'll obviously need to determine the location of your running script in a pre-compiled block.

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
 use acc;

=head1 DESCRIPTION

Used to support ClearCase scripting in general. and Accelerated ClearCase
in particular.

=head1 CONSTANTS

=head2 ClearCase Types

These types are expected to exist as global types in the ACC Meta Data VOBs (AdminVOBs)

  ATTYPE_FROZEN               = 'Frozen'                      ;     # -c "ACC meta type" -vtype string -default \"\"
  ATTYPE_PROMOTION_LEVEL      = 'PromotionLevel'              ;     # -c "ACC meta type" -vtype string -enum \"released\",\"tested\",\"built\",\"integrated\"
  ATTYPE_KEYWORDS             = 'Keywords'                    ;     # -c "ACC meta type" -vtype string -default \"\"
  ATTYPE_LBTYPE_TEMPLATE      = 'LbtypeTemplate'              ;     # -c "ACC meta type" -vtype string -default \"[A-Z][A-Z0-9_-\.]{3,30}\"
  ATTYPE_BRTYPE_TEMPLATE      = 'BrtypeTemplate'              ;     # -c "ACC meta type" -vtype string -default \"[a-z][a-z0-9_]{3,30}\"
  ATTYPE_ATTYPE_TEMPLATE      = 'AttypeTemplate'              ;     # -c "ACC meta type" -vtype string -default \"[a-zA-Z][a-zA-Z0-9]{3,30}\"
  ATTYPE_HLTYPE_TEMPLATE      = 'HltypeTemplate'              ;     # -c "ACC meta type" -vtype string -default \"[a-zA-Z][a-zA-Z0-9]{3,30}\"
  ATTYPE_ACCMETADATA          = 'AccMetaData'                 ;     # -c "ACC meta type" -vtype string -default \"\"
  HLTYPE_PUBLISHED            = 'Published'                   ;     # -c "ACC meta type"
  HLTYPE_COMPOSITE            = 'CompositeLbtype'             ;     # -c "ACC meta type"
  HLTYPE_RESTRICTED           = 'Restricted'                  ;     # -c "ACC meta type"
  LBTYPE_INITIAL              = 'INITIAL'                     ;     # -c "ACC meta type"

=head2 Keywords

These constants defines keywords refered to in the code

 TRIGGER_PERL                = 'ratlperl'                    # -c "perl interpreter for triggers scripts"
 GLOBAL_SCOPE                = 'global'                      # -c "Keyword"

=head2 Conventions and regular expressions

These regular expressions define different conventions.

 LOCAL_TYPE_PREFIX           = '^[Ll][Oo][Cc][Aa][Ll]_'      # -c "RegExp which defines local types prefix (local types must have this prefix)"
 REGEXP_METADATADEFAULT      = '<:AccMetaDataDefault::\\(/s*):>'  # -c "RegExp which determins the AccMetaDateDefault VOB within a region"
 ACC_TEMP_LBTYPE_NAME        = '^_\._\d+_\._\d+$'                   # -c "RegExp defining temp lbtype name while applying Restricted labels with the applyrestricted.pl utility script."

=head2 Environment Variables

These constants defines environment variables which code may be looking for to override default settings.

 CLEARCASE_FORCE_RESTRICTION = 'CLEARCASE_FORCE_RESTRICTION' # -c "Environment Variable, when set restrictions can be forced"
 CLEARCASE_ADMINVOB          = 'CLEARCASE_ADMINVOB'          # -c "Environment Variable, when set it overrides the default ACC meta Data VOB - obsoletede - use CLEARCASE_ACCMETADATAVOB"
 CLEARCASE_ACCMETADATAVOBVOB = 'CLEARCASE_ACCMETADATAVOB'    # -c "Environment Variable, when set it overrides the default ACC meta Data VOB"

=head2 Standart VOBtype definition

ACC has some functions used to identify the VOB type.
This functions are especially important for

A VOB is defined as one of four types of VOBs, which is PVOB, AdminVOB, UCMVOB and BaseVOB.

=head3 PVOB

A PVOB or ProjectVOB is defined as UCM enabled VOB, which has a hyperlink og type "AdminVOB" pointing towards it.

=head3 AdminVOB

A AdminVOB is defined as a non-UCM enabled VOB, which has a hyperlink og type "AdminVOB" pointing towards it.

=head3 UCMVOB

A UCMVOB is defined as a VOB, that is neither a AdminVOB or a PVOB and has AdminVOB hyperlink pointing towards a VOB, which is a PVOB

=head3 BaseVOB

A BaseVOB is defined as a VOB, that is neither a AdminVOB or a PVOB and has AdminVOB hyperlink pointing towards a VOB, which is a PVOB

=head3 Selfcontained VOBs

Selfcontained VOBs (VOBs with no AdminVOB hyperlink, what so ever) have essitially no ACCified VOB type and is currently not supported.


=cut
#rwbi under here
#head2 Custom VOBtype definition
#
#ACC supports custom VOBtypes, defined by a string text in an attribute called AccVOBType set on the VOB it self.
#This allows you to
#
#

###PRAQMA:INITMETA:BEGIN
use constant ATTYPE_FROZEN          => 'Frozen';                    # -c "ACC meta type" -vtype string -default \"\"
use constant ATTYPE_PROMOTION_LEVEL => 'PromotionLevel';            # -c "ACC meta type" -vtype string -enum \"released\",\"tested\",\"built\",\"integrated\"
use constant ATTYPE_KEYWORDS        => 'Keywords';                  # -c "ACC meta type" -vtype string -default \"\"
#rwbi use constant ATTYPE_ACCVOBTYPE      => 'AccVOBType';                  # -c "ACC meta type" -vtype string -default \"\"
use constant ATTYPE_LBTYPE_TEMPLATE => 'LbtypeTemplate';            # -c "ACC meta type" -vtype string -default \"[A-Z][A-Z0-9_-\.]{3,30}\"
use constant ATTYPE_BRTYPE_TEMPLATE => 'BrtypeTemplate';            # -c "ACC meta type" -vtype string -default \"[a-z][a-z0-9_]{3,30}\"
use constant ATTYPE_ATTYPE_TEMPLATE => 'AttypeTemplate';            # -c "ACC meta type" -vtype string -default \"[a-zA-Z][a-zA-Z0-9]{3,30}\"
use constant ATTYPE_HLTYPE_TEMPLATE => 'HltypeTemplate';            # -c "ACC meta type" -vtype string -default \"[a-zA-Z][a-zA-Z0-9]{3,30}\"
use constant ATTYPE_ACCMETADATA     => 'AccMetaData';               # -c "ACC meta type" -vtype string -default \"\"
use constant HLTYPE_PUBLISHED       => 'Published';                 # -c "ACC meta type"
use constant HLTYPE_COMPOSITE       => 'CompositeLbtype';           # -c "ACC meta type"
use constant HLTYPE_RESTRICTED      => 'Restricted';                # -c "ACC meta type"
use constant LBTYPE_INITIAL         => 'INITIAL';                   # -c "ACC meta type"
use constant ATTYPE_LBINPROGRESS    => 'AccLabellingInProgress';    # -c "ACC meta type" -vtype string -default \"\"
###PRAQMA:INITMETA:END

# ACC global constants
use constant TRIGGER_PERL => 'ratlperl';                            # -c "perl interpreter for triggers scripts"
use constant GLOBAL_SCOPE => 'global';                              # -c "Keyword"

use constant LOCAL_TYPE_PREFIX      => '^[Ll][Oo][Cc][Aa][Ll]_';             # -c "RegExp which defines local types prefix (local types must have this prefix)"
use constant REGEXP_METADATADEFAULT => '<:AccMetaDataDefault::\\(/s*):>';    # -c "RegExp which determins the AccMetaDateDefault VOB within a region"
use constant ACC_TEMP_LBTYPE_NAME   =>
  '^_\._\d+_\._\d+$';    # -c "RegExp defining temp lbtype name while applying Restricted labels with the applyrestricted.pl utility script."

use constant CLEARCASE_FORCE_RESTRICTION => 'CLEARCASE_FORCE_RESTRICTION';    # -c "Environment Variable, when set restrictions can be forced"
use constant CLEARCASE_ADMINVOB          => 'CLEARCASE_ADMINVOB';             # -c "Environment Variable, when set it overrides the default ACC meta Data VOB"
use constant CLEARCASE_ACCMETADATAVOBVOB => 'CLEARCASE_ACCMETADATAVOB';       # -c "Environment Variable, when set it overrides the default ACC meta Data VOB"

# These Constants are used to identify VOB types:
use constant VOBTYPE_PVOB                => 'pvob';       
use constant VOBTYPE_ADMINVOB            => 'adminvob';       
use constant VOBTYPE_UCM_CLIENT          => 'ucmvob';       
use constant VOBTYPE_BCC_CLIENT          => 'bccvob';
use constant ATTYPE_CUSTOM_VOBTYPE       => 'ACC_VOBType';


# Module version
$VERSION = "1.1.";
$BUILD   = "7";
my $header = <<ENDHEADER;
#########################################################################
#     This module contains a class which is a helper-module for         #
#     the acc approach to ClearCase scripting.                          #
#     Date:       2007-08-27                                            #
#     Author:     Lars Kruse, lars.kruse\@krusecontrol.net               #
#     Copyright:  OPEN                                                  #
#########################################################################
ENDHEADER

# Revision information
#########################################################################
my $revision = <<ENDREVISION;
DATE        EDITOR  NOTE
----------  -------------  ----------------------------------------------
2007-08-27  Lars Kruse     1st release prepared for ATP
                           (version 1.0)
2007-09-19  Lars Kruse     Backstepped to version 0.1.2
2007-11-07  Lars Kruse     Added some support for publishing lbtype
                           stepped to version 1.0.3
2007-21-07  Lars Kruse     Added some support for composite labels
                           and config specs. Stepped to version 1.0.4
2008-20-06  Jens Brejner   Stepped to v.l.0.6, don´t know what was changed
                           in v1.0.5. Added 2 constants.
2009-28-07  Jens Brejner   Removed duplicate declaration.
2009-21-10  Mikael Jensen  Stepped to v.1.1.7 Added functions:
                           "is_pvob" and "is_clientorucmvob"

-------------------------------------------------------------------------
ENDREVISION
my $self = {};    #Reference to an anonymous hash, Will be blessed later

=head1 FUNCTIONS

The following functions are defined in the acc.pm module but not necessarily exported.
Look in the acc.pm file to seee what is actually exported.

=cut

sub new {
    my $class = shift;    #Cache the package name
    bless( $self, $class );
    return $self;
}

#############################################################################

sub get_adminvob($) {

=head2 get_adminvob( $vob )

Takes a vobtag and returns the top-level AdminVOB in the chain of AdminVOB hyperlinks.

Parameters:

 $vob              = The VOB to check.

Returns:

 The top most AdminVOB in the chain of AdminVOB hyperlinks. if the VOB has no AdminVOB hyperlinks it returns $vob (self).

=cut

    my $vob = shift;
    my $retval = join "", get_hlinks( $vob, "->", "AdminVOB" );
    if ( $retval eq "" ) {
        return $vob;
    } else {
        return &get_adminvob($retval);
    }
}

##############################################################################

sub is_adminvob {

=head2 is_adminvob( $vob )

Takes a vobtag and determins if it is an AdminVOB to other client VOBs.

Parameters:

 $vob              = The VOB to check.

Returns:

 1..n = TRUE: The number of client VOBs that uses this VOB as ADMINVOB.
 0    = FALSE - This VOB has no AdminVOB role.

=cut

    my $vob = shift;

	my @clients = get_hlinks( $vob, "<-", "AdminVOB");
	my $clientcount = scalar @clients;
	$clientcount && return $clientcount;

#    my $cmd     = "cleartool desc -s -aattr " . acc::ATTYPE_ACCMETADATA . " $vob";
#    my @res     = `$cmd`;
#    my $isadmin = scalar @res;
#    return $isadmin;

}

##############################################################################


sub is_clientvob {

=head2 is_clientvob( $vob )

Takes a vobtag and determins if it is a client VOB to some AdminVOB.

Parameters:

 $vob              = The VOB to check.

Returns:

 1..n = TRUE: The number of AdminVOB hyperlinks pointing FROM this VOB towards another VOB.
 0    = FALSE - This VOB has no AdminVOB hyperlkinks.

=cut

    my $vob = shift;
    my @adminvobs = get_hlinks( $vob, "<-", "AdminVOB" );    # It this VOB pointet to by any AdminVOB hyoperlinks
    return ( scalar @adminvobs ) ? 0 : 1;
}

###############################################################
sub is_poradminvob {
#REVIEW LAK
# Don't use raw integers, use named states!!!!!

=head2 is_poradminvob( $vob )

Takes a vobtag and determins if it is an (UCM) PVOB to other client VOBs.

Parameters:

 $vob              = The VOB to check.

Returns:

 2    = TRUE Base - The VOB is a AdminVOB (base Clearcase)
 1    = TRUE UCM  - The VOB is a PVOB (UCM)
 0    = FALSE     - The VOB is not a PVOB or adminvob

=cut
    my $vob = shift;
    return 0 unless my @adminvobs = get_hlinks("vob:".$vob, "<-", "AdminVOB" );
    #REVIEW LAK: Below try running without the -l in the command below.
    # You will get a result in the format:
    #  \PDS_PVOB            APPDKHI013:E:\ClearCaseStorage\VOBs\PDS_PVOB.vbs  (ucmvob)
    # and you can match against: /\(ucmvob\)$/
    
    my $cmd     = "cleartool lsvob -l $vob";
    my $res     = `$cmd`;
    # REVIEW LAK: At this point you chould check the value of $? and handle the potential error-state you are in if $? is true
    # REVIEW LAK: Below, # Don't use raw integers, use named states!!!!!
    # The '.*' preceeding 'ucmvob' should be used with caution. I bacically tranlate to "Any number (including zero!) of occurences of anything"'
    # But you are actually looking for "one or more occurences of white spaces: '\s+' so it should read:
    # $res =~ /Vob registry attributes:\s+ucmvob/
    
	return 2 unless ($res =~ /Vob registry attributes:.*ucmvob/);
    return 1;
 }

##############################################################################

sub is_baseorucmvob {
#REVIEW LAK
# Don't use raw integers, use named states!!!!!	
=head2 is_baseorucmvob( $vob )

Takes a vobtag and determins if it is a client (UCM) VOB to some PVOB.

Parameters:

 $vob              = The VOB to check.

Returns:
 2    = TRUE Base - This is a normal client VOB (VOBs AdminVOB is not UCM)
 1    = TRUE UCM  - This VOB is a UCM client VOB (VOBs AdminVOB is a PVOB)
 0    = FALSE     - This VOB has no AdminVOB hyperlkinks.

=cut

	my $vob = shift;
	return 0 unless	my @adminvobs = get_hlinks("vob:".$vob, "->", "AdminVOB" );
	# REVIEW LAK: Get rid of the debug statement commented out below
	#print "test - AdminVOBs are: @adminvobs";
	foreach (@adminvobs) {
        s/vob://;
        #REVIEW LAK
        # Don't use raw integers, use named states!!!!!
        if (is_poradminvob($_) == 1)  { return 1};
	}
	return 2;
}

##############################################################################

sub get_vobtype {

=head2 get_vobtype( $vob )

Takes a vobtag and determins what kind of vob it is, based on returnlist below.

Parameters:

 $vob              = The VOB to check.
# REVIEW LAK
# The vob types should be identified as constants rater than just returning integers
# See the constanct defined line 170-173
# By definition of the fory types: PVOB, AdminVob, UCM client and Base CC client, a VOB can not be "not idetified"
# If the VOB isn't either PVOB, AdminVOB or UCM client VOB, then by definition, it is a Base ClearCase client vob
# thus get_vobtype should never return 0

Returns:
 4    = BaseCC AdminVOB - This VOB is a normal AdminVOB (not UCM enabled)
 3    = UCM PVOB        - This VOB is a UCM PVOB (ucmvob tagged)
 2    = BaseCC ClientV  - This VOB is a normal client VOB (VOBs AdminVOB is not UCM)
 1    = UCM Client VOB  - This VOB is a UCM client VOB (VOBs AdminVOB is a PVOB)
 0    = Not identified  - This VOB could not be identified.
        This usually means that it is a selfcontained VOB
        (no AdminVOB hyperlink at all)

=cut
	my $vob = shift;
	# REVIEW LAK: 
	# I don't get this construction! is_poradminvob is called to recieve ether 1 or 2
	# and then it's incremented by 2.
	# Usually when you create an is_xxx method you would expect it to return a boolean: 0 or 1
	# It's seldom seen that a boolen function has a built in 'or' clause: PVOB or AdminVOB but
	# even if it does, then I would expect it to return 1 if the VOB is either PVOB or AdminVOB and 0 
	# if it's not
	# I wouldn't excpect a boolean function to return a range of three possible return values (by definition is't not boolean anymore!)
	# It's dangerous to just stat throwing integeres around is_poradminvob returs raw integers and get_vobtype 
	# increments them - unconditionnally by 2 - in that case you could argue that is_poradminvob would be 
	# repsonsible for having retuned either 0, 3 or 4 ...hmm it starts getting nasty!
	# When states are used, they should be defined as named states (See the suggested constants in line 170-173)
	# and then the named states should be referenced.
	# The same - conceptual - commetns goes for is_baseorucmvob to.
	# Basically the functions is_poradminvob and is_baseorucmvob are both artificial - they shouldn't have been 
	# seperate functions
	# The logic they provide should have been here - in get_vobtype

	if (my $ret_val = is_poradminvob($vob)) {
		$ret_val+=2;
		return $ret_val;
	}
    return is_baseorucmvob($vob);
}

##############################################################################

sub get_restriction($$) {

=head2 get_restriction( $qualified_lbtype, $resultref )

Takes a fully qualified lbtype and retrives the brtype it's restricted to.

Parameters:

 $qualified_brtype = The label type to check in the format lbtype:name@\AdminVOB.
 $resultref        = A reference to the scalar the will contain the name of the
                     branch type which the labe type is restricted to, will contain an
                     empty string "" if it's not restricted.

Returns:

 1 = Suceedes
 0 = Some error occured, the value of $resultref is not valid.

=cut

    my $qual_lbtype = shift;
    my $resultref   = shift;

    my @restlist;
    get_from_hlinks( \$qual_lbtype, \acc::HLTYPE_RESTRICTED, \@restlist );
    if ( scalar(@restlist) > 1 ) {
        print "WARNING:\n" . "$qual_lbtype has more than one restriction - that is wrong! ...FIX IT!\n";
        return 0;
    } else {
        $$resultref = ( scalar(@restlist) > 0 ) ? $restlist[0] : "";
        return 1;
    }
}

###############################################################

sub split_dir_file($) {

=head2 split_dir_file( $path )

Splits a path in two: the directory part and the file name part

Parameters:

 $path = The path to split.

Returns:

 ($dir, $file) A two-item array.

=cut

    my ( $dir, $file );
    $file = shift;
    $dir  = ".\\";
    $file =~ /(.*\\)(.*)$/ && do {
        $dir  = $1;
        $file = $2;
    };
    return ( $dir, $file );
}

###############################################################
sub get_hlinks($$$) {

=head2 get_hlinks( $obj, $direction, $hltype )

retrieves the hyperlinks of a certain type from og to an object.

Parameters:

 $obj       =  The fully qualified object in the format type:name@\vob.
 $direction =  The direction to look for legal values are "->" and "<-"
 $hltype    =  The hyperlink to look for

Returns:

 @objects   =  An array containing the objects pointed to or from by the specifiec hyperlinks.

=cut

    my $obj       = shift;
    my $direction = shift;
    my $hltype    = shift;
    my @retval;
    my $cmd = "cleartool desc -ahlink $hltype $obj";
    my $res = `$cmd`;
    foreach my $ln ( split /\n/, $res ) {
        if ( $ln =~ /\s*$hltype\s*$direction\s*(.*)\s*$/ ) {
            push @retval, $1;
        }
    }
    return @retval;
}

###############################################################
sub is_frozen ($) {

=head2 is_frozen(  \$fqlbtype)

Check a label type to see if it's
already frozen.

Parameters:

 $fqlbtype       =  The fully qualified lbtype in the format fully qualifed (lbtype:btyptype@vob).

Returns:

 1     =  The type is frozen.
 0     =  The type isn't frozen (or some error occured)

=cut

    my $fqlbtyperef = shift;
    my $label       = $$fqlbtyperef;

    $label = "lbtype:" . $label;
    $label =~ s/^lbtype:lbtype:/lbtype:/;
    my $cmd = "cleartool desc -s -aattr " . acc::ATTYPE_FROZEN . " " . $label;
    my @res = `$cmd`;

    return scalar(@res);

}

###############################################################

sub get_from_hlinks($$$) {

=head2 get_from_hlinks(  $typeref, $hltyperef, $returnarrref )

Retrieves the objects pointet to by hyperlinks of a certain type pointing from an object.

Parameters:

 $typeref        =  A reference to the The fully qualified object in the format type:name@\vob.
 $hltyperef      =  A reference to the hltype to search for.
 $returnarrayref =  A reference to an arry where the objects pointed to will be placed

Returns:

 -1    =  An error occured - the content of the returnarray is not valid
 0...n =  The number of objects pointed to

=cut

    my $typeref      = shift;
    my $hltyperef    = shift;
    my $returnarrref = shift;
    my $cmd          = "cleartool desc -ahlink $$hltyperef $$typeref";
    my $res          = `$cmd`;
    $? && do {
        my ( $package, $filename, $line ) = caller;
        print STDERR "ERROR:\n" . "Command:\t'$cmd'\n" . "Retuned:\t$res\n" . "Line: $line in '$filename'\n";
        return -1;
    };
    my $direction = "->";
    foreach my $ln ( split /\n/, $res ) {
        if ( $ln =~ /\s*$$hltyperef\s*$direction\s*(.*)\s*$/ ) {
            push @$returnarrref, $1;
        }
    }
    return scalar(@$returnarrref);
}

###############################################################

sub get_to_hlinks($$$) {

=head2 get_to_hlinks(  $typeref, $hltyperef, $returnarrref )

Retrieves the objects pointet from by hyperlinks of a certain type pointing to an object.

Parameters:

 $typeref        =  A reference to the The fully qualified object in the format type:name@\vob.
 $hltyperef      =  A reference to the hltype to search for.
 $returnarrayref =  A reference to an arry where the objects pointed from will be placed

Returns:

 -1    =  An error occured - the content of the returnarray is not valid
 0...n =  The number of objects pointed from

=cut

    my $typeref      = shift;
    my $hltyperef    = shift;
    my $returnarrref = shift;
    my $cmd          = "cleartool desc -ahlink $$hltyperef $$typeref";
    my $res          = `$cmd`;
    $? && do {
        my ( $package, $filename, $line ) = caller;
        print STDERR "ERROR:\n" . "Command:\t'$cmd'\n" . "Retuned:\t$res\n" . "Line: $line in '$filename'\n";
        return -1;
    };
    my $direction = "<-";
    foreach my $ln ( split /\n/, $res ) {
        if ( $ln =~ /\s*$$hltyperef\s*$direction\s*(.*)\s*$/ ) {
            push @$returnarrref, $1;
        }
    }
    return scalar(@$returnarrref);
}

###############################################################
sub mkrestriction($$$) {

=head2 mkrestriction(  $lbtyperef, $brtyperef, $vobref )

Makes a a lbtype restricted to a branchtype. Meaning that the label only cna be applied to versions that resides on that
particulare branch type.

Parameters:

 $lbtyperef      =  A reference to the lbtype (only it's name - not fully qualified).
 $brtyperef      =  A reference to the brtype (only it's name - not fully qualified).
 $returnarrayref =  A reference to the VOB (an ACC meta data VOB)

Returns:

 1     =  Restriction is either created or existed already
 0     =  ERROR the restriction couldn't be created.

=cut

    my $lbtyperef = shift;
    my $brtyperef = shift;
    my $vobref    = shift;
    my $full_lb   = "lbtype:" . $$lbtyperef . "\@" . $$vobref;
    my $full_br   = "brtype:" . $$brtyperef . "\@" . $$vobref;

    system("cleartool desc $full_lb >nul");
    $? && exit 1;
    system("cleartool desc $full_br >nul");
    $? && exit 1;
    system( "cleartool desc hltype:" . acc::HLTYPE_RESTRICTED . "\@$$vobref >nul" );
    $? && exit 1;

    my $cmd = "cleartool mkhlink " . acc::HLTYPE_RESTRICTED . " " . $full_lb . " " . $full_br;

    # scalar_dump(\$cmd);

    my @restlist;
    if ( get_from_hlinks( \$full_lb, \acc::HLTYPE_RESTRICTED, \@restlist ) && grep $full_br, @restlist ) {
        print "WARNING:\n" . "$full_lb already has a restriction to \n$full_br\n";
        return 1;    # Return true even though we didn't do anything
    }

    if ( ( lc( $ENV{acc::CLEARCASE_FORCE_RESTRICTION} ) ne "true" ) && get_to_hlinks( \$full_lb, \"GlobalDefinition", \@_ ) ) {
        print STDERR "WARNING:\n" . "$full_lb is already instantiated with the following children:\n";
        foreach (@_) { print STDERR "\t-> " . $_ . "\n"; }
        print STDERR "You should manually run:\n"
          . "\tcleartool find -avobs -version lbtype($$lbtyperef) -print\n"
          . "\tcleartool find -avobs -version \"{lbtype($$lbtyperef) && !brtype($$brtyperef)}\" -print\n"
          . "Note: You need to be in a view context when you run it and also be aware, that it will potentially\n"
          . "take a long time to finish\n"
          . "You should only carry on if you can validate the result (the output from the command should \n"
          . "be completely EMPTY\n"
          . "$$brtyperef ...NO EXCEPTIONS!)\n"
          . "Define a system variabel named "
          . acc::CLEARCASE_FORCE_RESTRICTION
          . " (value should be \"true\")\n"
          . "And run the command again\n";
        return 0;
    }

    system($cmd);
    return $? / 256;
}

##########################################################################################
sub scalar_dump($) {

=head2 scalar_dump(  \$scalar  )

Prints debug information about a scalar. (scalar name, package, linie number and value).

Parameters:

 $scalar      =  The scalar to dump.

Returns:

 void

=cut

    my $ref = shift;
    my ( $package, $filename, $line ) = caller;
    print STDERR "   ########   Dumping scalar   ########\n"
      . "   Package:          \t$package '$filename'\n"
      . "   Line:             \t$line\n"
      . "   $ref: \t["
      . $$ref . "]\n";
}

##########################################################################################
sub objexist($) {

=head2 objexist(  \$obj  )

Prints debug information about a scalar. (scalar name, package, linie number and value).

Parameters:

 $obj      =  object to test existence for.

Returns:

 1         =  Object exist;
 0         =  Object doesn't exist

=cut

    my $objref = shift;
    my $cmd    = "cleartool desc vob:" . $$objref . " >nul 2>\&1";
    system($cmd);
    return ($?) ? 0 : 1;    # Cleartool desc returns 1 on error and 0 on succes, so it'll have to be inverted:
}

##########################################################################################
sub mkhlink_unique($$$) {

=head2 mkhlink_unique(  \$fromobj, \$toobj, \$hltype )

creates a hyperlink if it doesn't  already exist. Will not create it if it's already there.

Parameters:

 $fromobj     = The fully qualified name of the from object (type:name@vob).
 $toobj       = The fully qualified name of the to object (type:name@vob).
 $hltype      = The name of the hlink type to create.

Returns:

 1     =  Succes - created the hyperlink  or validated that it already existed.
 0     =  ERROR - hyperlink doesn't exist and couldn't be created.

=cut

    my $fromobjref = shift;
    my $toobjref   = shift;
    my $hltyperef  = shift;

    get_from_hlinks( $fromobjref, $hltyperef, \@_ );

    my @matches;
    foreach (@_) {
        $_ eq $$toobjref && push @matches, $_;
    }

    my $count = scalar @matches;
    ( $count > 1 ) && do {
        print STDERR "WARNING: $$fromobjref is already pointing to $$toobjref\n" . "         with hyperlink $$hltyperef $count times\n";
    };

    ( $count eq 1 ) && do {
        print STDERR "$$fromobjref is already pointing to $$toobjref\n";
    };

    exit 1 if $count > 0;

    my $cmd = "cleartool mkhlink $$hltyperef $$fromobjref  $$toobjref";
    system($cmd);
    $? && do {
        print STDERR "ERROR: Failed to create the hyperlink:\nCommand executed was: '$cmd'\n";
        exit 0;
    };
}

################################################################################################
sub mkattr_unique($$) {

=head2 mkattr_unique(  \$attype, \$obj )

creates an attribute using the attypes default value it doesn't  already exist. Will not create it if it's already there.

Parameters:

 $attype      = The name of the attribute type to create.
 $obj         = The fully qualified name of the object to which the attribute shall be attached.

Returns:

 1     =  Succes - created the attribute or validated that it already existed.
 0     =  ERROR - attribute doesn't exist and couldn't be created.

=cut

    my $attyperef = shift;
    my $objref    = shift;

    my $cmd = "cleartool desc -s -aattr " . $$attyperef . " " . $$objref . " 2>\&1";

    my @res = `$cmd`;
    $? && do {
        $_ = join '', @res;
        print STDERR "ERROR: Failed to query attribute:\nCommand executed was: '$cmd'\n It returned: '$_'\n";
        exit 0;
    };

    if ( scalar(@res) ) {
        print "Object " . $$objref . " already has an attribute of type " . $$attyperef . "\n";
    } else {
        my $cmd = "cleartool mkattr -default " . $$attyperef . " " . $$objref;
        system($cmd);
        $? && do {
            print STDERR "ERROR: Failed to create the attribute:\nCommand executed was: '$cmd'\n";
            exit 0;
        };
        return 1;
    }
}

####################################################################################################
sub rmhlink_all($$$) {

=head2 rmhlink_all(  $fromobjref, $toobjref, $hltyperef )

Will remove all hyperlink of the specifiec hltype pointing from one object to another.

Parameters:

 $fromobjref     = The fully qualified name of the from object (type:name@vob).
 $toobjref       = The fully qualified name of the to object (type:name@vob).
 $hltyperef      = The name of the hlink type to remove.

Returns:

 1     =  Succes - removed all hyperlinks or validated that no one existed.
 0     =  ERROR -  Couldn't remove all hyperlinks.

=cut

    my $fromobjref = shift;
    my $toobjref   = shift;
    my $hltyperef  = shift;

    my $cmd = "cleartool desc -l -ahlink $$hltyperef $$fromobjref";
    @_ = `$cmd`;
    $? && do {
        print "the command '$cmd' failed!\n";
        exit 0;
    };

    my $direction = "->";
    my $type      = $$toobjref;
    $type =~ s/\\/\\\\/;

    my $retval = 1;
    my @matches;
    foreach my $ln (@_) {
        chomp($ln);
        if ( $ln =~ /^\s*(\S*)\s*$direction\s*($type)$/ ) {
            push @matches, $1;
            $_ = "cleartool rmhlink $1";
            system($_);
            $? && do {
                print "ERROR: The command '$_' failed!\n";
                $retval--;
              }
        }
    }
    if ( scalar(@matches) == 0 ) { print "No hyperlinks to remove\n"; exit 0; }
    exit $retval;
}

################################################################################################
sub _list_published($$) {

    my $vobref = shift;
    my $long   = shift;

    #  my $cmd = "cleartool desc vob:$$vobref \>nul";
    #  system($cmd);
    #  $? && die "ERROR $$vob is not a legal VOB\n";
    #  my $adminvob = get_adminvob("vob:".$$vobref);
    #  my $xpublish_hltype = "hltype:".acc::HLTYPE_PUBLISHED."\@".$adminvob;
    my $xpublish_hltype = "hltype:" . acc::HLTYPE_PUBLISHED . "\@" . $$vobref;

    #  $cmd = "cleartool desc $xpublish_hltype \>nul";
    #  system($cmd);
    #  $? && do {print STDERR "$xpublish_hltype doesnt exist\n"; return 1};

    if ( !$long ) {
        get_from_hlinks( \$xpublish_hltype, \acc::HLTYPE_PUBLISHED, \@_ );
        foreach (@_) {
            chomp($_);
            $_ =~ /lbtype:(.*)\@.*/;

            # s/lbtype://;
            # print $_."\n";
            print $1. "\n";
        }
    } else {
        my $cmd = "cleartool desc -l -ahlink " . acc::HLTYPE_PUBLISHED . " $xpublish_hltype";
        @_ = `$cmd`;
        $? && do {
            print "the command '$cmd' failed!\n";
            exit 1;
        };
        my $direction = "->";
        my $hltype    = acc::HLTYPE_PUBLISHED;
        foreach my $ln (@_) {
            chomp($ln);
            if ( $ln =~ /^\s*($hltype\@\d+\@.+\s+$direction\s.+)$/ ) {
                print $1. "\n";
            }
        }
    }

    return 0;
}

############################################################################################
sub list_published($$) {

=head2 list_published(  $vobref, $long )

Will print all published labels from a VOB in short or long format.

Parameters:

 $vobref         = The VOB (ACC Meta data) to retrive published labels from.
 $long           = Boolean, true indicates long format, false means short.

Returns:

 0     =  Succes - removed all hyperlinks or validated that no one existed.
 1     =  ERROR -  Couldn't remove all hyperlinks.

=cut

    my $vobref = shift;
    my $long   = shift;
    my $retval = get_published( $vobref, $long, \@_ );
    foreach (@_) { print $_}
    return $retval;
}

############################################################################################
sub get_acc_meta_data_vobs($) {

=head2 get_acc_meta_data_vobs( \@returnlist )

Will return all ACC Meta Data VOBs that are tagged up in the region where it's executed.

Parameters:

 @returnlist     = The result.

Returns:

 1     =  Succes the value of @returnlist is valid;
 0     =  ERROR -  Some error occured don't trust content of @returnlist.

=cut

    my $returnarrayref = shift;

    my $cmd = "cleartool lsvob -s 2>\&1";
    $_ = `$cmd`;

    # $? || return 0;
    foreach my $vob ( split /^/, $_ ) {
        chomp($vob);
        my $cmd = "cleartool desc -fmt \"\%n:\%[" . acc::ATTYPE_ACCMETADATA . "]Na\" vob:$vob";
        $_ = `$cmd`;
        my $regexp = "(.*):" . acc::ATTYPE_ACCMETADATA;
        $_ =~ /$regexp/ && push @$returnarrayref, $1;
    }
    return 1;
}

#########################################################################################
sub get_published($$$) {

=head2 get_published(  $vobref, $long, $returnarrayref  )

Will return an array with all published labels from a VOB in short or long format.

Parameters:

 $vobref         = The VOB (ACC Meta data) to retrive published labels from.
 $long           = Boolean, true indicates long format, false means short.
 $returnarrayref = A reference to the array that will store the result.

Returns:

 0     =  Succes - removed all hyperlinks or validated that no one existed.
 1     =  ERROR -  Couldn't remove all hyperlinks.

=cut

    my $vobref          = shift;
    my $long            = shift;
    my $returnarrayref  = shift;
    my $xpublish_hltype = "hltype:" . acc::HLTYPE_PUBLISHED . "\@" . $$vobref;

    if ( !$long ) {
        get_from_hlinks( \$xpublish_hltype, \acc::HLTYPE_PUBLISHED, \@_ );
        foreach (@_) {
            chomp($_);
            $_ =~ /lbtype:(.*)\@.*/;
            push @$returnarrayref, $1 . "\n";
        }
    } else {
        my $cmd = "cleartool desc -l -ahlink " . acc::HLTYPE_PUBLISHED . " $xpublish_hltype";
        @_ = `$cmd`;
        $? && do {
            print "the command '$cmd' failed!\n";
            exit 1;
        };
        my $direction = "->";
        my $hltype    = acc::HLTYPE_PUBLISHED;
        foreach my $ln (@_) {
            chomp($ln);
            if ( $ln =~ /^\s*($hltype\@\d+\@.+\s+$direction\s.+)$/ ) {
                push @$returnarrayref, $1 . "\n";
            }
        }
    }
    return 0;
}

###############################################################
sub get_composite($$$) {

=head2 get_composite( $lbtype, $level, $resultref )

Returns the composite structure of a lbtype into an array. The functino calls itself recursively.

Parameters:

  $lbtype        = The label to construct
  $level         = The indent level to construct (stepped on for each recursive call)
  $resultref     = A reference to the array that will hold the result

Returns:

 void  =  Noting, empty, not used!

=cut

    my $lbtype    = shift;
    my $level     = shift;
    my $resultref = shift;

    push @$resultref, &indent( $level++ ) . $lbtype;
    my @children;
    get_to_hlinks( \$lbtype, \acc::HLTYPE_COMPOSITE, \@children );
    foreach my $child (@children) {
        &get_composite( $child, $level, $resultref );
    }

    sub indent($)

      # Internal to get_composite
    {
        my $level = shift;

        #my $count = shift;
        my $str = join "", $level;

        #for (my $i = 0; $i < $count; $i++) {
        # $str = $str."\t";
        #}
        $str = $str . "#";
        return $str;
    }
}

###############################################################
sub validate_lbtype($$) {

=head2 validate_lbtype( $lbtype, $retvalref )

Validates the lbtype as a global type in the adminvob, will return the
fully qualified name to the global type.

Parameters:

 $lbtype         = The type to validate.
 $retvalref      = A reference to the scalar that will contain the result.

Returns:

 1     =  Succes - validated that the type is global.
 0     =  ERROR -  Type doesn't exist or isn't global.

=cut

    my $lbtype = shift;
    $lbtype = $$lbtype;
    my $retvalref = shift;

    #Make sure lbtype: is prefixed only once
    $lbtype = "lbtype:" . $lbtype;
    $lbtype =~ s/^lbtype:lbtype:/lbtype:/;

    # The format will return a string in the format:
    # <global|ordinary> lbtype:<tag>@<AdminVOB>
    my $cmd = "cleartool desc -fmt \"\%[type_scope]p \%Xn\" $lbtype";
    my ( $scope, $xlbtype ) = split / /, `$cmd`;

    # Quit if the cleartool describe command failed
    $? && do { print STDERR "$lbtype is not a legal lbtype\n"; return 0 };

    # Quit if scope of type is not global
    ( $scope ne acc::GLOBAL_SCOPE ) && do { print STDERR "$xlbtype doesn't have " . acc::GLOBAL_SCOPE . " scope\n"; return 0 };

    # OK! Set the out-parameter to the fq_typename
    $$retvalref = $xlbtype;
    return 1;
}

###############################################################
sub freeze($) {

=head2 freeze( $lbtyperef )

Takes a reference to a fully qualified label type and applies the
Frozen attribute to it.

Parameters:

 $lbtyperef     =  A FQ lbtype.

Returns:

 1 =  Success
 0 =  Some error occured.

=cut

    my $lbtyperef = shift;
    my $qual_lbtype;
    validate_lbtype( $lbtyperef, \$qual_lbtype );

    #my $cmd = "cleartool mkattr -default ".acc::ATTYPE_FROZEN." ".$qual_lbtype;

    #system($cmd);
    #$? && do {
    #   print STDERR "ERROR: Failed to create the attribute:\nCommand executed was: '$cmd'\n";
    #   exit 0;
    # };
    #return 1;
    return mkattr_unique( \acc::ATTYPE_FROZEN, \$qual_lbtype );
}

###############################################################
sub labels_to_cs($$$) {

=head2 labels_to_cs( $labelcsv, $branch, $csref )

Takes a comma separated list of label types, and potentially a working branch
and returns a valid config spec. if the working branch is specified as an empty
string, the config spec will be read only.

Note that that this method doesn't the $branch, you should do that before you
call the function.

Parameters:

 $labelscsv     =  A prioritzed comma separated list of label
                   types to adress in the config spec.
 $branch        =  The branch to use as work branch, if this parameter
                   is an empty string ("" as opposed to not defined) then
                   the generated config spec will be read-only
 $csref         =  Outparameter, A reference to the scalar that
                   will contain the config spec.

Returns:

 1 =  Success
 0 =  Some error occured, the content of $csref is not valid.

=cut

    my $labelcsv = shift;
    my $branch   = shift;
    my $csref    = shift;

    my $qual_labels;
    foreach ( split /,/, $labelcsv ) {
        my $qual_lbtype;
        validate_lbtype( \$_, \$qual_lbtype ) || do {
            print "ERROR: $_ couldnt't be validated as 'global' in the adminvob\n";
            return 0;
        };
        $qual_labels = $qual_labels . $qual_lbtype . ",";
    }
    chop($qual_labels);    ## get rid of the tailing comma

    push @$csref, "##################### ACCELERATED CLEARCASE ###################";
    push @$csref, "##  THIS CONFIG SPEC IS AUTOMATICALLY CREATED. UNDER NORMAL  ##";
    push @$csref, "## CONDITIONS YOU SHOULD NOT EDIT THIS CONFIG SPEC YOURSELF. ##";
    push @$csref, "## THIS COMMENT BLOCK CONTAINS INFORMATION WHICH IS REQUIRED ##";
    push @$csref, "##   FOR THE ABILITY TO RE-SYNCHRONIZE THE CONFIG SPEC WITH  ##";
    push @$csref, "##    THE COMPOSITE LABLES - IF YOU CHANGE THAT INFORMATION  ##";
    push @$csref, "##           THEN YOU REALLY ASKED FOR IT YOURSELF           ##";
    push @$csref, "##                 ...YOU'LL BE ON YOUR OWN!!!               ##";
    push @$csref, "###############################################################";
    push @$csref, "## acc::view::lbtypes::" . $qual_labels;
    push @$csref, "## acc::view::workbranch::" . $branch;
    push @$csref, "###############################################################";
    push @$csref, "";

    my $rule_clause = " -nocheckout";    ##assume that we need the -nocheckout clause
    if ( $branch ne "" ) {
        $rule_clause = "";               ##detronize the -nocheckout clause
        push @$csref, "element * CHECKEDOUT";
        push @$csref, "element * .../" . $branch . "/LATEST";
        push @$csref, "";
        push @$csref, "mkbranch " . $branch;
        push @$csref, "";
    }

    foreach my $qual_lbtype ( split /,/, $qual_labels ) {

        push @$csref, "############# BEGIN expanding:" . $label;
        my @composite;

        get_composite( $qual_lbtype, 0, \@composite );
        foreach my $br (@composite) {
            print "\$br:\t$br\n";
            lbtype_to_csrule( \$br, \$_ ) && push @$csref, $_ . $rule_clause;
        }
        push @$csref, "#############  END  expanding:" . $label;
        push @$csref, "";

    }

    if ( $branch ne "" ) {
        push @$csref, "element * /main/0";
        push @$csref, "";
        push @$csref, "end mkbranch " . $branch;
    }
    return 1;
}

###############################################################
sub lbtype_to_csrule($$) {

=head2 lbtype_to_csrule( $lbref, $retref )

Converts a label name into the corresponding Config Spec rule. (in the format "element * <lbtype>")

Parameters:

 $qualified_brtype = The label type to convert.
 $$retref          = A reference to the scalar the will contain the name of the
                     config spec rule.

Returns:

 1 = Suceedes
 0 = Some error occured, the value of $retref is not valid.

=cut

    my $lbref  = shift;
    my $retref = shift;

    print "\$\$lbref:\t$$lbref\n";

    if ( $$lbref =~ /(\s*)lbtype:(.*)\@(.*)$/ ) {
        $$retref = $1 . "element * " . $2;
        return 1;
    } else {
        $$retref = "";
        return 0;
    }
}

################################################################
sub initmeta($) {

=head2 initmeta( \$vob )

Creates or replaces the reguired meta data (types) to a vob (ACC Meta Data VOB). Also Attaches the AccMetaData attribute to the VOB.

Parameters:

 $vob     =  A vob tag.

Returns:

 1 =  Success - types are created or validated
 0 =  Some error occured.

=cut

    $_ = shift;
    my $vob = $$_;

    system("cleartool desc vob:$vob >nul 2>\&1");
    ($?) && do {
        print STDERR "ERROR: The VOB $vob doesn't exist\n";
        exit 1;
    };

    # Create the required types

    # defined them first:
    my %types = (
        "attype:" . acc::ATTYPE_FROZEN . "\@" .
          $vob => "-c \"ACC meta type\" -vtype string -default \\\"\\\" ",
        "attype:" . acc::ATTYPE_PROMOTION_LEVEL . "\@" .
          $vob => "-c \"ACC meta type\" -vtype string -enum \\\"released\\\",\\\"tested\\\",\\\"built\\\",\\\"integrated\\\" ",
        "attype:" . acc::ATTYPE_KEYWORDS . "\@" .
          $vob => "-c \"ACC meta type\" -vtype string -default \\\"\\\" ",
        "attype:" . acc::ATTYPE_LBTYPE_TEMPLATE . "\@" .
          $vob => "-c \"ACC meta type\" -vtype string -default \\\"[A-Z][A-Z0-9_-\\\\.]{3,30}\\\" ",
        "attype:" . acc::ATTYPE_BRTYPE_TEMPLATE . "\@" .
          $vob => "-c \"ACC meta type\" -vtype string -default \\\"[a-z][a-z0-9_]{3,30}\\\" ",
        "attype:" . acc::ATTYPE_ATTYPE_TEMPLATE . "\@" .
          $vob => "-c \"ACC meta type\" -vtype string -default \\\"[a-zA-Z][a-zA-Z0-9]{3,30}\\\" ",
        "attype:" . acc::ATTYPE_HLTYPE_TEMPLATE . "\@" .
          $vob => "-c \"ACC meta type\" -vtype string -default \\\"[a-zA-Z][a-zA-Z0-9]{3,30}\\\" ",
        "attype:" . acc::ATTYPE_ACCMETADATA . "\@" .
          $vob => "-c \"ACC meta type\" -vtype string -default \\\"\\\" ",
        "hltype:" . acc::HLTYPE_PUBLISHED . "\@" .
          $vob => "-c \"ACC meta type\" ",
        "hltype:" . acc::HLTYPE_COMPOSITE . "\@" .
          $vob => "-c \"ACC meta type\" ",
        "hltype:" . acc::HLTYPE_RESTRICTED . "\@" .
          $vob                                        => "-c \"ACC meta type\" ",
        "lbtype:" . acc::LBTYPE_INITIAL . "\@" . $vob => "-c \"ACC meta type\" "
    );

    foreach ( keys(%types) ) {

        # if it altready exist set the -replace switch
        my $cmd = "cleartool desc $_ >nul 2>\&1";
        system($cmd);
        my $replace = ($?) ? "" : " -replace  ";

        # Construct and execute the command;
        my ( $type, $tag ) = split /:/, $_;
        $cmd = "cleartool mk" . $type . $replace . " -global -acquire " . $types{$_} . " " . $tag . " 2>\&1";
        $_   = `$cmd`;
        chomp($_);

        # make the proper output
        if ( !$? ) {
            print $_. "\n";
        } else {
            print STDERR "ERROR:\nThe command:\t'$cmd'\nreturned:\t'$_'\n";
        }
    }

    # Attach the necessary attributes (templates) to the vob

    # Set the META DATA attribute
    my $fqvob = "vob:" . $vob;
    mkattr_unique( \acc::ATTYPE_ACCMETADATA, \$fqvob );

    # Apply the naming template attributes

    mkattr_unique( \acc::ATTYPE_ATTYPE_TEMPLATE, \$fqvob );
    mkattr_unique( \acc::ATTYPE_HLTYPE_TEMPLATE, \$fqvob );
    mkattr_unique( \acc::ATTYPE_BRTYPE_TEMPLATE, \$fqvob );
    mkattr_unique( \acc::ATTYPE_LBTYPE_TEMPLATE, \$fqvob );

    # lock the INITIAL lbtype ...make frozen!
    my $fqlbtype_initial = "lbtype:" . acc::LBTYPE_INITIAL . "\@$vob";

    mkattr_unique( \acc::ATTYPE_FROZEN, \$fqlbtype_initial );

    # APPLY TRIGGERS!

    print "\n"
      . "###########################################################\n"
      . "##   REMEMBER TO APPLY ALL THE NECESSARY TRIGGERS!!!!    ##\n"
      . "##   Both on the ACC Meta Data VOB  and all Client VOBs  ##\n"
      . "###########################################################\n";

    return 1;
}

################################################################
sub set_default_acc_meta($$) {

=head2 set_default_acc_meta( \$vob,\$region )

Assigns the role "default Acc Meta VOB" to a VOB within an existing region.
if another VOB already has that role it will be revoked from the current VOB and assigned to the new one.

Parameters:

 $vob        =  A vob tag.
 $region     =  A region tag

Returns:

 1 =  Success - default meta data VOB role assigend
 0 =  Some error occured.

=cut

    $_ = shift;
    my $vob = $$_;
    $_ = shift;
    my $region = $$_;

    scalar_dump( \$vob );
    scalar_dump( \$region );
    return 1;
}

################################################################
sub get_default_acc_meta($) {

=head2 get_default_acc_meta( \$result )

Returns the "default Acc Meta VOB" within the context from where
it's executed.

Parameters:

  $result

Returns:

 1 =  Success - default meta data VOB is stored in $result
 0 =  There is no default meta data VOB defined.

=cut

    my $resultref = shift;
    $$resultref = defined( $ENV{acc::CLEARCASE_ACCMETADATAVOBVOB} ) ? $ENV{acc::CLEARCASE_ACCMETADATAVOBVOB} : "none";
    $_ = ( $$resultref ne "" ) ? 1 : 0;
    return $_;
}

################################################################
sub validate_global_invob($$$) {

=head2 validate_global_invob( $vobref, $typeref, $kindref, $paramsref )

validates that a certain type exist as global in a VOB (ACC meta VOB). if it doesn't it will be created as a global type.
if the type exist but is not global it will be replaced

Parameters:

 $vobref     =  A vob tag.
 $typeref    =  The type to validate/create.
 $kindref    =  The kind of the type, must be one of "lbtype", "attype", "hltype"
 $paramsref  =  The additional parameters that will be passed to the mkxxtype command if any.

Returns:

 3 =  Success - type existed as local - changed to global
 2 =  Success - Type existed as global - type is validated
 1 =  Success - type is created as global
 0 =  Some error occured.

=cut

    my $vobref  = shift;
    my $typeref = shift;
    my $kindref = shift;
}
