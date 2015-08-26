
print "Running at $ENV{COMPUTERNAME}\n";

my $viewname="$ENV{JOB_NAME}_view";
unless (qx(cleartool lsview -s $viewname)) {
 qx(cleartool mkview -tag $viewname -stgloc -auto);
}

foreach my $vobtag (sort qx(cleartool lsvob -s)){
 chomp $vobtag;
 my @result = ();
 qx(cleartool mount $vobtag);
 my $cmd ="forfiles /P \"m:\\$viewname$vobtag\\lost+found\" /C \"cmd /c echo \@fdate \@path\" 2>&1";
 @result = sort qx($cmd);
 if ($#result > 0) {
  print @result;
  print "\n";
 }
 qx(cleartool umount $vobtag);

}

