#!/usr/bin/perl 

#######################################################################
# pw.pl -- Query the Programmable Web API 
# Copyright (C) 2013  Devin Scannell
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#######################################################################

unless ( @ARGV ) {
    print <<USAGE;
    
    Query the Programmable Web API/Mashup APIs, parse the JSON
    and format as a tab delimited file. 

    $0 [api|mashup] [--password=s] [--gdrive] [--page=i]
    [--json_dump] [--json_local]

    --password : Provide MySQL/GDrive password if required 
    --gdrive : Use GDrive instead of local MySQL DB
    --page : PW API output page to download 
    --json_dump : write JSON formatted pages to local files
    --json_local : use local JSON files instead of API if available

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

my $tag = time;

##################################################
# vars 
##################################################

#my $target='apis';
my $dir_local = 'data';

my $mysql_db = 'api_keys';
my $mysql_table = 'lookup';
my $mysql_target = 'ProgrammableWeb';

my $json_local = undef;

my $query = 'google-maps';
my $password=undef;
my $page=0;

GetOptions(    
    'gdrive' => \$gdrive, 
    'password=s' => \$password, # get api_key from google drive insead of local DB 
    'debug=i' => \$debug,
    'json_dump' => \$json_dump,
    'json_local' => \$json_local,
    'page=i' => \$page,
#    'target=s' => \$target
    );

$target = ( $ARGV[0] =~ /^m/i ? 'mashups' : 'apis' );
my $api_base_url = 'http://api.programmableweb.com/'.$target.'/'; # ?apikey=;
my $api_params='?alt=json&apikey=';

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
print valid_json($json_test), ref($perl), @{ (values %{$perl})[0] } if $debug >=2;
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
dateModified
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

mkdir( $dir_local ) if $json_dump && ! -e $dir_local;

##################################################
# Access PW API and pull down records.
# Default is 20 records / page.
# As of June 14th 2013 there are 468 pages.
##################################################

my $pw_entries=1000;
open($fh, ">$target".".".$tag.".tab");
print {$fh} '#'.$keys[0],@keys[1..$#keys];

until ( $pw_entries < 20 ) { 
    $page++;
    my $json_file = $dir_local.'/'.join('.', $target, $page, 'json');
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
	$json_resp = get( $query_url );
	die unless $json_resp;
	print $json_resp if $debug >= 2;	
	
	if ( $json_dump ) {
	    open(OUT, ">".$json_file);
	    print OUT $json_resp;
	    close OUT;
	}
    }
    
    # clean up PW JSON 
    $json_clean = &make_compliant_JSON( $json_resp );
    
    # still get unclean JSON from PW sometimes so throw a panic...

    my $json_hash;
    eval { $json_hash = json_to_perl( $json_clean ); };

    my $fail_count;
    while ( $@ ) {
	warn $@;
	$@ =~ /line\s+(\d+)/;
	my $line = $1;
	my @lines = split/\n/, $json_clean;
	delete $lines[ $line-1 ];
	$json_clean=join("\n", @lines);
	eval { $json_hash = json_to_perl( $json_clean ); };
	print $page, $json_file, $query_url, ++$fail_count;
	print `head -$line $json_file | tail -1`;
    }
    
    #
    
    $pw_entries = scalar( @{ $json_hash->{'entries'} } );
    print $page, $json_file, $query_url, ($pw_entries || 0) if $debug;
    
    foreach my $pw_api_rec ( @{ $json_hash->{'entries'} } ) {
	my @values;
	foreach my $rec_key ( @keys ) {
	    my $pw_api_val = $pw_api_rec->{$rec_key};
	    if ( $rec_key eq 'dateModified' || $rec_key eq 'updated' ) {
	        die( "Regex: ".$pw_api_val ) unless $pw_api_val =~ /^(\d+)\-(\d+)\-(\d+)/;
		push @values, $1;
		my $days = (2013-$1)*365 + (6-$2)*30 + (21 - $3)*1;
		push @values, $days;
	    }
	    push @values, ( ref($pw_api_val) ? join(';', @{$pw_api_val}) : $pw_api_val );
	    $values[-1] =~ s/\n+/\s/g; # 
	}
	$values[3]="__NONE__" unless $values[3];
	print {$fh} @values ;
    }

    last if  $pw_entries < 20;
}

exit;

sub make_compliant_JSON {
    my $json_now = shift @_;

    $json_now =~ s/[\cM|\n]+/\n/g; # strip windows line ends

    ##########################################
    # 
    ##########################################

    # not sure why perl fails... 
    $json_now =~ s/\|/:/g;
    my $before='before.'.$tag;
    my $after='after.'.$tag;
    open(BEFORE, ">$before");
    print BEFORE $json_now;
    close BEFORE;
    system('sed s/\|/\:/g '."$before > $after");    
    open(AFTER, "$after");
    local $/ = "DEVIN_SAYS_STOP";
    my $json_new = <AFTER>;
    close AFTER;
    system("rm $before $after") unless $debug;

    ##########################################
    # 
    ##########################################

    # file start 
    die($json_new) unless $json_new =~ s/^q?pwfeed\s+\=\s+//;
    # json list behaviour 
    $json_new =~ s/\,(\s+\n\s+\]\,)/\1/mg; # this is an ugly fix!     
    # file end 
    $json_new =~ s/\}\,(\n\]\s+\})\;/\}\1/mg; # api file end if contains records 
    $json_new =~ s/^(\]\s+\})\;/\1/mg;  # api file end if no records 
    # other violations 
    die($json_new) unless $json_new =~ s/\'/\"/g;
    $json_new =~ s/\\\&apos\;//g;
    
    return $json_new;
}
