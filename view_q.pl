######################## STANDARD STUFF ##############################
#
require 5.001;
use strict;
our ( $scriptdir, $scriptfile );
BEGIN { if ($0 =~ /(.*[\/\\])(.*)$/){
  $scriptdir = $1; $scriptfile = $2; } else {
  $scriptdir = "."; $scriptfile = $0; }
}

# Use clauses
use Getopt::Long;

# File version
our $VERSION      = "0.1";
our $BUILD        = "1";

my $debug = 0;
my $verbose_mode=1;

# Header and revision history
our $header = <<ENDHEADER;
#########################################################################
#     $scriptfile  version $VERSION\.$BUILD                                      
#     This script is managing views based on their last accessed dates.
#     The script has several different features for taking views in and 
#     out of quarantine.
#     Execute with -help switch to learn more 
#     Date:       2009-03-25                                            
#     Author:     Lars Kruse, lars.kruse\@praqma.net               
#     Copyright:  Lars Kruse
#     License:    GNU General Pulic License
#     Support:    http://www.praqma.info
#########################################################################

ENDHEADER

# Revision information
#########################################################################
our $revision = <<ENDREVISION;
DATE        EDITOR  NOTE
----------  -------------  ----------------------------------------------
2009-03-25  Lars Kruse     1st release prepared for RUG-DK (version 0.1.1)
-------------------------------------------------------------------------

ENDREVISION

my $usage = <<ENDUSAGE;
  $scriptfile -lsquarantine [-autopurge | -autorecover]
  $scriptfile -nasince date [-autoquarantine]
  $scriptfile -quarantine stgloc
  $scriptfile -recover stgloc
  $scriptfile -purge stgloc
  $scriptfile -touch [-region region] viewtag
  $scriptfile -help

ENDUSAGE


my $doc = <<ENDDOC;
            
-lsquarantine           List views that are currently in quarantine. 
                        NOTE: This switch is only supporten when executed on 
                        ClearCase Registry server.        
-autopurge              Optional switch only valid together with -lsquarantine. When 
                        -autopurge is appied the storages found by -lsquarantine will
                        automatically be purged (permanently deleted)                                                                                    
-autorecover            Optional switch only valid together with -lsquarantine. When 
                        -autorecover is appied the storages found by -lsquarantine will
                        automatically be recovered.                                                                                    
-nasince date           Lists views that are not accessed since date. Date must 
                        be in the format YYYY-MM-DD.
-autoquarantine         Optional swith only valid together with -nasince. When 
                        -autoquarantine is applied the views found be -nasince will be 
                        put into quarantine.
-quarantine stgloc      Will put the viewstg applied as stglog into quarantine. The format
                        of stgloc must be the global path (as listed with lsview).
-recover stgloc         Will recover the viewstg applied as stgloc out of quarantine. The 
                        format of stgloc can be the global path (as listed with lsview).
                        or the local path (as listed by rgy_check, stranded views).                        
-purge stgloc           Will purge (rmview) the viewstg applied as stgloc. The 
                        format of stgloc can be the global path (as listed with lsview).
                        or the local path (as listed by rgy_check, stranded views).
-touch viewtag          Will update the 'Last accessed' date of the view applied in 
                        viewtag to the current time.
-region region          The region switch is used to qualify the viewtag applied with
                        -touch if necessary. if -region is omitted, the viewtag is 
                        searched in the current region.                                                     
-help                   Get help with the scritp syntax etc.

ENDDOC

my ($sw_lsquarantine, $sw_recover, $sw_purge, $sw_nasince, $sw_quarantine, $sw_autoquarantine,
    $sw_autopurge, $sw_help, $sw_region, $sw_touch, $sw_autorecover);  
my %options = ( "autoquarantine"     => \$sw_autoquarantine,             
                "lsquarantine"       => \$sw_lsquarantine,          
                "nasince=s"          => \$sw_nasince,          
                "help"               => \$sw_help,
                "quarantine=s"       => \$sw_quarantine,
                "recover=s"          => \$sw_recover,
                "purge=s"            => \$sw_purge,
                "autopurge"          => \$sw_autopurge,
                "autorecover"        => \$sw_autorecover,
                "touch"              => \$sw_touch,
                "region=s"           => \$sw_region);
                
die "$usage" unless GetOptions(%options);

defined($sw_help) && do {print $header.$revision.$usage.$doc; exit 0;};   

### Global variables ###
our %stg_directory;
our $view_q_file=".view_quarantine";


### RECOVER ###
defined($sw_recover) && do {
  print "recover\n";
  (  defined($sw_lsquarantine) || defined($sw_purge) || defined($sw_nasince) ||
     defined($sw_quarantine) || defined($sw_touch) || 
     defined($sw_autoquarantine) || defined($sw_autopurge)  || defined($sw_region) || defined($sw_autorecover)
  ) && do {print "Wrong syntax\n".$usage; exit 1;};
  
  recover_stg($sw_recover);
  exit 0;
};

### LSQUARANTINE ###
defined($sw_lsquarantine) && do {
  print "lsquarantine\n";
  (  defined($sw_purge) || defined($sw_nasince) || defined($sw_quarantine) || defined($sw_touch) || 
     defined($sw_autoquarantine) || defined($sw_region)
  ) && do {print "Wrong syntax\n".$usage; exit 1;};
  (  defined($sw_autorecover) && defined($sw_autopurge) ) && do {print "-autopurge and -autorecover can't be used together\n".$usage; exit 1;};
  foreach (lsquarantined() ){
    print $_;
    defined($sw_autopurge) && do {
       purge_stg($_);
    };

    defined($sw_autorecover) && do {
       recover_stg($_);
    };

  }
  exit 0;
};

### PURGE ###
defined($sw_purge) && do {
  print "purge\n";
  (  defined($sw_nasince) || defined($sw_quarantine) || defined($sw_touch) || 
     defined($sw_autoquarantine) || defined($sw_autopurge) || defined($sw_region)  || defined($sw_autorecover)
  ) && do {print "Wrong syntax\n".$usage; exit 1;};
  purge_stg($sw_purge);
  exit 0;
};

### NASINCE ###
defined($sw_nasince) && do {
  print "nasince\n";
  (  defined($sw_quarantine) || defined($sw_touch) || 
     defined($sw_autopurge) || defined($sw_region)  || defined($sw_autorecover)
  ) && do {print "Wrong syntax\n".$usage; exit 1;};
  
  my @views;
  die "ERROR: Wrong date format (use YYYY-DD-MM)\n" unless vwsstgs_nasince($sw_nasince,\@views);
  foreach (sort @views) {
    print $_;
    defined($sw_autoquarantine) && do {
      my ($d, $stg) = split(/\t/, $_);
      quarantine_stg($stg); 
    };
  }
  exit 0;
};

### QUARANTINE ###
defined($sw_quarantine) && do {
  print "quarantine\n";
  (  defined($sw_touch) || defined($sw_autoquarantine) || defined($sw_autopurge) || 
     defined($sw_region)  || defined($sw_autorecover)
  ) && do {print "Wrong syntax\n".$usage; exit 1;};
  quarantine_stg($sw_quarantine);
  exit 0;
};

### TOUCH ###
defined($sw_touch) && do{
  print "touch\n";
  (  defined($sw_autoquarantine) || defined($sw_autopurge)  || defined($sw_autorecover)) && do {print "Wrong syntax\n".$usage; exit 1;};
  exit 0;
};

print "Wrong syntax\n".$usage;
exit 1;


#######################################
#######################################

#my %views = get_views_across_regions();
#while (($stg,$tags) = each(%views)){ print $stg."\n".$tags."\n"; }



 #quarantine_stg("\\\\cccq7\\cc_stg\\views\\CCCQ7\\student\\student_bugfix_34.vws"); 

#my @list;
#lsquarantined(\@list);
#foreach (@list) {
#  print $_; 
#  recover_stg($_);
#}
#die;


#quarantine_stg("\\\\cccq7\\cc_stg\\views\\CCCQ7\\student\\student_bugfix_34.vws");
#die;




#die;
#die unless quarantine_stg("\\\\cccq7\\cc_stg\\views\\CCCQ7\\student\\student_bugfix_34.vws");
#die unless recover_stg("\\\\cccq7\\cc_stg\\views\\CCCQ7\\student\\student_bugfix_34.vws");










#############################

=head2 lsquarantined( )

NOTE: This function will only run on ClearCase registry servers!!!

This function lists all the quarantined views.

The format of the listing is the local view storage.

A quarantined view is defined as a view that is reported "stranded" by rgy_check and which has
a .view_quarantine file in the admin directory of the storage.

Parameters:

  none 

Returns:

  @result    =    The list of quarantined storages.

=cut

sub lsquarantined( ){
  my @result;
  foreach (grep(/-local_path/, `rgy_check -views 2>&1`)){
    /-local_path = \"(\S*)?\"/;
    push(@result, "$1\n") if (-e "$1\\admin\\$view_q_file"); 
  };
  return @result;
}


=head2 recover_stg( $stg )

This function recovers a view storage.

It will recreat all the tags in all regions where it was tagged at the time it was quarantiend.

Parameters:

  $stg   = The storage to quarantine (the global one, as reported by a lsview command, or 
           simply the local-path as reported by rgy_check) 

Returns:

  1    =    Success
  0    =    The $stg does not conatain a .view_quarantine file in the admin directory.

=cut

sub recover_stg( $ ){
  my $stg = shift;
  chomp($stg);
  my $view_q_file_loc = "$stg\\admin\\$view_q_file";
  return 0 unless (-e $view_q_file_loc);
  open  VIEW_Q_FILE ,"$view_q_file_loc" or die "Couldn't open '$view_q_file_loc'\n";
  foreach (<VIEW_Q_FILE>){print $_; system($_);};
  close VIEW_Q_FILE or print STDERR "Couldn't close '$view_q_file_loc'\n";
  # my $cnt = unlink $view_q_file_loc; print "Deleted $cnt file(s)\n";
  return 1;
}


sub purge_stg($){
  my $stg = shift;
  chomp($stg);
  my $view_q_file_loc = "$stg\\admin\\$view_q_file";
  (-e $view_q_file_loc)  || do {
    print STDERR "ERROR: '$stg' is not a quarantined storage\n";
    return 0;
  };
  
    
  my $mktagcmd = "cleartool mktag -view -tag VIEW_Q_TEMP_TAG $stg";
  my $endviewcmd = "cleartool endview -server VIEW_Q_TEMP_TAG";
  my $rmviewcmd = "cleartool rmview $stg";
  
  print "$mktagcmd\n";
  system("$mktagcmd");
  $_ = $?/256; print "Returned:$_\n";

  print "$endviewcmd\n";
  system("$endviewcmd");
  $_ = $?/256; print "Returned:$_\n";

  print "$rmviewcmd\n";
  system("$rmviewcmd");
  $_ = $?/256; print "Returned:$_\n";
  
  return 1;
}



=head2 quarantine_stg( $stg )

This function quarantines a view storage.

It will untag tags in all regions and record the reverse commands (the corresponding
mktag commands) in a file named .view_quarantine located in the admin directory of the 
view storage.

Parameters:

  $stg   = The storage to quarantine (the global one, as reported by a lsview command) 

Returns:

  1    =    Success
  0    =    The $stg parameter is invald - nothing to do!

=cut


sub quarantine_stg( $ ){
  my $stg = shift;
  chomp($stg);
  prepare_stg_directory();
  return 0 unless defined($stg_directory{"$stg"}); # Get out if the view storage has no entry in the directory
  my @rmtags;
  my @mktags;
  foreach (split(/;/, $stg_directory{"$stg"})){
     push(@mktags, "cleartool mktag -view ".$_." ".$stg."\n");
     s/-tag//;  # strip the -tag switch which isn't used in rmtag
     push(@rmtags, "cleartool rmtag -view ".$_);
  }
  my $view_q_file_loc = $stg."\\admin\\".$view_q_file;  
  open  VIEW_Q_FILE ,">$view_q_file_loc" or die "Couldn't open '$view_q_file_loc'\n";
  foreach (@mktags){print VIEW_Q_FILE $_;};
  close VIEW_Q_FILE;
  foreach (@rmtags){print $_."\n";system($_);};
  return 1;
}

=head2 vwsstgs_nasince( $cut_date, \@result )

This function pushes (global) view storage locations onto the result array
handed into the sub as a refernce if they havent been accessed since $cut_date.

The format of the resulting list entries are like this:
  <YYYY-MM-DD> <view_stg>

Where  view <YYYY-MM-DD> is the last accessed date, and <view_stg> is the global view storage location.

Parameters:

  $cut_date      =  The date to compare against. The scalar must be in the format YYYY-DD-MM
  \@result       =  An arrary reference passed into the sub function

Returns:

  1    =    The content of @result is trust worthy
  0    =    The $cut_date is in an unsupported format. The content of @result is crab!

=cut

sub vwsstgs_nasince($$){
  my $cut_date = shift;
  my $result = shift;
  return 0 unless ($cut_date =~ /(\d\d\d\d-\d\d-\d\d)/);          
  prepare_stg_directory();
  foreach my $stg (keys(%stg_directory)){
    @_ = split(/;/, $stg_directory{"$stg"}); # Turn the semi-colon seprated list of tags into an array
    $_ = $_[0];                      # Get a region/tag pair (anyone will do, so we just grab the first)
    s/-tag//;                        # strip the -tag switch, it's not used in lsview
    @_ = split(/\n/,`cleartool lsview -age $_`);       # lsview with the -age switch return two lines
    $_ = @_[1];                      # Grab the second line (where the relevant timestamp is listed)
    /(\d\d\d\d-\d\d-\d\d)/;          # Get the date in the format YYYY-MM-DD
    
    push(@$result, $1."\t".$stg."\n") if $1 < $cut_date; #If the last accessed date is prior to the cut_date, push it onto the result.
  }
  return 1;
}


=head2 sub prepare_stg_directory( )

This function is related to the global hash: %stg_directory.

%stg_directory is used be several sub functions as a common directory listing of view storages
and view tags.

After it has been prepared, the format of the hash entries are like this:

  keys                 = The global view storage location;
  values               = A semi-colon separated list of all region/tags pairs in the 
                         format: -region <region> -tag <tag>

This function validates that the global hash containing all views across all regions is 
loaded and trustworthy.

All operations querying the directory should call this sub function first.

Parameters:

  none

Returns:

  0      The %stg_directory is already prepared, it will be reused.
  1      The %stg_directory has been prepared.

=cut

sub prepare_stg_directory(){
  return 0 if keys(%stg_directory); # Someone else already prepared the directory, reuse it! Let's get out.
  foreach my $region (`cleartool lsregion`){
    chomp($region);
    foreach (`cleartool lsview -region $region`){
      /^[\s\*]*(\S*)\s*(\S*)$/; # Any number of whitespaces or * (if the view is started) followed by non-whitespace chars (the view tag) followed by some whitespaces and tne another set of non-whitespace chars (the view storage)  
      $stg_directory{"$2"}=$stg_directory{"$2"}."-region \"$region\" -tag \"$1\";"; #build a unique list of view storages containing the tags in all regions
    }
  }
  return 1
}
