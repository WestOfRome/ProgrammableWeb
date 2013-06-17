#!/usr/bin/perl 

unless ( @ARGV ) {
    print <<USAGE;
    
Query the Programmable Web API to get data on APIs. 

USAGE
exit;
}

##################################################
# local modules 
##################################################

use Getopt::Long;
use LWP::Simple;
use DBI;
use JSON::Parse qw(json_to_perl json_file_to_perl valid_json);

local $, = "\t";
local $\ = "\n";

##################################################
# vars 
##################################################

my $api_base_url = 'http://api.programmableweb.com/apis/'; # ?apikey=;
my $api_params='?alt=json&apikey=';

my $mysql_db = 'api_keys';
my $mysql_table = 'lookup';
my $mysql_target = 'ProgrammableWeb';

my $json_local = undef;

my $query = 'google-maps';
my $password=undef;

GetOptions(    
    'gdrive' => \$gdrive, 
    'password=s' => \$password, # get api_key from google drive insead of local DB 
    'debug' => \$debug,
    'json_dump' => \$json_dump,
    'json_local' => \$json_local
    );

# test json_to_perl code 

my $json_test = <<JSONTEST;
{ "entries": 
      [
       {
	   "updated":"2013-06-15T06:40:03Z",
	   "title":"ProgrammableWeb "
       },
       {
	   "subtitle":"ProgrammableWeb "
       }
      ]
}
JSONTEST
    
my $perl = json_to_perl ( $json_test );
print $json_test;
print valid_json($json_test), ref($perl), @{ (values %{$perl})[0] };
die unless valid_json($json_test);

my @keys=qw(
title
summary
description
fees
serviceEndpoint
downloads
useCount
category
tags
protocols
dataFormats
authentication
ssl
limits
terms
company
);

##################################################
# Get API key from local (MySQL DB) library of API keys.
# Option to query from cloud based key library.  
##################################################

my $api_key;
if ( $gdrive ) {
    throw("WIP");
    
} else {
    my $dbh = DBI->connect('dbi:mysql:'.$mysql_db, $ENV{'USER'}, $password)
	or die "Connection Error: $DBI::errstr\n";
    
    my $mysql_query = " SELECT apikey FROM $mysql_table ".
	"WHERE api='$mysql_target'; ";
    
    my $prep = $dbh->prepare($mysql_query);
    $prep->execute();
    my $hashref = $prep->fetchrow_hashref();
    $api_key = $hashref->{'apikey'};    
    print $mysql_query, $api_key if $debug;    
}

mkdir('data') if $json_dump && ! -e 'data';

##################################################
# Access PW API and pull down records.
# Default is 20 records / page.
# As of June 14th 2013 there are 468 pages.
##################################################

my $page=0;
my $pw_entries=1000;
open($fh, ">pw.tab");
print {$fh} '#'.$keys[0],@keys[1..$#keys];

until ( $pw_entries < 20 ) { 
    $page++;
    my $json_file = "data/pw.".$page.".json";
    my $query_url = join( '/', $api_base_url, '' ).$api_params.$api_key.'&page='.$page; 
    print $page, $json_file, $query_url if $debug >=2;
    
    my $json_resp;
    if ( $json_local && -e $json_file ) {
	# $json_hash = json_file_to_perl( $json_file );    
	local $/ = "DEVIN_SAYS_STOP";
	open(my $fhin, $json_file);
	$json_resp = <$fhin>;
	close($fhin);
	
    } else {
	my $json_resp = get( $query_url );
	print $json_resp if $debug >= 2;	
	
	if ( $json_dump ) {
	    open(OUT, ">".$json_file);
	    print OUT $json_resp;
	    close OUT;
	}
    }
    
    # clean up PW JSON 
    $json_resp =~ s/^pwfeed\s+\=\s+//;    
    $json_resp =~ s/\'/\"/g;
    $json_resp =~ s/\,(\s+\n\s+\]\,)/\1/mg; # this is an ugly fix! 
    $json_resp =~ s/\}\,(\n\]\s+\})\;/\}\1/mg;
    $json_resp =~ s/\\\&apos\;//;
    # 

    my $json_hash = json_to_perl( $json_resp );    
    my $pw_entries = scalar( @{ $json_hash->{'entries'} } );
    print $page, $json_file, $query_url, $pw_entries if $debug;

    foreach my $pw_api_rec ( @{ $json_hash->{'entries'} } ) {
	my @values;
	foreach my $rec_key ( @keys ) {
	    my $pw_api_val = $pw_api_rec->{$rec_key};	    
	    push @values, ( ref($pw_api_val) ? join(';', @{$pw_api_val}) : $pw_api_val );
	    $values[-1] =~ s/\n+/\s/g; # 
	}
	$values[3]="__NONE__" unless $values[3];
	print {$fh} @values ;
    }
}

