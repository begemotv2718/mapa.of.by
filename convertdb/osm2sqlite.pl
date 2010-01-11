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


package MySAXHandler;

use base qw(XML::SAX::Base);
use strict;
use DBI;
use Carp;
use Encode qw(encode decode);
use Data::Dumper;

my %instructions=(
                   tag => \&_process_tag,
                   nd  => \&_process_node_ref,
                   member => \&_process_member_ref,
                   node => \&_process_node,
                  );
sub _escape_value
{
  my $self=shift;
  my $value=shift;
  $value=~s/^'//s;
  $value=~s/'$//s;
  $value=~s/^"//s;
  $value=~s/"$//s;
  my $qvalue=$self->{dbh}->quote($value);
#  $value=encode('UTF-8',$value);
  return $qvalue;
}  

sub _process_node
{
  my ($self,$el,$parent,$count)=@_;
  my $lat=$el->{'Attributes'}->{'{}lat'}->{'Value'};
  my $lon=$el->{'Attributes'}->{'{}lon'}->{'Value'};
  my $id=$el->{'Attributes'}->{'{}id'}->{'Value'};
  return "INSERT INTO nodes VALUES($id,$lat,$lon)";
}

sub _process_tag
{
  my ($self,$el,$parent,$count)=@_;
  my $parent_name=$parent->{'LocalName'};
  my $parent_id=$parent->{'Attributes'}->{'{}id'}->{'Value'};
  my $type=$el->{'Attributes'}->{'{}k'}->{'Value'};
  my $qvalue=$self->_escape_value($el->{'Attributes'}->{'{}v'}->{'Value'});
  return "INSERT INTO tags VALUES (NULL, \'$type\', $qvalue, \'$parent_name\' ,$parent_id )"; 
}

sub _process_node_ref
{
  my ($self,$el,$parent,$count)=@_;
  my $parent_name=$parent->{'LocalName'};
  my $parent_id=$parent->{'Attributes'}->{'{}id'}->{'Value'};
  my $refid=$el->{'Attributes'}->{'{}ref'}->{'Value'};
  if($parent_name eq 'way')
  {
    return ("INSERT INTO waynoderef VALUES ( NULL, $parent_id, $refid, $count)");
  }
  elsif($parent_name eq 'relation')
  {
    return("INSERT INTO relrefs VALUES ( NULL, $parent_id, 'node', '', $refid,$count)");
  }  
  return;
}

sub _process_member_ref
{
  my ($self,$el,$parent,$count)=@_;
  my $parent_name=$parent->{'LocalName'};
  my $parent_id=$parent->{'Attributes'}->{'{}id'}->{'Value'};
  my $refid=$el->{'Attributes'}->{'{}ref'}->{'Value'};
  my $role=$el->{'Attributes'}->{'{}role'}->{'Value'};
  my $reftype=$el->{'Attributes'}->{'{}type'}->{'Value'};
  return "INSERT INTO relrefs VALUES (NULL, $parent_id, '$reftype', '$role', $refid, $count)";
}

sub _dbh_process
{
  my $self=shift;
  my $command=shift;

  my $dbh=$self->{'dbh'};
  if($command)
  {
    eval {$dbh->do($command);};
    croak($@,$command) if $@;
    $self->{'dbh_pending'}++;
  }
  if($self->{'dbh_pending'}>1000)
  { 
    $self->{'dbh_pending'}=0;
    $dbh->commit();
  }
}  

sub start_element
{
   my ($self, $el)=@_;
   my $stack=$self->{'stack'};
   my $count=$self->{'count'};
   push @$stack, $el;
   push @$count,{};

   my $name=$el->{'LocalName'};
   if($instructions{$name})
   {
     $count->[-2]->{$name}++;
     $self->_dbh_process($instructions{$name}($self,$el, $$stack[-2],$count->[-2]->{$name}));
   }
   else
   { 
     if($name ne 'way' && $name ne 'relation') {print Dumper $el;}
   }  
}

sub end_element
{ 
   my ($self,$el)=@_;
   my $stack=$self->{'stack'};
   pop @$stack;
   my $count=$self->{'count'};
   pop @$count;
}   

sub init_db
{
  my $self=shift;
  my %data=@_;
  my $tablefile=$data{'file'};
  $self->{'dbh'}=DBI->connect("dbi:SQLite:dbname=$tablefile","","",{ RaiseError => 1, AutoCommit => 0, unicode => 1} ) || croak("Error opening database $! $@");
  my $dbh=$self->{'dbh'};
  eval {
      local $dbh->{PrintError} = 0;
      $dbh->do("DROP TABLE IF EXISTS nodes");
      $dbh->do("DROP TABLE IF EXISTS tags");
      $dbh->do("DROP TABLE IF EXISTS waynoderef");
      $dbh->do("DROP TABLE IF EXISTS relrefs");
      $dbh->commit();
  };
  warn($@);
  eval {
    $dbh->do("CREATE TABLE nodes (id INTEGER PRIMARY KEY,  lat DOUBLE, lon DOUBLE)");
    $dbh->do("CREATE TABLE waynoderef  (id INTEGER PRIMARY KEY, wayid INTEGER, nodeid INTEGER, count INTEGER)");
    $dbh->do("CREATE INDEX idx_node_way ON waynoderef(nodeid)");
    $dbh->do("CREATE INDEX idx_way_way ON waynoderef(wayid)");
    $dbh->do("CREATE TABLE relrefs  (id INTEGER PRIMARY KEY, relid INTEGER, reftype VARCHAR, role VARCHAR, refid INTEGER, count INTEGER)");
    $dbh->do("CREATE INDEX idx_rel_ref ON relrefs(reftype, refid)");
    $dbh->do("CREATE INDEX idx_rel_rel ON relrefs(relid)");
    $dbh->do("CREATE TABLE tags  (id INTEGER PRIMARY KEY, name VARCHAR, value VARCHAR, reftype VARCHAR, refid INTEGER)");
    $dbh->do("CREATE INDEX idx_tags_names ON tags(name,value)");
    $dbh->do("CREATE INDEX idx_tags_ref ON tags(reftype,refid)");
    $dbh->commit();
  };
  croak($@) if $@;
}

sub new
{
  my $package=shift;
  my $self=$package->SUPER::new();
  $self->init_db(@_);
  $self->{'stack'}=[];
  $self->{'count'}=[];
  return $self;
}

sub DESTROY
{
  my $self=shift;
  $self->{'dbh'}->commit();
  $self->{'dbh'}->disconnect();
}

1;

package main;

use XML::SAX::ParserFactory;

if(scalar(@ARGV)!=2){
  die "Usage: osm2sqlite.pl <sqlite file> <osm file>";
}

my $handler=MySAXHandler->new(file=>$ARGV[0]) || die $!;
my $parser=XML::SAX::ParserFactory->parser(
                                            Handler=> $handler 
                                    );
$parser->parse_uri($ARGV[1]);

