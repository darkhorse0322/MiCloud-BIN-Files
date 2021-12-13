#!/usr/bin/perl


use Fcntl 'LOCK_EX', 'LOCK_NB';

flock DATA, LOCK_EX | LOCK_NB  or exit;

sub print_log {

        (my $text)=@_;

        my ($second, $minute, $hour, $dayOfMonth, $month, $year, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime();
        my $line = sprintf ("%02d/%02d/%04d %02d:%02d:%02d %s\n",$dayOfMonth,$month+1,$year+1900,$hour,$minute,$second,$text);
        open FO2,">>/usr/local/tagmix/log/s3.log";
        print FO2 $line;
        close FO2;
}

$PARTNER="TAGMIX";
if (-f "/usr/local/tagmix/bin/bmat" || -f "/usr/local/tagmix/bin/BMAT") {
	$PARTNER="BMAT";
}
$DEVICEID=`hostname`;
chomp $DEVICEID;
$prefix=$PARTNER."/".$DEVICEID;

print_log ("Running s3.pl");
$dir="/usr/local/tagmix/sessions";
opendir DIR,$dir;
foreach $session (readdir DIR) {
	($session eq '.' || $session eq '..') && next;
	$file="$dir/$session";
	@stats=stat($file);
	$t=time();	
	$size=-s $file;
	if ($t-$stats[9] > 60) {
		$aws_size=0;
		$ret=`/usr/bin/aws s3 ls s3://tagmix-fitlet2-backups/$prefix/$session`;
		$ret=~/\d+\-\d+-\d+ \d+:\d+:\d+\s+(\d+)\s+/ && ($aws_size=$1);
		if ($aws_size==$size) {
			print_log ("Deleting $file");
			unlink ($file);
		}
		else {
			print_log ("Copying $file to S3");
			system ("/usr/bin/aws s3 cp $file s3://tagmix-fitlet2-backups/$prefix/$session");
		}
	}
}

__DATA__
This exists so flock() code above works.
DO NOT REMOVE THIS DATA SECTION.

