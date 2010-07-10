#!/usr/local/bin/perl

no strict 'refs';
#    This is the mail text template file for using the mail capabilities of view_q
#    Do not modify this file, it will be overwritten when you update the distribution
#    next time.
#    Instead make a copy of this file, and customize it for your needs.

#    Do NOT change the text strings the  pattern ===UPPERCASE===, the are used
#    to find substitutions later
#



$_smtpserver = 'localhost'; # SMTP server name
$_fromadress = 'jbrejner@praqma.net'; # CC administrator email
$_ccadmin_name = 'your Clearcase Administrator';
$_graceperiod = 7; # How many days before quarantine

$_warnsubject = "You have unused ClearCase views, that will be removed in $_graceperiod days";

$_warnofquarantine = <<ENDWARNQ;

Hello ===USER===.

This an automated mail from the Accellerated ClearCase view house-keeping ===¤===
procedure.
Below is a list of views that have been registered to you, but you have not ===¤===
used since ===CUTDATE=== so we will remove them automatically in a couple of days.

If you do nothing, the view(s) will be quaratined for $_graceperiod days, then ===*===
it will removed for good.
While in quarantine, it will not be visible or usable, but we can get it back.
If you want to keep the view(s); use them, either run a view update or do a ===*===
checkout, followed by a undo checkout.

Some views are only used for reading or are old build-views you want to keep.
These views can be flagged by $_ccadmin_name so this house keeping job will ignore ===¤===
it in future runs.

You will get now further notifications, and you can not reply to this mail, but ===*===
feel free to contact $_ccadmin_name.

===VIEWLIST===

ENDWARNQ

$_adminwarnsubj = "View_q found unaccessed views";

$_warnsummary = <<ENDSUMWARN;

View_q found the following views haven't been accessed since ===CUTDATE===, and the
owners have been notified.

===NOEMAIL===

Owner\tView

===WARNVIEWS===

ENDSUMWARN

$_adminsubj = "View_q have processed views:";

$_actionsummary = <<ENDSUMRMV;

View_q have ===ACTION=== the following views:

Owner\tView

===WARNVIEWS===

ENDSUMRMV


1;

