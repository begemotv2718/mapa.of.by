#!/usr/bin/perl
use strict;
BEGIN{
  my $home=(getpwuid($>))[7];
  my @userdirs;
  foreach my $dir (@INC)
  {
    push @userdirs, "$home/perl/$dir" if -e "$home/perl/$dir";
  }
  push @INC, @userdirs;
}
use Encode qw(encode decode);
use DBI;

my @street_list=(
#    {street => "Радиальная", house => "40", location => [53.8926131666667,27.6471197777778]},
    {street => "Кульман", house => "13", location => [53.9225005185185,27.5760661851852]},
    {street => "Натуралистов", house => "10", location => [53.928351,27.618144]},
    {street => "Захарова", house => "36", location => [53.9054275882353,27.5790262941177]},
    {street => "Фрунзе", house => "7", location => [53.905691,27.5749624]},
    {street => "Янки Лучины", house => "62", location => [53.83909452,27.58537572]},
    {street => "Герасименко", house => "9", location => [53.8778424,27.690311]},
    {street => "Долгобродская", house => "38", location => [53.8856676,27.6188888]},
    {street => "Бобруйская", house => "3", location => [53.8932842222222,27.5433332222222]},
    {street => "Матусевича", house => "7", location => [53.9149624,27.4858206]},
    {street => "Мазурова", house => "20", location => [53.896319,27.4247908]},
    {street => "Шаранговича", house => "36", location => [53.8836642384615,27.4439212076923]},
    {street => "Курчатова", house => "6", location => [53.8378164,27.4712806]},
); 



my $dbh= DBI->connect("dbi:SQLite:dbname=$ARGV[0]","","",{ RaiseError => 1, AutoCommit => 0 }) || die $!;

foreach my $element(@street_list){
   my $street=$element->{'street'};
   my $house=$element->{'house'};
   my $street_code=join(" AND ", map { my $x=ucfirst(lc($_)); "street LIKE '%$x%'"; } split /\s+/,$street );
   my $query="SELECT lat, lon FROM geocode WHERE $street_code AND number='$house'";
   my @result=$dbh->selectrow_array($query);
   assert_close(\@result,$element->{'location'},$query);
}

$dbh->disconnect();

sub assert_close
{
 my ($arg1, $arg2,$log)=@_;
 die "Test failed! No result. Log=$log" unless (ref($arg1) eq 'ARRAY') && $$arg1[0];
 my $delta=delta_distance($arg1,$arg2);
 print "$log, delta=$delta\n";
 die "Test failed! Delta=$delta Logged=$log\n" unless $delta<30;
}

sub delta_distance
{
  my $ref1=shift;
  my $ref2=shift;
  my ($lat1, $lon1, $lat2, $lon2)= map {$_*3.1415926/180.0; } (@$ref1, @$ref2);
  my $delta=sqrt(($lat1-$lat2)**2+($lon1-$lon2)**2*cos(($lat1+$lat2)/2.0)**2)*6_356_752.3;
}
  
