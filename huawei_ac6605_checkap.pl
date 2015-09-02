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
use constant AP_TYPE => '.1.3.6.1.4.1.2011.6.139.2.6.1.1.2'; #hwApUsedType
use constant AP_STATE => '.1.3.6.1.4.1.2011.6.139.2.6.1.1.8'; #HwApRunState
use constant AP_REGION => '.1.3.6.1.4.1.2011.6.139.2.6.1.1.4'; #hwApUsedRegionIndex

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

sub HexParseMac {
        my $hmac=shift;
        $hmac=~s/0x//;
        $hmac=~s/^(\w\w)(\w\w)(\w\w)(\w\w)(\w\w)(\w\w)$/$1:$2:$3:$4:$5:$6/i;
        return lc($hmac);
}

if (!GetOptions( 'hostname|H=s' => \$wlanac,
                 'community|C=s' => \$community,
		'region0|0' => \$region0,
                 'ip|I=s' => \$ip )) { 
	print "Wrong Params\n";
        exit(0);
}

if (!defined($ip)) {
   print "Options:
   --hostname|-H - Huawei AC6605 IP / name
   --community|-C - snmp community
   --region0|-0 - use check for Region=0 ( I'm using region=0 for newly added APs)
   --ip|-I - Access-point IP
";
   exit(0);
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
						AP_TYPE.".".$apid,
						AP_STATE.".".$apid,
						AP_REGION.".".$apid,
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

print STDOUT "AP: ".$res->{AP_NAME.".".$apid}." MAC: ".$mac." TYPE: ".$res->{AP_TYPE.".".$apid}." STATE: ".$state." REGION:".$res->{AP_REGION.".".$apid}." ";


if ($state eq "UNKNOWN") {
	print " Wrong STATE ".$res->{AP_STATE.".".$apid}." from AC6605\n";
	exit($ERRORS{'CRITICAL'});

}

if ($mac ne $ap->{$ip}->{'mac'}) {
	print " Wrong MAC JSON:".$ap->{$ip}->{'mac'}." AC6605: ".$mac."\n";
	exit($ERRORS{'WARNING'});
}


if ($res->{AP_REGION.".".$apid} == 0 && defined($region0)) {
	print " - Wrong region for AP \n";
	exit($ERRORS{'WARNING'});
}

if ($hwApRunStates{$res->{AP_STATE.".".$apid}} eq 'normal') {
	print " -  OK\n";
	exit($ERRORS{'OK'});
}

if ($hwApRunStates{$res->{AP_STATE.".".$apid}} eq 'fault' ) {
	print " - CRITICAL\n";
	exit($ERRORS{'CRITICAL'});

}

#Rest AP State are WARNING
print " -  WARNING\n";
exit($ERRORS{'WARNING'});
