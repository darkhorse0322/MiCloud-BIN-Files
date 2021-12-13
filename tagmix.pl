#!/usr/bin/perl

use JSON;
use POSIX qw(strftime);
use Data::Dumper;
use Fcntl 'LOCK_EX', 'LOCK_NB';

if ($ARGV[0] eq "-v") {
	print "tagmix.pl v1.3\n";
	exit;
}

flock DATA, LOCK_EX | LOCK_NB  or exit;

if (-f "/usr/local/tagmix/bin/bmat" || -f "/usr/local/tagmix/bin/BMAT") {
	$PARTNER="BMAT";
}
else {
	$PARTNER="TAGMIX";
}
$DEVICEID=`hostname`;
chomp $DEVICEID;

print_log ("Partner $PARTNER Device Id $DEVICEID");

# Create links to ffmpeg (just in case)
system ("ln -s `which ffmpeg` /usr/local/tagmix/bin/ffmpegTagmix 2>/dev/null");
system ("ln -s `which ffmpeg` /usr/local/tagmix/bin/ffmpegRecord 2>/dev/null");

# Create folders (just in case)
system ("mkdir /usr/local/tagmix/sessions/ 2>/dev/null");
system ("mkdir /usr/local/tagmix/log/ 2>/dev/null");

# Just in case an ffmpeg process is still running
system ("killall ffmpegTagmix 2>/dev/null");
system ("killall ffmpegRecord 2>/dev/null");

$PIDA=`/bin/pidof aplay`;
chomp $PIDA;
if ($PIDA eq "") {
	print_log ("Starting passthrough");
	system ("(/usr/bin/arecord -f cd -D plug:dsnoop | /usr/bin/aplay) &");
}

my %endpoint_info;
my $ID=0;
my $stopTime=0;

$SIG{INT}  = \&signal_handler;
$SIG{TERM} = \&signal_handler;

sub signal_handler {
	close FI;
	system ("/usr/bin/killall ffmpegTagmix 2>/dev/null");
	system ("/usr/bin/killall ffmpegRecord 2>/dev/null");
	%endpoint_info=showEndPoint($PARTNER."::".$DEVICEID,0,0);
	$ID=$endpoint_info{'id'};
	if ($ID) {
		$date = strftime '%Y-%m-%d %H:%M:%S', localtime;
		print_log ("Deleting EndPoint");
		if (deleteEndPoint($ID)) {
			$ID=0;
		}	
	}
    	die "Caught a signal $!\n";
}

sub print_log {

        (my $text)=@_;

        my ($second, $minute, $hour, $dayOfMonth, $month, $year, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime();
        my $line = sprintf ("%02d/%02d/%04d %02d:%02d:%02d %s\n",$dayOfMonth,$month+1,$year+1900,$hour,$minute,$second,$text);
        open FO2,">>/usr/local/tagmix/log/tagmix.log";
        print FO2 $line;
        close FO2;
}

sub createEndPoint {

	($session,$artist,$venue,$promoter,$campaign,$event_id,$partner_deviceId) = @_;

	my %data=();
	my $json = new JSON;

	$cmd = "curl -s -X POST -H \"Content-Type: application/json\" -d '{\"session name\":\"$session\",\"artist\":\"$artist\",\"venue\":\"$venue\",\"promoter\":\"$promoter\",\"campaign\":\"$campaign\",\"description\":\"\",\"event_info_id\": $event_id,\"partner_deviceId\": \"$partner_deviceId\"}' \"http://audio-api.tagmix.me/TagMix/Endpoints\"";
	$str=`$cmd`;

	$date = strftime '%Y-%m-%d %H:%M:%S', localtime;
	print_log ("Create: $str");
	%data = eval {
		my $json_text = $json->allow_nonref->relaxed->decode($str);

		if ($json_text->{'success'}) {
			return %{$json_text->{'data'}};
		}
	};
	return %data;
}

sub deleteEndPoint {

	($id) = @_;

	my %data=();
	my $json = new JSON;

	$cmd = "curl -s -X DELETE \"http://audio-api.tagmix.me/TagMix/Endpoints/$id\"";
	$str=`$cmd`;

	$date = strftime '%Y-%m-%d %H:%M:%S', localtime;
	print_log ("Delete: $str");
	$ret=0;
	$ret=eval {
		my $json_text = $json->allow_nonref->relaxed->decode($str);

		if ($json_text->{'success'}) {
			return 1;
		}
	};
	return $ret;
}

sub showEndPoint {

	(my $id, my $music, my $PID) = @_;

	my %data=();
	my $json = new JSON;

	my $streaming=($PID ne "")?1:0;
	$cmd = "curl -s \"http://audio-api.tagmix.me/TagMix/Endpoints/$id?music=$music&streaming=$streaming\"";
	$str=`$cmd`;

	$date = strftime '%Y-%m-%d %H:%M:%S', localtime;
	print_log ("Show: $str");
	%data = eval {
		my $json_text = $json->allow_nonref->relaxed->decode($str);

		if ($json_text->{'success'}) {
			return (%{$json_text->{'data'}});
		}
	};
	return %data;
}

$inMusic=0;
$lastCheck=time();
while (1) {
	$last=128;
	$n=-50;
	$abs=0;
	$lastT=time();
	$repeats=0;
	open FI,"arecord -f U8 -D plug:dsnoop 2>/dev/null|";
	binmode FI;
	while ($lastCheck+60>=time()) {
		read FI,$buffer,1;
		$n++;
		($n<=0) && (next);
		my $c = unpack "C", $buffer;
		if (abs($last-$c)==1) {
			# During silence (better always), small variations = no variation
			$last=$c;
		}
		$abs+=abs($last-$c);
		$t=time();
		if ($t != $lastT) {
			# Initial state
			($inMusic==-1) && ($inMusic=(($abs/$n<0.2)?0:1));

			# In music
			if ($inMusic) {
				#print_log ("Music abs $abs repeats $repeats");
				($abs/$n<0.2)?($repeats++):($repeats=0);
				if ($repeats >= 50) {
					$inMusic=0;
					$repeats=0;
					last;
				}
			}

			# In silence
			else {
		#		print_log ("Silence");
				($abs/$n>0.5)?($repeats++):($repeats=0);
				if ($repeats >= 20 && (time() >= ($stopTime + 60))) {
					$inMusic=1;
					$repeats=0;
					last;
				}
			}

			$n=$abs=0;
			$lastT=$t;
		}
		$last=$c;
	}
	close FI;

	$lastCheck=time();
	$PIDA=`/bin/pidof aplay`;
	chomp $PIDA;
	if ($PIDA eq "") {
		print_log ("Starting passthrough");
		system ("(/usr/bin/arecord -f cd -D plug:dsnoop | /usr/bin/aplay) &");
	}
	$PID=`/bin/pidof ffmpegTagmix`;
	$PIDR=`/bin/pidof ffmpegRecord`;
	chomp $PID;
	chomp $PIDR;
	$date = strftime '%Y-%m-%d %H:%M:%S', localtime;
	print_log ("inMusic $inMusic PIDs $PID $PIDR time ".time()." stopTime $stopTime");
	if ($inMusic) {
		print_log ("Check Endpoint");
		%endpoint_info=showEndPoint($PARTNER."::".$DEVICEID,$inMusic,$PID);
		$ID=$endpoint_info{'id'};
		print_log ("ID: $ID");
		if (!$ID) {
			print_log ("Create Endpoint");
			$session_name="$PARTNER $DEVICEID $date";
			%endpoint_info = createEndPoint ($session_name,"","","","",0,$PARTNER."::".$DEVICEID);
			$ID=$endpoint_info{'id'};
		}
		if (($ID eq ""||$ID==0) && $PID ne "") {
			system ("/usr/bin/killall ffmpegTagmix 2>/dev/null");
			#system ("/usr/bin/killall ffmpegRecord 2>/dev/null");
		}
		if ($ID && $PID eq "") {
			$user="source";
			$password=$endpoint_info{'password'};
			$host=$endpoint_info{'host'};
			$port=8000;
			$mountpoint=$endpoint_info{'mountpoint'};
			print_log ("Launching ffmpeg: $user:$password $host:$port $mountpoint");
			system ("(arecord -f cd -D plug:dsnoop | /usr/local/tagmix/bin/ffmpegTagmix -re -vn -i - -acodec libmp3lame -ab 128k -ac 2 -ar 44100 -f mp3 \"icecast://$user:$password\@$host:$port/$mountpoint\") >/usr/local/tagmix/log/ffmpeg.log 2>&1 &");

		}
		if ($PIDR eq "") {
			$file="/usr/local/tagmix/sessions/".time().".mp3";
			print_log ("Starting recording: $file");
			system ("(arecord -f cd -D plug:dsnoop | /usr/local/tagmix/bin/ffmpegRecord -re -vn -i - -acodec libmp3lame -ab 128k -ac 2 -ar 44100 -f mp3 -y $file) >/usr/local/tagmix/log/record.log 2>&1 &");

		}
	}
	if (!$inMusic) {
		if ($PID ne "") {
			print_log ("Killing ffmpegTagmix");
			system ("/usr/bin/killall ffmpegTagmix 2>/dev/null");
		}
		if ($PIDR ne "") {
			print_log ("Killing ffmpegRecord");
			system ("/usr/bin/killall ffmpegRecord 2>/dev/null");
		}
		%endpoint_info=showEndPoint($PARTNER."::".$DEVICEID,$inMusic,$PID);
		$ID=$endpoint_info{'id'};
		if ($ID) {
			print_log ("Deleting EndPoint");
			if (deleteEndPoint($ID)) {
				$ID=0;
			}	
				$stopTime=time();
		}
	}
}

__DATA__
This exists so flock() code above works.
DO NOT REMOVE THIS DATA SECTION.

