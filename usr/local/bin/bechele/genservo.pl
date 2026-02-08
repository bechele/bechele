#!/usr/bin/perl -w 
# create subsequent servo entries to be copied to ConfigL
#
my $count=120;                         # THe number of subsequent entries to create
my $start=140;                         # starting at servo number
my $stop=$start+$count;

for (my $i=$start;$i < $stop; $i++) {  # repeat until all lines are output
  print "                [76,534,0,76,534,'Servo $i'],                     #Servo $i\n";
}
# Result will be output to STDOUT - To save to file run with: 'genservo.pl > outfile.txt'
