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
use lib '/usr/lib/nagios/plugins';
use utils qw /%ERRORS/;
use Net::SNMP qw(:snmp :asn1 );
use Mysnmp qw ( snmp_session );
#use List::MoreUtils qw/ uniq /;
use Getopt::Long;
use JSON;

use constant AP_NAME => '.1.3.6.1.4.1.2011.6.139.2.6.1.1.7'; #HwApSysName
use constant AP_IP => '.1.3.6.1.4.1.2011.6.139.2.6.1.1.15'; #hwApIpAddress
use constant AP_MAC => '.1.3.6.1.4.1.2011.6.139.2.6.1.1.5'; #hwApMAC
use constant AP_SN => '.1.3.6.1.4.1.2011.6.139.2.6.1.1.6'; #hwApSn
use constant AP_TYPE => '.1.3.6.1.4.1.2011.6.139.2.6.1.1.2'; #hwApUsedType
use constant AP_STATE => '.1.3.6.1.4.1.2011.6.139.2.6.1.1.8'; #HwApRunState
use constant AP_REGION => '.1.3.6.1.4.1.2011.6.139.2.6.1.1.4'; #hwApUsedRegionIndex
use constant AP_USERCOUNT => '.1.3.6.1.4.1.2011.6.139.2.6.6.1.5'; #hwApOnlineUserNum
use constant AP_TEMP => '.1.3.6.1.4.1.2011.6.139.2.6.6.1.4'; #hwApTemperature

my %hwApRunStates = (
                         1=>'idle',
                         2=> 'autofind',
                         3=>'typeNotMatch',
                         4=>'fault',
                         5=>'config',
                         6=>' configFailed',
                         7=>'download',
                         8=>'normal',
                         9=>'committing',
                         10=>'commitFailed',
                          11=>'standby',
                          12=>'vermismatch',
                                );

my $wlanac;
my $community;
my $ip;
my $version;
my $region0=undef;
my $json_file="/var/lib/nagios3/wlanac.json";
my $warning;
my $warning_usercount=15;
my $warning_aptemp=60;
my $critical;
my $critical_usercount=25;
my $critical_aptemp=80;

sub HexParseMac {
        my $hmac=shift;
        $hmac=~s/0x//;
        $hmac=~s/^(\w\w)(\w\w)(\w\w)(\w\w)(\w\w)(\w\w)$/$1:$2:$3:$4:$5:$6/i;
        return lc($hmac);
}

sub get_nagios() {
	my $code=shift;
	return "" unless ($code);

	foreach my $k (keys(%ERRORS)) {
		if ($ERRORS{$k}==$code) {
			$k=~s/^(\w{4}).*/$1/;	
			return "(".$k."!!)"
		}
	}

	return 'NOTFOUND';
}

if (!GetOptions( 'hostname|H=s' => \$wlanac,
                 'community|C=s' => \$community,
		'region0|0' => \$region0,
		'warning|w=s' => \$warning,
		'critical|x=s' => \$critical,
                 'ip|I=s' => \$ip )) { 
	print "Wrong Params\n";
        exit(0);
}

if (!defined($ip)) {
   print "Options:
   --hostname|-H - Huawei AC6605 IP / name
   --community|-C - snmp community
   --region0|-0 - use check for Region=0 ( I'm using region=0 for newly added APs)
   --warning|-w - warning value for Connected Users to AP,The temperature of AP - ex. 15,60  ( default : 15, 60 )
   --critical|-x - critical value for Connected Users to AP,The temperature of AP - ex. 25,80 ( default : 25,80 )
   --ip|-I - Access-point IP
";
   exit(0);
}

if (defined($warning)) {
	my @warn=split(',',$warning);
	if (scalar(@warn)==2) {
	$warning_usercount=int($warn[0]) if ($warn[0]=~m/^\d+$/);
	$warning_aptemp=int($warn[1]) if ($warn[1]=~m/^\d+$/);
	}
}

if (defined($critical)) {
	my @crit=split(',',$critical);
	if (scalar(@crit)==2) {
	$critical_usercount=int($crit[0]) if ($crit[0]=~m/^\d+$/);
	$critical_aptemp=int($crit[1]) if ($crit[1]=~m/^\d+$/);
	}
}

if ($critical_usercount<$warning_usercount || $critical_aptemp<$warning_aptemp) {
		print STDOUT "Wrong args\n";
		exit($ERRORS{'UNKNOWN'});
}

if (!open(FILE,"<$json_file")) {
         print STDOUT "Error opening $json_file file \n";
         exit($ERRORS{'UNKNOWN'});
}
my $jsondata;

while (<FILE>) {
	$jsondata.=$_;
}
close(FILE);

if (!length($jsondata)) {
                print "$json_file is Empty\n";
                exit($ERRORS{'UNKNOWN'});
}

if ($ip!~m/^\d+\.\d+\.\d+.\d+$/) {
                print "Wrong ip-address $ip \n";
                exit($ERRORS{'UNKNOWN'});
}

my $json = JSON->new();
my $ap=$json->decode($jsondata);

if (!exists($ap->{$ip})) {
                print "Not FOUND in $json_file\n";
                exit($ERRORS{'UNKNOWN'});
}

my $apid=int($ap->{$ip}->{'apid'});

my $s=&snmp_session($wlanac,$community,'snmpv2',0);

if ((ref($s) eq "" )) {
	exit($ERRORS{'UNKNOWN'});
} 

my $res=$s->get_request( -varbindlist => [ AP_NAME.".".$apid,
						AP_IP.".".$apid,
						AP_MAC.".".$apid,
						AP_SN.".".$apid,
						AP_TYPE.".".$apid,
						AP_STATE.".".$apid,
						AP_REGION.".".$apid,
						AP_USERCOUNT.".".$apid,
						AP_TEMP.".".$apid,
                                                        ] );

my $err = $s->error();

if ($err ne "") {
                print STDOUT "Connection errror : $err\n";
                exit($ERRORS{'UNKNOWN'});
}

my $state='UNKNOWN';
if (defined($hwApRunStates{$res->{AP_STATE.".".$apid}})) {
	$state=$hwApRunStates{$res->{AP_STATE.".".$apid}};
}

#convert mac 
my $mac=&HexParseMac($res->{AP_MAC.".".$apid});
my %normal = ( 'users' => 0 , 'temp' => 0 );

if ($hwApRunStates{$res->{AP_STATE.".".$apid}} eq 'normal') {
		if ($res->{AP_USERCOUNT.".".$apid} > $warning_usercount) {
			$normal{'users'}=$ERRORS{'WARNING'};
			if ($res->{AP_USERCOUNT.".".$apid} > $critical_usercount) {
				$normal{'users'}=$ERRORS{'CRITICAL'};
			}
		}

		if ($res->{AP_TEMP.".".$apid} > $warning_aptemp ) {
				$normal{'temp'}=$ERRORS{'WARNING'};
				if ($res->{AP_TEMP.".".$apid} > $critical_aptemp) {
						$normal{'temp'}=$ERRORS{'CRITICAL'};
				}
		}
}

print STDOUT "AP: ".$res->{AP_NAME.".".$apid}.
	     " MAC: ".$mac.
	     " SN: ".$res->{AP_SN.".".$apid}.
	     " TYPE: ".$res->{AP_TYPE.".".$apid}.
	     " STATE: ".$state.
	     " REGION:".$res->{AP_REGION.".".$apid}.
	     " TEMP".&get_nagios($normal{'temp'}).":".$res->{AP_TEMP.".".$apid}.
	     " USERCOUNT".&get_nagios($normal{'temp'}).":".$res->{AP_USERCOUNT.".".$apid}.
	     " ";
 


if ($state eq "UNKNOWN") {
	print " -  Wrong STATE ".$res->{AP_STATE.".".$apid}." from AC6605\n";
	exit($ERRORS{'CRITICAL'});

}

if ($mac ne $ap->{$ip}->{'mac'}) {
	print " -  Wrong MAC JSON:".$ap->{$ip}->{'mac'}." AC6605: ".$mac."\n";
	exit($ERRORS{'WARNING'});
}


if ($res->{AP_REGION.".".$apid} == 0 && defined($region0)) {
	print " - Wrong region for AP \n";
	exit($ERRORS{'WARNING'});
}


if ($hwApRunStates{$res->{AP_STATE.".".$apid}} eq 'normal') {
		my $normal_exit=($normal{'users'} > $normal{'temp'})?$normal{'users'}:$normal{'temp'};

		if ($normal_exit != $ERRORS{'OK'}) { 
			print "\n";
			exit($normal_exit);
		}

		print " - OK\n";
		exit($ERRORS{'OK'});
}

if ($hwApRunStates{$res->{AP_STATE.".".$apid}} eq 'fault' ) {
	print " - CRITICAL\n";
	exit($ERRORS{'CRITICAL'});

}

#Rest AP State are WARNING
print " -  WARNING\n";
exit($ERRORS{'WARNING'});
