#!/usr/bin/perl

use DBI;
use strict;
use Cwd qw(cwd getcwd);
my @currDir = split('/',cwd);
# print $currDir[-1];
# print getcwd;
use Archive::Zip;
my $zip = Archive::Zip->new();

# ------ configuration ---- #
my $database = "OnSong.sqlite3";
my $userid = "";
my $password = "";
my $CoreDirectory = "./$currDir[-1]-database_dump/";
my $OutDirectory = $CoreDirectory."updated/";
my $DelDirectory = $CoreDirectory."marked_as_deleted/";
my $NoFilePath = $CoreDirectory."no-file-path/";
my $ReportPath = $CoreDirectory."html-reports/";
# Logging
my $Log = $CoreDirectory."_logfile.txt";
my $Fav = $ReportPath."favourite.html";
my $Top = $ReportPath."topics.html";
my $Vers = $ReportPath."version.html";
my $Chrd = $ReportPath."chords.html";
my $Allt = $ReportPath."all_songs_by_title.html";
my $Alld = $ReportPath."deleted_songs.html";
my $Alla = $ReportPath."all_songs_by_artist.html";
my $Book = $ReportPath."books.html";
my $Sets = $ReportPath."sets.html";
my $Medi = $ReportPath."songs_from_images.html";

# my $Dels = $ReportPath."deleted_songs.html";
# my $Actv = $ReportPath."active_songs.html";
# my $Unkn = $ReportPath."songs_with_unknown_status.html";

# ------ don't modify beneath this line -------- #

my $MatchFilesize;
my $NotMatchingFilesize;
my $PDFcount;
my $NonExist;
my $CountDel;
my $CountNondel;
my $AllFiles;
my $NotMatchingFilesizeDeleted;

#-----------------------------------------------------------
# format_seconds($seconds)
# Converts seconds into days, hours, minutes, seconds
# Returns an array in list context, else a string.
#-----------------------------------------------------------

sub FormatSeconds($) {
    my $tsecs = shift;
    use integer;
    my $secs  = $tsecs % 60;
    my $tmins = $tsecs / 60;
    my $mins  = $tmins % 60;
    my $thrs  = $tmins / 60;
    my $hrs   = $thrs  % 24;
    my $days  = $thrs  / 24;
    my $age = "";
    $age .= $days . "d " if $days || $age;
    $age .= $hrs  . "h " if $hrs  || $age;
    $age .= $mins . "m " if $mins || $age;
    $age .= $secs . "s " if $secs || $age;
    $age =~ s/ $//;
    return $age;
}

sub FormatDateTime($) {
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

sub FormatDate($) {
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

sub returnIcon($) {
  my $x = shift;
  my $icon = "icon_unknown";
  if ($x == "1"){ $icon = "icon_star"; }
  if ($x == "2"){ $icon = "icon_circle"; }
  if ($x == "3"){ $icon = "icon_arrow"; }
  if ($x == "9"){ $icon = "icon_flag"; }
  return $icon;
}

sub SwapOutSpaces($) {
	my $x = shift;
	$x =~ s/(\’|\'|\"|\;|\\|\/|,|\!|\@|\#|\$|\%|\^|\&|\*|\(|\))//gi; #remove these
  $x =~ s/\ -\ /-/gi; # Swap space em space for a single em (eg "file - tab.crd" to "file-tab.crd")
	$x =~ s/(\ |\?|\.)/_/gi; # replace with underscore
  $x =~ s/___/_/gi;
  $x =~ s/__/_/gi;
	return $x;
}

sub HTMLFooter($) {
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

sub HTMLHeader($) {
  my $text;
  my $x = shift;
  my $now = localtime();
  $text = <<EOF;
<html>
<head>
<title>$x generated $now</title>
<style>
body { font: 62.5%/1.5  "Lucida Grande", "Lucida Sans", Tahoma, Verdana, sans-serif; color: #000000; text-align:left; } .data { font-family: Arial, Helvetica, sans-serif; border-collapse: collapse; width: 100%; }
.data td, .data th { border: 1px solid #ddd; padding: 8px; }
.data tr:nth-child(even){ background-color: #f2f2f2; }
.data tr:hover { background-color: #ddd; }
.data th { padding-top: 12px; padding-bottom: 12px; text-align: left; background-color: #0000aa; color: white; }
h1 span { border: 1px solid #ddd; padding: 8px; margin-left: 10px; font-size: 0.5em; float: right; }
span.anchors { display:inline-block; margin 10px auto; width: 20px; font-size: 2em; }
.icon_arrow { float: right; height: 16px; width: 16px; margin: 0 auto; background-repeat: no-repeat; background-size: 16px 16px; padding: 0 10px;
  background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAArElEQVQ4jaWSMQvCMBCFv4g4Vafb/I0dRIqLVNRNRAr5hc7tIoLgoHGwkVRCU64PAgeX993LEUjIie3tT1IAYOHEbscAAI5ObBlrGCd2lkoA1G19ME2++09wA549pw7ul07sXvOEUB2IBtCBTJUAD3lpE3jNxwAqoNACKmBlmly1xJ8ZvktcJgwZcG3rC7D2ZgCTGufEZsAdOANFaIZh/+ANnGLmoYAHsImZAT6l+TOi5O4ddwAAAABJRU5ErkJggg==);}
.icon_unknown { float: right; height: 16px; width: 16px; margin: 0 auto; background-repeat: no-repeat; background-size: 16px 16px; padding: 0 10px; }
.icon_circle {float: right; height: 16px; width: 16px; margin: 0 auto; background-repeat: no-repeat; background-size: 16px 16px; padding: 0 10px;
  background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAAwElEQVQ4jaWTMQrCQBBFn0sKT+ABRFKIiHey8iQiwcJCxFN4ADGtpYWVnYWNpQg2Er5FDHETNyGb+Ww37+/M7gwUQ4SICHFCPL7njFghhqX8HzBALBBv5FSCWCO6/+BdBVjU3jYR8wZwpm0GD2rKrmpnbIApELgfxxkGmIE4etye6dJB3IGeRwUAL+MJWn1cW/A3A8QtDGIQ/RbfOEl90hH2HKTUoOkoH3DsQ1TTToLYlGHbKEQsydf5Sb7Oo2L6B9EZD8MS1RXbAAAAAElFTkSuQmCC);}
.icon_flag { float: right; height: 16px; width: 16px; margin: 0 auto; background-repeat: no-repeat; background-size: 16px 16px; padding: 0 10px;
  background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAAsUlEQVQ4je3SMWpCQRSF4U8RS0klgp1Yp05hXEFq95A9uAcLixSpLAIuIIsI2JjeTdiFIDkpfMpjigcGxCZ/dQ9zOHPn3gFhHvbhQUFoh2lYhk34DK9hBJ3KN0QPb2GBbaUfMVOZa9zjgOdOcTDCsuyiifYl5v+AKwWUa2xiiw98qX24MuAdE9xVeoc1Vq1jfSYM6uIlJDyFbhiH/p+e0OJbcVsTt9/CKeDgON2fSwN+Aa32KevyFMVlAAAAAElFTkSuQmCC);}
.icon_star { float: right; height: 16px; width: 16px; margin: 0 auto; background-repeat: no-repeat; background-size: 16px 16px; padding: 0 10px;
  background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAA/ElEQVQ4jaWSvUpDQRCFvxtEEgliZwprC5E8gXUKEVGCvodFnsAyiIhInsYiWFvoO1hYmCbgCUFyUmSVvZfsmuiBZYb5OTtndiEDi6bFTq6mlksCJ8Dpfwi6wMUvNcthsWUxtpDF9l8m6ABNoM5CytoE3YRfQmFxCVxFZN/2MNwOMAVegz+L7AMAFscW7xZe8XxYnJVGsWhZPK7QPLTYW6rHomZxnWnuW2zEPaUlFg1mwDC1MOCpaPCVJAhIbhw4rwaKqgTgDWgBn0APmAB3LP7ECNitThETHAWtLxYHUXzf4jnkOsn5LG4t7q2f949zmxY3FoMcQTuZTNTMAQgNrjte9swtAAAAAElFTkSuQmCC);}

.unknown { height: 32px; width: 32px; margin: 0 auto; background-repeat: no-repeat; background-size: 32px 32px; 
  background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAACXBIWXMAAAsTAAALEwEAmpwYAAAGxmlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgNi4wLWMwMDIgNzkuMTY0NDg4LCAyMDIwLzA3LzEwLTIyOjA2OjUzICAgICAgICAiPiA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPiA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIiB4bWxuczp4bXA9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iIHhtbG5zOnhtcE1NPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvbW0vIiB4bWxuczpzdEV2dD0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL3NUeXBlL1Jlc291cmNlRXZlbnQjIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgeG1wOkNyZWF0b3JUb29sPSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgeG1wOkNyZWF0ZURhdGU9IjIwMjItMDMtMTNUMDg6NDA6MDIrMDg6MDAiIHhtcDpNZXRhZGF0YURhdGU9IjIwMjItMDMtMTZUMTg6NTU6MDYrMDg6MDAiIHhtcDpNb2RpZnlEYXRlPSIyMDIyLTAzLTE2VDE4OjU1OjA2KzA4OjAwIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOmQwNmI1YjVjLWEzOGMtNDFmNS05NjUyLTU1OTZjYWVhNTYxMiIgeG1wTU06RG9jdW1lbnRJRD0iYWRvYmU6ZG9jaWQ6cGhvdG9zaG9wOjQyOWZmMmUyLTcxMjEtNjg0YS1iZGZjLTU3OGE5ODk3YjFjYyIgeG1wTU06T3JpZ2luYWxEb2N1bWVudElEPSJ4bXAuZGlkOjFjNzdiNWI0LTdhMTktNDE4OS1hYjQxLTYxMzMwNjU2MTdiZSIgZGM6Zm9ybWF0PSJpbWFnZS9wbmciIHBob3Rvc2hvcDpDb2xvck1vZGU9IjMiIHBob3Rvc2hvcDpJQ0NQcm9maWxlPSJzUkdCIElFQzYxOTY2LTIuMSI+IDx4bXBNTTpIaXN0b3J5PiA8cmRmOlNlcT4gPHJkZjpsaSBzdEV2dDphY3Rpb249ImNyZWF0ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6MWM3N2I1YjQtN2ExOS00MTg5LWFiNDEtNjEzMzA2NTYxN2JlIiBzdEV2dDp3aGVuPSIyMDIyLTAzLTEzVDA4OjQwOjAyKzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIvPiA8cmRmOmxpIHN0RXZ0OmFjdGlvbj0ic2F2ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6ODk0OWZiNTAtMzFmZS00MDAwLWJkMjctNWMxYjAzZjkwZjA3IiBzdEV2dDp3aGVuPSIyMDIyLTAzLTEzVDA4OjQwOjAyKzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgc3RFdnQ6Y2hhbmdlZD0iLyIvPiA8cmRmOmxpIHN0RXZ0OmFjdGlvbj0ic2F2ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6ZDA2YjViNWMtYTM4Yy00MWY1LTk2NTItNTU5NmNhZWE1NjEyIiBzdEV2dDp3aGVuPSIyMDIyLTAzLTE2VDE4OjU1OjA2KzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgc3RFdnQ6Y2hhbmdlZD0iLyIvPiA8L3JkZjpTZXE+IDwveG1wTU06SGlzdG9yeT4gPC9yZGY6RGVzY3JpcHRpb24+IDwvcmRmOlJERj4gPC94OnhtcG1ldGE+IDw/eHBhY2tldCBlbmQ9InIiPz7H2+FN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);}

.cross { height: 32px; width: 32px; margin: 0 auto; background-repeat: no-repeat; background-size: 32px 32px; 
  background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAACXBIWXMAAAsTAAALEwEAmpwYAAAGxmlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgNi4wLWMwMDIgNzkuMTY0NDg4LCAyMDIwLzA3LzEwLTIyOjA2OjUzICAgICAgICAiPiA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPiA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIiB4bWxuczp4bXA9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iIHhtbG5zOnhtcE1NPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvbW0vIiB4bWxuczpzdEV2dD0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL3NUeXBlL1Jlc291cmNlRXZlbnQjIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgeG1wOkNyZWF0b3JUb29sPSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgeG1wOkNyZWF0ZURhdGU9IjIwMjItMDMtMTNUMDg6NDE6MzQrMDg6MDAiIHhtcDpNZXRhZGF0YURhdGU9IjIwMjItMDMtMTZUMTg6NTU6MDQrMDg6MDAiIHhtcDpNb2RpZnlEYXRlPSIyMDIyLTAzLTE2VDE4OjU1OjA0KzA4OjAwIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOmYyOTM5MjM0LTlmMTUtNDA4MC1iNWNkLTkwZjNlZTJiOWQ2NCIgeG1wTU06RG9jdW1lbnRJRD0iYWRvYmU6ZG9jaWQ6cGhvdG9zaG9wOjIyMDgzMDBhLTBhMWYtZWQ0ZS1iODVmLTVjMjUzMDQ0YTlmMCIgeG1wTU06T3JpZ2luYWxEb2N1bWVudElEPSJ4bXAuZGlkOjllYWI4NTNjLTI5MmUtNGI2OS05ZDNhLTFkOWE1MzMxNWI4MiIgZGM6Zm9ybWF0PSJpbWFnZS9wbmciIHBob3Rvc2hvcDpDb2xvck1vZGU9IjMiIHBob3Rvc2hvcDpJQ0NQcm9maWxlPSJzUkdCIElFQzYxOTY2LTIuMSI+IDx4bXBNTTpIaXN0b3J5PiA8cmRmOlNlcT4gPHJkZjpsaSBzdEV2dDphY3Rpb249ImNyZWF0ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6OWVhYjg1M2MtMjkyZS00YjY5LTlkM2EtMWQ5YTUzMzE1YjgyIiBzdEV2dDp3aGVuPSIyMDIyLTAzLTEzVDA4OjQxOjM0KzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIvPiA8cmRmOmxpIHN0RXZ0OmFjdGlvbj0ic2F2ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6MGYyMDI2MTYtMzg2MS00MTg1LThiMjUtY2VkZTcyMWUxYzFlIiBzdEV2dDp3aGVuPSIyMDIyLTAzLTEzVDA4OjQxOjM0KzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgc3RFdnQ6Y2hhbmdlZD0iLyIvPiA8cmRmOmxpIHN0RXZ0OmFjdGlvbj0ic2F2ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6ZjI5MzkyMzQtOWYxNS00MDgwLWI1Y2QtOTBmM2VlMmI5ZDY0IiBzdEV2dDp3aGVuPSIyMDIyLTAzLTE2VDE4OjU1OjA0KzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgc3RFdnQ6Y2hhbmdlZD0iLyIvPiA8L3JkZjpTZXE+IDwveG1wTU06SGlzdG9yeT4gPC9yZGY6RGVzY3JpcHRpb24+IDwvcmRmOlJERj4gPC94OnhtcG1ldGE+IDw/eHBhY2tldCBlbmQ9InIiPz73xUgR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);}

.tick { height: 32px; width: 32px; margin: 0 auto; background-repeat: no-repeat; background-size: 32px 32px; 
  background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAACXBIWXMAAAsTAAALEwEAmpwYAAAGxmlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgNi4wLWMwMDIgNzkuMTY0NDg4LCAyMDIwLzA3LzEwLTIyOjA2OjUzICAgICAgICAiPiA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPiA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIiB4bWxuczp4bXA9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iIHhtbG5zOnhtcE1NPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvbW0vIiB4bWxuczpzdEV2dD0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL3NUeXBlL1Jlc291cmNlRXZlbnQjIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgeG1wOkNyZWF0b3JUb29sPSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgeG1wOkNyZWF0ZURhdGU9IjIwMjItMDMtMTNUMDg6Mzg6MjcrMDg6MDAiIHhtcDpNZXRhZGF0YURhdGU9IjIwMjItMDMtMTZUMTg6NTU6MDIrMDg6MDAiIHhtcDpNb2RpZnlEYXRlPSIyMDIyLTAzLTE2VDE4OjU1OjAyKzA4OjAwIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOjJjNTVhOTI4LWI2YWUtNDgzYi05NGQ2LWIzOTAyYjM2MjRhMCIgeG1wTU06RG9jdW1lbnRJRD0iYWRvYmU6ZG9jaWQ6cGhvdG9zaG9wOmM3MGIzODljLWY5ZTUtYmM0OC1iOTQ5LTNhNjU3Y2Q3Mjg0NiIgeG1wTU06T3JpZ2luYWxEb2N1bWVudElEPSJ4bXAuZGlkOmEwYjRjOThjLTQ3ZjMtNDEwNi05NTZmLTQxZmIzMGEyMzhhZiIgZGM6Zm9ybWF0PSJpbWFnZS9wbmciIHBob3Rvc2hvcDpDb2xvck1vZGU9IjMiIHBob3Rvc2hvcDpJQ0NQcm9maWxlPSJzUkdCIElFQzYxOTY2LTIuMSI+IDx4bXBNTTpIaXN0b3J5PiA8cmRmOlNlcT4gPHJkZjpsaSBzdEV2dDphY3Rpb249ImNyZWF0ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6YTBiNGM5OGMtNDdmMy00MTA2LTk1NmYtNDFmYjMwYTIzOGFmIiBzdEV2dDp3aGVuPSIyMDIyLTAzLTEzVDA4OjM4OjI3KzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIvPiA8cmRmOmxpIHN0RXZ0OmFjdGlvbj0ic2F2ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6YjZlZTU0MTUtNTk4Ni00OGNmLTlkOGItYjc1ODBhNDllOWI5IiBzdEV2dDp3aGVuPSIyMDIyLTAzLTEzVDA4OjM4OjI3KzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgc3RFdnQ6Y2hhbmdlZD0iLyIvPiA8cmRmOmxpIHN0RXZ0OmFjdGlvbj0ic2F2ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6MmM1NWE5MjgtYjZhZS00ODNiLTk0ZDYtYjM5MDJiMzYyNGEwIiBzdEV2dDp3aGVuPSIyMDIyLTAzLTE2VDE4OjU1OjAyKzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjIuMCAoTWFjaW50b3NoKSIgc3RFdnQ6Y2hhbmdlZD0iLyIvPiA8L3JkZjpTZXE+IDwveG1wTU06SGlzdG9yeT4gPC9yZGY6RGVzY3JpcHRpb24+IDwvcmRmOlJERj4gPC94OnhtcG1ldGE+IDw/eHBhY2tldCBlbmQ9InIiPz4wcxmc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)
}
td.red { background-color: red; opacity: 0.5; }
td.yellow { background-color: yellow; opacity: 0.5; }
button.toggler { width: 70px; }
#footer { width: 100%; border: 1px solid #aaa; background: #eee; margin-top: 40px; }
#footer p { padding: 10px 0 0 10px; }
#header { width: 100%; border: 4px solid #000; background: #00f; }
#header p { font-size: 4em; text-align: center; color: white; }
.dateBox { font-size: 0.6em; }
.hidden-class { display: none; }
.show-class { display: inline; }
</style>
<script>
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
<div id=header><p>OnSong database details - $x</p></div>
EOF
return $text;
}

if (! -d $CoreDirectory) { mkdir $CoreDirectory or die $!; }
open(LOG, ">$Log") or die $!;
if (! -d $OutDirectory) { mkdir $OutDirectory or die $!; print LOG "made $OutDirectory\n"; }
if (! -d $DelDirectory) { mkdir $DelDirectory or die $!; print LOG "made $DelDirectory\n"; }
if (! -d $NoFilePath) { mkdir $NoFilePath or die $!; print LOG "made $NoFilePath\n"; }
if (! -d $ReportPath) { mkdir $ReportPath or die $!; print LOG "made $ReportPath\n"; }

my $driver = "SQLite";
my $dsn = "DBI:$driver:dbname=$database";
my $dbh = DBI->connect($dsn, $userid, $password, { RaiseError => 1 })
   or die $DBI::errstr;

# Count database files and local files and print to log
my $count_nondeleted = $dbh->prepare( qq(select count (*) from Song where deleted != '1';) );
my $count_deleted = $dbh->prepare( qq(select count (*) from Song where deleted = '1';) );
my $content = $dbh->prepare( qq(select filepath, content, deleted, modified, created, viewed, syncTimestamp, lastImportedOn, ID, filename, byline, title from Song;) );
my $rv1 = $count_nondeleted->execute() or die $DBI::errstr;
while(my @row = $count_nondeleted->fetchrow_array()) { print LOG "\nDatabase count of active files: ".$row[0]."\n"; }
my $rv2 = $count_deleted->execute() or die $DBI::errstr;
while(my @row = $count_deleted->fetchrow_array()) { print LOG "Database count of deleted files: ".$row[0]."\n"; }
my $rv3 = $content->execute() or die $DBI::errstr;
if ($^O ne 'MSWin32') {
  my $localcount = `ls -1 | wc -l | sed 's/^ *//g'`;
  print LOG "Local file count: ".$localcount."\n";
} else {
  print LOG "#TODO: Fix for Windows";
}

while(my @row = $content->fetchrow_array()) {
  my $folder;
  my $Deleted;
  my $filename;
  # set the folder to write to:
  if ($row[2] == "1") { # deleted == 1
    $folder = $DelDirectory;
    $CountDel++;
    $Deleted = "true";
  } else {
    $folder = $OutDirectory;
    $CountNondel++;
  }

  # fix filename or filepath
  if ($row[9]) {
    $filename = $row[9];
  } else {
    $filename = $row[0];
  }

  # Check if file already exists
  if (-e $filename) { # filename
    my $size = -s $filename;
    # Check if the size of the database content is the same as the file on disk
    if (length($row[1]) eq $size) {
      $MatchFilesize++;
      #print LOG "MATCH [$MatchFilesize] File '$filename' matches file size\n";
      $AllFiles++;
    } else {
      if ($filename =~ /crd$/) {
        if ($Deleted) {
          $NotMatchingFilesizeDeleted++;
        } else {
          $NotMatchingFilesize++;
        } 
        print LOG "CREATE [$NotMatchingFilesize] File <$folder$filename> doesnt match file size, creating\n";
        $AllFiles++;
        # Create a new file with the database content, plus the original file for comparison
        open(FH, '>', $folder.$filename) or die $!;
        print FH $row[1];
        print FH "\n\n";
        print FH "##########################################################################\n";
        if ($Deleted) {
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
        print FH "# Original file is below ....\n";
        print FH "##########################################################################\n";

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
        close(FH); 
      } else {
        $PDFcount++;
        print LOG "PDF   [$PDFcount] File '$filename' is a non-crd file\n";
      }
    }
  } else { # if we get here, we couldn't get a filename from the DB
    if ($Deleted) {
#      print "file $filename does not exist and deleted\n";
      $filename = SwapOutSpaces($row[10]."-".$row[11]).".crd";
      print LOG "DEL    [File '$filename' does not exist and is marked deleted\n";
    } else {
      $folder = $NoFilePath;
      # print "file $filename does not exist not deleted\n";
      $filename = SwapOutSpaces($row[10]."-".$row[11]).".crd";
      $NonExist++;
      print LOG "???    [$NonExist] File '$filename' does not exist and is not marked deleted - making a newbie\n";
      $AllFiles++;
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
print "CountDel: $CountDel CountNondel: $CountNondel\n";
print "File exists and matchs the size: $MatchFilesize\n";
print "File exists, but doesn't match the filesize (potentially modified?): $NotMatchingFilesize\n";
print "File doesn't exist (potentially deleted?): $NotMatchingFilesizeDeleted\n";
print "File is a PDF or other type of file: $PDFcount\n";
print "Allfiles: $AllFiles\n";
print "File didn't exist: $NonExist\n";

# import instruments as hash reference
my %polyphony;
my $H1 = $dbh->prepare( qq(select ID, polyphony from SongInstrument;) );
my $aa4 = $H1->execute() or die $DBI::errstr;
while(my @row = $H1->fetchrow_array()) {
  $polyphony{$row[0]} = $row[1];
}

# Report on favs
open(FAV, ">$Fav") or die $!;
print FAV &HTMLHeader("Favourites");
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
    $icon= &returnIcon($row[0]);
    print FAV "<h1><button class=\"toggler\" id=\"b_L$row[0]\" onclick=\"toggle('L$row[0]')\">Show</button> Level $row[0] <div class=$icon>&nbsp;</div></h1>\n<table class=data id=\"L$row[0]\" style=\"display:none;\">";
    print FAV "<tr><th>Song</th><th>Artist</th></tr>\n";
  }
  if ($row[5]) {
    $filename = $row[5];
  } else {
    $filename = $row[4];
  }
  if (!$filename) { $filename = "unknown"; }
  # <td>$row[1]</td>
  print FAV "<tr><td title=\"ID: $row[1]\"><div class=$icon style=\"float:left;\">&nbsp;</div>$row[2]</td><td title=\"File: $filename\">$row[3]</td></tr>"; #add dates
  $current = $row[0];
}
print FAV &HTMLFooter("Favourites");

# Create Topic page
open(TOP, ">$Top") or die $!;
print TOP &HTMLHeader("Topics");
print TOP "<h1>Topics</h1>\n<table class=data>";
print TOP "<tr><th>Topic</th><th>Date created</th><th>Date modified</th></tr>\n";
my $T1 = $dbh->prepare(qq(select * from Topic order by topic;));
my $rv5 = $T1->execute() or die $DBI::errstr;
while(my @row = $T1->fetchrow_array()) {
  print TOP "<tr><td title=\"ID: $row[0]\">$row[1]</td><td title=\"ID: $row[0]\">".FormatDateTime($row[2])."</td><td>".FormatDateTime($row[3])."</td></tr>";
}
print TOP &HTMLFooter("Topics");

# Create Version page
open(VER, ">$Vers") or die $!;
print VER &HTMLHeader("Version");
print VER "<h1>Version</h1>\n<table class=data>";
print VER "<tr><th>Version</th><th>Updated</th><th>Model</th><th>OS</th><th>UDID</th></tr>\n";
my $T2 = $dbh->prepare(qq(select * from version;));
my $rv6 = $T2->execute() or die $DBI::errstr;
while(my @row = $T2->fetchrow_array()) {
  print VER "<tr><td>$row[0]</td><td>".FormatDateTime($row[1])."</td><td>$row[2]</td><td>$row[3]</td><td>$row[4]</td></tr>";
}
print VER &HTMLFooter("Version");

# Report on Chords
open(CRD, ">$Chrd") or die $!;
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
    print CRD "<tr><th>Name * Alias</th><th>Tab</th><th>Fingering</th><th>Priority</th><th>Custom</th></tr>\n";
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

# Display all songs by title to one HTML file:
open(ALL, ">$Allt") or die $!;
print ALL &HTMLHeader("All songs by title");
print ALL "<button class=\"hideButton\">Toggle deleted</button>";
my $A1 = $dbh->prepare( qq(select ID, title, byline, content, deleted, filename, filepath, alpha, bylineAlpha, lastImportedOn, syncTimestamp, created, modified, lastPlayedOn, viewed, duration, favorite from Song order by alpha, title;) );
my $rv8 = $A1->execute() or die $DBI::errstr;
$current = " ";
my $localCount;
while(my @row = $A1->fetchrow_array()) {
  $localCount++;
  my $filename;
  if ($current ne $row[7]) {
    if ($current ne " ") {
      print ALL "</table>\n";
    }
    print ALL "<h1><button class=\"toggler\" id=\"b_A$row[7]\" onclick=\"toggle('A$row[7]')\">Show</button> Song title: $row[7]</h1>\n<table class=data id=\"A$row[7]\" style=\"display:none;\">";
    print ALL "<tr><th>Song title</th><th>Artist</th><th>Dates</th><th>Active</th></tr>\n";
    $current = $row[7];
  }
  if ($row[5]) {
    $filename = $row[5];
  } else {
    $filename = $row[6];
  }
  if (!$filename) { $filename = "unknown"; }
  # <td>$row[1]</td>
    if ($row[4]) { print ALL "<tr class=\"deleted\">"; } else { print ALL "<tr class=\"active\">"; }
  print ALL "<td title=\"ID: $row[0]\"><span class=".returnIcon($row[16])." style=\"float:none\">&nbsp;</span>".$row[1];
  if ($row[15]) { print ALL " (".FormatSeconds($row[15]).")"; }
  print ALL "</td><td title=\"File: $filename\">$row[2]</td><td class=\"dateBox\">";
  # Dates
  if ($row[11]) { print ALL "Created: ".FormatDateTime($row[11])."<br />"}
  if ($row[12]) { print ALL "Modified: ".FormatDateTime($row[12])."<br />"}
  if ($row[9]) { print ALL "Last imported: ".FormatDateTime($row[9])."<br />"}
  if ($row[10]) { print ALL "Last synced: ".FormatDateTime($row[10])."<br />"}
  if ($row[13]) { print ALL "Last played: ".FormatDateTime($row[13])."<br />"}
  if ($row[14]) { print ALL "Last viewed: ".FormatDateTime($row[14])."<br />"}
  print ALL "</td>";
  # Active
  if ($row[4]) {
    print ALL "<td><div class=\"cross\" title=\"Deleted song\">&nbsp;</div></td>";
  } else {
    print ALL "<td><div class=\"tick\" title=\"Active\">&nbsp;</div></td>";
  }
  print ALL "</tr>";
}
print ALL &HTMLFooter("All songs by title (Counted: $localCount)");

# Display all songs by artist to one HTML file:
open(ALA, ">$Alla") or die $!;
print ALA &HTMLHeader("All songs by artist");
my $A2 = $dbh->prepare( qq(select ID, title, byline, deleted, created, modified, lastPlayedOn, viewed, favorite from Song;) );
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

foreach (@sorted_data) {
  if ($current_anchor ne $_->{'bylineAlpha'}) {
    # next if $_->{'bylineAlpha'} == "#";
    $listOfLinks .= "<span class=\"anchors\"><a href=\"#".$_->{'bylineAlpha'}."\">".$_->{'bylineAlpha'}."</a></span>";
    $current_anchor = $_->{'bylineAlpha'};
  }
}

$listOfLinks .= "<button class=\"hideButton\">Toggle deleted</button>";

foreach (@sorted_data) {
  #print "-->".$_->{'bylineAlpha'}." - ".$_->{'byline'}." - ".$_->{'title'}."\n";
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
    print ALA "<tr><th>Song title</th><th>Artist</th><th>Dates</th><th>Active</th></tr>\n";
    $current = $_->{'byline'};
    $artistCount++;
  }
  if ($_->{'deleted'}) {
    print ALA "<tr class=\"deleted\">";
  } else {
    print ALA "<tr class=\"active\">";
  }
  print ALA "<td title=\"ID: $_->{'ID'}\"><span class=".returnIcon($_->{'favourite'})." style=\"float:none\">&nbsp;</span>$_->{'title'}</td><td title=\"ID: $_->{'ID'}\">$_->{'byline'}</td><td class=\"dateBox\">";
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
print ALA &HTMLFooter("All songs by artist (Songs: $localCount / Artists: $artistCount)");

# Display all Books to one HTML file:
#TODO: add favourite icons
open(BOOK, ">$Book") or die $!;
print BOOK &HTMLHeader("All books");
my $A3 = $dbh->prepare( qq(select A.ID, B.songID, C.title, C.byline, C.alpha from Collection A inner join CollectionSong B on A.ID = B.collectionID inner join Song C on B.songID = C.ID;) );
my $ra1 = $A3->execute() or die $DBI::errstr;
$current = "  ";
while(my @row = $A3->fetchrow_array()) {
  if ($current ne $row[0]) {
    if ($current ne "  ") {
      print BOOK "</table>\n";
    }
    print BOOK "<h1><button class=\"toggler\" id=\"b_A$row[0]\" onclick=\"toggle('A$row[0]')\">Show</button> Book: $row[0]</h1>\n<table class=data id=\"A$row[0]\" style=\"display:none;\">";
    print BOOK "<tr><th>Song title</th><th>Artist</th></tr>\n";
    $current = $row[0];
  }
  print BOOK "<tr><td title=\"ID: $row[1]\">$row[2]</td><td title=\"ID: $row[1]\">$row[3]</td></tr>";
}
print BOOK &HTMLFooter("All books");

# Display all Media (images) to one HTML file:
open(MEDI, ">$Medi") or die $!;
print MEDI &HTMLHeader("All songs as images");
my $A4 = $dbh->prepare( qq(select ID, title, filename, type, created, modified, originalFilename from SongMedia;) );
my $ra2 = $A4->execute() or die $DBI::errstr;
print MEDI "<h1>All songs as images</h1>";
print MEDI "<table class=data >";
print MEDI "<tr><th>Song title</th><th>Internal file name</th><th>type</th><th>Created</th><th>Modified</th><th>Original file name</th></tr>\n";
while(my @row = $A4->fetchrow_array()) {
  print MEDI "<tr><td title=\"ID: $row[0]\">$row[1]</td><td title=\"ID: $row[0]\">$row[2]</td><td>$row[3]</td><td>".FormatDateTime($row[4])."</td><td>".FormatDateTime($row[5])."</td><td>$row[6]</td></tr>";
}
print MEDI &HTMLFooter("All songs as images");

# Display all Sets to one HTML file:
#TODO: add favourite icons
open(SETS, ">$Sets") or die $!;
print SETS &HTMLHeader("All sets");
my $A5 = $dbh->prepare( qq(select DISTINCT B.setID, B.songID, A.ID, A.title, A.created, A.modified, A.datetime, C.title, C.byline, A.quantity from SongSet A inner join SongSetItem B on A.ID = B.setID inner join Song C on B.SongID = C.ID order by A.orderIndex DESC, B.orderIndex;) );
my $ra3 = $A5->execute() or die $DBI::errstr;
$current = "  ";
while(my @row = $A5->fetchrow_array()) {
  if ($current ne $row[3]) {
    if ($current ne "  ") {
      print SETS "</table>\n";
    }
    print SETS "<h1><button class=\"toggler\" id=\"b_A$row[3]\" onclick=\"toggle('A$row[3]')\">Show</button> Set: $row[3] ($row[9] songs)<span>Created: ".FormatDate($row[4]).", Modified: ".FormatDate($row[5])."</span></h1>\n<table class=data id=\"A$row[3]\" style=\"display:none;\">";
    print SETS "<tr><th>Song title</th><th>Artist</th></tr>\n";
    $current = $row[3];
  }
  print SETS "<tr><td title=\"ID: $row[1]\">$row[7]</td><td title=\"ID: $row[1]\">$row[8]</td></tr>";
}
print SETS &HTMLFooter("All sets");

# Display all deleted songs to one HTML file:
#TODO: add favourite icons
open(DEL, ">$Alld") or die $!;
print DEL &HTMLHeader("All deleted songs");
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
    print DEL "<tr><th>Song title</th><th>Artist</th><th>File</th><th>Dates</th></tr>\n";
    $current = $row[7];
  }
  if ($row[5]) {
    $filename = $row[5];
  } else {
    $filename = $row[6];
  }
  if (!$filename) { $filename = "unknown"; }
  # <td>$row[1]</td>
  print DEL "<tr><td title=\"ID: $row[0]\">$row[1]</td><td title=\"ID: $row[0]\">$row[2]</td><td>$filename</td><td class=\"dateBox\">";
  # Dates
  if ($row[11]) { print DEL "Created: ".FormatDateTime($row[11])."<br />"}
  if ($row[12]) { print DEL "Modified: ".FormatDateTime($row[12])."<br />"}
  if ($row[9]) { print DEL "Last imported: ".FormatDateTime($row[9])."<br />"}
  if ($row[10]) { print DEL "Last synced: ".FormatDateTime($row[10])."<br />"}
  if ($row[13]) { print DEL "Last played: ".FormatDateTime($row[13])."<br />"}
  if ($row[14]) { print DEL "Last viewed: ".FormatDateTime($row[14])."<br />"}
  print DEL "</td>";
  print DEL "</tr>";
}
print DEL &HTMLFooter("All deleted songs (Counted: $localCount)");









$dbh->disconnect();

if (-e "./$currDir[-1]-database_dump.zip") {
  unlink "./$currDir[-1]-database_dump.zip"; # remove file if exists
}
$zip->addTree( $CoreDirectory );
$zip->writeToFileNamed("./$currDir[-1]-database_dump.zip");

