#!/usr/bin/perl -w
#------------------------------------------------------------
#   Program to aqire living thing movements according to the MP3 to be played
#   Copyright (C) <2024>  <Rolf Jethon>
#   Version 2.0
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
#------------------------------------------------------------
use strict;
use lib '/usr/local/bin/bechele/Modules';
use ConfigL;
use RPi::MultiPCA9685 qw(init_PWM setChannelPWM disablePWM);
use POSIX qw/ceil floor/;
use Curses::UI;
if ($ConfigL::use_gamepad) {
  use Linux::Joystick;
} else {
  use Device::SerialPort qw( :PARAM :STAT 0.07 );
}
use WiringPi::API qw(:wiringPi);
#use RPi::WiringPi;
use Time::HR;
use Audio::Play::MPG123;
use File::Find::Rule;
use File::Temp qw( :POSIX );
$SIG{INT} = \&ctrlc;
use vars qw/$frames $full_range $maxstep $minstep $nummoves $steps_determined $saved @active_x @pages_x @pages_y @channely @channelx @active_y $justview $viewall $api $serial $filepos $mp3 $maxfiles $recording $just_loaded $outfilename $inext $iprev $nextp $prevp $outfilename $servo @servocontent $dual $previouscount $contentcount $pwm_en $dev $periodstart @filelist @joy_content $js/;
init_i2c();
my $mp3dir=$ARGV[0];                                  # the name of the MP3 dir to process
if ( ! $mp3dir ) {                                    # stop if no argument has been passed
  print "usage: $0 <mp3_dirname>\n";
  exit 0;
}
system 'clear';
$api = WiringPi::API->new;
#$api = RPi::WiringPi->new;
$api->setup; # use wiringpi port numbers
my $player = new Audio::Play::MPG123;
init_ports();
disablePWM();                                     # disable the PWM via chip register
&$pwm_en(0);                                      # enable the pwm output by hardware
my $fh = tmpfile();
open STDERR, ">&fh";
my $cui = new Curses::UI( -color_support => 1, -clear_on_exit => 1,);
#my $sectionheight;
#if ($ConfigL::num_servos < 6) { $sectionheight = 8 } else { if ($ConfigL::num_servos >38) {$sectionheight =40;} else {$sectionheight = $ConfigL::num_servos+2}} 
my $statuspos=0;                     # the actual position in the status section to be output to
my @statuslines;                     # keeps the status messages (ring buffer)
my $filepath='';
my $num_notebooks=ceil($ConfigL::num_servos/$ConfigL::num_servos_per_row);		   
my $notebookheight;
if ($ConfigL::num_servos_per_row < 23){$notebookheight=28} else {$notebookheight=$ConfigL::num_servos_per_row+5}
# ----------- create the section frames -----------
my $win1 = $cui->add(                 # The window for notebook x
                    undef, 'Window',
                     -border => 0,
                     -y    => 0,
                     -x => 0,
                     -width => 43,
                     -height => $notebookheight,
                     -bfg  => 'red',
                     -title => 'Notebook X',
                     -releasefocus =>1
                   );
my $xlabel = $win1->add('myxlabel', 'Label', -text=>"Joystick X",-reverse=>1,-padleft=>16,-bg=>'black',-fg=>'white');
my $win2 = $cui->add(                 # The window for notebook y
                    undef, 'Window',
                     -border => 0,
                     -y    => 0,
                     -x    => 44,
                     -width => 43,
                     -height => $notebookheight,
                     -bfg  => 'red',
                     -title => 'Notebook Y',
                     -releasefocus =>1
                   );
my $ylabel = $win2->add('myylabel', 'Label', -text=>"Joystick Y",-reverse=>1,-padleft=>16,-bg=>'black',-fg=>'white');
my $win3 = $cui->add(                 # The base window 
                    undef, 'Window',
                     -border => 0,
                     -y    => 0,
                     -x    => 88,
                     -height => $notebookheight,
                     -bfg  => 'red',
                     -title => 'Settings',
                     -releasefocus =>1
                   );
my $nbx = $win1->add(               # The servo selection frame for joystick X
	             undef,'Notebook',
                     -border => 1,
                     -bfg  => 'red',
                     -y => 1,
                     -title => 'Channel X',
                     -releasefocus =>1
                   );
my $nby = $win2->add(              # The servo selection frame for joystick Y
	             undef,'Notebook',
                     -border => 1,
                     -bfg  => 'red',
                     -y => 1,
                     -title => 'Channel Y',
                     -releasefocus =>1
                   );
for (my $i=0;$i<$num_notebooks;++$i){
  $pages_x[$i] = $nbx->add_page("S$i",-releasefocus =>1);    #notebook pages x	
  $pages_y[$i] = $nby->add_page("S$i",-releasefocus =>1);    #notebook pages y	
}
my $tr = $win3->add(               # The tracking range selection frame
                     'fra2', 'Container',
                     -border => 1,
                     -y    => 4,
                     -bfg  => 'red',
                     -title => 'Track Sets:',
                     -height => 7,
                     -releasefocus =>1
                   );
my $cf = $win3->add(               # The tracking range selection frame
                     'fra3', 'Container',
                     -border => 1,
                     -y    => 11,
                     -bfg  => 'red',
                     -title => 'Copy Servos:',
                     -height => 5,
                     -releasefocus =>1
                   );
my $af = $win3->add(               # The action frame
                    'fra4', 'Container',
                     -border => 1,
                     -y    => 16,
                     -bfg  => 'red',
                     -title => 'Process:',
                     -height => 5,
                     -releasefocus =>1
                   );
my $ef = $win3->add(               # The exit frame
                    'fra5', 'Container',
                     -border => 1,
                     -y    => 21,
                     -bfg  => 'red',
                     -title => 'Note:',
                     -height => 3,
                     -releasefocus =>1
                   );
my $sf = $win3->add(               # The status frame
                    'fra6', 'Container',
                     -border => 1,
                     -y    => 24,
                     -bfg  => 'red',
                     -title => 'Status:',
                     -focusable =>0,
                     -releasefocus =>1
                   );
my $ff = $win3->add(                # The file frame
                    'fra0', 'Container',
                     -border => 1,
                     -y    => 0,
                     -bfg  => 'red',
                     -title => 'File:',
                     -height => 4,
                     -releasefocus =>1
                   );
$cui->set_binding(\&exit_dialog,"\cQ"); 
# ----------- setup the file section ---------
my $filelabel = $ff->add('myfilelabel', 'Label', -text=>"Path: ", -bold=>1);
my $fileentry = $ff->add('mytextentry', 'TextEntry', -text=>$filepath, -sbborder=>1,-y=>0,-x=>6);
my $nextbutton = $ff->add('mynextbutton','Buttonbox', -buttons => [
                            { -label => '<<', -value=>4, -onpress=> \&mpprev10},
                            { -label => 'Prev', -value=>2, -shortcut=>'p',-onpress=> \&mpprev},
                            { -label => 'Next', -value=>1, -shortcut=>'n',-onpress=> \&mpnext},
                            { -label => '>>', -value=>5, -onpress=> \&mpnext10},
                            { -label => 'Save', -value=>3, -shortcut=>'s',-onpress=> \&savesv}
                          ],-y=>1,-fg=>'red',-bg=>'black');
# ----------- Set up the servo selection ------
for ( my $servonr=0;$servonr < $ConfigL::num_servos;$servonr++) {
  my $i=int($servonr/($ConfigL::num_servos_per_row));   
  $channelx[$servonr] = $pages_x[$i]->add("mychannelx$servonr",'Checkbox', 
                -label=>"$$ConfigL::servosettings[$servonr][5]($servonr)", 
                   -y=>$servonr-$i*($ConfigL::num_servos_per_row),
                   -onchange=>\&unchecky
                  );
  $channely[$servonr] = $pages_y[$i]->add("mychannely$servonr",'Checkbox',
                    -label=>"$$ConfigL::servosettings[$servonr][5]($servonr)",
                    -y=>$servonr-$i*($ConfigL::num_servos_per_row),
                    -onchange=>\&uncheckx
                  );
}
# ------------- define the movement record range ------
my $startsetlabel = $tr->add('mystartsetlabel', 'Label', -text=>'Start at move: ', -bold=>1);
my $startset = $tr->add('mystartset', 'TextEntry', -sbborder=>1,-x=>16,-width=>10);
my $stopsetlabel = $tr->add('mystopsetlabel', 'Label', -text=>'Stop at move: ', -bold=>1,-y=>1);
my $stopset = $tr->add('mystopset', 'TextEntry', -sbborder=>1,-y=>1,-x=>16,-width=>10);
my $maxsetlabel = $tr->add('mymaxsetlabel', 'Label', -text=>'Maximum move: ', -bold=>1,-y=>2);
my $maxset = $tr->add('mymaxset', 'Label', -text=>'<        >',-bold=>1,-y=>2,-x=>16);
my $maximize = $tr->add('mymaximize', 'Checkbox', -label=>'Update "Maximum move" field at the end of the MP3',-checked=>1,-y=>3);
my $fullrange = $tr->add('myfullrange', 'Checkbox', -label=>'record/output all moves independent of Start and Stop',-checked=>1,-y=>4);
# ------------ setup the status section ---------------
my $status = $sf->add('statustext','TextViewer',-fg=>'yellow',-wrapping=>1);
my $statusheight=$status->height();
my $proclabel = $ef->add('myproclabel', 'Label', -text=>" Exit with Ctrl-Q  - PgUp/PgDn to change servo page", -bg=>'black',-fg=>'white');
# ----------- setup the copy section ------------------
my $cpbutton = $cf->add('mycpbutton','Buttonbox', -buttons => [
                            { -label => 'Copy',-value=>1, -shortcut=>'c',-onpress=>\&copyservo}
                          ],-fg=>'red',-bg=>'black');
my $cpsrclabel = $cf->add('mycosrclabel', 'Label', -text=>"From svo:",-bold=>1,-y=>1);
my $cpsrc = $cf->add('mycpsource', 'TextEntry', -sbborder=>1,-y=>1,-x=>9,-width=>7);
my $cptillabel = $cf->add('mycotillabel', 'Label', -text=>"Till:", -bold=>1,-x=>17,-y=>1);
my $cptill = $cf->add('mycptill', 'TextEntry', -sbborder=>1,-x=>22,-width=>7,-y=>1);
my $cpdstlabel = $cf->add('mycodstlabel', 'Label', -text=>"To:", -bold=>1,-x=>30,-y=>1);
my $cpdst = $cf->add('mycpdest', 'TextEntry', -sbborder=>1,-x=>33,-width=>7,-y=>1);
my $cpinvlabel = $cf->add('mycoinvlabel', 'Label', -text=>"Invert:", -bold=>1,-x=>41,-y=>1);
my $cpinv = $cf->add('mycpinv', 'Checkbox', -checked=>0,-y=>1,-x=>48);
my $cpsftlabel = $cf->add('mycosftlabel', 'Label', -text=>"Shift moves +/-:", -bold=>1,-x=>18,-y=>2);
my $cpshift = $cf->add('mycpshift', 'TextEntry', -sbborder=>1,-x=>34,-width=>10,-y=>2);
my $cprot = $cf->add('mycprot', 'Checkbox', -label=>'Rotate moves',-checked=>1,-y=>2);
$fileentry->focus();
# ----------- setup the actions to perform ------------
my $viewallbox = $af->add('viewall', 'Checkbox', -label=>'View all servos',-checked=>0,-y=>1);
my $fistrtlabel = $af->add('myfistrtlabel', 'Label', -text=>"Fill move:",-bold=>1,-y=>1,-x=>22);
my $fistrt = $af->add('myfistrt', 'TextEntry', -sbborder=>1,-y=>1,-x=>32,-width=>10);
my $fistrtvallabel = $af->add('myfistrtvallabel', 'Label', -text=>"Value:", -bold=>1,-x=>43,-y=>1);
my $fistrtval = $af->add('myfistrtval', 'TextEntry', -sbborder=>1,-x=>49,-width=>8,-y=>1);
my $fistoplabel = $af->add('myfistoplabel', 'Label', -text=>"To move:", -bold=>1,-x=>24,-y=>2);
my $fistop = $af->add('myfistop', 'TextEntry', -sbborder=>1,-x=>32,-width=>10,-y=>2);
my $fistopvallabel = $af->add('myfistopvallabel', 'Label', -text=>"Value:", -bold=>1,-x=>43,-y=>2);
my $fistopval = $af->add('myfistopval', 'TextEntry', -sbborder=>1,-x=>49,-width=>8,-y=>2);
my $procbutton = $af->add('myprocbutton','Buttonbox', -buttons => [
                            { -label => 'Record', -value=>1, -shortcut=>'r',-onpress=>\&record},
                            { -label => 'View', -value=>2, -shortcut=>'v',-onpress=>\&view},
                            { -label => 'Fill', -value=>3, -shortcut=>'f',-onpress=>\&fill}
                          ],-fg=>'red',-bg=>'black');
########################################################
@_= File::Find::Rule->file()                          # check the mp3 directory and fill the array with the file names
                           ->name("*.mp3")
                           ->maxdepth(1)
                           ->in( $mp3dir );
@filelist=sort(@_);
$maxfiles=$#filelist;                                 # note the number of mp3s in folder
if ( $maxfiles == -1) { err("No files to process in $mp3dir")}
#hardwaretest();
my $stepwidth=$ConfigL::stepwidth;                    # use the refresh rate from the config file
my $waittime_serial=8000000;                          # wait for 8 ms (8000000 ns)
$mp3=get_mp(-1);                                      # determine the first mp3 file to read
$_=$maxfiles+1;
printstatus("$_ MP3 files in folder $mp3dir\n");
load_file();
maxrange();                                           # after loading use the maximum moves
$cui->mainloop;
exit 0;
########################################################
# exit the script
########################################################
sub exit_dialog{
  $cui->mainloopExit();
  exec 'reset';
}

########################################################
# start recording
########################################################
sub record {
  $minstep=$startset->get();                         # prepare startstep
  $maxstep=$stopset->get();                         # and stopstep
  $full_range=$fullrange->get();
  if (($minstep >= $maxstep) and (!$full_range)) { printstatus("\"Start at move\" must be larger than \"Stop at move\" - change the values oractivate select \"record all\"");return;}
  $cui->leave_curses();
  $justview=0;
  for (my $a=0;$a<$ConfigL::num_servos;$a++){
    $active_x[$a]=$channelx[$a]->get();              # make a shortcut for quick access to the checkbox content
    $active_y[$a]=$channely[$a]->get();
  } 
  system 'clear';
  print "Press start button on joystick to start recording                               \n";
  print "--------------------------------------------------------------------------------\n";
  wait_for_start();
  while ($cui->get_key(0) != -1) {                   # flush all keystrokes to not confuse curses
  }	  
  $cui->reset_curses();
}
########################################################
# start viewing
########################################################
sub view {
  $minstep=$startset->get();                         # prepare startstep
  $maxstep=$stopset->get();                         # and stopstep
  $full_range=$fullrange->get();
  if (($minstep >= $maxstep) && (!$full_range)) { printstatus("\"Start at move\" must be larger than \"Stop at move\" - change the values oractivate select \"record all\"");return;}
  $cui->leave_curses();
  $justview=1;
  for (my $a=0;$a<$ConfigL::num_servos;$a++){
    $active_x[$a]=$channelx[$a]->get();              # make a shortcut for quick access to the checkbox content
    $active_y[$a]=$channely[$a]->get();
  } 
  system 'clear';
  print "Press start button on joystick to start viewing                                 \n";
  print "--------------------------------------------------------------------------------\n";
  wait_for_start();
  $saved=1;
  while ($cui->get_key(0) != -1) {                   # flush all keystrokes to not confuse curses
  }	  
  $cui->reset_curses();
}
########################################################
# fill selected servos with value vector
########################################################
sub fill {
  $minstep=$startset->get();                         # prepare startstep
  $maxstep=$stopset->get();                         # and stopstep
  my $strtmove=$fistrt->get();
  my $strtval=$fistrtval->get();
  my $stopmove=$fistop->get();
  my $stopval=$fistopval->get();
  my $exitmarker=0;
  my $maxcount=$previouscount;
  if ( $previouscount==undef ) {                                                         # if no maxset - exit
    printstatus("Error: No moves defined yet - record at least one time first, to determine the number of moves for this audio file\n");
    $exitmarker =1;
  }
  if ("x$strtmove" eq "x" or $strtmove=~/\D/ or $strtmove >= $previouscount or $strtmove < 0){  # check for valid field content
    printstatus("Error: invalid fill move start defined - enter a number below $maxcount into field \"Fill move:\"\n");
    $exitmarker =1;
  }	  
  if ("x$stopmove" eq "x" or $stopmove=~/\D/ or $stopmove > $previouscount or $stopmove < 0){  # check for valid field content
    printstatus("Error: invalid fill move stop defined - enter a number below $maxcount into field \"To move:\"\n");
    $exitmarker =1;
  }	  
  if ("x$strtval" eq "x" or $strtval=~/\D/ or $strtval > $ConfigL::pwm_res or $strtval < 0){  # check for valid field content
    printstatus("Error: invalid PWM value defined - enter a number in between 0 and $ConfigL::pwm_res into field \"Value (left)\"\n");
    $exitmarker =1;
  }	  
  if ("x$stopval" eq "x" or $stopval=~/\D/ or $stopval > $ConfigL::pwm_res or $stopval < 0){  # check for valid field content
    printstatus("Error: invalid PWM value defined - enter a number in between 0 and $ConfigL::pwm_res into field \"Value (right)\"\n");
    $exitmarker =1;
  }	  
  if ($strtmove > $stopmove) {
    printstatus("Error: fill direction is negative \"Fill move\" must be smaller than \"To move\"\n");
    $exitmarker =1;
  }  
  if ($exitmarker) { printstatus("No changes have been made\n"); return;}
  my $len=$stopmove-$strtmove;                                             # number of steps to calculate
  my $valrange=$stopval-$strtval;                                          # pwm range for this vector
  for (my $a=0;$a<$ConfigL::num_servos;$a++){
    if ($channelx[$a]->get() or $channely[$a]->get()) {                    # make a shortcut for quick access to the checkbox content
      for (my $b=0;$b <= $len;$b++){
        my $val=int($b*$valrange/$len+$strtval+0.5);                       # rounding the vector result
        $servocontent[$b+$strtmove][$a]=int($val);                         # enter the result into the servo array 
      }
    }  
  } 
  printstatus("sucess: Selected servos filled with vector from move $strtmove to move $stopmove with value $strtval to value $stopval\n");
}
#############################################################
#  waits for a button to be pressed on the steering stick
#  returns the content split into an array
#############################################################
sub wait_for_start {
  my $stop=1;
  my $start;
mainloop: while ($stop==1) {
    get_one_read();                                   # read one serial set
    $stop=$joy_content[3];        
    $start=$joy_content[2];        
    if ($start == 0) {                                # check for the start button
      $saved=0;                                       # indicate that changes have not been saved
      while ($start==0) {                             # keep in loop until start button is released
        get_one_read();                               # read one serial set
        $start=$joy_content[2];        
      }
      $player->load($mp3);
#---------------------------------------------------------------------------------------------------------------------------------------
      $frames=$player->frame();                       # Need this nasty construction to convince Audio::Play::MPG123 providing the frame 
      $player->poll(1);                               # count, since it does not deliver the frame count when the file has not start
      $frames=$player->frame();                       # playing ...
      $player->load($mp3);                            # make sure to start at the beginning of the file
#---------------------------------------------------------------------------------------------------------------------------------------
      if ($full_range==1){                             # record during whole MP3 or start with offset
        $contentcount=0;
      } else {
	      #my $jump=int(($frames->[0]+$frames->[1])*$minstep/($previouscount));
        my $jump=int(($frames->[1])*$minstep/($previouscount));
        $player->jump ($jump);
        $contentcount=$minstep;
      }
      $periodstart=gethrtime();                       # synchronize time reference with the start of the MP3
      $player->poll(0);
      $recording=1;                                   # indicator, that recording is active
      add_one_set();                                  # add the first set from the previous reading (start key trigger)
    }
    if ( $recording==1 && (($periodstart + $stepwidth) <= gethrtime())) {
      get_one_read();                                 # if the period time has reached, read the cross stick
      #add_one_set();                                 # and add the data to the array -> not necessary, because after read
    }                                                 # recording is set to 2 by hsleep
    if ( $recording==2 ) {
      add_one_set();                                  # if the period is reached during a wait, take the data from the recent read
      if ((! $full_range==1) && $contentcount > $maxstep ){
        $recording=0;
	disablePWM();
        print "Press stop button to return to menu or start to run again\n";
        next mainloop;
      } 
      $recording=1;                                   # reset the "period end during wait" flag 
    }
  }
  disablePWM();
  $player->stop();
  $recording=0;
}
#############################################################
#  add one data set to the array
#############################################################
sub add_one_set {
  print "$contentcount"; 
  $viewall=$viewallbox->get();
  for (my $svo=0;$svo<$ConfigL::num_servos;$svo++){
    if ($justview==1){
      if ($viewall==1){ print"\[$svo:$servocontent[$contentcount][$svo]\]"}
      else { if ($active_x[$svo]) {print"\[$svo:$servocontent[$contentcount][$svo]\]"}
             if ($active_y[$svo]) {print"\[$svo:$servocontent[$contentcount][$svo]\]"}
      }
    }
    else {
      if ($active_x[$svo]) { $servocontent[$contentcount][$svo]=$joy_content[4];print "\[$svo:$joy_content[4]\]"}
      if ($active_y[$svo]) { $servocontent[$contentcount][$svo]=$joy_content[5];print "\[$svo:$joy_content[5]\]"}
    }
  }
  print "\n";
  for (my $c=0;$c<=$ConfigL::num_servos;$c++) {
    if ( $contentcount==0 && $servocontent[$contentcount][$c] eq undef) { 
      $servocontent[$contentcount][$c]=$ConfigL::servores/2;   # if no data available, use middle position
    } else {
      if ( $servocontent[$contentcount][$c] eq undef) { 
	$servocontent[$contentcount][$c]=$servocontent[$contentcount-1][$c]; 
      }	
    }                                                 # fill empty fields with the content of the previous set
  } 
  put_one_move($servocontent[$contentcount-1]);
  $periodstart+=$stepwidth;
  $contentcount++; 
}
#############################################################
#  a hires sleep ( in nanoseconds )
#############################################################
sub hsleep {
  my $duration=shift;
  my $now=gethrtime();
  while ($now + $duration >= gethrtime()) {           # As long as the sleep duration is not reached, keep in loop
    if ($recording > 0) {
      $player->poll(0);
      if ($player->state == 0) {                      # MP3 reached his end
         $recording=0;                                # indicate to quit from wait_for_start
         if ($maximize->get==1 && $justview!=1 ) {    # determine the max lenght 
	   $contentcount--;
           $previouscount=$contentcount;              # note the maximum duration of the mp3 
	   if ($stopset->get() > $contentcount) { $stopset->text($contentcount);}# make sure stopcount is never larger than the maximum moves
	   $maxset->text("<$contentcount>");
           $maximize->uncheck; 
         } 
         print "Press stop button to return to menu or start to run again\n"; # if the MP3 is finished -> loop
	 disablePWM();
      } else {                                              
        if ($periodstart + $stepwidth <= gethrtime()) {$recording=2} # tell that the period time has reached
      }
    }
  }
  return;
}
#############################################################
#  load previously recorded data from file
#############################################################
sub load_file{
  $outfilename=$mp3;
  $outfilename=~s/\.mp3//i;
  $outfilename=$outfilename.'.svo';
  $cui->status("Loading file $outfilename - please wait ....");
  showpath($outfilename);                             # show the path in file section
  printstatus( "Servo output filename is $outfilename\n");
  my $exist = (stat("$outfilename"))[2];              # check if a servo file exists
  $steps_determined=0;                                # note that never a mp3 end has been reached
  if ( $exist ) {                                     # load it, if so
    my $data;
    open (BIN,"<$outfilename")||err("Cannot open File $outfilename $!");
    while (read BIN,my $chunk,8192) {
      $data.=$chunk;                                  # read the data into var                         
    }
    close (BIN);
    my $lastbyte=chop $data;                          # cut off the checksum
    my $prelastbyte=chop $data;                       
    my $sumnum=unpack 'v',($prelastbyte.$lastbyte);   # convert the binary checksum into a number
    my $sum=unpack("%16C*",$data) % 32767;            # calculate the checksum for the data
    (my $dummy,$stepwidth,$ConfigL::servores,$ConfigL::num_servos)=unpack"vvvv",($data); # read the header into vars  
    if ($sumnum!=$sum) {                              # if file checksum is incorrect, die
      die "loaded file $outfilename has a bad checksum\n";
    }
    $stepwidth*=1000000;                              # convert step duration from ms into ns
    my $hz=1000000000/$stepwidth;
    $data=substr $data,8;                             # shorten the file
    my $j=0;                   
    while ( $data ) {                                 # as long as we have content, read it into array
      $servocontent[$j]=[unpack ("v[$ConfigL::num_servos]",$data)];
      $data=substr $data,$ConfigL::num_servos*2;
      $j++;         
    }
    $contentcount=$j-1;                               # note the number of sets in the file
    $previouscount=$contentcount;                     # remember the number of sets
    $maximize->uncheck;                               # keep the maximum moves until demanded manually
    printstatus( "Existing $outfilename has $j moves at a refresh rate of $hz Hz\n");  
    $nummoves=$j-1;
    maxrange();
    if ($sumnum!=$sum) {                              # if checksum is correct, read the data into vars
      printstatus( "loaded file $outfilename has a bad checksum\n");
    }
    $saved=1;
  } else { printstatus("No $outfilename exists - created when saved\n");
    $saved=0;
    $maximize->check;                                 # set the default to determine the maximum moves with the next record
  }
  $cui->nostatus;
}
#############################################################
# set the movement range to maximum
#############################################################
sub maxrange{
  $startset->text(0);
  $stopset->text($nummoves);
  $maxset->text("<$nummoves>");
}
#############################################################
# save the servo file
#############################################################
sub savesv {
  $outfilename=$fileentry->get(); 
  save_file();
  $saved=1;
}
#############################################################
# switch to previous or next mp3 file
#############################################################
sub mpnext {
  mpfile(1);
}
sub mpnext10 {
  mpfile(10);
}
sub mpprev {
  mpfile(-1);
}
sub mpprev10 {
  mpfile(-10);
}
########################################################
# prepare MP3-read
########################################################
sub mpfile {
  my $step=shift;
  if ( $saved==0 ) {
    my $answer=$cui->dialog(-message => "$outfilename has not been saved !\ncontinue without saving?",
                            -buttons=>[
                            { -label => 'No', -value=>0, -shortcut=>'n'},
                            { -label => 'Yes', -value=>1, -shortcut=>'y'},
                            { -label => 'Save', -value=>2, -shortcut=>'s'}
                            ]);
    if ( $answer==0) {
      return;
    }
    if ( $answer==2) {
      savesv();
    }
  }
  $mp3=get_mp($step);
  load_file();
  if ( $maximize->get()==1 ){
    &maxrange;
  }
}
#############################################################
# output path to file section
#############################################################
sub err {
  my $msg=shift;
  $cui->error($msg);
  exit_dialog();
}
#############################################################
# output path to file section
#############################################################
sub showpath {
  $fileentry->text(shift); 
  $fileentry->draw(1);
}
#############################################################
# output text to status section
#############################################################
sub printstatus {
  if ($statuspos >= $statusheight) {
    $statuspos=0; 
  }
  $statuslines[$statuspos]=shift;
  $statuspos++;
  my $statusline='';
  for (my $a=$statuspos;$a<$statusheight;$a++) {
    $statusline.=$statuslines[$a];
  }
  for (my $a=0;$a<$statuspos;$a++){
    $statusline.=$statuslines[$a];
  }
  $status->text($statusline); 
  $status->draw(1);
}
#############################################################
#  make sure never x and y are checked together
#############################################################
sub uncheckx {
  for ($a=0;$a<$ConfigL::num_servos;$a++) {
    if($channely[$a]->get()){
      $channelx[$a]->uncheck();
    }
  } 
}
sub unchecky {
  for ($a=0;$a<$ConfigL::num_servos;$a++) {
    if($channelx[$a]->get()){
      $channely[$a]->uncheck();
    }
  } 
}
#############################################################
#  saves the recorded data
#############################################################
sub save_file{
  # $stepwidth $servores $num_servos                  # vars in use
  # if ($just_loaded) { return }                        # do not save if data has not been changed
  my $bincontent;                                     # this var receives the binary coded servo positions 
  my $j=0;
  $cui->status("Saving file $outfilename - please wait ....");
  foreach my $set (@servocontent) {                   # put the array elements step by step binary coded into the string
    for (my $i=0;$i<$ConfigL::num_servos;$i++) {               
      $bincontent.=pack "v",($set->[$i]);             # save each servo position into a 16 bit word
    }
    if ($j>=$previouscount) { last }                   # only write till the new end
    $j++;
  }
  my $header=pack "vvvv",($previouscount,$stepwidth/1000000,$ConfigL::servores,$ConfigL::num_servos); # binarize the header elements
  my $sum=pack 'v',(unpack("%16C*",$header.$bincontent) % 32767); # calculate the checksum for the complete data stream
  open (BIN,">$outfilename")||err( "Cannot create output file $outfilename $!");
  binmode BIN;
  print BIN $header.$bincontent.$sum;                 # save header,body and checksum into file
  close (BIN);
  $cui->nostatus;
  printstatus("File $outfilename written\n");
}
#############################################################
#  reads the serial line as long as we get a string, followed by \n
#  returns the content splittet into an array
#############################################################
sub get_one_read {
  if ($ConfigL::use_gamepad) {                       # ----------------------- gamepad handling ---------------------------------
    hsleep ($waittime_serial);
    my $event=$js->nextEvent;
    if ($event){
      if ($event->isButton) {
        if ($event->button == $ConfigL::gamepad_start) {
          if ($event->buttonDown){
            $joy_content[3]=0;
          } else {
            $joy_content[3]=1;
          }
        }
        if ($event->button == $ConfigL::gamepad_stop) {
          if ($event->buttonDown){
            $joy_content[2]=0;
          } else {
            $joy_content[2]=1;
          }
        }
      }
      if ($event->isAxis) {
        if ($event->axis == $ConfigL::gamepad_axis_x) {
          $joy_content[0]=$event->axisValue;
        }
        if ($event->axis == $ConfigL::gamepad_axis_y) {
          $joy_content[1]=$event->axisValue;
        }
      }
    }
    $joy_content[4]=int($ConfigL::servores * ($joy_content[0]-$ConfigL::gamepad_x_start) / ($ConfigL::gamepad_x_end-$ConfigL::gamepad_x_start));
    if ( $joy_content[4] <= 0 ) { $joy_content[4]=1; }
    $joy_content[5]=int($ConfigL::servores * ($joy_content[1]-$ConfigL::gamepad_y_start) / ($ConfigL::gamepad_y_end-$ConfigL::gamepad_y_start));
    if ( $joy_content[5] <= 0 ) { $joy_content[5]=1; }
  } else {                                             # --------------------------- serial joystick handling ----------------------------
    my ($count,$data,$i)=(0,0,0);
    while (! (substr $data,-1 eq "\n")) {
      $serial->write('4');              # sent the command to the arduino to send one set
      hsleep ($waittime_serial);
      ($count,$data)=$serial->read(32);
      if ( $count ) {                   # if we have data, put it into the array
        @joy_content=split / /,$data;
        $joy_content[4]=int($ConfigL::servores * ($joy_content[0]-$ConfigL::joystick_x_start) / ($ConfigL::joystick_x_end-$ConfigL::joystick_x_start));
        if ( $joy_content[4] <= 0 ) { $joy_content[4]=1; }
        $joy_content[5]=int($ConfigL::servores * ($joy_content[1]-$ConfigL::joystick_y_start) / ($ConfigL::joystick_y_end-$ConfigL::joystick_y_start));
        if ( $joy_content[5] <= 0 ) { $joy_content[5]=1; }
      } else { $serial->purge_all(); }  # else try again
      if ($i >= 10) { err "serial device does not respond";}
      $i++;
    }
  }
}
#############################################################
#  move one set - send positions to servos
#############################################################
sub put_one_move {
  my $setref=shift;                                   # contains the refereence to one anonymous array containing the moves for one set
  my $i=0;
  my @allpos=();
  foreach my $servopos (@$setref) {                   # set the positions for all of the servos
    my $way=$$ConfigL::servosettings[$i][1]-$$ConfigL::servosettings[$i][0];  # the drive way (resolution) of the servo (<= 4096 steps)
    my $resfactor=$way/$ConfigL::servores;                     # calculate the correction factor PCA9685 has 4096 steps
    my $pos;
    if ($$ConfigL::servosettings[$i][2]) {
      $pos=int(($ConfigL::servores-$servopos)*$resfactor+$$ConfigL::servosettings[$i][0]); # take the Servostart from ConfigL::servosettings and invert the direction
    } else {
      $pos=int($servopos*$resfactor+$$ConfigL::servosettings[$i][0]);             # take the Servostart from ConfigL::servosettings
    }
    push (@allpos,(0,$pos));
    $i++;
  }
    my $mref=\@allpos;
    setChannelPWM(0,$mref);
}
#############################################################
#  Does a simple hardware test - this routine never stops !!!
#  only to be run on demand for testing purposes
#############################################################
sub hardwaretest {
  $serial->purge_all();                                         # clear the buffers of the serial line 
  while (1) {
    print ">>>>>";
    $serial->write('4');
    hsleep($waittime_serial);
    my ($count,$data)=$serial->read(32);
    if ($count) {
      print $data;
    }
    print "<<<<<";
  }
}
#############################################################
#  get the next mp3 file name to play
#############################################################
sub get_mp {
  my $move=shift;
  $filepos+=$move;                                 # update the position in the array we are reading from
  if ($filepos <= 0) { $filepos=0 }                   # do not go beyond first file
  if ($filepos > $maxfiles) { $filepos=$maxfiles }    # and do not exceed last file
  return $filelist[$filepos];                         # return the mp3 file to load
}
#############################################################
#  copy servo move sets to other servos
#############################################################
sub copyservo {
  my $srcsvo=$cpsrc->get();
  my $destsvo=$cpdst->get();
  my $tillsvo=$cptill->get();                                       
  my $strtset=$startset->get();                                                   # the move number to start copying
  my $stpset=$stopset->get();                                                     # the move number to stop copying
  my $shift=$cpshift->get();                                                      # how much to shift within the servo
  my $rotate=$cprot->get();                                                       # rotate if indicated - means exceeding moves will be wrapped around
  my $invert=$cpinv->get();                                                       # invert if indicated - the movement direction is inverted
  my $svocopydirection;
  my $movecopydirection;
  my $invtxt="";                                                                  # inverted text - goes into copy message when inverted
  my $svorange;                                                                   # How many servos to copy in one go
  my $svospan;                                                                    # How many servos to copy in one go - alway positive
  my $svodist;                                                                    # distance in between source and destination servo
  my $maxmoves=$previouscount;                                                    # limit the move count to end of the MP3 - take from the ????????????
  my $exitmarker=0;
  my @copycontent;
  if ("x$srcsvo" eq "x" or $srcsvo=~/\D/ or $srcsvo >= $ConfigL::num_servos) {    # sourceservo is valid and numeric ?
    printstatus("Error: invalid source servo defined - enter a number into field \"From:\"\n");
    $exitmarker =1;
  }
  if ($destsvo >= $ConfigL::num_servos) {                                          # destservo is valid and numeric ?
    printstatus("Error: invalid destination servo - must be below $ConfigL::num_servos\n");
    $exitmarker =1;
  }
  if ("x$destsvo" eq "x" or $destsvo=~/\D/) {                                      # destservo is valid and numeric ?
    printstatus("Error: invalid destination servo defined - enter a number into field \"To:\"\n");
    $exitmarker =1;
  }
  if ( $maxmoves==undef ) {                                                       # if no maxmoves - exit
    printstatus("Error: No moves defined yet - record moves first\n");
    $exitmarker =1;
  }
  if ("x$tillsvo" eq "x"){$tillsvo=int($srcsvo);$svorange=0;$svocopydirection=1} else {
    if ($tillsvo=~/\D/){                                                          # tillservo is not numeric ? 
      printstatus("Error: \"Till:\" must be numeric\n");
      $exitmarker =1;
    } 
    $svorange=$tillsvo-$srcsvo;                                                   # how many servos to copy
    $svospan=abs($svorange);                                                      # to make svospan always positive
    if ($tillsvo < $srcsvo){$svocopydirection=0;} else { $svocopydirection=1;}    # determine the servo copy direction
    if ($destsvo + $svospan >= $ConfigL::num_servos){
      printstatus("Error: Copy destination exceeds maximum number of servos\n");
      $exitmarker =1;
    }
  }
  if ("x$shift" eq "x"){$shift=0;}                                                # if the shift field has left empty take it as zero
  my $moves;                                                                      # contains how many moves to copy
  if ($stpset-$strtset >= 0) {$movecopydirection=1;$moves=$stpset-$strtset;}else{$movecopydirection=0;$moves=$strtset-$stpset} # determine the moves copy direction
  $moves++;
  if ($rotate) {
    if ($shift > $maxmoves or ($shift * -1)>$maxmoves){                           # make sure number of shifts is smaller or equal than number of moves
      printstatus("Error: Shift-Rotate for more than $maxmoves moves - decrease number of shifts\n");
      $exitmarker=1;
    } 
  } else {
    if ($shift+$strtset+$moves >= $maxmoves or $shift+$strtset+$moves <= 0){
      printstatus("Error: Shifting exceeds move 0 or maximum number of moves - decrease number of shifts or change \"Start/Stop at move\"\n");
      $exitmarker=1;
    }  
  }  
  if ($exitmarker) { printstatus("nothing has been copied !\n"); return 0 }
  $svodist=$destsvo-$srcsvo;                                                      # distance between source and destination servo
  my $jb=0;                                                                       # buffer counter for Servos
  my $ib;                                                                         # buffer counter for moves
  my $ii;                                                                         # read the moves starting from this set
  #-------------------here we first fill the buffer with the servo moves --------- 
  for (my $j=$srcsvo;ckloop($j,$tillsvo,$svocopydirection);$j=crement($j,$svocopydirection)) {
    $ii=$strtset;
    $ib=0;
    for (my $i=0;$i < $moves;$i++) {
      if ($ii < 0) {$ii=$maxmoves}                                                # turn around (rotate) reading when counting down
      if ($ii > $maxmoves) {$ii=0}                                                # turn around (rotate) when counting up
      if ($invert) {
	 my $inverted=$ConfigL::servores-$servocontent[$ii][$j];                  # invert the servo pwm value
         $copycontent[$ib][$jb]=$inverted;                                        # and put into content array
	 $invtxt=" inverted";
      } else {
         $copycontent[$ib][$jb]=$servocontent[$ii][$j];                           # use the un-inverted servo PWM value
	 $invtxt="";
      }
      $ii=crement($ii,$movecopydirection);
      $ib++;
    }
    $jb++;
  }                                                                               # here the buffer @copycontent is completely filled
  #-------------------here we paste the buffer to the new destination ------------ 
  my $jo=$destsvo;
  my $io;
  for (my $j=0;$j < $jb;$j++) {
    if ($movecopydirection) {
      if ($strtset+$shift < 0) {$io=$maxmoves+1+($strtset+$shift);}
      else {$io=$strtset+$shift;} 
    }
    else {
      if ($stpset+$shift < 0) {$io=$maxmoves+1+($stpset+$shift);} 
      else {$io=$stpset+$shift;}                                                  # always start to copy to the lower position 
    }
    if ($io < 0){$io=$maxmoves+$shift+1;}                                         # set turnaround position to next read
    for (my $i=0;$i < $moves;$i++){
      if ($io > $maxmoves) {$io=0}                                                # turn around (rotate) when counting up
      $servocontent[$io][$jo]=$copycontent[$i][$j];
      $io++;
    }	    
    $jo++;
  }	  
  printstatus("Servo $srcsvo till $tillsvo copied$invtxt into Servo $destsvo from move $strtset to $stpset shifted by $shift moves\n");
}
#############################################################
# increment or decrement depending on $copydirection
#############################################################
sub crement {
  my $i=shift;
  my $copydir=shift;
  if ($copydir){ $i++ } else {$i--}  
  return $i;
}
#############################################################
# check if limit condition is met - depending on copydirection
#############################################################
sub ckloop {
  my $i=shift;       # counter loop value
  my $param=shift;   # Parameter to check against
  my $copydir=shift; # copydirection: 0= backwards 1= forwards
  my $condition;     # as long as condition is 1 stay in loop
  if ($copydir){
    if ($i <= $param){$condition=1 } else {$condition=0} 
  } else {
    if ($i >= $param){$condition=1 } else {$condition=0} 
  }
  return $condition;
}
#############################################################
#  logging tool
#############################################################
sub logs {
  if (fileno(LOG)==undef) {
    open (LOG,">>/tmp/bechele.log")||err("Cannot open /tmp/bechele.log $!");
  }
  print LOG shift."\n";
  close LOG;
}
#############################################################
#  initializes the hardware
#############################################################
sub init_ports {
  if ($ConfigL::use_gamepad) {
    @joy_content=(0,0,1,1);
    $js = Linux::Joystick->new(device => $ConfigL::joystick_device,nonblocking => 1);
  } else {
    $serial = Device::SerialPort->new($ConfigL::serialport); # init the serial port at pin 10 (RXD)
    $serial->baudrate(38400);
    $serial->databits(8);
    $serial->stopbits(1);
    $serial->purge_all();
    $serial->rts_active(0);
    $serial->dtr_active(0);
    $serial->purge_all();                              # flush the buffer
  }
# gpio setup
# ----------
  $pwm_en=sub{$api->write_pin($ConfigL::OE,shift)};             # port 0 pin 11 (OE)
  $inext= sub{return ($api->read_pin($ConfigL::NEXT))};         # Port 1 pin 12 (Next mp3)
  $iprev= sub{return ($api->read_pin($ConfigL::PREV))};         # Port 4 pin 16 (Prev mp3)
  # init input for next file activate pulldown
  $api->pin_mode($ConfigL::NEXT,0);                             # port 1 (pin 12) as input
  $api->pull_up_down($ConfigL::NEXT,1);                         # activate pulldown
  # init input for previous/stop file activate pulldown
  $api->pin_mode($ConfigL::PREV,0);                             # port 4 (pin16) as input
  $api->pull_up_down($ConfigL::PREV,1);                         # activate pulldown
  # init pwm enable pin 11 ($pwm_en)as output and set to 1 (inactive)
  $api->pin_mode($ConfigL::OE,1);                               # port 0 (pin 11) as output
  $api->write_pin($ConfigL::OE,1);                              # init port 0 to 1
}
sub init_i2c {
  my$success=init_PWM($ConfigL::i2cport,$ConfigL::i2c_address,$ConfigL::i2c_freq,$ConfigL::num_servos);
}
sub ctrlc {
$SIG{INT} = \&ctrlc;
  disablePWM();
  exit;
}
END {
  disablePWM();
}

