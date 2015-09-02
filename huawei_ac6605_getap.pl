#!/usr/bin/perl -w
#
# Copyright (C) 2015 Piotr Chytla <pch@packetconsulting.pl>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
#
#
use strict;
use warnings;
use Net::SNMP;
use Mysnmp qw(snmp_session my_walk);
use Time::HiRes qw( gettimeofday tv_interval );
use Getopt::Long;
use JSON;

#OIDs
use constant AP_NAME => '.1.3.6.1.4.1.2011.6.139.2.6.1.1.7'; #HwApSysName
use constant AP_IP => '.1.3.6.1.4.1.2011.6.139.2.6.1.1.15'; #hwApIpAddress
use constant AP_MAC => '.1.3.6.1.4.1.2011.6.139.2.6.1.1.5'; #hwApMAC
use constant AP_REMOVE_TIME => 2592000; # after 1m of inactivity remove ap from .json file

my $fname="/var/lib/nagios3/wlanac.json";
my $wlanac;
my $community;
my $version;

sub removebase() {
        my $href=shift;
        my $base=shift;
        my %ret;
	return $href if(ref($href) eq "");

        foreach my $x (keys(%{$href})) {
                if ($x=~m/^$base\.(.+)$/) {
                        my $n=$1;
                        $ret{$n}=$href->{$x};
                }
        }

        return \%ret;
}

sub ParseMac {
        my $oid=shift;
        my @omap=split(/\./,$oid);
        return join(':',map(sprintf("%.02x",$_),@omap));
}

sub HexParseMac {
        my $hmac=shift;
        $hmac=~s/0x//;
        $hmac=~s/^(\w\w)(\w\w)(\w\w)(\w\w)(\w\w)(\w\w)$/$1:$2:$3:$4:$5:$6/i;
        return lc($hmac);
}

if (!GetOptions( 'hostname|H=s' => \$wlanac,
                 'community|C=s' => \$community,
		)) {
        print "Wrong Params\n";
        exit(0);
}

if (!defined($wlanac) || !defined($community)) {
   print "Opcje:
   --hostname|-H - Huawei AC6605 IP / name
   --community|-C - snmp community
";
   exit(0);
}


my $ap={};
my $jsondata="";
my $json=JSON->new();
if (open(FILE,"<$fname")) {
	while (<FILE>) {
		$jsondata.=$_;
	}
	$ap=$json->decode($jsondata) if (length($jsondata)>0);
	close(FILE);
} 

while (my ($k,$v) = each(%{$ap})) {
	next if (time()-$v->{'time'}<AP_REMOVE_TIME);
	print "IP: ".$k." MAC ".$v->{'mac'}." Removed - last seen ".time()-$v->{'time'}." sec\n";
}

my $s=&snmp_session($wlanac,$community,'snmpv2c',0);

if (ref($s) eq "") {
	print "Connection error:  $s\n";	
	exit(0);
}

my $apip=&removebase(&my_walk($s,AP_IP),AP_IP);
my $apname=&removebase(&my_walk($s,AP_NAME),AP_NAME);
my $apmac=&removebase(&my_walk($s,AP_MAC),AP_MAC);
$s->close();

if (ref($apip) eq "") {
		print "No data?\n";
		exit(1);
}

while (my ($apid,$ip) = each(%{$apip})) {
	my $mac=HexParseMac($apmac->{$apid});
	my $name=$apname->{$apid};
	#skip inactive AP 
	next if ($ip eq '255.255.255.255');

	if (exists($ap->{$ip})) {
			#checking existing AP
			#MAC
			if ($ap->{$ip}->{'mac'} ne $mac) {
				print "IP: ".$ip." MAC ".$ap->{$ip}." MAC changed ".$mac." ".$name."\n";
				$ap->{$ip}->{'mac'}=$mac;
				$ap->{$ip}->{'apid'}=$apid;
				$ap->{$ip}->{'time'}=time();
				$ap->{$ip}->{'name'}=$name;
				next;
			}
			#name 
			if ($ap->{$ip}->{'name'} ne $name) {
				print "IP: ".$ip." MAC ".$ap->{$ip}." AP-NAME changed ".$mac." ".$name."\n";
				$ap->{$ip}->{'mac'}=$mac;
				$ap->{$ip}->{'apid'}=$apid;
				$ap->{$ip}->{'time'}=time();
				$ap->{$ip}->{'name'}=$name;
				next;
			} 

                        print "IP: ".$ip." MAC ".$mac." OK ".$name."\n";
                        $ap->{$ip}->{'time'}=time();
                        next;

	}

	#add new AP	
	print "IP: ".$ip." MAC ".$mac." adding ".$name."\n";
	$ap->{$ip}->{'mac'}=$mac;
	$ap->{$ip}->{'apid'}=$apid;
	$ap->{$ip}->{'time'}=time();
	$ap->{$ip}->{'name'}=$name;
}

$json=JSON->new();
$json->pretty();
if (open(FILE,">$fname")) {
	print FILE $json->encode($ap);
	close(FILE);
}

exit(0);

