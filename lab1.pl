#my %views = get_views_across_regions();
#while (($stg,$tags) = each(%views)){ print $stg."\n".$tags."\n"; }


my @views;
die unless get_vwsstgs_nasince("2008-01-01",\@views);
foreach (sort @views) {print $_}




#############################
sub get_vwsstgs_nasince($$){
  my $cut_date = shift;
  my $result = shift;
  return 0 unless ($cut_date =~ /(\d\d\d\d-\d\d-\d\d)/);          
  my %views =  get_vwsstgs_across_regions();
  foreach $stg (keys(%views)){
    @_ = split(/;/, $views{"$stg"}); # Turn the semi-colon seprated list of tags into an array
    $_ = $_[0];                      # Get the first one (any - one will do)
    s/-tag//;                        # strip the -tag switch, it's not used in lsview
    $age_res = `cleartool lsview -age $_`;
    @_ = split(/\n/,$age_res);       # Split the result on \n (I want to throw away the first line)
    $_ = @_[1];                      # Grab the second line (where the relevant timestamp is listed)
    /(\d\d\d\d-\d\d-\d\d)/;          # Now get the date in the format YYYY-MM-DD
    
    push(@$result, $1."\t".$stg."\n") if $1 < $cut_date;
  }
  return 1;
}



=head2 get_vwsstgs_across_regions()

This function returns a hash containing all views across all regions.

The format of the hash entries are like this:
  keys                 = The global view storage location;
  values               = a semi-colon separated list of all region/tags pairs in the 
                         format: -region <region> -tag <tag>

Parameters:
  none

Returns:
  %vws_stgs (The hash)

=cut

sub get_vwsstgs_across_regions(){
  my %vws_stgs;
#  foreach my $region (`cleartool lsregion`){
     my $region = "QTEST";
    chomp($region);
    foreach $v (`cleartool lsview -region $region`){
      # Any number of whitespaces or * (if the view is started) followed by non-whitespace chars (the view tag) followed by whitespaces by non-whitespace chars (the view storage)  
      $v =~ /^[\s\*]*(\S*)\s*(\S*)$/;
      $vws_stgs{"$2"}=$vws_stgs{"$2"}."-region \"$region\" -tag \"$1\";";
    }
#  }
  return %vws_stgs;
}










