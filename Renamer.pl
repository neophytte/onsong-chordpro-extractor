#!/usr/bin/perl
use strict;
my $DIAG = 0;
my $count = my $SrcDircount = my $countPDF = my $countTXT = my $countSGB = my $countREG = my $countFIX = my $FixedEntities = 0;
my $LastLine = "# This song was fixed #";
my ($day, $month, $year)=(localtime)[3,4,5];
my $fixed = sprintf("# Fixed on %04d-%02d-%02d #",$year+1900,($month)+1,$day);
my $FileNameCount = 1;

my $RenameAll = 0; # Set this to rename all files 

my $OnSongFix = 0; # Adds key as first [], adds default tempo, adds default time measure, add default duration 
my $TitleLine = 0;
## ^^ this bit is broken, don't use ... 
my $DefaultTempo = "{tempo: 120}";
my $DefaultKey = "{key:C}";
my $DefaultTime = "{time: 4/4}";
my $DefaultDuration = "{duration: 3:30}";

my $RemoveTheFromStart = 1;
my $RemoveThe = 1;
my $RemoveAnd = 0;
my $RemoveA = 0;

my $ArtistFirst = 1;

my $IncludeYear = 1;
my $IncludeKey = 1;
my $IncludeNotes = 1;

my $SwapEntities = 1;

my $SrcExt = "crd";
my $OutExt = "crd";
my $SrcDir = '';

# Win32
# [HKEY_CURRENT_USER\SOFTWARE\Ten by Ten\Songsheet Generator]
# "Songs Path"="C:\Users\[[USER]]\iCloudDrive\Songsheet Generator Songs"
# Mac
# ~/Library/Application Support/ChordMaestro/dev/config/Preferences/org/openide/filesystems/nb.properties
#org.netbeans.modules.openfile.OpenFileAction=~/Library/Mobile Documents/com~apple~CloudDocs/Songsheet Generator Songs

my $OS = $^O;

if (($DIAG) && ($OS eq "MSWin32")) { print "Windows"; }
if (($DIAG) && ($OS eq "Darwin")) { print "Mac OSX"; }
# Dir based on OS:
if ($OS eq "MSWin32") { $SrcDir = "C:\\Users\\[[USER]]\\iCloudDrive\\Songsheet Generator Songs"; }
if ($OS eq "Darwin")  { $SrcDir = "/Library/Mobile Documents/com~apple~CloudDocs/Songsheet Generator Songs";}
if ($SrcDir eq '') {
	print "Sorry, I don't know your OS [".$OS."]... :(";
	die;
}

if ($DIAG) { print $SrcDir."\n"; }
opendir(DIR, $SrcDir) or die $!;
while (my $file = readdir(DIR)) {
	$SrcDircount++;
	my $i = 0;
	next if ($file =~ m/^\./); # skip any dot files
	if ($file =~ m/pdf$/i) { $countPDF++; }
	if ($file =~ m/txt$/i) { $countTXT++; }
	if ($file =~ m/sgb$/i) { $countSGB++; }
	if ($file =~ m/reg$/i) { $countREG++; }
	if ($file =~ m/$SrcExt$/) { # select any [.crd] [matching file extension] files
		$count++;
		if ($DIAG) { print "[".$count."] Working on: ".$file."\n"; }
		open(FILE, "<$file") or die $!;
		#print "Length: ".length( $file )."\n";
		my $StartLength = 0;
		my $Str = my $Art = my $Tit = '';
		my @Lines = '';
		while (<FILE>) {
			chomp;
			$StartLength += length( $_ );
			$i++; # Line index
			if ($_ =~ m/^\{/) {
				if ($_ =~ m/^\{artist:/i)                  { if ($RemoveTheFromStart) {RemoveThe($_);$_ =~ s/(:\ the\ |:the\ )/:/i;}; $Art .= DataClense($_); }
				if ($_ =~ m/(^\{t:|^\{title:)/i)           { if ($RemoveTheFromStart) {RemoveThe($_);$_ =~ s/(:\ the\ |:the\ )/:/i;}; $Tit .= DataClense($_); $TitleLine = $i; }
				if ($_ =~ m/(^\{st:|^\{subtitle:)/i)       {
					if ($Art) { # If there is an Artist, this is a true subtitle
						$Tit .= DataClense($_);
					} else { # If there is no Artist, it's likely the Artist
						if ($RemoveTheFromStart) {RemoveThe($_);$_ =~ s/(:\ the\ |:the\ )/:/i;}
						$Art .= DataClense($_);
						$_ =~ s/(st:|subtitle:)/artist:/; # Fix it in-line too
					}
				}
				if (($_ =~ m/^\{key:/i) && $IncludeKey)    { $Str .= DataClense($_); }
				if (($_ =~ m/^\{year:/i) && $IncludeYear)  { $Str .= DataClense($_); }
# TODO: sort new varibles
				if (($_ =~ m/^\{composer:/i) && $IncludeYear)  { $Str .= DataClense($_); }
				if (($_ =~ m/^\{lyricist:/i) && $IncludeYear)  { $Str .= DataClense($_); }
				if (($_ =~ m/^\{copyright:/i) && $IncludeYear)  { $Str .= DataClense($_); }
				if (($_ =~ m/^\{album:/i) && $IncludeYear)  { $Str .= DataClense($_); }
				if (($_ =~ m/^\{time:/i) && $IncludeYear)  { $Str .= DataClense($_); }
				if (($_ =~ m/^\{tempo:/i) && $IncludeYear)  { $Str .= DataClense($_); }
				if (($_ =~ m/^\{duration:/i) && $IncludeYear)  { $Str .= DataClense($_); }
				if (($_ =~ m/^\{capo:/i) && $IncludeYear)  { $Str .= DataClense($_); }
				if (($_ =~ m/^\{meta:/i) && $IncludeYear)  { $Str .= DataClense($_); }
			}
			if ($SwapEntities) {
				if ($_ =~ m/^\{/) {
					$_ = &Swap($_);
					if ($DIAG) { print "#"; }
				}
				push @Lines, $_;
				if ($DIAG) { print "."; }
			}
		}
		my $EndLength = 0;
		if ($OnSongFix) {
			# Fix random things for OnSong to work correctly
			my $FixTempo = 1;
			my $FixKey = 1;
			my $FixTime = 1;
			my $FixDuration = 1;
			my $MyKey = '';
			my $KeyContinue = 1;
			# Check where the 'title' tag exists - this is my marker
			# cycle through text - see whether the keys are already existing:
			foreach my $Line (@Lines) { 
				if ($Line =~ m/^\{tempo:/)   { $FixTempo = 0; if ($DIAG) { print "Not fixing Tempo ..."; }}
				if ($Line =~ m/^\{key:/)     { $FixKey = 0; if ($DIAG) { print "Not fixing Key ..."; } }
				if ($Line =~ m/^\{time:/)    { $FixTime = 0; if ($DIAG) { print "Not fixing Time sig ..."; } }
				if ($Line =~ m/^\{duration:/){ $FixDuration = 0; if ($DIAG) { print "Not fixing Duration ..."; } }
				if (($Line =~ m/\[/) && ($KeyContinue)){ 
					(undef,$MyKey,undef) = split /[\[\]]+/,$Line,3; 
					$DefaultKey = "{key:".$MyKey."}";
					$KeyContinue=0;
					if ($DIAG) { print "Key is now: ".$DefaultKey; }
				}
			}
			# determine which are not available and insert as required
			if ($FixTempo)   { splice @Lines, $TitleLine+1, 0, $DefaultTempo; } 
			if ($FixKey)     { splice @Lines, $TitleLine+1, 0, $DefaultKey; }
			if ($FixTime)    { splice @Lines, $TitleLine+1, 0, $DefaultTime; }
			if ($FixDuration){ splice @Lines, $TitleLine+1, 0, $DefaultDuration; }
		}
		
		foreach (@Lines) { $EndLength += length($_); } # Find total size of ending file
		if ($DIAG) { print "Length: ".$StartLength." to ".$EndLength." - file:".$file."\n"; } # Compare start size and end size to see if there were any changes
		if ((($SwapEntities) && ($EndLength > $StartLength))) {
			$FixedEntities++;
			close (FILE);
			print "[Fixing] $file\n";
			open(FILE, ">$file") or die $!;
			if ($DIAG) { print "Length of array: ".$#Lines."\n"; }
			for my $Line (1..$#Lines) {
					next if $Lines[1] =~ /^$/; # Skip first line if blank
			    print FILE $Lines[$Line]."\n";
			}
			if ($Lines[$#Lines] ne $LastLine) {
				print FILE "\n\n\n\n\n".$fixed."\n".$LastLine."";
			}
		}
		close (FILE);
		if (substr($Str, -1) == "-") { substr($Str, -1) = ""; } # remove trailing hyphen
		if (substr($Art, -1) == "-") { substr($Art, -1) = ""; } # remove trailing hyphen
		if (substr($Tit, -1) == "-") { substr($Tit, -1) = ""; } # remove trailing hyphen
		my $NewName = '';
		if ($ArtistFirst) { # Put in Artist first format
			if ($Art) { $NewName .= $Art; }
			if ($Tit) { $NewName .= "-".$Tit; }
			if ($Str) { $NewName .= "-".$Str; }
		} else { # Put in Title first format
			if ($Tit) { $NewName .= $Tit; }
			if ($Art) { $NewName .= "-".$Art; }
			if ($Str) { $NewName .= "-".$Str; }
		}
		if (length $NewName > 0) { # If it found some tags - proceed, allow for extension ...
			my $tmp = $NewName.".".$OutExt;
			if (($file ne $tmp)){
				if (-f "$tmp") { # Check if filename exists
					$FileNameCount = 1;
					while (-e $NewName.".".$FileNameCount.".".$OutExt) {
						$FileNameCount++;
					}
					$NewName.=".".$FileNameCount; # Add a number if file exists eg file.1.EXT file.2.ext
				}
				$NewName .= ".".$OutExt; # Add extension
				print "[Renaming] $file --> $NewName\n";
				$countFIX++;
				rename $file, $NewName;
			} else {
				if ($DIAG) { print "[ERR] $file --> $NewName | exists\n"; }
			}
		} else {
			print "[ERR] no tags found ... $file\n";
		}
	}
}
closedir(DIR);
PrettyPrint();
PrettyPrint("Ext","Count");
PrettyPrint();
PrettyPrint("All",$SrcDircount);
PrettyPrint("---","----");
PrettyPrint($SrcExt." files",$count);
if ($countPDF)      { PrettyPrint("PDF files",$countPDF); }
if ($countTXT)      { PrettyPrint("txt files",$countTXT); }
if ($countSGB)      { PrettyPrint("Songbooks",$countSGB); }
if ($countREG)      { PrettyPrint("reg files",$countREG); }
if ($countFIX || $FixedEntities) { PrettyPrint(); }
if ($countFIX)      { PrettyPrint("Fixed",$countFIX); }
if ($FixedEntities) { PrettyPrint("Entities",$FixedEntities); }

PrettyPrint();
exit 0;

sub RemoveThe($x) {
	my $x = shift;
	$x =~ s/(:\ the\ |:the\ )/:/i;
	return $x;
}

sub DataClense($x) {
	my $x = shift;
	$x =~ s/\}\s+$//g; # Delete any spaces after the terminating brace
	$x =~ s/(\\|\/)/-/g; # Swap slashes for hyphen
	$x =~ s/(\&|\+)/and/g; # Swap symbol and for bareword and
	$x =~ s/(\{.*:|\}|\(|\)|\[|\]|,|\'|\"|\%|\@|\!|\#|\^|\*|\<|\>|\:|\;|\?)//g; # Remove icky yucky stuff
	if ($RemoveThe) { $x =~ s/(\ the\ |the\ )//gi; }
	if ($RemoveAnd) { $x =~ s/(\ and|and\ )//gi; }
	if ($RemoveA)   { $x =~ s/^a\ //i; }
	if ($RemoveA)   { $x =~ s/\ a\ /\ /gi; }
	$x =~ s/^\ //g; # Fix leading space issue
	$x =~ s/(\ |\.)/_/g; # Swap space and dots for underscore
	return $x."-";
}

sub Swap($x) {
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

sub PrettyPrint($x,$y){
	my $x = shift;
	my $y = shift;
	if (($x eq "") && ($y eq "")) {
		# blank line
		print "+--------------+--------+\n";
	} else {
		print "| ";
		printf ("%-12s",$x);
		print " | ";
		printf ("%6s",$y);
		print " |\n";
	}
}
