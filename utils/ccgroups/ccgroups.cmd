@rem = '-*- Perl -*-';
@rem = '
@echo off
call ratlperl %0 %*
exit /B %ERRORLEVEL%
@rem ';

our ($Scriptdir, $Scriptfile);
BEGIN{
	$Scriptdir =".\\";$Scriptfile = $0;                                # Assume the script is called from 'current directory' (no leading path - $0 is the file)
	$Scriptfile =~/(.*\\)(.*)$/ &&  do{$Scriptdir=$1;$Scriptfile=$2;}  # Try to match on back-slashes (file path included) and correct mis-assumption if any found
}

my %unique;
my $setx = $Scriptdir."setx.exe";

(-e $setx) || die "can't locate 'set.exe' (From the MS Ressource Kit) - should be in same folder as $Scriptfile\n";

print "Investigating available VOBs to determine interesting ClearCase groups\n";

foreach $vob (`cleartool lsvob -s`){
  $cmd="cleartool desc vob:$vob";
  foreach $g (grep /\s*group (.*)$/m, `$cmd`){
    ($_,$group) = split /\\/,$g;
    print ".";
    $unique{$group}="";
  }
}

print "\n\n";

$cmd2="$setx CLEARCASE_GROUPS \"";
foreach $k (sort keys(%unique)){
  chomp($k);
  $cmd2 = $cmd2.$k.";";
}
$cmd2 = $cmd2."\"";

system ($cmd2);

$result = ($?)? "Error setting the CLEARCASE_GROUPS environment variable failed\n".
                "Please contact your ClearCase admin!"
              : "SUCCES!\n".
                "The CLEARCASE_GROUPS environment variable is now set correct.\n".
                "But it's NOT updated in your currently running programs. Therefore\n".
                "you should stop and restart all running application that needs to \n".
                "access files that are in ClearCase";
print $result;

exit $?/256;

__END__

######################## DOCUMENTATION ##############################
=pod

=head1 NAME

ccgroups - A utility script for setting the CLEARCASE_GROUPS environment variable.

Script:        F<ccgroup.pl>


=head1 SYNOPSIS

Execute on the ClearCase client machine, to set the CLEARCASE_GROUPS environment variable. 
After the execution the CLEARCASE_GROUP variable will contain a semi-colon seperated list 
of all the groups and additional groups that are referred to by the VOBs avaiable in the 
curent region.

=head2 Restrictions

None

=head2 Dependencies

F<setx.exe> from the Microsoft Ressource Kit must be located in the same directory as F<ccgroup.pl> 
itself.

The script is a self executing perls script (do't be fooled by the F<.cmd> extension)  the script is 
dependant on the ratlperl intepreter being installed (it is per default in any ClearCase client installation).

=head1 DESCRIPTION

ClearCase queries the domain controller what groups a user is memeber of, but it really only pays attention 
to the first 32 groups in the reply.

If you let the CLEARCASE_GROUPS environment variable contain a list of groups that are used as security groups on 
ClearCase VOBs then ClearCase will validate membership of these groups first.

You wan't the CLEARCASE_GROUPS to be setup correct if you use "addtional groups" on any of your VOBs.

An HEY! If CLEARCASE_GROUPS is setup correct you don't have to set the CLEARCASE_PRIMARY_GROUP.

=head1 AUTHOR

Lars Kruse, E<lt>lak@praqma.netE<gt>.

=head1 BUGS

See the website below.

=head1 COPYRIGHT

This program is distributed under the GNU General Pulic License v3.0

Support:    http://launchpad.net/acc

=for html <a href="http://launchpad.net/acc">Project home at Launchpad</a>

=cut