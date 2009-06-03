# Prevents developers from creating development streams in a project.
#
# Written by David Baird <david.baird@homemailNOSPAM.com>
#
# Install like this:
#
#   ct  mktrtype -ucmobject -all -preop mkstream \
#       -c 'No development streams for a project' \
#       -execunix 'perl {unix_trigger_path}/ucm_block_devstream.pl' \
#       -execwin  'perl {windows_trigger_path}\\ucm_block_devstream.pl' \
#       UCM_BLOCK_DEVSTREAM@{pvob_tag}
#
#   ct mkattype -vtype integer -default 1 -nc block_devstream@{pvob_tag}
#
# Turn on for project like this:
#
#   ct mkattr -default block_devstream project:{project_name}@{pvob_tag}
#

# values from trigger environment
my $project = $ENV{CLEARCASE_PROJECT};
my ($trigvob) = ($project =~ m{([^/\\]+)$});

# check value of blocking attribute and non-error exit if this project doesn't
# block developement streams
my $blocked = qx{cleartool describe -short -aattr block_devstream project:$project};
exit 0 if $blocked != 1;

# notify user
$project =~ s/\@(.+)//;
my $prompt= "Development streams are not permitted for the '$project' project.";

# notify the user of the error and stop the operation
if (length($ENV{CLEARCASE_CMDLINE}) != 0 and $ENV{ATRIA_WEB_GUI} == 0) {
    print STDERR "$trigvob trigger: Error: $prompt\n";
}
else {
    system qw{clearprompt proceed -mask proceed -type error -default proceed -prompt}, qq{"$prompt"};
}

# error exit
exit 1;

