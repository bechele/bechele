#!/usr/bin/perl -w
#   ckecksum utility to proof the integrity of svo files
#   Copyright (C) <2015>  <Rolf Jethon>
#   Version 1.0
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.

if ( ! $ARGV[0] ) {                     # stop if no argument has been passed
  print "usage: $0 <name.svo>\n";
  exit 0;
}
my $data;
my $infilename=$ARGV[0];
open (BIN,"<$infilename")||die "cannot read input file $infilename $!";
    while (read BIN,my $chunk,2048) {
      $data.=$chunk;                                  # read the data into var
    }
close (BIN);
my $lastbyte=chop $data;
my $prelastbyte=chop $data;
my $sumnum=unpack 'v',($prelastbyte.$lastbyte);
print 'checksum calculated: '.unpack("%16C*",$data) % 32767;
print "\nChecksum in File: " .$sumnum."\n";

