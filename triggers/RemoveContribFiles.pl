#
#
# RemoveContribFiles.pl
#
# On checkin and uncheckout remove associated ".contrib" files
# in "dynamic" views.
#
# Date:   April. 25, 2005, Roland Møller - IBM
############################################################
# History: xx/xx/xxxx : 
############################################################
#
# Install like this:
#
#  cleartool mktrtype -element -all -nc -postop uncheckout,checkin 
#  -exec "ratlperl \\Ol50707\NNTriggers\ReadyForProdTriggers\RemoveContribFiles.pl" \
#  RemoveContribFiles@{pvob_tag}
#
###############################
# Do only for "dynamic" views #
# and non-directory types.    #
###############################

#if ("$ENV{'CLEARCASE_VIEW_KIND'}" ne "dynamic")
#   { exit 0; }

# for debugging
# system ("clearprompt proceed -prompt \" ok \" -mask proceed -prefer_gui");

if ("$ENV{'CLEARCASE_ELTYPE'}" eq "directory")
   { exit 0; }

$ELEMENT = "$ENV{'CLEARCASE_PN'}";

@CONTRIBS = glob("$ELEMENT".".contrib*");

foreach $CONTRIB (@CONTRIBS)
{ 
   if ( ("$CONTRIB" =~ /\.contrib$/) or
        ("$CONTRIB" =~ /\.contrib\.[0-9]+$/ )) 
   {
      $ob_type=`cleartool desc -fmt %m $CONTRIB`;

      if ("$ob_type" eq "view private object")
      {
         ######################################################
         # Inform of and remove any associated .contrib files #
         ######################################################
         printf ("Removing \".contrib\" file \"$CONTRIB\"...\n");
         unlink ($CONTRIB);
      }
   }
}
exit 0;

