#!/usr/local/bin/perl

no strict 'refs';
#    This is the mail text template file for using the mail capabilities of view_q
#    Do not modify this file, it will be overwritten when you update the distribution
#    next time.
#    Instead make a copy of this file, and customize it for your needs.

#    Do NOT change the text strings the  pattern ===UPPERCASE===, they are used
#    to find substitutions later
#

$_maildomain = '';	# Example @ibm.com. Use this if the user's email is equal to login with this value appeneded.
# for instance user joed has email joed@ibm.com. If you leave this blank, we will try to determine the email by using dsquery
$_smtpserver = 'localhost'; # SMTP server name optionally with port to then the format is "server:port"
$_fromadress = 'jbrejner@praqma.net'; # CC administrator email
$_ccadmin_name = 'your Clearcase Administrator';
$_graceperiod = 7; # How many days before quarantine

$_warnsubject = "You have unused ClearCase views, that will be removed in $_graceperiod days";

($_warnofquarantine = <<ENDWARNQ) =~ s/^\s+//gm;

	Hello ===USER===.

	This an automated mail from the Accellerated ClearCase view house-keeping procedure. You can not reply to this mail.

	Below is a list of views that have been registered to you, but you have not used since ===CUTDATE=== so we will remove them automatically in a couple of days.

	If you do nothing - the view(s) will be quaratined for a period, then it will removed for good.
	While in quarantine, it will not be visible or usable, but we can get it back.
	If you want to keep the view(s); use it. Either run a view update or do a checkout, followed by a undo checkout.

	Some views are only used for reading or are old build-views you want to keep. That kind of views can be flagged by $_ccadmin_name so this house keeping job will ignore it in future runs.

	You will not get further notifications about the view removal, but please feel free to contact $_ccadmin_name.

	===VIEWLIST===

ENDWARNQ

$_adminwarnsubj = "View_q found unaccessed views";

($_warnsummary = <<ENDSUMWARN)  =~ s/^\s+//gm;

	View_q found the following views haven't been accessed since ===CUTDATE===, and the
	owners have been notified.

	===NOEMAIL===

	Owner\tView

	===WARNVIEWS===

ENDSUMWARN

$_adminsubj = "View_q have processed views:";

($_actionsummary = <<ENDSUMRMV)  =~ s/^\s+//gm;

	View_q have ===ACTION=== the following views:

	Owner\tView

	===WARNVIEWS===

ENDSUMRMV

$_adminnotifyignored = "View_Q: Ignored views report";
($_notifyignored = <<NOTIFYIGNORED)  =~ s/^\s+//gm;

Hello Administrator.
View_Q has the following views in ignored state

===IGNOREDVIEWS===

NOTIFYIGNORED



1;

