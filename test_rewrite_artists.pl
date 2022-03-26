#!/usr/bin/perl

use DBI;
use Data::Dumper;
my $database = "OnSong.sqlite3";
my $userid = "";
my $password = "";

my $driver = "SQLite";
my $dsn = "DBI:$driver:dbname=$database";
my $dbh = DBI->connect($dsn, $userid, $password, { RaiseError => 1 })
   or die $DBI::errstr;

sub BylineAlpha($) {
  my $x = shift;
  my $output = uc(substr $x, 0,1); # get the sort key
  if ($output !~ /[A-Z]/) {
    $output = "#"; # OnSong misses 'null's - I've included them
  }
  return $output;
}

#open(ALA, ">$Alla") or die $!;
#print ALA &HTMLHeader("All songs by artist");
my $A2 = $dbh->prepare( qq(select ID, title, byline, deleted, created, modified, lastPlayedOn, viewed from Song;) ); # where byline like 'Richard%'
my $rv9 = $A2->execute() or die $DBI::errstr;
# $current = "  ";
# my $display;
my $dataCount = 0;
my @data;
my $bylineAlpha;
while(my @row = $A2->fetchrow_array()) {
  $dataCount++;
  if ($row[2] =~ /\;/g) { # check if there are multiple artists.
    # print ".";
    #my $count = $row[2] =~ tr/\;//; # count how many artists
    # print $count+1;
    my @artists = split(';',$row[2]);
    # print "-".scalar @artists;
    foreach ( @artists ) { # for each entry in artists
    	# print "\$_ is $_";
      $_=~ s/^\s+|\s+$//g;
      $bylineAlpha = BylineAlpha($_);
      push @data, {
        'ID' => $row[0],
        'title' => $row[1],
        'bylineAlpha' => $bylineAlpha,
        'byline' => $_,
        'deleted' => $row[3],
        'created' => $row[4],
        'modified' => $row[5],
        'lastPlayedOn' => $row[6],
        'viewed' => $row[7]
      } # push all data back, but with the different artists
	  }
  } else {
    $bylineAlpha = BylineAlpha($row[2]);
    push @data, {
      'ID' => $row[0],
      'title' => $row[1],
      'bylineAlpha' => $bylineAlpha,
      'byline' => $row[2],
      'deleted' => $row[3],
      'created' => $row[4],
      'modified' => $row[5],
      'lastPlayedOn' => $row[6],
      'viewed' => $row[7]
    }
  }
}

my $size = @data;
#print "Size:  is $size\n";

# print Dumper(@data);

print "-------------------------------------------------------------------------------------------------------------------------------------------------\n";

my @sortedData = sort {
  $a->{'bylineAlpha'} cmp $b->{'bylineAlpha'} || # sort by alpha
  $a->{'byline'} cmp $b->{'byline'} || # then sort by artists name
  $a->{'title'} cmp $b->{'title'} # then sort by song title
} @data;

# print Dumper(@sorted_data);

foreach (@sortedData) {
  # print "-->".$sortedData{'ID'}."\n";
  # print "2->".$sortedData{ID}."\n";
  print "--> ".$_->{'bylineAlpha'}." - ".$_->{'byline'}." - ".$_->{'title'}."\n";
}
print "Size:  is $size from $dataCount rows\n";
