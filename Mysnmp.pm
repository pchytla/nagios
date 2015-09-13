package Mysnmp;
use strict;
use Net::SNMP;
use Time::HiRes qw( gettimeofday tv_interval );

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT_OK = qw (
	snmp_session
	my_walk
);

our @EXPORT = qw(
);


sub snmp_session() {
        my $hostname=shift;
        my $community=shift;
        my $ver=shift;
        my $bulk=shift;

        my %args = ( '-version'    => $ver,
                     '-hostname'   => $hostname,
                     '-timeout'    => 5,
                     '-retries'    => 3,
                     '-community'   => $community );

        $args{'-nonblocking'} = 1 if ($bulk) ;

        my ( $snmpsession, $err ) =  Net::SNMP->session(
                                                %args,
                                                );

        if ($err) {
                        print STDERR "ERR: Connection error  $hostname : $err\n";
                        return "ERR_NORESP";
        }
        return $snmpsession;
}

sub my_walk() {
        my $s=shift;
        my $oid=shift;
        my $baseoid=$oid;
        my $r;
        my $t0=[gettimeofday()];
        my $res;
        outer: while ($res=$s->get_next_request(-varbindlist => [ $oid ])) {
                my @k=keys(%{$res});
                $oid=$k[0];
                last outer unless($oid =~ m/$baseoid/);
                $r->{$oid}=$res->{$oid};
        }
        if (!defined($res)) {
                        print STDERR $s->{'_hostname'}." : ERR: OID($baseoid) ".$s->error."\n";
        }

        print STDERR $s->{'_hostname'}. "(my_walk) OID ".$oid." elapsed time : ".sprintf("%f",tv_interval($t0))." sec\n";
        return $r;
}

1;
