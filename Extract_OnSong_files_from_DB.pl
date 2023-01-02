#!/usr/bin/perl
use DBI;
use strict;
use Cwd qw(cwd getcwd);
use Archive::Zip;
my @currDir = split('/',cwd);
my $zip = Archive::Zip->new();

# Compiler for Windows: (TODO: test this!)
# perl -MCPAN -e "install PAR::Packer" 
# pp -o Extract_OnSong_files_from_SQLite_DB.exe Extract_OnSong_files_from_SQLite_DB.pl 

sub DisplayHelp {
  print "$0 - help is coming sometime ... \n";
}

my $coreDirectory;
my $database;
my $printFile = 0;
my $noCreateFiles = 0;

if (@ARGV) {
  foreach my $argNum (0 .. $#ARGV) {
    if ($argNum == "-f") {
      $printFile = 1;
    }
    if ($argNum == "--nocreate") {
      $noCreateFiles = 1;
    }
    if ($argNum == "-?") {
      &DisplayHelp;
      exit;
    }
  }
  # needs to contain no spaces
  # TODO: add flag for using different directory to the current
  # $coreDirectory = $ARGV[0]."-database_dump/";
  # $database = $ARGV[0]."/OnSong.sqlite3";
} 
$coreDirectory = "./$currDir[-1]-database_dump/";
$database = "OnSong.sqlite3";
print "Using directory: $coreDirectory\n";

# ------ configuration ---- #
my $userid = ""; # DB user
my $password = ""; # DB pass
my $outDirectory = $coreDirectory."updated/";
my $delDirectory = $coreDirectory."deleted-files/";
my $nonDelDirectory = $coreDirectory."non-modified/";
my $noFilePath = $coreDirectory."file-path-issue/";
my $noFilePathDel = $noFilePath."deleted/";
my $reportPath = $coreDirectory."html-reports/";
my $createdFilePath = $coreDirectory."crd-to-html-files/";
my $DelCmd = $coreDirectory."delete-files.sh";
# Logging
my $logFile = $coreDirectory."_logfile.txt";
my $favourites = $reportPath."my-favourite.html";
my $topics = $reportPath."all-topics.html";
my $version = $reportPath."onsong-version.html";
my $chordFile = $reportPath."chords.html";
my $allSongsByTitle = $reportPath."all-songs-by-title.html";
my $allDeletedSongs = $reportPath."deleted-songs.html";
my $allSongsByArtist = $reportPath."all-songs-by-artist.html";
my $books = $reportPath."my-books.html";
my $setLists = $reportPath."my-sets.html";
my $mediaAsSongs = $reportPath."images-as-songs.html";
my $activeSongsByTitle = $reportPath."active-songs-by-title.html";

# ------ initialize -------- #

my $matchFileSize;
my $notMatchingFileSize;
my $PDFcount;
my $nonExist;
my $countDeleted;
my $countNonDeleted;
my $allFiles;
my $notMatchingFileSizeDeleted;
my $unknownCounter = 0;

# ------ subs -------- #

sub FormatSeconds($) { # expect seconds as INT, return human readable time string
    my $tsecs = shift;
    use integer;
    my $secs  = $tsecs % 60; 
    my $tmins = $tsecs / 60;
    my $mins  = $tmins % 60; 
    my $thrs  = $tmins / 60;
    my $hrs   = $thrs  % 24;
    my $days  = $thrs  / 24;
    my $age = "";
    if (($secs < 10) && $mins) { $secs = "0".$secs; } # add leading zero
    if (($mins < 10) && $hrs) { $mins = "0".$mins; } # add leading zero
    $age .= $days . "d " if $days || $age;
    $age .= $hrs  . "h " if $hrs  || $age;
    $age .= $mins . "m " if $mins || $age;
    $age .= $secs . "s " if $secs || $age;
    $age =~ s/ $//;
    return $age;
}

sub FormatDateTime($) { # expect date in unix format, return date and time as string (eg 2020-10-01 09:35:25)
  my $x = shift;
  if ($x) {
    my ($S, $M, $H, $d, $m, $Y) = localtime($x);
    $m += 1;
    $Y += 1900;
    my $dt = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $Y, $m, $d, $H, $M, $S);
    return $dt;
  } else {
    return;
  }
}

sub FormatDate($) { # expect date in unix format, return date as string (eg 1st Oct 2020)
  my $x = shift;
  my $suffix = "th";
  my @months = ('Jan','Feb','Mar','Apr','May', 'Jun', 'Jul', 'Aug','Sep','Oct','Nov','Dec');
  if ($x) {
    my ($S, $M, $H, $d, $m, $Y) = localtime($x);
    $Y += 1900;
    if (($d == '1')||($d == '21')||($d == '31')) { $suffix = "st"; }
    if (($d == '2')||($d == '22')) { $suffix = "nd"; }
    if (($d == '3')||($d == '23')) { $suffix = "4d"; }
    my $dt = $d."".$suffix." ".$months[$m]." ".$Y;
    return $dt;
  } else {
    return;
  }
}

sub ReturnFilename($$) { # expect STR filename, STR filepath, return the correct(?) filename or unknown
  my $filename;
  my $x = shift;
  my $y = shift;
  if ($x) {
    $filename = $x;
  } else {
    $filename = $y;
  }
  if (!$filename) { 
    $filename = "unknown$unknownCounter";
    $unknownCounter++; 
  }
  return $filename;
}

sub ReturnIcon($) { # expect icon number as INT, return icon name
  my $x = shift;
  my $icon = "icon_unknown";
  if ($x == "1"){ $icon = "icon_star"; }
  if ($x == "2"){ $icon = "icon_circle"; }
  if ($x == "3"){ $icon = "icon_arrow"; }
  if ($x == "9"){ $icon = "icon_flag"; }
  return $icon;
}

sub SwapOutSpaces($) { # remove non-OS compliant characters from a supplied string
	my $x = shift;
  $x =~ s/^\s+//; # trim left
  $x =~ s/\s+$//; # trim right
	$x =~ s/(\’|\'|\"|\;|\\|\/|,|\!|\@|\#|\$|\%|\^|\&|\*|\(|\))//gi; #remove these
  $x =~ s/\ -\ /-/gi; # Swap space em space for a single em (eg "file - tab.crd" to "file-tab.crd")
	$x =~ s/(\ |\?|\.)/_/gi; # replace with underscore
  $x =~ s/___/_/gi;
  $x =~ s/__/_/gi;
	return $x;
}

sub SwapHTMLEntities($) { # remove HTML tags from a supplied string
	my $x = shift;
	$x	=~ s/\</\&lt;/g; # replace < with &lt;
	$x	=~ s/\>/\&gt;/g; # replace > with &gt;
	$x	=~ s/\&/\&amp;/g; # replace & with &amp;
  # Do we need more .. ?
	return $x;
}

sub SongHTMLHeader($$) { # expects title as string, time as int, generate HTML song header text 
  my $text;
  my @tmp ='';
  my $x = shift;
  my $y = shift || 8000;
  # split $y on : and multiply left by 6000 ie 3:30 = (3 * 6000) + (30 * 100) = 21000
  if ($y =~ /\:/) {
    @tmp = split(/\:/, $y);
    my $res = ($tmp[0] * 6000) + ($tmp[1] *100);
    $y = $res;
  }
  $text = <<EOF;
<html>
  <head>
  <title>$x</title>
  <style>
    * {font: 100%/1 "Helvetica Bold","Helvetica", sans-serif; color: #000000; text-align:left;padding:0;margin:0;}
    body {padding-left:10px;background-color:#f3e4d4;}
    .artist {font-size:1.25rem;display:block;}
    .capo {font-size:1.25rem;display:block;}
    .chord {font-weight:bold;background-color:yellow;}
    .lyrics, .lyrics_chorus {}
    .lyrics_tab, .lyrics_chorus_tab { font-family: "Courier New", Courier; font-size:1rem; }
    .lyrics_chorus, .lyrics_chorus_tab, .chords_chorus, .chords_chorus_tab { font-weight: bold; }
    .chords, .chords_chorus, .chords_tab, .chords_chorus_tab { font-size:1rem; color: blue; padding-right: 4pt;}
    .comment { color:blue; margin:10px 0; }
    .italic { font-style: italic; }
    .box { border: solid; }
    .copyright { padding: 20px 0; border: 1px solid #aaa; border-radius: 20px; margin: 10px auto;}
    table.line {padding-left:10px;}
    #footer { width: 100%; border: 1px solid #aaa; background: #eee; margin-top: 40px; }
    #footer p { padding: 10px 0 0 10px; }
    .clear { clear:both; }
    #header { width: 100%; }
    #header #top { width: 100%; background-color: black; align-content: center; height: 32px; position: fixed; top: 0; left:0; padding-left: 10px; }
    #header #top .title { position: absolute; top: -4px; color: antiquewhite; padding: 0;}
    #to_top { height:58px; background-repeat: no-repeat; background-image:url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAA6CAYAAADRN1sJAAAACXBIWXMAAAsTAAALEwEAmpwYAAAGxmlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgNi4wLWMwMDIgNzkuMTY0NDg4LCAyMDIwLzA3LzEwLTIyOjA2OjUzICAgICAgICAiPiA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPiA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIiB4bWxuczp4bXA9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyIgeG1sbnM6cGhvdG9zaG9wPSJodHRwOi8vbnMuYWRvYmUuY29tL3Bob3Rvc2hvcC8xLjAvIiB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIgeG1sbnM6c3RFdnQ9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZUV2ZW50IyIgeG1wOkNyZWF0b3JUb29sPSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgeG1wOkNyZWF0ZURhdGU9IjIwMjItMTItMjhUMjI6NTY6MjUrMDg6MDAiIHhtcDpNb2RpZnlEYXRlPSIyMDIyLTEyLTI5VDE3OjIzOjMxKzA4OjAwIiB4bXA6TWV0YWRhdGFEYXRlPSIyMDIyLTEyLTI5VDE3OjIzOjMxKzA4OjAwIiBkYzpmb3JtYXQ9ImltYWdlL3BuZyIgcGhvdG9zaG9wOkNvbG9yTW9kZT0iMyIgcGhvdG9zaG9wOklDQ1Byb2ZpbGU9InNSR0IgSUVDNjE5NjYtMi4xIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOmNiODBiOThiLTJmMzEtNDhhOS1iMjAxLWYyNmRjMzcxMmU1MiIgeG1wTU06RG9jdW1lbnRJRD0iYWRvYmU6ZG9jaWQ6cGhvdG9zaG9wOjJiOGQzMWMzLTY5OTItMGI0OC1hMTI3LWEwZjhmZWZiYTE1YyIgeG1wTU06T3JpZ2luYWxEb2N1bWVudElEPSJ4bXAuZGlkOjAxZTYwYzZjLWM2MDUtNDJlYy1iMjk0LTczMWE2NTlmNTQyYSI+IDx4bXBNTTpIaXN0b3J5PiA8cmRmOlNlcT4gPHJkZjpsaSBzdEV2dDphY3Rpb249ImNyZWF0ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6MDFlNjBjNmMtYzYwNS00MmVjLWIyOTQtNzMxYTY1OWY1NDJhIiBzdEV2dDp3aGVuPSIyMDIyLTEyLTI4VDIyOjU2OjI1KzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIvPiA8cmRmOmxpIHN0RXZ0OmFjdGlvbj0ic2F2ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6YWFmOGU4YzQtMDg0Zi00NGIyLTg1ZmYtZWI1NjIwODkyNzQ2IiBzdEV2dDp3aGVuPSIyMDIyLTEyLTI4VDIyOjU4OjM3KzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgc3RFdnQ6Y2hhbmdlZD0iLyIvPiA8cmRmOmxpIHN0RXZ0OmFjdGlvbj0ic2F2ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6Y2I4MGI5OGItMmYzMS00OGE5LWIyMDEtZjI2ZGMzNzEyZTUyIiBzdEV2dDp3aGVuPSIyMDIyLTEyLTI5VDE3OjIzOjMxKzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgc3RFdnQ6Y2hhbmdlZD0iLyIvPiA8L3JkZjpTZXE+IDwveG1wTU06SGlzdG9yeT4gPC9yZGY6RGVzY3JpcHRpb24+IDwvcmRmOlJERj4gPC94OnhtcG1ldGE+IDw/eHBhY2tldCBlbmQ9InIiPz7dCeuO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);}
    #header #show { float: right; height: 24px; width: 24px; margin: 0 auto; margin-top: 2px; background-repeat: no-repeat; background-size: 24px 24px; padding: 0 10px; background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAACXBIWXMAAA7EAAAOxAGVKw4bAAAC4UlEQVRYhb2XzUtUURjGn3sYQkJkGGSQiBiGiJZS0CLC6EsiImgXEdFCYopwGREWSItoEdKihUS0jAJpERSEk39AHyhuQoJMcREhpVBqUr8W5158vTNz7x2/Hrgwc877Pu9zzuW+H4EyAshJOiTphKR9ksqS8pKcpHlJk5JGJY1IGg6CYDErd1rgdqAfmCE7fgAPgJ3rCeyAayHZWrEQit/WKE7QIHhe0lNJJ2Nbi5KG5a/5k/zVO0ltkkqSDkvqDv9bfJR0NgiCqSwnLwLjsZPMAjeAQgb/VqACTMc4poG9ac55YCzmOAS0pyqvL+RhjGsGKDVycMDLmMNtIClILun9hjYXgWXDOQa01DOsxIL3pRD3AHMh+RP8Z5ok4q/hvhs3yIfvOcKLlJOXYqcC6EkRPGBsl4Cy3ewzm3NARwpZN7UYSPFpAb4Y+8FowwFfzUZ/ElHoUwiFWpzO4HfJ2P8CWgUcMIvLwI40opDsIFAF3gFXM/q0AN9NvHMCrpuFkSxE6wHw2MR75CTtN/vVzRYgn0UjdDr5FBrhcxYGoIzP8/apZBQwYX6XcvIlNUIzJTSeTFxGPxsjl9Vp0xA1ExFqU+TGw8b44+Q7mQi7t0CAjTHlJH0wC0e2QMAx83vUSXprFrrS0vB6gK+cZ8xS1Ul6r5XXkJN0ZbMESDovKeotfkt65YIg+Cdp0Bj1AsWNjozvAW6ZpedBEMxHm22xHD1EcjkuU4vEegDcN7ZLwJ64weUY4c0EsiK+CbHP0QT7C6xuSO7VM3LA67iIpJvIgjD4kuEcp15LFhoXqO2I19qUbscPJ/bkM9hOqIFjRx0Rs/iynU90XglcYXWTEwWvacsbDSYFSc8kHY9tLUp6I1+2J+Q/Jcmn17L8YHJKtYPJqPxgMpl2ACvCAb3Utl7NYAG4Q0rrniakCNwFvjUROBpOd6Xx130FDYTkJHXJj+ed8ldekK+oPyVNyV91VU2M5/8BQwxqcYjaAsEAAAAASUVORK5CYII=);}
		#header .favourite img { paddding-left: 5px; width: 24px; float: right; }
		#header .scroll { float: right; padding: 5px 20px 0 10px; }
    #header .title {padding: 5px 0;}
		#autoscroll { text-decoration-line: none; padding: 10px; }
    #top .icon_star,#top .icon_arrow,#top .icon_circle,#top .icon_flag { height: 24px; width: 24px; background-size: 24px 24px;}
		.title { font-size: 1.5rem; margin: 10px 0; }
    .artist { font-size: 1.25rem; }
    .nomargin { margin: 0; -webkit-text-stroke-width: 1px; -webkit-text-stroke-color: black; color: antiquewhite; }
		#rTitle { float: right; position: absolute; top: 35px; right: 40px; text-align: left; }
    #extra { padding: 20px; border: 1px solid #aaa; border-radius: 40px; }
    #extra div:first-child { padding-top: 0; }
    #extra div { padding-top:10px; }
		.capo { font-size: 1.25rem; }
		.time { font-size: 1.25rem; text-align: right; }
  </style>
  <script src="https://ajax.googleapis.com/ajax/libs/jquery/3.3.1/jquery.min.js"></script>
	<script>
		\$(document).ready(function () {
			\$('#autoscroll').on('click', function (event) {
				if (this.hash !== '') {
					event.preventDefault();
					var hash = this.hash;
					\$('html, body').animate({ scrollTop: \$(hash).offset().top,},$y,function () {
							window.location.hash = hash;
						}
					);
				} // End if
			});
		});
    \$(document).ready(function(){
      \$('#show').click(function() {
        \$('#extra').toggle(600);
      });
    });
	</script>
  </head>
  <body>
EOF
# TODO: Add only needed icon
$text .= &AddIconsToHTML();
return $text;
}

# TODO: sub to check all directories to find file
sub ReturnFoundFile($){
  #
  return;
}

sub ConvertToHTML($) { # expects song as array of strings
  # Based on Web Chord by	Martin Vilcans (see https://webchord.sourceforge.net/ )
	my($mySongContent) = &SwapHTMLEntities(@_);
  my($artist,$copyright,$title,$content,$subtitle,$capo,$duration,$icon,$composer,$lyricist,$unknown,$extracontent,$filename) = '';
  my(@chords,@lyrics,@listOfChords,@meta,@book,@album,@define,@links);
	my($mode) = 0;
	# mode classes: 0 (normal) 1 (chorus)      2 (normal+tab) 3 (chorus + tab)
	my @lClasses = ('lyrics', 'lyrics_chorus', 'lyrics_tab',  'lyrics_chorus_tab');
	my @cClasses = ('chords', 'chords_chorus', 'chords_tab',  'chords_chorus_tab');
  # Process the song ...
	while($mySongContent ne '') {
		$mySongContent	=~ s/(.*)\n?//; # extract and remove line
		$_ = $1;
		chomp;
		if(/^icon/) { $icon = $_ ; next; }              # checks for icon
		if(/^#(.*)/) {                                  # a line starting with # is a comment
			$content .= "<!-- $1 -->\n";                  # insert as HTML comment
		} elsif(/{(.*)}/) {                             # this is a command
			$_ = $1;
			if(/^title:/i || /^t:/i) {                    # title
        $title = $';
			} elsif(/^subtitle:/i || /^st:/i) {           # subtitle
        $subtitle = $';
			} elsif(/^capo:/i) {                          # capo
        $capo = $';
			} elsif(/^artist:/i) {                        # artist
        $artist = $';
      } elsif(/^filename:/i)	{                     # filename from DB
        if ($' !~ /(crd|cho|pro|chopro|chord)$/i) { # ignore chord pro type files
          $filename = $';
          my $foundFile = &ReturnFoundFile($filename);
          if ($filename =~ /(jpe?g|png|gif)$/i) {   # if it's an image
            # TODO: check all directories to find file
            $content .=  "<img src='../non-modified/".$filename."' />\n";
          } elsif ($filename =~ /pdf$/i) {          # if it's a PDF
            # TODO: check all directories to find file
            $content .=  "<iframe src='../non-modified/".$filename."' title='".$filename."' style='border:none;height:800px;width:100%;'></iframe>\n";
          } else { # not sure what type of file this is?
            # TODO: check all directories to find file
            # my $foundFile = &ReturnFoundFile($filename);
            if ($foundFile) {
              # put the found file in here
              $content .=  "<p><a href='../non-modified/".$filename."'>Direct file contents</a></p>\n";
            } else {
              # error message, can't find file
              $content .=  "<p><a href='../non-modified/".$filename."'>Direct file contents</a></p>\n";
            }
          }
        }
			} elsif(/^copyright:/i)	{                     # copyright
				 $copyright = "<p class=\"copyright\">$'</p>\n";
			} elsif(/^link:/i)	{                         # link
				 my $tmp = "<a target='_blank' href=\"$'\">$'</a>\n";
         push(@links,$tmp);
			} elsif(/^meta:/i)	{                         # meta
         push(@meta, $');
			} elsif(/^key:/i)	{                           # key
				 $content .=  "<!-- Key: $' -->\n";
			} elsif(/^duration:/i)	{                     # duration
				 $duration = $';
			} elsif(/^time:/i)	{                         # time
				 $content .=  "<!-- Time: $' -->\n";
			} elsif(/^tempo:/i)	{                         # tempo
				 $content .=  "<!-- Tempo: $' -->\n";
			} elsif(/^year:/i)	{                         # year
				 $content .=  "<!-- Year: $' -->\n";
      } elsif(/^composer:/i)	{                     # composer
				 $composer = $';
      } elsif(/^lyricist:/i)	{                     # lyricist
				 $lyricist = $';
      } elsif(/^book:/i)	{                         # book
				push(@book, $');
      } elsif(/^album:/i)	{                         # album
				push(@album, $');
      } elsif(/^define:/i)	{                       # define
				push(@define, $_);
			} elsif(/^start_of_chorus/i || /^soc/i)	{     # start_of_chorus
				$mode |= 1;
			} elsif(/^end_of_chorus/i || /^eoc/i) {       # end_of_chorus
				$mode &= ~1;
			} elsif(/^comment:/i ||	/^c:/i)	{             # comment
				$content .= "<p class=\"comment\">$'</p>\n";
			} elsif(/^comment_italic:/i || /^ci:/i)	{     # comment_italic
				$content .= "<p class=\"comment italic\">$'</p>\n";
			} elsif(/^comment_box:/i || /^cb:/i) {        # comment_box
				$content .= "<p class=\"comment box\">$'</p>\n";
			} elsif(/^start_of_tab/i || /^sot/i) {        # start_of_tab
				$mode |= 2;
			} elsif(/^end_of_tab/i || /^eot/i) {          # end_of_tab
				$mode &= ~2;
			} else {
				$content .=  "<!--Unknown command:	$_-->\n";
				$unknown .=  "<p>Unknown command:	$_</p>\n";
			}
		} else { # this is a line with chords and lyrics
      if ($_ =~ /^http*/) { # make links clickable, then move on ... 
        my $link = "<a href='$_' target=_blank>$_</a>";
        push(@links, $link);
        next;
      }
			@chords=("");
			@lyrics=();
			s/\s/\&nbsp;/g; # replace spaces with hard spaces
			while(s/(.*?)\[(.*?)\]//) {
				push(@lyrics,$1);
				push(@chords,$2	eq '\'|' ? '|' : $2);
        push(@listOfChords, $2) unless grep{$_ eq $2} @listOfChords;
			}
			push(@lyrics,$_);				    # rest of line (after last chord) into @lyrics
			if($lyrics[0] eq "") {			# line began with a chord
				shift(@chords);				    # remove first item
				shift(@lyrics);				    # (they	are both empty)
			}

			if(@lyrics==0) {	# empty	line
				$content .=  "<br/>\n";
			} elsif(@lyrics==1 && $chords[0] eq "")	{	# line without chords
				$content .= "<div class=\"$lClasses[$mode]\">$lyrics[0]</div>\n";
			} else {
				$content .= "<table class='line'><tr>";
				my($i);
				for($i = 0; $i < @chords; $i++) {
					$content .= "<td class=\"$cClasses[$mode]\"><span class='chord'>$chords[$i]</span></td>";
				}
				$content .= "</tr>\n<tr>";
				for($i = 0; $i < @lyrics; $i++) {
					$content .= "<td class=\"$lClasses[$mode]\">$lyrics[$i]</td>";
				}
				$content .= "</tr>\n</table>\n";
			}
		}
	}	#while
  if (!$artist && $subtitle){ # if there is no artist, but a subtitle, make that the artist!
    $artist = $subtitle;
  }
  $filename = $createdFilePath.&SwapOutSpaces($artist)."-".&SwapOutSpaces($title).".html";
  my @unique = do { my %seen; grep { !$seen{$_}++ } @listOfChords };
  $content .= $copyright;

  # Create head div, Left side first
  my $headDiv = "";
  if ($icon) { $headDiv .= "<span class='$icon'>&nbsp;</span>"; }
  $headDiv .= "</div><div class='title nomargin'>$title</div>";
  if ($subtitle) { $headDiv .= "<div class='subtitle'>$subtitle</div>"; }
  if ($artist) { $headDiv .= "<div class='artist'>$artist</div>"; }
  # Stuff for the right goes here
  $headDiv .= "<div id='rTitle'>";
  if ($capo) { $headDiv .= "<div class='capo'>Capo: $capo</div>"; }
  $headDiv .= "</div></div><br class='clear'/>";
  # Stuff hidden at first goes here
  $headDiv .= "<div id='extra' style='display: none'>";
  if ($duration) { $extracontent .= "<div class='duration'>Time: $duration</div>"; }
  foreach my $element ( @meta ) {
    $extracontent .= "<div class='meta'>$element</div>";
  }
  if ($composer) { $extracontent .= "<div class='composer'>Composer: $composer</div>"; }
  if ($lyricist) { $extracontent .= "<div class='lyricist'>Lyricist: $lyricist</div>"; }
  foreach my $element(@book) {
    $extracontent .= "<div class='book'>Book: $element</div>";
  }
  foreach my $element(@album) {
    $extracontent .= "<div class='album'>Album: $element</div>";
  }
  foreach my $element(@links) {
    $extracontent .= "<div class='links'>Link: $element</div>";
  }
  $extracontent .= $unknown; # add the unknown stuff
  # determine if there is a DIV
  my $startDiv;
  if ($extracontent) {
    $headDiv .= $extracontent;
    $startDiv = "<div id='header'><div id='top'><span class='title'>$title</span><span id='show'>&nbsp;</span><span class='scroll'><button><a id='autoscroll' href='#footer'>Autoscroll</a></button></span>";
  } else {
    #$headDiv .= "<div>No further information available for this song</div>";
    $startDiv = "<div id='header'><div id='top'><span class='title'>$title</span><span class='scroll'><button><a id='autoscroll' href='#footer'>Autoscroll</a></button></span>";
  }
  $headDiv .= "</div>";

  #TODO: map chords to images for chords - https://metacpan.org/dist/Music-Image-Chord or https://metacpan.org/pod/Music::FretboardDiagram
  if (@listOfChords) { 
    $content .= "<p class='chordlist'>Chords: @listOfChords </p>"; 
  }
  open(FILE, '>', $filename) or die $!;
  if ($duration) { 
    print FILE &SongHTMLHeader($title." - ".$artist, $duration)
  } else {
    print FILE &SongHTMLHeader($title." - ".$artist);
  }
  print FILE $startDiv;
  print FILE $headDiv;
  print FILE $content;
  print FILE "<div onclick='window.location.href=\"#header\";' id='to_top'>&nbsp;</div>";
  print FILE &HTMLFooter($filename);
  close(FILE)
}

sub HTMLFooter($) { # expects filename or sectionname as string, generate footer text 
  my $text;
  my $x = shift;
  my $now = localtime();
  $text = <<EOF;
</table>
<div id=footer>
<p>Click show or hide for individual areas as applicable</p>
<p>Date formats are all YYYY-MM-DD HH:mm:ss</p>
<hr />
<p>Page for $x generated $now</p>
<p>By $0 &copy; Richard Mortimer 2022</p>
</div>
</body>
</html>
EOF
return $text;
}

sub HTMLHeader($$) { # generate header text, expects title as strings and icon as binary string
  my $text;
  my $title = shift;
  my $icon = shift;
  my $now = localtime();
  $text = <<EOF;
<html>
<head>
<title>$title generated $now</title>
<style>
body { font: 62.5%/1.5  "Lucida Grande", "Lucida Sans", Tahoma, Verdana, sans-serif; color: #000000; text-align:left; } .data { font-family: Arial, Helvetica, sans-serif; border-collapse: collapse; width: 100%; }
.data td, .data th { border: 1px solid #ddd; padding: 8px; }
.data tr:nth-child(even){ background-color: #f2f2f2; }
.data tr:hover { background-color: #ddd; }
.data th { padding-top: 12px; padding-bottom: 12px; text-align: left; background-color: #0000aa; color: white; }
h1 span { border: 1px solid #ddd; padding: 8px; margin-left: 10px; font-size: 0.5em; float: right; }
span.right { float: right; }
span.anchors { display:inline-block; margin 10px auto; width: 20px; font-size: 2em; }
td.red { background-color: red; opacity: 0.5; }
td.yellow { background-color: yellow; opacity: 0.5; }
button.toggler { width: 70px; }
#footer { width: 100%; border: 1px solid #aaa; background: #eee; margin-top: 40px; }
#footer p { padding: 10px 0 0 10px; }
#header { width: 100%; border: 4px solid #000; background: #00f; }
#header p { font-size: 4em; text-align: center; color: white; }
.dateBox { font-size: 0.6em; }
.sidebar { height: 100%; width: 0; position: fixed; z-index: 1; top: 0; left: 0; background-color: #111; overflow-x: hidden; transition: 1.5s; padding-top: 30px; }
.sidebar a { padding: 8px 8px 8px 3px; text-decoration: none; font-size: 1.2em; color: #818181; display: block; transition: 1.5s; }
.sidebar a:hover { color: #f1f1f1; }
.sidebar .closebtn { position: absolute; top: 0; width: 100%; }
.openbtn { cursor: pointer; background-color: #111; color: white; padding: 10px 15px; border: none; }
.openbtn:hover { background-color: #444; }
.icon_unknown { float: right; height: 16px; width: 16px; margin: 0 auto; background-repeat: no-repeat; background-size: 16px 16px; padding: 0 10px; }
#main { transition: margin-left 1.5s; padding: 16px; }
</style>
<script>
var isSidebarOpen = false;

function sideNavClicked(){
	isSidebarOpen ? closeNav() : openNav();
}
function openNav() {
	isSidebarOpen=true;
  document.getElementById("mySidebar").style.width = "100px";
  document.getElementById("main").style.marginLeft = "100px";
}
function closeNav() {
	isSidebarOpen=false;
  document.getElementById("mySidebar").style.width = "0";
  document.getElementById("main").style.marginLeft= "0";
}
function toggle(div) {
  var x = document.getElementById(div);
  var y = document.getElementById('b_' + div);
  if (x.style.display === "none") {
    x.style.display = "table";
    x.style.width = "100%";
    y.innerText = "Hide";
  } else {
    x.style.display = "none";
    y.innerText = "Show";
  }
}
</script>
<script src="https://ajax.googleapis.com/ajax/libs/jquery/3.4.0/jquery.min.js"></script>
<script>
\$(document).ready(function(){
  \$("button.hideButton").click(function(){
    \$("tr.deleted").toggle();
  });
});
</script>
</head>
<body>
<div id=header><p>OnSong database details - $title</p></div>
EOF
  if ($icon ne 'false') {
    $text .= &AddIconsToHTML();
  }
  return $text;
}

sub AddIconsToHTML() {
  my $text .= <<EOI;
<style>
.icon_arrow { float: right; height: 16px; width: 16px; margin: 0 auto; background-repeat: no-repeat; background-size: 16px 16px; padding: 0 10px; background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAArElEQVQ4jaWSMQvCMBCFv4g4Vafb/I0dRIqLVNRNRAr5hc7tIoLgoHGwkVRCU64PAgeX993LEUjIie3tT1IAYOHEbscAAI5ObBlrGCd2lkoA1G19ME2++09wA549pw7ul07sXvOEUB2IBtCBTJUAD3lpE3jNxwAqoNACKmBlmly1xJ8ZvktcJgwZcG3rC7D2ZgCTGufEZsAdOANFaIZh/+ANnGLmoYAHsImZAT6l+TOi5O4ddwAAAABJRU5ErkJggg==);}
.icon_circle {float: right; height: 16px; width: 16px; margin: 0 auto; background-repeat: no-repeat; background-size: 16px 16px; padding: 0 10px;  background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAAwElEQVQ4jaWTMQrCQBBFn0sKT+ABRFKIiHey8iQiwcJCxFN4ADGtpYWVnYWNpQg2Er5FDHETNyGb+Ww37+/M7gwUQ4SICHFCPL7njFghhqX8HzBALBBv5FSCWCO6/+BdBVjU3jYR8wZwpm0GD2rKrmpnbIApELgfxxkGmIE4etye6dJB3IGeRwUAL+MJWn1cW/A3A8QtDGIQ/RbfOEl90hH2HKTUoOkoH3DsQ1TTToLYlGHbKEQsydf5Sb7Oo2L6B9EZD8MS1RXbAAAAAElFTkSuQmCC);}
.icon_flag { float: right; height: 16px; width: 16px; margin: 0 auto; background-repeat: no-repeat; background-size: 16px 16px; padding: 0 10px; background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAAsUlEQVQ4je3SMWpCQRSF4U8RS0klgp1Yp05hXEFq95A9uAcLixSpLAIuIIsI2JjeTdiFIDkpfMpjigcGxCZ/dQ9zOHPn3gFhHvbhQUFoh2lYhk34DK9hBJ3KN0QPb2GBbaUfMVOZa9zjgOdOcTDCsuyiifYl5v+AKwWUa2xiiw98qX24MuAdE9xVeoc1Vq1jfSYM6uIlJDyFbhiH/p+e0OJbcVsTt9/CKeDgON2fSwN+Aa32KevyFMVlAAAAAElFTkSuQmCC);}
.icon_star { float: right; height: 16px; width: 16px; margin: 0 auto; background-repeat: no-repeat; background-size: 16px 16px; padding: 0 10px; background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAA/ElEQVQ4jaWSvUpDQRCFvxtEEgliZwprC5E8gXUKEVGCvodFnsAyiIhInsYiWFvoO1hYmCbgCUFyUmSVvZfsmuiBZYb5OTtndiEDi6bFTq6mlksCJ8Dpfwi6wMUvNcthsWUxtpDF9l8m6ABNoM5CytoE3YRfQmFxCVxFZN/2MNwOMAVegz+L7AMAFscW7xZe8XxYnJVGsWhZPK7QPLTYW6rHomZxnWnuW2zEPaUlFg1mwDC1MOCpaPCVJAhIbhw4rwaKqgTgDWgBn0APmAB3LP7ECNitThETHAWtLxYHUXzf4jnkOsn5LG4t7q2f949zmxY3FoMcQTuZTNTMAQgNrjte9swtAAAAAElFTkSuQmCC);}
.unknown { height: 32px; width: 32px; margin: 0 auto; background-repeat: no-repeat; background-size: 32px 32px; background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAACXBIWXMAAAsTAAALEwEAmpwYAAAGxmlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgNi4wLWMwMDIgNzkuMTY0NDg4LCAyMDIwLzA3LzEwLTIyOjA2OjUzICAgICAgICAiPiA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPiA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIiB4bWxuczp4bXA9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iIHhtbG5zOnhtcE1NPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvbW0vIiB4bWxuczpzdEV2dD0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL3NUeXBlL1Jlc291cmNlRXZlbnQjIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgeG1wOkNyZWF0b3JUb29sPSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgeG1wOkNyZWF0ZURhdGU9IjIwMjItMDMtMTNUMDg6NDA6MDIrMDg6MDAiIHhtcDpNZXRhZGF0YURhdGU9IjIwMjItMDMtMTZUMTg6NTU6MDYrMDg6MDAiIHhtcDpNb2RpZnlEYXRlPSIyMDIyLTAzLTE2VDE4OjU1OjA2KzA4OjAwIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOmQwNmI1YjVjLWEzOGMtNDFmNS05NjUyLTU1OTZjYWVhNTYxMiIgeG1wTU06RG9jdW1lbnRJRD0iYWRvYmU6ZG9jaWQ6cGhvdG9zaG9wOjQyOWZmMmUyLTcxMjEtNjg0YS1iZGZjLTU3OGE5ODk3YjFjYyIgeG1wTU06T3JpZ2luYWxEb2N1bWVudElEPSJ4bXAuZGlkOjFjNzdiNWI0LTdhMTktNDE4OS1hYjQxLTYxMzMwNjU2MTdiZSIgZGM6Zm9ybWF0PSJpbWFnZS9wbmciIHBob3Rvc2hvcDpDb2xvck1vZGU9IjMiIHBob3Rvc2hvcDpJQ0NQcm9maWxlPSJzUkdCIElFQzYxOTY2LTIuMSI+IDx4bXBNTTpIaXN0b3J5PiA8cmRmOlNlcT4gPHJkZjpsaSBzdEV2dDphY3Rpb249ImNyZWF0ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6MWM3N2I1YjQtN2ExOS00MTg5LWFiNDEtNjEzMzA2NTYxN2JlIiBzdEV2dDp3aGVuPSIyMDIyLTAzLTEzVDA4OjQwOjAyKzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIvPiA8cmRmOmxpIHN0RXZ0OmFjdGlvbj0ic2F2ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6ODk0OWZiNTAtMzFmZS00MDAwLWJkMjctNWMxYjAzZjkwZjA3IiBzdEV2dDp3aGVuPSIyMDIyLTAzLTEzVDA4OjQwOjAyKzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgc3RFdnQ6Y2hhbmdlZD0iLyIvPiA8cmRmOmxpIHN0RXZ0OmFjdGlvbj0ic2F2ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6ZDA2YjViNWMtYTM4Yy00MWY1LTk2NTItNTU5NmNhZWE1NjEyIiBzdEV2dDp3aGVuPSIyMDIyLTAzLTE2VDE4OjU1OjA2KzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgc3RFdnQ6Y2hhbmdlZD0iLyIvPiA8L3JkZjpTZXE+IDwveG1wTU06SGlzdG9yeT4gPC9yZGY6RGVzY3JpcHRpb24+IDwvcmRmOlJERj4gPC94OnhtcG1ldGE+IDw/eHBhY2tldCBlbmQ9InIiPz7H2+FN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);}
.cross { height: 32px; width: 32px; margin: 0 auto; background-repeat: no-repeat; background-size: 32px 32px; background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAACXBIWXMAAAsTAAALEwEAmpwYAAAGxmlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgNi4wLWMwMDIgNzkuMTY0NDg4LCAyMDIwLzA3LzEwLTIyOjA2OjUzICAgICAgICAiPiA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPiA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIiB4bWxuczp4bXA9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iIHhtbG5zOnhtcE1NPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvbW0vIiB4bWxuczpzdEV2dD0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL3NUeXBlL1Jlc291cmNlRXZlbnQjIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgeG1wOkNyZWF0b3JUb29sPSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgeG1wOkNyZWF0ZURhdGU9IjIwMjItMDMtMTNUMDg6NDE6MzQrMDg6MDAiIHhtcDpNZXRhZGF0YURhdGU9IjIwMjItMDMtMTZUMTg6NTU6MDQrMDg6MDAiIHhtcDpNb2RpZnlEYXRlPSIyMDIyLTAzLTE2VDE4OjU1OjA0KzA4OjAwIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOmYyOTM5MjM0LTlmMTUtNDA4MC1iNWNkLTkwZjNlZTJiOWQ2NCIgeG1wTU06RG9jdW1lbnRJRD0iYWRvYmU6ZG9jaWQ6cGhvdG9zaG9wOjIyMDgzMDBhLTBhMWYtZWQ0ZS1iODVmLTVjMjUzMDQ0YTlmMCIgeG1wTU06T3JpZ2luYWxEb2N1bWVudElEPSJ4bXAuZGlkOjllYWI4NTNjLTI5MmUtNGI2OS05ZDNhLTFkOWE1MzMxNWI4MiIgZGM6Zm9ybWF0PSJpbWFnZS9wbmciIHBob3Rvc2hvcDpDb2xvck1vZGU9IjMiIHBob3Rvc2hvcDpJQ0NQcm9maWxlPSJzUkdCIElFQzYxOTY2LTIuMSI+IDx4bXBNTTpIaXN0b3J5PiA8cmRmOlNlcT4gPHJkZjpsaSBzdEV2dDphY3Rpb249ImNyZWF0ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6OWVhYjg1M2MtMjkyZS00YjY5LTlkM2EtMWQ5YTUzMzE1YjgyIiBzdEV2dDp3aGVuPSIyMDIyLTAzLTEzVDA4OjQxOjM0KzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIvPiA8cmRmOmxpIHN0RXZ0OmFjdGlvbj0ic2F2ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6MGYyMDI2MTYtMzg2MS00MTg1LThiMjUtY2VkZTcyMWUxYzFlIiBzdEV2dDp3aGVuPSIyMDIyLTAzLTEzVDA4OjQxOjM0KzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgc3RFdnQ6Y2hhbmdlZD0iLyIvPiA8cmRmOmxpIHN0RXZ0OmFjdGlvbj0ic2F2ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6ZjI5MzkyMzQtOWYxNS00MDgwLWI1Y2QtOTBmM2VlMmI5ZDY0IiBzdEV2dDp3aGVuPSIyMDIyLTAzLTE2VDE4OjU1OjA0KzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgc3RFdnQ6Y2hhbmdlZD0iLyIvPiA8L3JkZjpTZXE+IDwveG1wTU06SGlzdG9yeT4gPC9yZGY6RGVzY3JpcHRpb24+IDwvcmRmOlJERj4gPC94OnhtcG1ldGE+IDw/eHBhY2tldCBlbmQ9InIiPz73xUgR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);}
.tick { height: 32px; width: 32px; margin: 0 auto; background-repeat: no-repeat; background-size: 32px 32px; background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAACXBIWXMAAAsTAAALEwEAmpwYAAAGxmlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgNi4wLWMwMDIgNzkuMTY0NDg4LCAyMDIwLzA3LzEwLTIyOjA2OjUzICAgICAgICAiPiA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPiA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIiB4bWxuczp4bXA9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iIHhtbG5zOnhtcE1NPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvbW0vIiB4bWxuczpzdEV2dD0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL3NUeXBlL1Jlc291cmNlRXZlbnQjIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgeG1wOkNyZWF0b3JUb29sPSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgeG1wOkNyZWF0ZURhdGU9IjIwMjItMDMtMTNUMDg6Mzg6MjcrMDg6MDAiIHhtcDpNZXRhZGF0YURhdGU9IjIwMjItMDMtMTZUMTg6NTU6MDIrMDg6MDAiIHhtcDpNb2RpZnlEYXRlPSIyMDIyLTAzLTE2VDE4OjU1OjAyKzA4OjAwIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOjJjNTVhOTI4LWI2YWUtNDgzYi05NGQ2LWIzOTAyYjM2MjRhMCIgeG1wTU06RG9jdW1lbnRJRD0iYWRvYmU6ZG9jaWQ6cGhvdG9zaG9wOmM3MGIzODljLWY5ZTUtYmM0OC1iOTQ5LTNhNjU3Y2Q3Mjg0NiIgeG1wTU06T3JpZ2luYWxEb2N1bWVudElEPSJ4bXAuZGlkOmEwYjRjOThjLTQ3ZjMtNDEwNi05NTZmLTQxZmIzMGEyMzhhZiIgZGM6Zm9ybWF0PSJpbWFnZS9wbmciIHBob3Rvc2hvcDpDb2xvck1vZGU9IjMiIHBob3Rvc2hvcDpJQ0NQcm9maWxlPSJzUkdCIElFQzYxOTY2LTIuMSI+IDx4bXBNTTpIaXN0b3J5PiA8cmRmOlNlcT4gPHJkZjpsaSBzdEV2dDphY3Rpb249ImNyZWF0ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6YTBiNGM5OGMtNDdmMy00MTA2LTk1NmYtNDFmYjMwYTIzOGFmIiBzdEV2dDp3aGVuPSIyMDIyLTAzLTEzVDA4OjM4OjI3KzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIvPiA8cmRmOmxpIHN0RXZ0OmFjdGlvbj0ic2F2ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6YjZlZTU0MTUtNTk4Ni00OGNmLTlkOGItYjc1ODBhNDllOWI5IiBzdEV2dDp3aGVuPSIyMDIyLTAzLTEzVDA4OjM4OjI3KzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgc3RFdnQ6Y2hhbmdlZD0iLyIvPiA8cmRmOmxpIHN0RXZ0OmFjdGlvbj0ic2F2ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6MmM1NWE5MjgtYjZhZS00ODNiLTk0ZDYtYjM5MDJiMzYyNGEwIiBzdEV2dDp3aGVuPSIyMDIyLTAzLTE2VDE4OjU1OjAyKzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgc3RFdnQ6Y2hhbmdlZD0iLyIvPiA8L3JkZjpTZXE+IDwveG1wTU06SGlzdG9yeT4gPC9yZGY6RGVzY3JpcHRpb24+IDwvcmRmOlJERj4gPC94OnhtcG1ldGE+IDw/eHBhY2tldCBlbmQ9InIiPz4wcxmc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)
}
</style>
EOI
  return $text;
}

# ------ build directory structure, if required -------- #

if (! -d $coreDirectory)   { mkdir $coreDirectory or die $!; }
open(LOG, ">$logFile") or die $!;
if (! -d $outDirectory)    { mkdir $outDirectory or die $!;    print LOG "made $outDirectory\n"; }
if (! -d $delDirectory)    { mkdir $delDirectory or die $!;    print LOG "made $delDirectory\n"; }
if (! -d $nonDelDirectory) { mkdir $nonDelDirectory or die $!; print LOG "made $nonDelDirectory\n"; }
if (! -d $noFilePath)      { mkdir $noFilePath or die $!;      print LOG "made $noFilePath\n"; }
if (! -d $noFilePathDel)   { mkdir $noFilePathDel or die $!;   print LOG "made $noFilePathDel\n"; }
if (! -d $reportPath)      { mkdir $reportPath or die $!;      print LOG "made $reportPath\n"; }
if (! -d $createdFilePath) { mkdir $createdFilePath or die $!; print LOG "made $createdFilePath\n"; }

my $driver = "SQLite";
my $dsn = "DBI:$driver:dbname=$database";
my $dbh = DBI->connect($dsn, $userid, $password, { RaiseError => 1 }) or die $DBI::errstr;

# Count database files and local files and print to log
my $countNonDeletedeted = $dbh->prepare( qq(select count (*) from Song where deleted != '1';) );
my $countDeletedeted = $dbh->prepare( qq(select count (*) from Song where deleted = '1';) );
my $content = $dbh->prepare( qq(select filepath, content, deleted, modified, created, viewed, syncTimestamp, lastImportedOn, ID, filename, byline, title, favorite from Song;) );
my $rv1 = $countNonDeletedeted->execute() or die $DBI::errstr;
while(my @row = $countNonDeletedeted->fetchrow_array()) { print LOG "\nDatabase count of active files: ".$row[0]."\n"; }
my $rv2 = $countDeletedeted->execute() or die $DBI::errstr;
while(my @row = $countDeletedeted->fetchrow_array()) { print LOG "Database count of deleted files: ".$row[0]."\n"; }
my $rv3 = $content->execute() or die $DBI::errstr;
if ($^O ne 'MSWin32') {
  my $localCount = `ls -1 | wc -l | sed 's/^ *//g'`;
  print LOG "Local file count: ".$localCount."\n";
} else {
  print LOG "#TODO: Fix local file count for Windows";
}

while(my @row = $content->fetchrow_array()) {
  my $folder;
  my $deleted;
  my $filename;
  # set the folder to write to:
  if ($row[2] == "1") { # deleted == 1
    $folder = $delDirectory;
    $countDeleted++;
    $deleted = "true";
  } else {
    $folder = $outDirectory;
    $countNonDeleted++;
    if ($noCreateFiles) {
      # do nothing
    } else {
      my $tmp = "{filename:".&ReturnFilename($row[9],$row[0])."}\n".$row[1]."\n".&ReturnIcon($row[12]); # don't mess with the initial values 
      &ConvertToHTML($tmp); # make a file for non-deleted songs ...
    }
  }

  # fix filename or filepath
  $filename = &ReturnFilename($row[9],$row[0]);

  # Check if file already exists
  if (-e $filename) { # filename
    my $size = -s $filename;
    # Check if the size of the database content is the same as the file on disk
    if (length($row[1]) eq $size) {
      $matchFileSize++;
      #print LOG "MATCH [$matchFileSize] File '$filename' matches file size\n";
      $allFiles++;
      system("cp -fR \"$filename\" \"$nonDelDirectory$filename\"");
    } else {
      if ($filename =~ /crd$/) {
        if ($deleted) {
          $notMatchingFileSizeDeleted++;
        } else {
          $notMatchingFileSize++;
        } 
        print LOG "CREATE [$notMatchingFileSize] File <$folder$filename> doesnt match file size, creating\n";
        $allFiles++;
        # Create a new file with the database content, plus the original file for comparison
        open(FH, '>', $folder.$filename) or die $!;
        print FH $row[1];
        print FH "\n\n";
        print FH "##########################################################################\n";
        if ($deleted) {
          print FH "# This file was marked as deleted!\n";
        } else {
          print FH "# This file was updated!\n";
        }
        print FH "# Size is [".length($row[1])."] in the database and [$size] as a file\n";
        print FH "# Modified date was ".FormatDateTime($row[3])."\n";
        print FH "# Created date was ".FormatDateTime($row[4])."\n";
        if (FormatDateTime($row[5])) { print FH "# Viewed date was ".FormatDateTime($row[5])."\n"; }
        print FH "# Sync timestamp was ".FormatDateTime($row[6])."\n";
        print FH "# Last imported was ".FormatDateTime($row[7])."\n";
        print FH "# Original ID was ".$row[8]."\n";
        # print FH "# Original file is below ....\n";
        print FH "##########################################################################\n";

        if ($printFile) {
          open(ORIG, '<', $filename);
          while(<ORIG>) {
            if ($_ !~ m/#\s#\s/) {
              print FH "# ".$_;
            } else {
              #print $_;
            }
          }
          print FH "\n";
          print FH "##########################################################################\n";
          print FH "# End of original file                                                   #\n";
          print FH "##########################################################################\n";
        }
        close(FH); 
      } else {
        $PDFcount++;
        print LOG "PDF   [$PDFcount] File '$filename' is a non-crd file\n";
        system("cp -fR \"$filename\" \"$nonDelDirectory$filename\"");
      }
    }
  } else { # if we get here, we couldn't get a filename from the DB
    if ($deleted) {
      $folder = $noFilePathDel;
      $filename = &SwapOutSpaces($row[10]."-".$row[11])."-DEL.crd";
      print LOG "DEL    [File '$filename' does not exist and is marked deleted\n";
      open(FH, '>', $folder.$filename) or die $!;
      print FH $row[1];
      print FH "\n\n";
      print FH "##########################################################################\n";
      print FH "# This file didn't exist and was marked as deleted!!\n";
      print FH "# Size [".length($row[1])."] in the database and did not exist as a file\n";
      print FH "##########################################################################\n";
      close(FH); 
    } else {
      $folder = $noFilePath;
      $filename = &SwapOutSpaces($row[10]."-".$row[11]).".crd";
      $nonExist++;
      print LOG "???    [$nonExist] File '$filename' does not exist and is not marked deleted - making a newbie\n";
      $allFiles++;
      open(FH, '>', $folder.lc($filename)) or die $!;
      print FH $row[1];
      print FH "\n\n";
      print FH "##########################################################################\n";
      print FH "# This file was marked as deleted!!\n";
      print FH "# Size [".length($row[1])."] in the database and did not exist as a file\n";
      print FH "##########################################################################\n";
      close(FH); 
    }
  }
}

print "\n";
print "CountDel: $countDeleted CountNondel: $countNonDeleted\n";
print "File exists and matchs the size: $matchFileSize\n";
print "File exists, but doesn't match the filesize (potentially modified?): $notMatchingFileSize\n";
print "File doesn't exist (potentially deleted?): $notMatchingFileSizeDeleted\n";
print "File is a PDF or other type of file: $PDFcount\n";
print "Allfiles: $allFiles\n";
print "File didn't exist: $nonExist\n";

# import instruments as a hash reference
my %polyphony;
my $H1 = $dbh->prepare( qq(select ID, polyphony from SongInstrument;) );
my $aa4 = $H1->execute() or die $DBI::errstr;
while(my @row = $H1->fetchrow_array()) {
  $polyphony{$row[0]} = $row[1];
}

# New page: Report on favorites (Favourites)
open(FAV, ">$favourites") or die $!;
print FAV &HTMLHeader("Favourites", "true");
my $L1 = $dbh->prepare( qq(select favorite, ID, title, byline, filepath, filename, lastPlayedOn, viewed from Song where favorite NOT NULL order by favorite DESC, title;) );
my $rv4 = $L1->execute() or die $DBI::errstr;
my $current = -1;
my $icon;
while(my @row = $L1->fetchrow_array()) {
  my $filename;
  if ($current ne $row[0]) {
    if ($current ne -1) {
      print FAV "</table>\n";
    }
    $icon= &ReturnIcon($row[0]);
    print FAV "<h1><button class=\"toggler\" id=\"b_L$row[0]\" onclick=\"toggle('L$row[0]')\">Show</button> Level $row[0] <div class=$icon>&nbsp;</div></h1>\n<table class=data id=\"L$row[0]\" style=\"display:none;\">";
    print FAV "<tr><th>Song</th><th width='50%'>Artist</th></tr>\n";
  }
  $filename = &ReturnFilename($row[5],$row[4]);
  print FAV "<tr><td title=\"ID: $row[1]\"><div class=$icon style=\"float:left;\">&nbsp;</div>$row[2]</td><td title=\"File: $filename\">$row[3]</td></tr>"; #add dates
  $current = $row[0];
}
print FAV &HTMLFooter("Favourites");

# New page: Topic page (Topics)
open(TOP, ">$topics") or die $!;
print TOP &HTMLHeader("Topics");
print TOP "<h1>Topics</h1>\n<table class=data>";
print TOP "<tr><th>Topic</th><th>Date created</th><th>Date modified</th></tr>\n";
my $T1 = $dbh->prepare(qq(select * from Topic order by topic;));
my $rv5 = $T1->execute() or die $DBI::errstr;
while(my @row = $T1->fetchrow_array()) {
  print TOP "<tr><td title=\"ID: $row[0]\">$row[1]</td><td title=\"ID: $row[0]\">".&FormatDateTime($row[2])."</td><td>".&FormatDateTime($row[3])."</td></tr>";
}
print TOP &HTMLFooter("Topics");

# New page: Report on version (Version)
open(VER, ">$version") or die $!;
print VER &HTMLHeader("Version");
print VER "<h1>Version</h1>\n<table class=data>";
print VER "<tr><th>Version</th><th>Updated</th><th>Model</th><th>OS</th><th>UDID</th></tr>\n";
my $T2 = $dbh->prepare(qq(select * from version;));
my $rv6 = $T2->execute() or die $DBI::errstr;
while(my @row = $T2->fetchrow_array()) {
  print VER "<tr><td>$row[0]</td><td>".&FormatDateTime($row[1])."</td><td>$row[2]</td><td>$row[3]</td><td>$row[4]</td></tr>";
}
print VER &HTMLFooter("Version");

# New page: Report on Chords (Chords)
open(CRD, ">$chordFile") or die $!;
print CRD &HTMLHeader("Chords");
my $C1 = $dbh->prepare( qq(select * from SongChord order by instrument, name, priority;) );
my $rv7 = $C1->execute() or die $DBI::errstr;
my $inst = "null";
my $stringLength = 0;

while(my @row = $C1->fetchrow_array()) {
  my $filename;
  my $tmp;
  if ($inst ne $row[1]) {
    $stringLength = 0;
    if ($inst ne "null") {
      print CRD "</table>\n";
    }
    $inst = $row[1];
    print CRD "<h1><button id=\"b_$row[1]\" onclick=\"toggle('$row[1]')\">Show</button> Instrument: <i>$row[1]</i></h1>\n<table class=data id=\"$row[1]\" style=\"display:none;\">"; #add headers
    print CRD "<tr><th>Name * Alias</th><th width='15%'>Tab</th><th width='15%'>Fingering</th><th width='15%'>Priority</th><th width='15%'>Custom</th></tr>\n";
    # Set string numbers
    $stringLength = $polyphony{$row[1]};
  }
  print CRD "<tr><td>$row[2]";
  if ($row[4]) { print CRD " * ".$row[4]; }
  print CRD "</td>";
  $tmp = length($row[3]);
  if ($tmp == "") {
    print CRD "<td class=yellow title=\"Missing chord definition\">";
  }
  elsif (($stringLength != 0) && ($tmp != $stringLength)) {
    print CRD "<td class=red title=\"Length incorrect, $tmp should be $stringLength\">";
  } else {
    print CRD "<td>";
  }
  print CRD "$row[3]</td>";
  # Check length of fingering
  $tmp = length($row[7]);
  if ($tmp == "") {
    print CRD "<td class=yellow title=\"Missing fingering definition\">";
  }
  elsif (($stringLength != 0) && ($tmp != $stringLength)) {
    print CRD "<td class=red title=\"Length incorrect, $tmp should be $stringLength\">";
  } else {
    print CRD "<td>";
  }
  print CRD "$row[7]</td><td>$row[5]</td><td>$row[6]</td></tr>";
}
print CRD &HTMLFooter("Chords");

# New page: Display all songs/active songs by title to one HTML file (All songs by title), (Active songs by title)
open(ALL, ">$allSongsByTitle") or die $!;
open(ALLA, ">$activeSongsByTitle") or die $!;
print ALL &HTMLHeader("All songs by title", "true");
print ALLA &HTMLHeader("Active songs by title", "true");
print ALL "<button class=\"hideButton\">Toggle deleted</button>";
my $A1 = $dbh->prepare( qq(select ID, title, byline, content, deleted, filename, filepath, alpha, bylineAlpha, lastImportedOn, syncTimestamp, created, modified, lastPlayedOn, viewed, duration, favorite from Song order by alpha, title;) );
my $rv8 = $A1->execute() or die $DBI::errstr;
$current = " ";
my $localCount;
my $activeCount;
while(my @row = $A1->fetchrow_array()) {
  my %data = (
    'ID' => $row[0],
    'title' => $row[1],
    'byline' => $row[2],
    'content' => $row[3],
    'deleted' => $row[4],
    'filename' => &ReturnFilename($row[5],$row[6]),
    'alpha' => $row[7],
    'bylineAlpha' => $row[8],
    'imported' => $row[9],
    'synced' => $row[10],
    'created' => $row[11],
    'modified' => $row[12],
    'played' => $row[13],
    'viewed' => $row[14],
    'duration' => $row[15],
    'favorite' => $row[16]
  );
  $localCount++;
  if ($current ne $data{'alpha'}) {
    if ($current ne " ") {
      print ALL "</table>\n";
      print ALLA "</table>\n";
    }
    print ALL "<h1><button class=\"toggler\" id=\"b_A$data{'alpha'}\" onclick=\"toggle('A$data{'alpha'}')\">Show</button> Song starts: $data{'alpha'}</h1>\n<table class=data id=\"A$data{'alpha'}\" style=\"display:none;\">";
    print ALL "<tr><th>Song title</th><th>Artist</th><th width='15%'>Dates</th><th width='10%'>Active</th></tr>\n";
    print ALLA "<h1><button class=\"toggler\" id=\"b_A$data{'alpha'}\" onclick=\"toggle('A$data{'alpha'}')\">Show</button> Song starts: $data{'alpha'}</h1>\n<table class=data id=\"A$data{'alpha'}\" style=\"display:none;\">";
    print ALLA "<tr><th>Song title</th><th>Artist</th><th width='15%'>Dates</th></tr>\n";
    $current = $data{'alpha'};
  }
  if ($data{'deleted'}) { 
    print ALL "<tr class=\"deleted\">"; 
  } else { 
    print ALL "<tr class=\"active\">";
    print ALLA "<tr class=\"active\">"; 
    $activeCount++;
  }
  print ALL "<td title=\"Database ID: $data{'ID'}\"><span class=".&ReturnIcon($data{'favorite'})." style=\"float:none\">&nbsp;</span>".$data{'title'};
  if ($data{'duration'}) { print ALL "<span class=right>[Time: ".FormatSeconds($data{'duration'})."]</span>"; }
  print ALL "</td><td title=\"File: $data{'$filename'}\">$data{'byline'}</td><td class=\"dateBox\">";
  if (!($data{'deleted'})){
    print ALLA "<td title=\"Database ID: $data{'ID'}\"><span class=".&ReturnIcon($data{'favorite'})." style=\"float:none\">&nbsp;</span>".$data{'title'};
  }
  if ($data{'duration'}) { print ALL "<span class=right>[Time: ".FormatSeconds($data{'duration'})."]</span>"; }
  if ($data{'duration'} && !($data{'deleted'})) { print ALLA "<span class=right>[Time: ".FormatSeconds($data{'duration'})."]</span>"; }
  if (!($data{'deleted'})){
    print ALLA "</td><td title=\"File: $data{'filename'}\">$data{'byline'}</td><td class=\"dateBox\">";
  }
  # Dates
  if ($data{'created'}) { print ALL "Created: ".FormatDateTime($data{'created'})."<br />"}
  if ($data{'modified'}) { print ALL "Modified: ".FormatDateTime($data{'modified'})."<br />"}
  if ($data{'imported'}) { print ALL "Last imported: ".FormatDateTime($data{'imported'})."<br />"}
  if ($data{'synched'}) { print ALL "Last synced: ".FormatDateTime($data{'synched'})."<br />"}
  if ($data{'played'}) { print ALL "Last played: ".FormatDateTime($data{'played'})."<br />"}
  if ($data{'viewed'}) { print ALL "Last viewed: ".FormatDateTime($data{'viewed'})."<br />"}
  print ALL "</td>";
  # Dates for all active file
  if (!($data{'deleted'})){
    if ($data{'created'}) { print ALLA "Created: ".FormatDateTime($data{'created'})."<br />"}
    if ($data{'modified'}) { print ALLA "Modified: ".FormatDateTime($data{'modified'})."<br />"}
    if ($data{'imported'}) { print ALLA "Last imported: ".FormatDateTime($data{'imported'})."<br />"}
    if ($data{'synched'}) { print ALLA "Last synced: ".FormatDateTime($data{'synched'})."<br />"}
    if ($data{'played'}) { print ALLA "Last played: ".FormatDateTime($data{'played'})."<br />"}
    if ($data{'viewed'}) { print ALLA "Last viewed: ".FormatDateTime($data{'viewed'})."<br />"}
    print ALLA "</td>";
  }
  # Active
  if ($data{'deleted'}) {
    print ALL "<td><div class=\"cross\" title=\"Deleted song\">&nbsp;</div></td>";
  } else {
    print ALL "<td><div class=\"tick\" title=\"Active\">&nbsp;</div></td>";
  }
  print ALL "</tr>";
  if (!($data{'deleted'})){
    print ALLA "</tr>";
  }
}
print ALL &HTMLFooter("All songs by title (Active: $activeCount, Total: $localCount)");
print ALLA &HTMLFooter("All active songs by title (Active: $activeCount, Total: $localCount)");

# New page: Display all songs by artist to one HTML file:
open(ALA, ">$allSongsByArtist") or die $!;
print ALA &HTMLHeader("All songs by artist", "true");
my $A2 = $dbh->prepare( qq(select ID, title, byline, deleted, created, modified, lastPlayedOn, viewed, favorite, filename, filepath from Song;) );
my $rv9 = $A2->execute() or die $DBI::errstr;
$current = "  ";
my $display;
my $artistCount = 0;
$localCount = 0;

my @data;
my $bylineAlpha;
while(my @row = $A2->fetchrow_array()) {
  if ($row[2] =~ /\;/g) {
    my $count = $row[2] =~ tr/\;//;
    my @artists = split(';',$row[2]);
    foreach ( @artists ) {
      $_=~ s/^\s+|\s+$//g;
      $bylineAlpha = uc(substr $_, 0,1);
      if ($bylineAlpha !~ /[A-Z]/) {
        $bylineAlpha = "#";
      }
      push @data, {
        'ID' => $row[0],
        'title' => $row[1],
        'bylineAlpha' => $bylineAlpha,
        'byline' => $_,
        'filename' => &ReturnFilename($row[10],$row[11]),
        'deleted' => $row[3],
        'created' => $row[4],
        'modified' => $row[5],
        'lastPlayedOn' => $row[6],
        'viewed' => $row[7],
        'favourite' => $row[8]
      }
	  }
  } else {
    $bylineAlpha = uc(substr $row[2], 0,1);
    if ($bylineAlpha !~ /[A-Z]/) {
      $bylineAlpha = "#";
    }
    push @data, {
      'ID' => $row[0],
      'title' => $row[1],
      'bylineAlpha' => $bylineAlpha,
      'byline' => $row[2],
      'filename' => ReturnFilename($row[10],$row[11]),
      'deleted' => $row[3],
      'created' => $row[4],
      'modified' => $row[5],
      'lastPlayedOn' => $row[6],
      'viewed' => $row[7],
      'favourite' => $row[8]
    }
  }
}
# Sort the data by bylineAlpha, byline, then title
my @sorted_data = sort {
  $a->{'bylineAlpha'} cmp $b->{'bylineAlpha'} || # use 'cmp' for strings
  $a->{'byline'} cmp $b->{'byline'} ||
  $a->{'title'} cmp $b->{'title'}
} @data;

my $current_anchor;
my $listOfLinks;

print ALA "<div id=\"mySidebar\" class=\"sidebar\"><button class=\"closebtn\" onclick=\"closeNav()\">Close</button><button class=\"hideButton\">Toggle deleted</button><ul>\n"; # make sidebar
foreach (@sorted_data) {
  if ($current_anchor ne $_->{'bylineAlpha'}) {
    print ALA "<li><a href=\"#".$_->{'bylineAlpha'}."\">".$_->{'bylineAlpha'}."</a></li>\n";
    $current_anchor = $_->{'bylineAlpha'};
  }
}
print ALA "<p>&nbsp;</p></div><div id=\"main\">\n";
$listOfLinks .= "<button class=\"openbtn\" onclick=\"sideNavClicked()\">Menu</button>\n";

foreach (@sorted_data) {
  $localCount++;
  my $filename;
  if ($current ne $_->{'byline'}) {
    if ($current ne "  ") {
      print ALA "</table>\n";
    }
    if ($current_anchor ne $_->{'bylineAlpha'}) { # add a new anchor
      print ALA $listOfLinks."\n";
      print ALA "<a name=\"".$_->{'bylineAlpha'}."\"></a>\n";
      $current_anchor = $_->{'bylineAlpha'};
    }
    if ($_->{'byline'}) {$display = $_->{'byline'}} else {$display = "None";}
    print ALA "<h1><button class=\"toggler\" id=\"b_A$_->{'byline'}\" onclick=\"toggle('A$_->{'byline'}')\">Show</button> Artist: $display</h1>\n<table class=data id=\"A$_->{'byline'}\" style=\"display:none;\">";
    print ALA "<tr><th>Song title</th><th width='30%'>Artist</th><th width='15%'>Dates</th><th width='10%'>Active</th></tr>\n";
    $current = $_->{'byline'};
    $artistCount++;
  }
  if ($_->{'deleted'}) {
    print ALA "<tr class=\"deleted\">";
  } else {
    print ALA "<tr class=\"active\">";
  }
  print ALA "<td title=\"ID: $_->{'ID'}\"><span class=".ReturnIcon($_->{'favourite'})." style=\"float:none\">&nbsp;</span>$_->{'title'}</td><td title=\"File: $_->{'filename'}\">$_->{'byline'}</td><td class=\"dateBox\">";
  # Dates
  if ($_->{'created'}) { print ALA "Created: ".FormatDateTime($_->{'created'})."<br />"}
  if ($_->{'modified'}) { print ALA "Modified: ".FormatDateTime($_->{'modified'})."<br />"}
  if ($_->{'lastPlayedOn'}) { print ALA "Last played: ".FormatDateTime($_->{'lastPlayedOn'})."<br />"}
  if ($_->{'viewed'}) { print ALA "Last viewed: ".FormatDateTime($_->{'viewed'})."<br />"}
  print ALA "</td>";
  # Active
  if ($_->{'deleted'}) {
    print ALA "<td><div class=\"cross\" title=\"Deleted song\">&nbsp;</div></td>";
  } else {
    print ALA "<td><div class=\"tick\" title=\"Active\">&nbsp;</div></td>";
  }
  print ALA "</tr>";
}
print ALA "</div>\n";
print ALA &HTMLFooter("All songs by artist (Songs: $localCount / Artists: $artistCount)");

# New page: Display all Books to one HTML file (All books)
open(BOOK, ">$books") or die $!;
print BOOK &HTMLHeader("All books", "true");
my $A3 = $dbh->prepare( qq(select A.ID, B.songID, C.title, C.byline, C.alpha from Collection A inner join CollectionSong B on A.ID = B.collectionID inner join Song C on B.songID = C.ID order by A.ID;) );
my $ra1 = $A3->execute() or die $DBI::errstr;
$current = "  ";
while(my @row = $A3->fetchrow_array()) {
  if ($current ne $row[0]) {
    if ($current ne "  ") {
      print BOOK "</table>\n";
    }
    print BOOK "<h1><button class=\"toggler\" id=\"b_A$row[0]\" onclick=\"toggle('A$row[0]')\">Show</button> Book: $row[0]</h1>\n<table class=data id=\"A$row[0]\" style=\"display:none;\">";
    print BOOK "<tr><th>Song title</th><th width='50%'>Artist</th></tr>\n";
    $current = $row[0];
  }
  print BOOK "<tr><td title=\"ID: $row[1]\">$row[2]</td><td title=\"ID: $row[1]\">$row[3]</td></tr>";
}
print BOOK &HTMLFooter("All books");

# New page: Display all media/images to one HTML file (All images as songs)
open(MEDI, ">$mediaAsSongs") or die $!;
print MEDI &HTMLHeader("All images as songs");
my $A4 = $dbh->prepare( qq(select ID, title, filename, type, created, modified, originalFilename from SongMedia;) );
my $ra2 = $A4->execute() or die $DBI::errstr;
print MEDI "<h1>All images as songs</h1>";
print MEDI "<table class=data >";
print MEDI "<tr><th>Song title</th><th>Internal file name</th><th>type</th><th>Created</th><th>Modified</th><th>Original file name</th></tr>\n";
while(my @row = $A4->fetchrow_array()) {
  print MEDI "<tr><td title=\"ID: $row[0]\">$row[1]</td><td title=\"ID: $row[0]\">$row[2]</td><td>$row[3]</td><td>".FormatDateTime($row[4])."</td><td>".FormatDateTime($row[5])."</td><td>$row[6]</td></tr>";
}
print MEDI &HTMLFooter("All images as songs");

# New page: Display all Sets to one HTML file (All sets)
open(SETS, ">$setLists") or die $!;
print SETS &HTMLHeader("All sets", "true");
my $A5 = $dbh->prepare( qq(select DISTINCT B.setID, B.songID, A.ID, A.title, A.created, A.modified, A.datetime, C.title, C.byline, A.quantity, C.favorite from SongSet A inner join SongSetItem B on A.ID = B.setID inner join Song C on B.SongID = C.ID order by A.orderIndex DESC, B.orderIndex;) );
my $ra3 = $A5->execute() or die $DBI::errstr;
$current = "  ";
while(my @row = $A5->fetchrow_array()) {
  if ($current ne $row[3]) {
    if ($current ne "  ") {
      print SETS "</table>\n";
    }
    # TODO: fix ' in $row[0] for JS, also in button id='...'
    print SETS "<h1><button class=\"toggler\" id=\"b_A$row[3]\" onclick=\"toggle('A$row[3]')\">Show</button> Set: $row[3] ($row[9] songs)<span>Created: ".FormatDate($row[4]).", Modified: ".FormatDate($row[5])."</span></h1>\n<table class=data id=\"A$row[3]\" style=\"display:none;\">";
    print SETS "<tr><th>Song title</th><th width='50%'>Artist</th></tr>\n";
    $current = $row[3];
  }
  my $icon = &ReturnIcon($row[10]);
  print SETS "<tr><td title=\"ID: $row[1]\"><span class='$icon'>&nbsp;</span>$row[7]</td><td title=\"ID: $row[1]\">$row[8]</td></tr>";
}
print SETS &HTMLFooter("All sets");

# New page: Display all deleted songs to one HTML file (All deleted songs)
open(DEL, ">$allDeletedSongs") or die $!;
open(DELT, ">$DelCmd") or die $!;
print DEL &HTMLHeader("All deleted songs", "true");
print DELT "# Use this file in the directory to remove deleted files\n#\n";
my $A6 = $dbh->prepare( qq(select ID, title, byline, content, deleted, filename, filepath, alpha, bylineAlpha, lastImportedOn, syncTimestamp, created, modified, lastPlayedOn, viewed from Song where deleted != '0' order by alpha, title;) );
my $rd1 = $A6->execute() or die $DBI::errstr;
$current = " ";
$localCount = 0;
while(my @row = $A6->fetchrow_array()) {
  $localCount++;
  my $filename;
  if ($current ne $row[7]) {
    if ($current ne " ") {
      print DEL "</table>\n";
    }
    print DEL "<h1><button class=\"toggler\" id=\"b_A$row[7]\" onclick=\"toggle('A$row[7]')\">Show</button> Song title: $row[7]</h1>\n<table class=data id=\"A$row[7]\" style=\"display:none;\">";
    print DEL "<tr><th>Song title</th><th width='20%'>Artist</th><th width='30%'>File</th><th width='15%'>Dates</th></tr>\n";
    $current = $row[7];
  }
  $filename = ReturnFilename($row[5],$row[6]);
  print DELT "rm \"$filename\"\n";
  print DEL "<tr><td title=\"ID: $row[0]\">$row[1]</td><td title=\"ID: $row[0]\">$row[2]</td><td>$filename</td><td class=\"dateBox\">";
  # Dates
  if ($row[11]) { print DEL "Created: ".FormatDateTime($row[11])."<br />"}
  if ($row[12]) { print DEL "Modified: ".FormatDateTime($row[12])."<br />"}
  if ($row[9])  { print DEL "Last imported: ".FormatDateTime($row[9])."<br />"}
  if ($row[10]) { print DEL "Last synced: ".FormatDateTime($row[10])."<br />"}
  if ($row[13]) { print DEL "Last played: ".FormatDateTime($row[13])."<br />"}
  if ($row[14]) { print DEL "Last viewed: ".FormatDateTime($row[14])."<br />"}
  print DEL "</td>";
  print DEL "</tr>";
}
print DEL &HTMLFooter("All deleted songs (Counted: $localCount)");
print DELT "\n # All deleted songs (Counted: $localCount)\n";

# ---- clean up ---- #

$dbh->disconnect();
my $zipFile = "./$currDir[-1]-complete-database-dump.zip";
if (-e $zipFile) {
  unlink $zipFile; # remove file if exists
}
$zip->addTree($coreDirectory);
$zip->writeToFileNamed($zipFile);

# End of program
