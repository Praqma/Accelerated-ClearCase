my %views;
foreach $region (`cleartool lsregion`){
#  print $region;
  chomp($region);
  
  foreach $view (`cleartool lsview -region $region`){
    # Any number of whitespaces or * (if the view is started) followed by non-whitespace chars (the view tag) followed by whitespaces by non-whitespace chars (the view storage)  
    chomp($view);
    $view =~ /^[\s\*]*(\S*)\s*(.*)$/;
    
#    $views{"$2"}=$views{"$2"}."$region:$1,";
#    if (defined($views{"$2"})){
#      print "Duplicate: '";
#      print $views{"$2"}."'\n";
#    }
    $views{"$2"}=$views{"$2"}."$region:$1,";
    # print "$2 $1\n";s
  }
}
  
while (($stg,$tags) = each(%views)){
  print $stg."  ".$tags."\n";
}