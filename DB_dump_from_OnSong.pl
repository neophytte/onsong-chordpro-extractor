#!/usr/bin/perl

use DBI;
use strict;

# ------ user configuration ---- #
my $database = "OnSong.sqlite3";
my $userid = "";
my $password = "";
my $OutDirectory = "./database_dump/";
my $DelDirectory = "./database_dump/deleted/";
# Logging
my $Log = "./logfile.txt";
my @TitleWordsToSkip = ["spoof\ ", "\ uke\ ", "medley"];

# ------ don't modify beneath this line -------- #

my $driver = "SQLite";
my $FileCount = my $NotPrintedCount = my $FileExistsCount = 0;
my $Lines;
my @Lines;

open(LOG, ">$Log") or die $!;

my $dsn = "DBI:$driver:dbname=$database";
my $dbh = DBI->connect($dsn, $userid, $password, { RaiseError => 1 })
   or die $DBI::errstr;
# print "Opened database successfully\n";

my $stmt = qq(select byline, title, filepath, deleted, content, key, transposedKey from Song;);
my $sth = $dbh->prepare( $stmt );
my $rv = $sth->execute() or die $DBI::errstr;

if($rv < 0) {
   print $DBI::errstr;
}

if (!-d $OutDirectory) {
  mkdir $OutDirectory;
  print "made $OutDirectory";
}

if (!-d $DelDirectory) {
  mkdir $DelDirectory;
  print "made $DelDirectory";
}

while(my @row = $sth->fetchrow_array()) {

  my $folder = "none";
  my $RawFilename = my $CompiledFilename = my $OutputString = "";
  my $Artist = my $Title = "";

  foreach (@TitleWordsToSkip) {
    if ($row[1] =~ m/$_/i) {
      print LOG "Skipping ".$row[1]." as it matches '".$_."'\n";
      next;
    }; # Ignore titles we don't want
  }

  if ($row[3] == "1") {
    $folder = $DelDirectory;
  } else {
    $folder = $OutDirectory;
  }

  if (length($row[4]) < 100) {
    # This is (probably) a dud file; probably a PDF or JPG that is not captured in the database
    print LOG "[ERR] content less than 100 for ".$CompiledFilename." (original file name was ".$row[2].")\n";
    $NotPrintedCount++;
    next;
  } else {
    # Here we can pull apart the details for the whole song ... 
    $FileCount++;

    @Lines = split(/(\n|\r)/, $row[4]);
    my $StartLength = length($row[4]);
    #print $row[4]."\n\n";
    $OutputString .= "[".$FileCount."] Lines: ".$#Lines." File length: ".$StartLength."";

    if ($row[5] ne $row[6]) {
      $OutputString .= " - key different (".$row[5].") to (".$row[6].")";
#      push @Lines, "{comment: key different (".$row[5].") to (".$row[6].")}\n";
      $row[4] .= "{comment: key different (".$row[5].") to (".$row[6].")}\n";
    }

    foreach(@Lines) {
      if ($_ =~ m/(\{t:|\{title:)/) {
        $Title = &GetContent($_);
        $OutputString .= " - Found title (".$Title.")";
        if ($Title ne $row[1]) {
          $OutputString .= ", different title ".$row[1];
        }
      }

      if ($_ =~ m/(\{artist:)/) {
        $Artist = &GetContent($_);
        $OutputString .= " - Found artist (".$Artist.")";
        if ($Artist ne $row[0]) {
          $OutputString .= ", different artist ".$row[0];
        }
      }

      if ($_ =~ m/\{c:\ \}/) {
        $row[4] =~ s/\{c:\ \}/\n/g; # swap out all empty comment lines ...
      }
    } # End of foreach @Lines
    
    if (!$Artist) { 
      $Artist = $row[0];
      $OutputString .= " - setting artist (".$row[0].")";
    }

    if (!$Title) { 
      $Title = $row[1]; 
      $OutputString .= " - setting title (".$row[1].")";
    }

    if (!$Artist) { 
      $Artist = "_check_artist";
      $OutputString .= " - can't find artist";
    }

    if (!$Title) { 
      $Title = "_check_title"; 
      $OutputString .= " - can't find title";
    }

    if ($Artist && $Title) {
      $CompiledFilename = $folder.&MakeOSFriendlyName($Artist)."-".&MakeOSFriendlyName($Title).".crd";
    } elsif ($row[0] && $row[1]) {
      $CompiledFilename = $folder.&MakeOSFriendlyName($row[0])."-".&MakeOSFriendlyName($row[1]).".crd";
    } else {
      $CompiledFilename = $folder.$row[2];
    }

    print LOG $OutputString." ".$CompiledFilename."\n";
  }

  if (!-e $CompiledFilename) {  
    open (FILE, ">$CompiledFilename") or warn "ERR".$!." on row ".$row[0]."\n";
    print FILE &SwapShortTagsForLongTags($row[4]);
    close FILE;
  } else {
    print "--> $CompiledFilename exists, appending ...\n";
    $FileExistsCount++;
    open (FILE, ">>$CompiledFilename") or die $!;
    print FILE "\n\n#-------------------#\n";
    print FILE "# Another version\n";
    print FILE "#-------------------#\n\n";
    print FILE &SwapShortTagsForLongTags($row[4]);
    close FILE;
  }
}

print "Operation done successfully - ".$FileCount." files, and ".$NotPrintedCount." not captured, ".$FileExistsCount." existing\n";
$dbh->disconnect();

sub SwapOutSpaces($) {
	my $x = shift;
	$x =~ s/(\ |\?|\.|\\|\/)/_/gi;
	return $x;
}

sub GetContent($) {
	my $x = shift;
	$x =~ s/(\{.*:|\})//gi; # Remove surrounding braces and just get content
	$x =~ s/(^\ )//gi; # Remove space at start
	$x =~ s/(\ \ \ \ \ $)//gi; # Remove 5 spaces at end
	$x =~ s/(\ \ \ \ $)//gi; # Remove 4 spaces at end
	$x =~ s/(\ \ \ $)//gi; # Remove 3 spaces at end
	$x =~ s/(\ $)//gi; # Remove space at end
	return $x;
}

sub MakeOSFriendlyName($) {
	my $x = shift;
  $x =~ s/(^the\ )//gi; # Remove leading 'the'
  $x =~ s/(\ and\ |\&)/_/gi;	# remove 'and'
	$x =~ s/(\ |\?|\.|\\|\/)/_/gi; 
  $x =~ s/(\{.*:|\}|\(|\)|\[|\]|,|\'|\"|\%|\@|\!|\#|\^|\*|\<|\>|\:|\;|\?|\+)//g; # Remove icky yucky stuff
  return $x;
}

sub SwapShortTagsForLongTags($) {
  my $x = shift;
	$x =~ s/^\{ns\}/\{new_song\}/; 
	$x =~ s/^\{t:/\{title:/;
	$x =~ s/^\{st:/\{subtitle:/;
	$x =~ s/^\{c:/\{comment:/;
	$x =~ s/^\{ci:/\{comment_italic:/;
	$x =~ s/^\{cb:/\{comment_box:/;
	$x =~ s/^\{col:/\{columns:/;
	$x =~ s/^\{soc\}/\{start_of_chorus\}/;
	$x =~ s/^\{eoc\}/\{end_of_chorus\}/;
	$x =~ s/^\{sot\}/\{start_of_tab\}/;
	$x =~ s/^\{eot\}/\{end_of_tab\}/;
	$x =~ s/^\{g\}/\{grid\}/;
	$x =~ s/^\{ng\}/\{no_grid\}/;
	$x =~ s/^\{np\}/\{new_page\}/;
	$x =~ s/^\{npp\}/\{new_physical_page\}/;
	$x =~ s/^\{colb\}/\{column_break\}/;
	return $x;
}