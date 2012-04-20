my $header = <<ENDHEADER;
###########################################################################################################
#     label_parent.pl                                                                                     #
#     This script is intended as postop trigger script (element -all) on the MKLABEL event                #
#     It checks if the parent folder of the CLEEARCASE_PN element being labeled is already labeled.       #
#     If not it's sets the label.                                                                         #
#     Install it on your VOBs like this:                                                                  #
#     mktrtype  -element -all -postop mklabel -exec "ratlperl label_parent.pl" LABEL_PARENT               #
#     Comment:    The intend is to ensure that a label is valid even on the element's parent              #
#     Variant:    Created for ATP (www.atp.dk)                                                            #
#     Date:       09-MAY-2007                                                                             #
#     Author:     Lars Kruse, lars.kruse\@krusecontrol.net                                                 #
#     Copyright:  Use it if you like it!                                                                  #
###########################################################################################################

ENDHEADER

$ENV{'CLEARCASE_OP_KIND'} || die $header;    # We're NOT executed from a ClearCase event!
$debug = 0;                                  #To run the trihher in verbose mode, set $debug=1 and
                                             #run the command that fire the trigger from commandline

exit validate_parent( $ENV{CLEARCASE_PN}, $ENV{CLEARCASE_LBTYPE} );

############# sub validate_parent #############
# validate_parent($pname,$lbtype)
# Returns 0 if the label is already on the parent
# Returns 0 if the label is not on the parent, and it succeeds in putting it there
# Returns 1 in all other cases

sub validate_parent {
	my $pname          = shift;
	my $lbtype         = shift;
	my $retval         = 0;
	my $parent         = get_parent($pname);
	my $cmd            = "cleartool desc -fmt \%Nl $parent";    #Returns a "whitespace seperated" list of lables on the element
	my @current_labels = split /\s/, `$cmd`;                    #split on whitespaces
	$debug && do {
		print "Current labels on parent $parent:\n";
		foreach (@current_labels) { print $_. "\n" }
	};
	if ( grep /^$lbtype$/, @current_labels ) {                  #look for EXACT lbtype name, including match on both line begin and line end
		$debug && print "lbtype:$lbtype already on parent:$parent\n";
	}
	else {
		$debug
		  && print "lbtype:$lbtype not on parent:$parent.  \n...setting it!\n";
		$cmd = "cleartool mklabel -replace $lbtype $parent";
		system("$cmd");
		$retval = ( ($?) / 256 );
	}
	return $retval;
}
############# sub get_parent #############
# get_parent($pname)
# returns the parrent diretory of $pname

sub get_parent {
	my $pname = shift;
	$pname =~ /(.*)\\(.*)$/;
	$debug && print "Parent:\t'$1'\nNode:\t'$2'\n";
	return "\"$1\"";
}
