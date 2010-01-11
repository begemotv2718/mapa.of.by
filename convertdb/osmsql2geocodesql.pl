#!/usr/bin/perl

#This lines is for hoster.by only to get access to SQLite module
BEGIN{
  my $home=(getpwuid($>))[7];
  my @userdirs;
  foreach my $dir (@INC)
  {
    push @userdirs, "$home/perl/$dir" if -e "$home/perl/$dir";
  }
  push @INC, @userdirs;
}
# End hoster.by specific code


package Math::Polygon::Calc;
#Polygon operations, fragment from the CPAN package


use List::Util    qw/min max/;
use Carp          qw/croak/;

sub polygon_bbox(@)
{
    ( min( map {$_->[0]} @_ )
    , min( map {$_->[1]} @_ )
    , max( map {$_->[0]} @_ )
    , max( map {$_->[1]} @_ )
    );
}

sub polygon_centroid(@)
{ 
    polygon_is_closed(@_)
       or croak "ERROR: polygon must be closed: begin==end";
    my $c_x    = 0;
    my $c_y    = 0;
    my $area   = 0;
    while(@_ >= 2)
    {   
        $c_x +=($_[0][0]+$_[1][0])*( $_[0][0]*$_[1][1] - $_[0][1]*$_[1][0]);
        $c_y +=($_[0][1]+$_[1][1])*( $_[0][0]*$_[1][1] - $_[0][1]*$_[1][0]);
        $area += $_[0][0]*$_[1][1] - $_[0][1]*$_[1][0];
        shift;
    }
    [$c_x/(3*$area),$c_y/(3*$area)];
}

sub polygon_area(@)
{   my $area    = 0;
    while(@_ >= 2)
    {   $area += $_[0][0]*$_[1][1] - $_[0][1]*$_[1][0];
        shift;
    }

    abs($area)/2;
}

sub polygon_is_closed(@)
{   @_ or croak "ERROR: empty polygon is neither closed nor open";

    my ($first, $last) = @_[0,-1];
    $first->[0]==$last->[0] && $first->[1]==$last->[1];
}

1;

package grouphouse;
#Almost dummy package to create sqlite aggregate function.
#Function conform to prototype for convenience
use strict;

our @call_prototype=qw(lat lon count);

sub new
{
  bless [], shift;
}

sub step
{
  my $self=shift;
  my %args;
  @args{@call_prototype}=@_;
  push @$self, \%args;
}

sub finalize
{
  my $self=shift;
  my @rows=map { [$_->{'lat'},$_->{'lon'},]; } sort {$a->{'count'} <=> $b->{'count'}} @$self;
  return join ", ", @{Math::Polygon::Calc::polygon_centroid(@rows)}; 
}

sub get_prototype
{
  return join(',',@call_prototype);
}

1;

package main;
use strict;
use Encode qw(encode decode);
use DBI;
use Data::Dumper;
use Time::HiRes qw(time);
my $maxlat=54.1;
my $minlat=53.75;
my $maxlon=27.85;
my $minlon=27.3;

my $dbh= DBI->connect("dbi:SQLite:dbname=$ARGV[0]","","",{ RaiseError => 1, AutoCommit => 0 });
$dbh->func("average_lonlat",3,'grouphouse','create_aggregate');

my $select_street="SELECT refid, value FROM tags WHERE name='addr:street' AND reftype='way'";
my $select_house="SELECT refid, value FROM tags WHERE name='addr:housenumber' AND reftype='way'";
my $query_houses="SELECT str.refid AS refid, str.value AS street, hs.value AS housenum FROM ($select_street) AS str, ($select_house) AS hs WHERE str.refid=hs.refid";
my $query_nodes="SELECT house.refid AS refid, w.nodeid AS id, w.count AS count, house.street AS street, house.housenum AS number FROM ($query_houses) AS house, waynoderef AS w WHERE w.wayid=house.refid ORDER BY w.count";
my $query_lonlat="SELECT * FROM ($query_nodes) NATURAL JOIN nodes";
my $query_restrict="SELECT * FROM ($query_lonlat) AS allhouses WHERE (allhouses.lat<$maxlat) AND (allhouses.lat>$minlat) AND (allhouses.lon<$maxlon) AND (allhouses.lon>$minlon) ORDER BY refid, count";
my $query_aggregate="SELECT refid, street, number, average_lonlat(".grouphouse::get_prototype().") FROM ($query_restrict) GROUP BY refid;";
{
  my $start=time;
  my $list=$dbh->selectall_arrayref($query_aggregate);
  my $end=time;
  print "Query took ".($end-$start)."\n";
  print scalar(@$list);
  $dbh->disconnect();
 


  my $dbh2=DBI->connect("dbi:SQLite:dbname=$ARGV[1]","","",{ RaiseError => 1, AutoCommit => 0 });
  eval {
    local $dbh2->{PrintError} = 0;
    $dbh2->do("DROP TABLE geocode");
  };

  eval {
    $dbh2->do("CREATE TABLE geocode (id INTEGER PRIMARY KEY,street VARCHAR, number VARCHAR, lat DOUBLE, lon DOUBLE)");
    $dbh2->commit();
  };
  die "$@" if $@;
  my $i=0;
  foreach my $element(@$list){
    my $street=$element->[1];
    print $street if $street=~/'/;
    my $number=$element->[2];
    my ($lat, $lon)= split /|/, $element->[3];
    print "INSERT INTO geocode VALUES( NULL, \'$street\', \'$number\', $element->[3])"."\n" unless $element->[3];
    $dbh2->do("INSERT INTO geocode VALUES( NULL, \'$street\', \'$number\', $element->[3])") if $element->[3];
    if($i%1000==0) {$dbh2->commit();}
    $i++;
  }
  $dbh2->commit();
  $dbh2->disconnect(); 
}

