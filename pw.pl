#!/usr/bin/perl 

unless ( @ARGV ) {
    print <<USAGE;
    
Query the Programmable Web API to get data on APIs. 

USAGE
exit;
}

use Getopt::Long;
use LWP::Simple;

local $, = "\t";
local $\ = "\n";

#########################

my $api_key = '';
my $base_url = 'http://api.programmableweb.com/apis/'; # ?apikey=;
my $gmaps = 'google-maps';
my $params='?alt=json&apikey='.$api_key;
#  (@ARGV[0] || $gmaps)

#########################
# 468 pages as of 20130613
#########################

my $recs=1000;
until ( $recs < 20 ) { 
    my $url = join( '/', $base_url, '' ).$params.'&page='.($cc++); 
    my $test = get( $url );
    my $recs = scalar( grep {/'title'\:/} split/\n/,$test );
    # print $cc, $url, $recs;

    my @titles = grep {/\'title\'\:/} split/\n/,$test; 
    my @fees = grep {/\'fees\'\:/} split/\n/,$test; 

    foreach my $x ( 0..$#titles ) {
	
	my $ti="__NONE__";
	my $fx="__NONE__";
	if ( $titles[$x] =~ /\:\"(.+)\"/ ) {
	    $ti=$1;
	}
	if ( $fees[$x] =~ /\:\"(.+)\"/ ) {
	     $fx=$1;
	    }
	print $x, $ti, $fx; # , $fees[$x];
    }
}

