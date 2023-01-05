onsong-chordpro-extractor

Using Perl to extract the ChordPro versions of songs from the OnSong SQLite database. Some of the programs are experiments and tests, put the perl file in the same directory as your database file (OnSong.sqlite3) and run to extract all songs known.

Steps:
```
1. Obtain backup file, make copy, put in convinient location and unzip
2. Put script in the same folder as the SQLite file
3. Run script
4. Done, review pages and files.
```

EG:
```
cp OnSong\ 202212162014.backup OnSong\ Backup.zip # Copy your time date stamped '.backup' file to a .zip file
unzip OnSong\ Backup.zip # unzip the copy
cd ~/Desktop/OnSong\ Backup/ # move to the target folder
chmod a+x Extract_OnSong_files_from_SQLite_DB.pl # allow execution of the perl script
./Extract_OnSong_files_from_SQLite_DB.pl # run the perl script
```
Always work on a backup!
