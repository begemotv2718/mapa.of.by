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

my %args=%{parse_args($ENV{'QUERY_STRING'})};
print "Content-type: text/plain; charset=utf-8\n\n";

my $dbh= DBI->connect("dbi:SQLite:dbname=build.db","","",{ RaiseError => 1, AutoCommit => 0 });
my $street=$args{'street'};
my $house=$args{'house'};
$street=~s/[A-Za-z]+//g; #Против кулхацкеров
$house=~s/[H-Zh-z]+//g; 
$house=~s/\s*//g;
$street=~s/\w+[.]\s*//g; #Избавляемся от ул., просп. etc
$street=~s/^\s*//;
$street=~s/\s*$//;
my $street_code=join(" AND ", map { my $x=ucfirst(lc($_)); "street LIKE '%$x%'"; } split /\s+/,$street );
if($house){
   my @list=$dbh->selectrow_array("SELECT lat, lon FROM geocode WHERE $street_code AND number='$house'");
   if($list[0]){
      print $list[0],",",$list[1],"\n";
   }else{
      print "Not found\n";
   }
}else{
   my @list=$dbh->selectrow_array("SELECT lat, lon FROM geocode WHERE $street_code");
   if($list[0]){
      print $list[0],",",$list[1],"\n";
   }else{
       print "Not found\n";
   }
}
$dbh->disconnect();


sub parse_args
{
  my $arg_list=shift;
  my %args;
  map { 
        my ($key, $val)=split /=/, $_;
        if($val=~/%/){
           #Normal browsers
           $val=~s/%([A-Fa-f0-9]{2,2})/chr(hex($1))/eg;
           $val=decode('UTF-8',$val); 
        }else{#if($val=~/\\x/){
           #ie
           local *F;
           open(F,'>>/tmp/request.log');
           print F $val;
           close F;
           $val=~s/[\\]{1,}x([A-Fa-f0-9]{2,2})/chr(hex($1))/eg;
           $val=decode('cp1251',$val);
        }
        $args{$key}=$val; 
      } split /&/, $arg_list;
  return \%args;
}
