#!/usr/bin/perl -w
#------------------------------------------------------------
#   Program to aqire living thing movements according to the MP3 to be played
#   Copyright (C) <2026>  <Rolf Jethon>
#   Version 3.0
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
use feature 'state';                                  # allow static variables
use Data::Dump qw(dump);
use bigfloat;
use Socket;                                           # use in any case - not expensive, even if network is not desired
use POSIX qw/ceil floor/;
my $mp3dir=$ARGV[0];                                  # the name of the MP3 dir to process
if ( ! $mp3dir ) {                                    # stop if no argument has been passed
  print "usage: $0 <mp3_dirname>\n";
  exit 0;
}
$mp3dir=~s/\/$//;                                     # remove a trailing slash fornm dirname so path are clean
use File::Copy;
if ( ! (-e "$mp3dir/ConfigL.pm" && -f "$mp3dir/ConfigL.pm" && -r "$mp3dir/ConfigL.pm")) {     #Make sure the ConfigL.pm file exists in the source directory
  copy ("/usr/local/bin/bechele/Modules/ConfigL.pm", "$mp3dir/ConfigL.pm") or die "copy of ConfigL.pm to $mp3dir failed: $!";   #otherwise copy from Modules directory
}
require "$mp3dir/ConfigL.pm";                         # load the Config File
my ($netport,$sendtonet,$sendtopca,$use_gamepad,$joystick_device,$serialport,$waittime_serial,$i2cport,$pwm_res,$i2c_address,$i2c_freq,$debug,$servores,$num_servos,$stepwidth,$play_full_mp3,$mp3loop,$block_popup_width,$matrix_popup_width,$max_out_pins,$dboutlist,$joystick_x_start,$joystick_x_end,$joystick_y_start,$joystick_y_end,$gamepad_start,$gamepad_stop,$gamepad_axis_y,$gamepad_axis_x,$gamepad_x_start,$gamepad_x_end,$gamepad_y_start,$gamepad_y_end,$num_servos_per_row,$OE,$NEXT,$PREV,$S1,$S2,$SHUT,$servosettings)=ConfigL::get_vars();
if ($sendtopca) {                                     # in case connecting a PCA9695 directly is desired, load the module for it
  eval {use RPi::MultiPCA9685 qw(init_PWM setChannelPWM disablePWM);RPi::MultiPCA9685->import(qw(init_PWM setChannelPWM disablePWM));1} or die "Error loading module RPi::MultiPCA9685 $@";
  init_i2c();
} 
if ($use_gamepad) {                                   # load the desired joystick module, depending on type and interface 
  eval {use Linux::Joystick;Linux::Joystick->import();1} or die "Error loading module Linux::Joystick $@";  # load and import Module for USB Joystick
} else {
  eval { require Device::SerialPort; Device::SerialPort->import(qw( :PARAM :STAT 0.07 )); 1 } or die "Error loading module Device::SerialPort $@"; # load serial Joystick requirements
}
no bigfloat;
use WiringPi::API qw(:wiringPi);
#use RPi::WiringPi;
use Time::HR;
use Audio::Play::MPG123;
use File::Find::Rule;
use File::Temp qw( :POSIX );
use Curses::UI;
use Curses::UI::Mousehandler::GPM;
$SIG{INT} = \&ctrlc;
use vars qw/$unlimited_range $actuators $num_actuators $boxes_exist @cbox_x_saved @cbox_y_saved $lastkey $blocks_open $matrix_open $nbx $in_popup $maxblkfiles $full_range $maxstep $minstep $nummoves $saved @channely @channelx @active_x @active_y $justview $api $serial $mp3 $maxfiles $recording $inext $iprev $outfilename @servocontent $previouscount $contentcount $pwm_en $periodstart @filelist @joy_content $js $wincnt/;
system 'clear';                                       # clear the screen
$api = WiringPi::API->new;
#$api = RPi::WiringPi->new;
$api->setup; # use wiringpi port numbers
my $player = new Audio::Play::MPG123;                 # init the MP3 player
init_ports();
disable_actuators();                                  # disable the PWM on network and PCA devices
&$pwm_en(0);                                          # enable the pwm output by hardware
my $fh = tmpfile();
calc_actuators();                                     # calculate, which actuators are servos and which relais
my $packet_counter=1;                                 # begin packet counting with 1
open STDERR, ">&fh";                                  # redirect Standard error to file
#---------------------- set up the main Curses::UI dialog -----------------------------------
my $cui = new Curses::UI( -color_support => 1, -clear_on_exit => 1, -key_support => 1,);
my @statuslines;                                      # keeps the status messages (ring buffer)
my $filepath='';
my $num_notebooks=ceil(($num_actuators)/$num_servos_per_row);		   
my $notebookheight;
if ($num_servos_per_row < 23){$notebookheight=28} else {$notebookheight=$num_servos_per_row+4}
my $win3 = $cui->add(                                 # The base window 
                    undef, 'Window',
                     -border => 0,
                     -y    => 0,
                     -bfg  => 'red',
                     -height => $notebookheight,
                     -title => 'Settings',
                     -releasefocus =>1,
                     -on_init=>\&matrix_ui
                   );
my $ff = $win3->add(                                  # The file frame
                    'fra0', 'Container',
                     -border => 1,
                     -y    => 0,
                     -bfg  => 'red',
                     -title => 'File:',
                     -height => 4,
                     -releasefocus =>1
                   );
my $tr = $win3->add(                                  # The tracking range selection frame
                     'fra2', 'Container',
                     -border => 1,
                     -y    => 4,
                     -bfg  => 'red',
                     -title => 'Track Sets:',
                     -height => 7,
                     -releasefocus =>1
                   );
my $cf = $win3->add(                                  # The copy servo frame
                     'fra3', 'Container',
                     -border => 1,
                     -y    => 11,
                     -bfg  => 'red',
                     -title => 'Copy Servos:',
                     -height => 5,
                     -releasefocus =>1
                   );
my $af = $win3->add(                                  # The action frame
                    'fra4', 'Container',
                     -border => 1,
                     -y    => 16,
                     -bfg  => 'red',
                     -title => 'Process:',
                     -height => 5,
                     -releasefocus =>1
                   );
my $ef = $win3->add(                                  # The exit frame
                    'fra5', 'Container',
                     -border => 1,
                     -y    => 21,
                     -bfg  => 'red',
                     -title => 'Note:',
                     -height => 3,
                     -focusable =>0,
                     -releasefocus =>1
                   );
my $sf = $win3->add(                                  # The status frame
                    'fra6', 'Container',
                     -border => 1,
                     -y    => 24,
                     -bfg  => 'red',
                     -title => 'Status:',
                     -focusable =>0,
                     -releasefocus =>1
                   );
$cui->set_binding(\&exit_dialog,"\cq"); 
$cui->set_binding(\&close_popups,"\cl");
$cui->set_binding(\&prevwin,"\cb"); 
$cui->set_binding(\&nextwin,"\cf"); 
# ----------- setup the file section ---------
my $filelabel = $ff->add('myfilelabel', 'Label', -text=>"Path: ", -bold=>1);
my $fileentry = $ff->add('mytextentry', 'TextEntry', -text=>$filepath, -sbborder=>1,-y=>0,-x=>6);
my $nextbutton = $ff->add('mynextbutton','Buttonbox', -buttons => [
                            { -label => '<<', -value=>4,-shortcut=>'<', -onpress=> \&mpprev10},
                            { -label => 'Prev', -value=>2, -shortcut=>'p',-onpress=> \&mpprev},
                            { -label => 'Next', -value=>1, -shortcut=>'n',-onpress=> \&mpnext},
                            { -label => '>>', -value=>5, -shortcut=>'>',-onpress=> \&mpnext10},
                            { -label => 'Save', -value=>3, -shortcut=>'s',-onpress=> \&savesv},
                            { -label => 'Block_operations', -value=>6, -shortcut=>'b',-onpress=> \&block_ui}
                          ],-y=>1,-fg=>'yellow',-bg=>'blue',-width=>38);
# ------------- define the movement record range ------
my $bookbutton = $tr->add('mybookbutton','Buttonbox', -buttons => [
                            { -label => 'Set_servo_matrix', -value=>1, -shortcut=>'m',-onpress=> \&matrix_ui}
                          ],-y=>0,-fg=>'yellow',-bg=>'blue',-width=>17);
my $startsetlabel = $tr->add('mystartsetlabel', 'Label', -text=>'Start at move: ', -bold=>1,-y=>1);
my $startset = $tr->add('mystartset', 'TextEntry', -sbborder=>1,-x=>16,-width=>10,-y=>1);
my $stopsetlabel = $tr->add('mystopsetlabel', 'Label', -text=>'Stop at move: ', -bold=>2,-y=>2);
my $stopset = $tr->add('mystopset', 'TextEntry', -sbborder=>1,-y=>2,-x=>16,-width=>10);
my $maxsetlabel = $tr->add('mymaxsetlabel', 'Label', -text=>'Maximum move: ', -bold=>1,-y=>2,-x=>27);
my $maxset = $tr->add('mymaxset', 'Label', -text=>'<        >',-bold=>1,-y=>2,-x=>43);
my $maximize = $tr->add('mymaximize', 'Checkbox', -label=>'Update "Maximum move" field at the end of the MP3',-checked=>1,-y=>3);
my $fullrange = $tr->add('myfullrange', 'Checkbox', -label=>'record/output all moves independent of Start and Stop',-checked=>1,-y=>4);
# ------------ setup the status section ---------------
my $status = $sf->add('statustext','TextViewer',-fg=>'yellow',-wrapping=>1);
my $statusheight=$status->height();
my $proclabel = $ef->add('myproclabel', 'Label', -text=>"Ctrl-Q Quit | Ctrl-F/B: window focus | Tab/Shift-Tab: element focus", -bg=>'black',-fg=>'white');
# ----------- setup the copy section ------------------
my $cpbutton = $cf->add('mycpbutton','Buttonbox', -buttons => [
                            { -label => 'Copy',-value=>1, -shortcut=>'c',-onpress=>\&copyservo}
                          ],-fg=>'yellow',-bg=>'blue',-width=>5);
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
$win3->focus();$wincnt=2;
# ----------- setup the actions to perform ------------
my $procbutton = $af->add('myprocbutton','Buttonbox', -buttons => [
                            { -label => 'Record', -value=>1, -shortcut=>'r',-onpress=>\&record},
                            { -label => 'View', -value=>2, -shortcut=>'v',-onpress=>\&view},
                            { -label => 'Fill', -value=>3, -shortcut=>'f',-onpress=>\&fill}
                          ],-fg=>'yellow',-bg=>'blue',-width=>17);
my $viewallbox = $af->add('viewall', 'Checkbox', -label=>'View all servos',-checked=>0,-y=>1);
my $fistrtlabel = $af->add('myfistrtlabel', 'Label', -text=>"Fill move:",-bold=>1,-y=>1,-x=>22);
my $fistrt = $af->add('myfistrt', 'TextEntry', -sbborder=>1,-y=>1,-x=>32,-width=>10);
my $fistrtvallabel = $af->add('myfistrtvallabel', 'Label', -text=>"Value:", -bold=>1,-x=>43,-y=>1);
my $fistrtval = $af->add('myfistrtval', 'TextEntry', -sbborder=>1,-x=>49,-width=>8,-y=>1);
my $nolimit = $af->add('mynolimit', 'Checkbox', -label=>'Unlimit range!',-checked=>0,-y=>2,-onchange=>\&warnrange);
my $fistoplabel = $af->add('myfistoplabel', 'Label', -text=>"To move:", -bold=>1,-x=>24,-y=>2);
my $fistop = $af->add('myfistop', 'TextEntry', -sbborder=>1,-x=>32,-width=>10,-y=>2);
my $fistopvallabel = $af->add('myfistopvallabel', 'Label', -text=>"Value:", -bold=>1,-x=>43,-y=>2);
my $fistopval = $af->add('myfistopval', 'TextEntry', -sbborder=>1,-x=>49,-width=>8,-y=>2);
#------------ further inits prior to start the user IF ----------------
@_= File::Find::Rule->file()                          # check the mp3 directory and fill the array with the file names
                           ->name("*.mp3")
                           ->maxdepth(1)
                           ->in( $mp3dir );
@filelist=sort(@_);
$maxfiles=$#filelist;                                 # note the number of mp3s in folder
if ( $maxfiles == -1) { err("No files to process in $mp3dir")}
#hardwaretest();
$mp3=get_mp(-1);                                      # determine the first mp3 file to read
$_=$maxfiles+1;
printstatus("$_ MP3 files in folder $mp3dir\n");
load_file();
maxrange();                                           # after loading use the maximum moves
matrix_ui();                                          # run matrix_ui once so some required parameters are setup
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
# Move focus to the next window in mainwindow
########################################################
sub nextwin{
  if ($in_popup){                                     #do not operate in popups 
    return 0;
  }
  $wincnt++;
  if ($wincnt>3){ $wincnt=0;}
  if ($wincnt==0){ $ff->focus();}
  if ($wincnt==1){ $tr->focus();}
  if ($wincnt==2){ $cf->focus();}
  if ($wincnt==3){ $af->focus();}
}
########################################################
# warn about the missing range check during fill operation
########################################################
sub warnrange {
  if (!$unlimited_range) {
    err(" Warning: The range for fill values will be no more checked!\n It is highly recommended not to activates this, if you don't need\n to fill relay values larger than 12 bit (more than 12 relay pins on one node) \n If you use unlimited fill values for Servos, the\n results will be unpredictable !! ");
  }
  $unlimited_range=$nolimit->get();
}
########################################################
# Move focus to the previous window in mainwindow
########################################################
sub prevwin{ 
if ($in_popup){                                       # do not operate in popups
return 0;
}
$wincnt--;
if ($wincnt<0){ $wincnt=3;}
if ($wincnt==0){ $ff->focus();}
if ($wincnt==1){ $tr->focus();}
if ($wincnt==2){ $cf->focus();}
if ($wincnt==3){ $af->focus();}
}
########################################################
# start recording
########################################################
sub record {
  $minstep=$startset->get();                          # prepare startstep
  $maxstep=$stopset->get();                           # and stopstep
  $full_range=$fullrange->get();
  if (($minstep >= $maxstep) and (!$full_range)) { printstatus("\"Start at move\" must be larger than \"Stop at move\" - change the values or activate \"record all\"");return;}
  $cui->leave_curses();
  $justview=0;
  for (my $act=0;$act<$num_actuators;$act++){
    $active_x[$act]=$channelx[$act]->get();               # make a shortcut for quick access to the checkbox content
    $active_y[$act]=$channely[$act]->get();
  } 
  system 'clear';
  print "Press start button on joystick to start recording                               \n";
  print "--------------------------------------------------------------------------------\n";
  wait_for_start();
  while ($cui->get_key(0) != -1) {                    # flush all keystrokes to not confuse curses
  }	  
  $cui->reset_curses();
}
########################################################
# start viewing
########################################################
sub view {
  $minstep=$startset->get();                          # prepare startstep
  $maxstep=$stopset->get();                           # and stopstep
  $full_range=$fullrange->get();
  if (($minstep >= $maxstep) && (!$full_range)) { printstatus("\"Start at move\" must be larger than \"Stop at move\" - change the values or activate \"record all\"");return;}
  $cui->leave_curses();
  $justview=1;
  for (my $act=0;$act<$num_actuators;$act++){
    $active_x[$act]=$channelx[$act]->get();               # make a shortcut for quick access to the checkbox content
    $active_y[$act]=$channely[$act]->get();
  } 
  system 'clear';
  print "Press start button on joystick to start viewing                                 \n";
  print "--------------------------------------------------------------------------------\n";
  wait_for_start();
  $saved=1;
  while ($cui->get_key(0) != -1) {                    # flush all keystrokes to not confuse curses
  }	  
  $cui->reset_curses();
}
########################################################
# fill selected servos with value vector
########################################################
sub fill {
  $minstep=$startset->get();                          # prepare startstep
  $maxstep=$stopset->get();                           # and stopstep
  my $strtmove=$fistrt->get();
  my $strtval=$fistrtval->get();
  my $stopmove=$fistop->get();
  my $stopval=$fistopval->get();
  my $exitmarker=0;
  my $maxpwmvalue;
  if ($unlimited_range) {
    $maxpwmvalue=65535;
  } else {
    $maxpwmvalue=$pwm_res-1;
  }
  if ( $previouscount==undef ) {                     # if no maxset - exit
    printstatus("Error: No moves defined yet - record at least one time first, to determine the number of moves for this audio file\n");
    $exitmarker =1;
  }
  if ("x$strtmove" eq "x" or $strtmove=~/\D/ or $strtmove > $previouscount or $strtmove < 0){  # check for valid field content
    printstatus("Error: invalid fill move start defined - enter a number below $previouscount into field \"Fill move:\"\n");
    $exitmarker =1;
  }	  
  if ("x$stopmove" eq "x" or $stopmove=~/\D/ or $stopmove > $previouscount or $stopmove < 0){   # check for valid field content
    printstatus("Error: invalid fill move stop defined - enter a number below $previouscount into field \"To move:\"\n");
    $exitmarker =1;
  }	  
  if ("x$strtval" eq "x" or $strtval=~/\D/ or $strtval > $maxpwmvalue or $strtval < 0){         # check for valid field content
    printstatus("Error: invalid PWM value defined - enter a number in between 0 and $maxpwmvalue into field \"Value (upper)\"\n");
    $exitmarker =1;
  }	  
  if ("x$stopval" eq "x" or $stopval=~/\D/ or $stopval > $maxpwmvalue or $stopval < 0){         # check for valid field content
    printstatus("Error: invalid PWM value defined - enter a number in between 0 and $maxpwmvalue into field \"Value (lower)\"\n");
    $exitmarker =1;
  }	  
  if ($strtmove > $stopmove) {
    printstatus("Error: fill direction is negative \"Fill move\" must be smaller than or equal to \"To move\"\n");
    $exitmarker =1;
  }  
  if ($exitmarker) { printstatus("No changes have been made\n"); return;}
  my $len=$stopmove-$strtmove;                                             # number of steps to calculate
  my $valrange=$stopval-$strtval;                                          # pwm range for this vector
  my $val;
  for (my $act=0;$act<$num_actuators;$act++){
    if ($channelx[$act]->get() or $channely[$act]->get()) {                    # make a shortcut for quick access to the checkbox content
      for (my $b=0;$b <= $len;$b++){
        if ($len ) {
          $val=int($b*$valrange/$len+$strtval+0.5);                        # rounding the vector result
        } else {
          $val=$strtval;
        }
        $servocontent[$b+$strtmove][$actuators->[$act]->[6]]=$val;                              # enter the result into the servo array 
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
  if ($use_gamepad) {
    if (! $js) { err ("No Joystick $joystick_device found\n"); return 0;}
    $js->flushEvents;
  } else {
    $serial->purge_all();
  }
  @joy_content=(0,0,1,1);
  print_activeservos();                               # output the info which servos are active and what are the values before start
mainloop: while ($stop==1) {
    if (! get_one_read()){return;}                    # read one serial set
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
      state $frames=$player->frame();                 # Need this nasty construction to convince Audio::Play::MPG123 providing the frame 
      $player->poll(1);                               # count, since it does not deliver the frame count when the file has not start
      $frames=$player->frame();                       # playing ...
      $player->load($mp3);                            # make sure to start at the beginning of the file
#---------------------------------------------------------------------------------------------------------------------------------------
      if ($full_range==1){                            # record during whole MP3 or start with offset
        $contentcount=0;
      } else {
        my $jump;
        { 
          use bigfloat;
          $jump=int(($frames->[1]+1)*$minstep/($previouscount));
          no bigfloat;
        }
        $player->jump ($jump);
        $contentcount=$minstep;
      }
      $periodstart=gethrtime();                       # synchronize time reference with the start of the MP3
      $player->poll(0);
      $recording=1;                                   # indicator, that recording is active
      if ( ! add_one_set()) { return 0;}              # add the first set from the previous reading (start key trigger) + stop on failure
    }
    if ( ! $recording ) {showjoy();}                  # display the joystick value vs active servos while waiting for start
    if ( $recording==1 && (($periodstart + $stepwidth) <= gethrtime())) {
      get_one_read();                                 # if the period time has reached, read the cross stick
      #add_one_set();                                 # and add the data to the array -> not necessary, because after read
    }                                                 # recording is set to 2 by hsleep
    if ( $recording==2 ) {
      if ( ! add_one_set()) { return 0;}              # if the period is reached during a wait, take the data from the recent read + stop on failure
      if ((! $full_range==1) && $contentcount > $maxstep ){
        $recording=0;
        $packet_counter=1;
	disable_actuators(); 
        print "Press stop button to return to menu or start to run again\n";
        print_activeservos();                         # output the info which servos are active and what are the values before start
        next mainloop;
      } 
      $recording=1;                                   # reset the "period end during wait" flag 
    }
  }
  $packet_counter=1;
  disable_actuators();
  $player->stop();
  $recording=0;
}
#############################################################
#  add one data set to the array
#############################################################
sub add_one_set {                                                            # array content of actuators->[<actuator definition line in ConfigL::servosettings>]->[configfield]: 
  print "$contentcount";                                                     # ->[5] = Label of the actuator ->[6] = Servonumber of the actuator ->[7] = 0: then its a Servo. 
  my $viewall=$viewallbox->get();                                            # If ->[7] > 0 then its a relais and the content is a bitpointer to the bit of the relais in the servodata 
  for (my $act=0;$act<$num_actuators;$act++){                                # Valid values 0, 1-16 where >1 means Bitposition+1 to distinguish it from a servo marker 
    if ($justview==1){
      if ($viewall==1){ printactuator($act,$contentcount);
      } else { 
        if ($active_x[$act]) { printactuator($act,$contentcount);}
        if ($active_y[$act]) { printactuator($act,$contentcount);}
      }
    } else {
      if (my $bit=$actuators->[$act]->[7]) {                                 # it is a relay
        my $servonr=$actuators->[$act]->[6];
        my $bitpos=16-$bit;
        my $joyy=$joy_content[5]>=$servores;                                 # two step joy position y
        my $joyx=$joy_content[4]>=$servores;                                 # two step joy position x
        if ($active_x[$act]){
          if  ($joyx) {
            $servocontent[$contentcount][$servonr]=($servocontent[$contentcount][$servonr] | (1 << ($bit-1 & 0xF)));
          } else {
            $servocontent[$contentcount][$servonr]=($servocontent[$contentcount][$servonr] & ~(1 << ($bit-1 & 0xF)));
          }
          printactuator($act,$contentcount);
        }
        if ($active_y[$act]){
          if  ($joyy) {
            $servocontent[$contentcount][$servonr]=($servocontent[$contentcount][$servonr] | (1 << ($bit-1 & 0xF)));
          } else {
            $servocontent[$contentcount][$servonr]=($servocontent[$contentcount][$servonr] & ~(1 << ($bit-1 & 0xF)));
          }
          printactuator($act,$contentcount);
        } 
        
      } else {   
        if ($active_x[$act]) { $servocontent[$contentcount][$actuators->[$act]->[6]]=$joy_content[4];printactuator($act,$contentcount);}
        if ($active_y[$act]) { $servocontent[$contentcount][$actuators->[$act]->[6]]=$joy_content[5];printactuator($act,$contentcount);}
      }
    }
  }
  print "\n";
  for (my $c=0;$c<$num_servos;$c++) {
    if ( $contentcount==0 && $servocontent[$contentcount][$c] eq undef) { 
      $servocontent[$contentcount][$c]=$servores/2;   # if no data available, use middle position
    } else {
      if ( $servocontent[$contentcount][$c] eq undef) { 
	$servocontent[$contentcount][$c]=$servocontent[$contentcount-1][$c]; 
      }	
    }                                                 # fill empty fields with the content of the previous set
  } 
  $periodstart+=$stepwidth;
  $contentcount++; 
  return (put_one_move($servocontent[$contentcount-1]));
}
#############################################################
#  print the servo value or relais bits while viewing or recording
#############################################################
sub printactuator {
  my $act=shift;
  my $move=shift;
  if (my $bit=$actuators->[$act]->[7]) {                                                                # the actuator is a relay
    my $bitpos=16-$bit; 
    my $binary = sprintf("%016s", sprintf "%b", $servocontent[$move][$actuators->[$act]->[6]]); # make a binary representation of the 16 bit word
    my $mybit=substr($binary,$bitpos,1);
    $mybit="->$mybit<-";
    substr($binary,$bitpos,1,$mybit);
    print "\[".$actuators->[$act]->[6].":$binary:$actuators->[$act]->[5]\]";   
  } else {
     print"\[$actuators->[$act]->[6]:$servocontent[$move][$actuators->[$act]->[6]]\]";
  }
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
           maxrange();
           $maximize->uncheck; 
         } 
         print "Press stop button to return to menu or start to run again\n"; # if the MP3 is finished -> loop
         $packet_counter=1;
         print_activeservos();                        # output the info which servos are active and what are the values before start
	 disable_actuators();
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
    (my $dummy,$stepwidth,$servores,$num_servos)=unpack"vvvv",($data); # read the header into vars  
    if ($sumnum!=$sum) {                              # if file checksum is incorrect, die
      die "loaded file $outfilename has a bad checksum\n";
    }
    $stepwidth*=1000000;                              # convert step duration from ms into ns
    my $hz=1000000000/$stepwidth;
    $data=substr $data,8;                             # shorten the file
    my $j=0;                   
    while ( $data ) {                                 # as long as we have content, read it into array
      $servocontent[$j]=[unpack ("v[$num_servos]",$data)];
      $data=substr $data,$num_servos*2;
      $j++;         
    }
    $contentcount=$j-1;                               # note the number of sets in the file
    $previouscount=$contentcount;                     # remember the number of sets
    $maximize->uncheck;                               # keep the maximum moves until demanded manually
    printstatus( "Existing $outfilename has $j moves at a refresh rate of $hz Hz\n");  
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
# set the movement range to maximum after saving
#############################################################
sub maxrange{
  $startset->text(0);
  $stopset->text($previouscount);
  $maxset->text("<$previouscount>");
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
# Open the joystick-servo matrix dialog (popup window)
#############################################################
sub matrix_ui{
  if ( $in_popup ) { close_popups() }                 # make sure not to call any popup when already open
  $in_popup=1;
  $matrix_open=1;
  our (@pages);
  my $matrixpopup = $cui->add(
      'mtxpopupwin', 'Window',
      -border => 0,
      -centered => 1,
      -width => $matrix_popup_width,
      -height => $notebookheight+2,
      -title => 'Set the joystick - servo matrix',
      -releasefocus=>0
  );
  my $win1 = $matrixpopup->add(                       # The window for notebook x
                      undef, 'Window',
                       -border => 0,
                       -y    => 0,
                       -bfg  => 'red',
                       -x => 0,
                       -width => $matrix_popup_width-1,
                       -height => $notebookheight,
                       -releasefocus =>1
  );
  $nbx = $win1->add(                                  # The servo selection frame for joystick X
                    'NB1','Notebook',
                    -y => 0,
                    -bfg  => 'red',
                    -focusable =>1,
                    -releasefocus =>1
  );
  for (my $i=0;$i<$num_notebooks;++$i){
    $pages[$i] = $nbx->add_page($i+1,-focusable=>1,-releasefocus =>1,-border=>0);    #notebook pages x
  }
# ----------- Set up the servo checkbox selection ------
  if ( ! $boxes_exist ) {                                              # in the first run do not try to determine the checked status
    my $j=0;                                                           # The actuator number
    foreach  my $actuator (@$actuators) {                              # create a checkbox for each actuator configured in ConfigL split into notebooks
      my $i=int($j/($num_servos_per_row));   
      $channelx[$j] = $pages[$i]->add("mychannelx$j",'Checkbox',       # do this for the X joystick bindings 
                      -y=>$j-$i*($num_servos_per_row),
                      -x=>2,  
                      -onchange=>\&unchecky,
                      -focusable=>1,
                      -releasefocus=>1
      );
      $channely[$j] = $pages[$i]->add("mychannely$j",'Checkbox',       # do this for the y joystick bindings 
                   -label=>"    $actuators->[$j]->[5]($actuators->[$j]->[6])", 
                      -y=>$j-$i*($num_servos_per_row),
                      -x=>15,
                      -onchange=>\&uncheckx,
                      -focusable=>1,
                      -releasefocus=>1
      );
      $j++;
    }
    $boxes_exist=1;                                                    # note that further runs need to use the checked info
  } else {                                                             # subsequent runs of the popup window
    my $j=0;
    foreach  my $actuator (@$actuators) {                              # create a checkbox for each actuator configured in ConfigL split into notebooks
      my $i=int($j/($num_servos_per_row));   
      $channelx[$j] = $pages[$i]->add("mychannelx$j",'Checkbox',       # do this for the X joystick bindings 
                      -y=>$j-$i*($num_servos_per_row),
                      -x=>2,
                      -onchange=>\&unchecky,                           # enable auto unchecking in case a servo is activated at both joystics
                      -focusable=>1,
                      -releasefocus=>1,
                      -checked=>$cbox_x_saved[$j]                      # recover the saved checkbox status
      );
      $channely[$j] = $pages[$i]->add("mychannely$j",'Checkbox',       # and also for Y joystick bindings
                      -label=>"$actuators->[$j]->[5]($actuators->[$j]->[6])",
                      -y=>$j-$i*($num_servos_per_row),
                      -x=>15,
                      -onchange=>\&uncheckx,                           # enable auto unchecking in case a servo is activated at both joystics
                      -focusable=>1,
                      -releasefocus =>1,
                      -checked=>$cbox_y_saved[$j]                      # recover the saved checkbox status
      );
    $j++;
    }
  } 
  my $fixwin=$matrixpopup->add(                                        # helper window to isolate the close button (blue background and clash with the text on the same line)
                         undef,'Window',
                         -border=>0,
                         -y=>$notebookheight,
                         -height=>2 
                         -focusable=>1,
                         -releasefocus=>1
  );
  my $xboxlabel = $fixwin->add('myxboxlabel', 'Label', -text=>"Joystick X    Joystick Y", -bold=>1,-x=>1,-bg=>'red',-fg=>'white'); 
  my $matrixquitbutton= $fixwin->add('mymatrixquitbutton','Buttonbox',-buttons => [{-label => ' Close',-onpress => \&close_popups}],-y=>1,-fg=>'yellow',-bg=>'blue',-width=>7); # define close button
  my $notebooknotes= $fixwin->add('mynotebooknotes', 'Label', -text=>" Space:Toggle Box|Ctrl-L: Close|Pg-up,Pg-dn: cycle pages|Tab,Shift-Tab: cycle boxes|Ctrl-E: Clear boxes",-x=>7,-y=>1,-bg=>'black',-fg=>'white'); # define info text
  $matrixpopup->set_binding(\&clearcb,"\ce");
  $matrixpopup->focus;
  $matrixpopup->draw;
  #============================================================
  # clear all checkboxes of the checkbox matrix - called by Ctrl-E
  #============================================================
  sub clearcb {
    for (my $act=0;$act<$num_actuators;$act++){
        $channelx[$act]->uncheck();
        $channely[$act]->uncheck();
    }
    $nbx->draw();
  }
  #============================================================
}
#############################################################
# close all popups - called via button close or Ctrl-L
#############################################################
  sub close_popups {
    if ($matrix_open) {
      for (my $act=0;$act<$num_actuators;$act++){     # save the content of the checkboxes for later reuse since Curses_UI is not able to keep the status of closed popups
        $cbox_x_saved[$act]=$channelx[$act]->get();
        $cbox_y_saved[$act]=$channely[$act]->get();
      }
      $cui->delete('mtxpopupwin');
      $matrix_open=0;
      $in_popup=0;
      $cui->draw();
    }
    if ($blocks_open) {$cui->delete('popup_window');$blocks_open=0;$in_popup=0;$cui->draw()}
  }
#############################################################
# Open the block operations dialog - export and import blocks of movement
#############################################################
sub block_ui{
  if ( $in_popup ) { close_popups() }                 # make sure not to call any popup when already open
  $in_popup=1;
  our ($blkdir,@blkfilelist,$blockoutfilename,$maxblkfiles);
  our $blocks_exist=0;
  $blocks_open=1;
  my $popup = $cui->add(
      'popup_window', 'Window',
      -border => 1,
      -centered => 1,
      -width => $block_popup_width,
      -height => $notebookheight,
      -title => 'Save or load servo movement data blocks',
      -releasefocus=>0
  );
  # content of the Popup
  $popup->add('popup_label', 'Label', -text => 'Save or load servo movement data blocks');
  my $ff = $popup->add(                               # The file frame
                  'fra0', 'Container',
                   -border => 1,
                   -y    => 0,
                   -bfg  => 'red',
                   -title => 'File:',
                   -height => 4,
                   -releasefocus =>1
                 );
  my $rr = $popup->add(                               # The region range selection frame
                   'fra2', 'Container',
                   -border => 1,
                   -y    => 4,
                   -bfg  => 'red',
                   -title => 'Block Range',
                   -height => 4,
                   -releasefocus =>1
                 );
  my $ia = $popup->add(                               # The import as selection frame
                   'fra3', 'Container',
                   -border => 1,
                   -y    => 8,
                   -bfg  => 'red',
                   -title => 'Import as',
                   -height => 4,
                   -releasefocus =>1
                 );
  my $df = $popup->add(                               # The description frame
                  'fra4', 'Container',
                   -border => 1,
                   -y    => 12,
                   -bfg  => 'red',
                   -height => 6,
                   -title => 'Block Description:',
                   -releasefocus =>1
                 );
  my $sf = $popup->add(                               # The status frame
                  'fra5', 'Container',
                   -border => 1,
                   -y    => 18,
                   -bfg  => 'red',
                   -title => 'Status:',
                   -focusable =>0,
                 );
  my $filelabel = $ff->add('myfilelabel', 'Label', -text=>"Path: ", -bold=>1); 
  our $blockfileentry = $ff->add('mytextentry', 'TextEntry', -text=>$blkfilelist[0], -sbborder=>1,-y=>0,-x=>6);   # create the file path entry
  my $popup_buttons = $ff->add('popup_buttons', 'Buttonbox',                                                      # create buttons and their calls
     -buttons => [
        { -label => 'Close', -onpress=> \&close_popups},
        { -label => '<<', -value=>1, -shortcut=>'<',-onpress=> \&blockprev10},
        { -label => 'Prev', -value=>2, -shortcut=>'p',-onpress=> \&blockprev},
        { -label => 'Next', -value=>3, -shortcut=>'n',-onpress=> \&blocknext},
        { -label => '>>', -value=>4, -shortcut=>'>',-onpress=> \&blocknext10},
        { -label => 'Export', -value=>5, -shortcut=>'e',-onpress=> \&blkexport},
        { -label => 'Import', -value=>6, -shortcut=>'i',-onpress=> \&blkimport},
     ],-y=>1,-fg=>'yellow',-bg=>'blue',-width=>36);
  my $startblksrvlbl = $rr->add('mystartsrvlabel', 'Label', -text=>'From Servo: ', -bold=>1);
  our $startblksrv = $rr->add('mystartblksrv', 'TextEntry', -sbborder=>1,-x=>12,-width=>10); # fromservo popup field
  my $toblksrvlbl = $rr->add('mytosrvlabel', 'Label', -text=>'To Servo: ', -bold=>1, -x=>26);
  our $toblksrv = $rr->add('mytoblksrv', 'TextEntry', -sbborder=>1,-x=>36,-width=>10);                      # toservo popup field
  my $startblkmovlbl = $rr->add('mystartmovlabel', 'Label', -text=>'From Move: ', -bold=>1,-y=>1);
  our $startblkmov = $rr->add('mystartblkmov', 'TextEntry', -sbborder=>1,-x=>12,-width=>10,-y=>1);          # frommove field
  my $toblkmovlbl = $rr->add('mytomovlabel', 'Label', -text=>'To Move: ', -bold=>1, -x=>26,-y=>1);
  our $toblkmov = $rr->add('mytoblkmov', 'TextEntry', -sbborder=>1,-x=>36,-width=>10,-y=>1);                # tomove field
  my $ldblockvals = $rr->add('myldblockvals','Buttonbox',-buttons=> [{ -label =>'load_block_values',-shortcut=>'b',-onpress => \&loadblockvalues}],-y=>0,-x=>47,-fg=>'red',-bg=>'black'); 
  my $ldservofilemax = $rr->add('myldservofilemax','Buttonbox',-buttons=> [{ -label =>'load_servofile_maximum',-shortcut=>'s',-onpress => \&loadsrvfilemax}],-y=>1,-x=>47,-fg=>'red',-bg=>'black'); 
  my $impstartblksrvlbl = $ia->add('impmystartsrvlabel', 'Label', -text=>'Servo: ', -bold=>1);
  our $impstartblksrv = $ia->add('impmystartblksrv', 'TextEntry', -sbborder=>1,-x=>12,-width=>10,-onblur =>\&settosrv); # import fromservo field
  my $imptoblksrvlbl = $ia->add('impmytosrvlabel', 'Label', -text=>'To: ', -bold=>1, -x=>26);
  our $imptoblksrv = $ia->add('impmytoblksrv', 'TextEntry', -sbborder=>1,-x=>36,-width=>10);                # import toservo field
  my $impstartblkmovlbl = $ia->add('impmystartmovlabel', 'Label', -text=>'Move: ', -bold=>1,-y=>1);
  our $impstartblkmov = $ia->add('impmystartblkmov', 'TextEntry', -sbborder=>1,-x=>12,-width=>10,-y=>1,-onblur => \&settomov); # import frommove field
  my $imptoblkmovlbl = $ia->add('impmytomovlabel', 'Label', -text=>'To: ', -bold=>1, -x=>26,-y=>1);
  our $imptoblkmov = $ia->add('impmytoblkmov', 'TextEntry', -sbborder=>1,-x=>36,-width=>10,-y=>1);          # import tomove field
  our $description = $df->add('mydescription','TextEditor',-vscrollbar=>1, -wrapping=>1);
  our $blkstatus = $sf->add('blkstatustext','TextViewer', -fg=>'yellow',-wrapping=>1,-focusable=>0);
  our $blkstatusheight=$blkstatus->height();
  $popup->focus;
  $popup->draw;                                                            # show the popup
  blockfile(0);                                                            # force reading the first block header
  #------------------------------------------------------------
  #  load the servofile maximum values into the four fromto parameters - called by keypress 's' or 'load_servofile_maximum'
  #------------------------------------------------------------
  sub loadsrvfilemax {
    if ( $previouscount==undef ) {                  # if no maxset - exit
      err("Error: No moves defined yet - record at least one time first,\nto determine the number of moves for this audio file");
      blkprintstatus("Loading servo file maximum: - nothing loaded\n");
      return 0;
    }
    $startblksrv->text(0);    
    $startblkmov->text(0);    
    $toblksrv->text($num_servos-1);
    $toblkmov->text($previouscount);
    $rr->draw(1);    
  }
  #------------------------------------------------------------
  #  load the max. block values into the four fromto parameters - this happens on hitting button "load_block_values" or keypress 'b'
  #------------------------------------------------------------
  sub loadblockvalues {
    if ( $previouscount==undef ) {                  # if no maxset - exit
      err("Error: No moves defined yet - record at least one time first,\nto determine the number of moves for this audio file");
      blkprintstatus("Loading block values: - nothing loaded\n");
      return 0;
    }
    my $rawheader=loadblkheader();
    my ($fromservo,$toservo,$frommove,$tomove)=unpack"vvvv",($rawheader); # read the header into vars
    $rawheader=substr $rawheader,8;                                       # cut off the header to get the description
    $startblksrv->text($fromservo);
    $impstartblksrv->text($fromservo);
    $description->text($rawheader);
    $toblksrv->text($toservo);
    $imptoblksrv->text($toservo);
    $startblkmov->text($frommove);
    $impstartblkmov->text($frommove);
    $toblkmov->text($tomove);
    $imptoblkmov->text($tomove);
    $rr->draw(1); 
    $df->draw(1);
    $ia->draw(1);
  }
  #------------------------------------------------------------
  #  read the file list of the block directory
  #------------------------------------------------------------
  sub get_blkfilelist {
    $blkdir=$mp3dir."/block";                                         # always try to read fom subdir 'block' in mp3 directory
    unless (-d $blkdir) {
      mkdir ($blkdir,0755) or die "could not create directory $blkdir $!"; # create it if it does not exist
      blkprintstatus ("created directory $blkdir");     
    }
    @_= File::Find::Rule->file()                                      # check the block directory and fill the array with the file names
           ->name("*.blk")
           ->maxdepth(1)
           ->in( $blkdir );
    @blkfilelist=sort(@_);
    $maxblkfiles=$#blkfilelist;                                       # note the number of blocks in folder
    if ( $maxblkfiles == -1) { err("No files to process in $blkdir")}
  }
  #------------------------------------------------------------
  #  saves the block data as a .blk file 
  #------------------------------------------------------------
  sub blkexport{
    $blockoutfilename=$blockfileentry->get(); 
    if (! ($blockoutfilename =~ /\.blk$/)){                           # make sure we have the .blk extension
      $blockoutfilename.=".blk";                                      # add desired extension
      $blockfileentry->text($blockoutfilename);                       # and update the file field in popup
    }  
    my $bincontent;                                                   # this var receives the binary coded servo positions
    my $fromservo=$startblksrv->get();
    my $toservo=$toblksrv->get();
    my $frommove=$startblkmov->get();
    my $tomove=$toblkmov->get();
    if ($fromservo eq ""|$fromservo !~ /\d/) {$fromservo=0;}          # if fromservofield is empty or not numeric - use zero
    if ($toservo eq ""|$toservo !~ /\d/) {$toservo=$num_servos-1;} # if toservofield is empty or not numeric use maximum servos
    if ($frommove eq ""|$frommove !~ /\d/) {$frommove=0;}             # same for frommove - use zero
    if ($tomove eq ""|$tomove !~ /\d/) {$tomove=$previouscount;}          # same for tomove - use maximum number of moves
    if ( $previouscount==undef ) {                  # if no maxset - exit
      err("Error: No moves defined yet - record at least one time first,\nto determine the number of moves for this audio file");
      blkprintstatus("File $blockoutfilename not written\n");
      return 0;
    }
    if ($toservo < $fromservo) {                                                                    # value limit checks
      err("Error: From Servo: must be smaller than To Servo:");                                     #  v    v    v    v
      blkprintstatus("File $blockoutfilename not written\n");
      return 0;
    }    
    if ($tomove < $frommove) {
      err("Error: From Move: must be smaller than To Move:");
      blkprintstatus("File $blockoutfilename not written\n");
      return 0;
    }
    if ($fromservo > $num_servos-1) {
      err("Error: From Servo: is larger than maximal number of servos ($num_servos)");
      blkprintstatus("File $blockoutfilename not written\n");
      return 0;
    }
    if ($toservo > $num_servos-1) {
      err("Error: To Servo: is larger than maximal number of servos ($num_servos)");
      blkprintstatus("File $blockoutfilename not written\n");
      return 0;
    }
    if ($frommove > $previouscount) {
      err("Error: From Move: is larger than maximal number of moves existing($previouscount)");
      blkprintstatus("File $blockoutfilename not written\n");
      return 0;
    }
    if ($tomove > $previouscount) {
      err("Error: To Move: is larger than maximal number of moves existing($previouscount)");
      blkprintstatus("File $blockoutfilename not written\n");
      return 0;
    }
    my $target_length = 1024;                         # string length of description
    my $exist = (stat("$blockoutfilename"))[2];       # check if a block file exists
    if ( $exist ) {
      my $answer=$cui->dialog(-message => "$blockoutfilename exists - overwrite ?",
                              -buttons=>[
                              { -label => 'No', -value=>0, -shortcut=>'n'},
                              { -label => 'Yes', -value=>1, -shortcut=>'y'}
                              ]);
      if ( $answer!=1) {
        blkprintstatus("Leave file $blockoutfilename untouched\n");
        return 0;
      }
    }
      for (my $j=$frommove;$j<=$tomove;$j++) {        # put the array elements step by step binary coded into the string
        for (my $i=$fromservo;$i<=$toservo;$i++) {
        $bincontent.=pack "v",($servocontent[$j][$i]);# save each servo position into a 16 bit word
      }
    }
    my $header=pack "vvvv",($fromservo,$toservo,$frommove,$tomove); # binarize the header elements
    my $descript=$description->get();
    if (length($descript) < $target_length) {
      $descript = $descript . (' ' x ($target_length - length($descript)));
    } else {
      $descript = substr($descript, 0, $target_length);
    }
    my $sum=pack 'v',(unpack("%16C*",$header.$descript.$bincontent) % 32767); # calculate the checksum for the complete data stream
    my $success= open (BIN,">$blockoutfilename");
    if (!$success) {
      my $msg=$!;
      err( "Cannot create output file $blockoutfilename $!");
      blkprintstatus("File $blockoutfilename not written - $msg\n");
      return 0;
    }
    binmode BIN;
    print BIN $header.$descript.$bincontent.$sum;     # save header,body and checksum into file
    close (BIN);
    $cui->nostatus;
    blkprintstatus("$blockoutfilename written - Servo: $fromservo to $toservo & Move: $frommove to $tomove\n");
    blockfile(0);                                     # update the limit fields 
    return 1;
  }
  #------------------------------------------------------------
  #  load block header from file to fill the from and to fields
  #------------------------------------------------------------
  sub loadblkheader{
    $blockoutfilename=$blockfileentry->get();
    if ($blockoutfilename eq "") {
      err("Provide a file name to read header or to export moves!");
      $blockoutfilename=$blkdir;                      # in caase of empty block file list - default to current block file directory
      $blockfileentry->text("$blockoutfilename/default-please-change");
      return 0;
    }
    my $exist = (stat("$blockoutfilename"))[2];       # check if a servo file exists
    if ( $exist ) {                                   # load it, if so
      open (BIN,"<$blockoutfilename")||err("Cannot open File $blockoutfilename $!");
      my $data;
      if (read BIN,my $chunk,1032) {                  # read only the header info 
        $data.=$chunk;                                # read the data into var
      }
      close (BIN);
      return $data;
      $blocks_exist=1;
    } else {return 0;}
  }
  #------------------------------------------------------------
  #  load previously saved block extract from file
  #------------------------------------------------------------
  sub blkimport{
    $blockoutfilename=$blockfileentry->get();         # get the filename from popup window
    if ($blockoutfilename eq "") {
      err("Please provide a file name to import - cancelling !");
      return 0;
    }
    blkprintstatus("Importing $blockoutfilename - please wait..\n");
    my $exist = (stat("$blockoutfilename"))[2];       # check if a servo file exists
    if ( $exist ) {                                   # load it, if so
      open (BIN,"<$blockoutfilename")||err("Cannot open File $blockoutfilename $!");
      my $data;
      while (read BIN,my $chunk,8192) {
        $data.=$chunk;                                # read the data into var
      }
      close (BIN);
      my $lastbyte=chop $data;                        # cut off the checksum
      my $prelastbyte=chop $data;
      my $sumnum=unpack 'v',($prelastbyte.$lastbyte); # convert the binary checksum into a number
      my $sum=unpack("%16C*",$data) % 32767;          # calculate the checksum for the data
      if ($sumnum!=$sum) {                            # if file checksum is incorrect, die
        die "loaded file $blockoutfilename has a bad checksum\n";
      }
      my $rawheader=substr($data,0,8);                # extract the header
      $data=substr($data,8);                          # shorten the data block
      my ($fromservo,$toservo,$frommove,$tomove)=unpack"vvvv",($rawheader); # read the header into vars
      my $descript=substr($data,0,1024);              # extract the description
      $data=substr($data,1024);                       # shorten the data block - from here $data only contains moves 
      my $num_servos=($toservo-$fromservo)+1;         # number of servos in block
      my $nummoves=($tomove-$frommove)+1;             # number of moves in block
      my $ifromservo=$impstartblksrv->get();          # desired servo start in servoarray
      my $itoservo=$imptoblksrv->get();               # desired servo stop in servoarray 
      my $ifrommove=$impstartblkmov->get();           # desired move start in servoarray
      my $itomove=$imptoblkmov->get();                # desired move stop in servoarray
      if ($itoservo > ($ifromservo+($num_servos-1))) {$itoservo=$ifromservo+($num_servos-1);}#if servo stop field would exceed the block, calc the value from block
      if ($itomove > ($ifrommove+($nummoves-1))) {$itomove=$ifrommove+($nummoves-1);}#if move stop field would exceed the block, calc the value from block
      if ($ifromservo !~ /\d/) {$ifromservo=0;}       # if servo start field is empty use zero 
      if ($itoservo !~ /\d/) {$itoservo=$ifromservo+($num_servos-1);}#if servo stop field is empty calc the value from block
      if ($ifrommove !~ /\d/) {$ifrommove=0;}         # if move start field is empty use zero
      if ($itomove !~ /\d/) {$itomove=$ifrommove+($nummoves-1);}#if move stop field is empty calc the value from block
      my $servorange=($itoservo-$ifromservo)+1;       # calc the nuber of target servos in servoarray
      my $moverange=($itomove-$ifrommove)+1;          # calc the nuber of target moves in servoarray
      if ( $previouscount==undef ) {                  # if no maxset - exit
        err("Error: No moves defined yet - record at least one time first,\nto determine the number of moves for this audio file");
        blkprintstatus("File $blockoutfilename not imported\n");
        return 0;
      }
      if ($itoservo < $ifromservo) {
        err("Error: From Servo:\($ifromservo\) must be smaller than To Servo:\($itoservo\)");
        blkprintstatus("File $blockoutfilename not imported\n");
        return 0;
      }
      if ($itomove < $ifrommove) {
        err("Error: From Move:\($ifrommove\) must be smaller than To Move:\($itomove\)");
        blkprintstatus("File $blockoutfilename not imported\n");
        return 0;
      }
      if ($ifromservo > $num_servos-1) {
        err("Error: From Servo: is larger than maximal number of servos ($num_servos)");
        blkprintstatus("File $blockoutfilename not imported\n");
        return 0;
      }
      if ($itoservo > $num_servos-1) {
        err("Error: To Servo: is larger than maximal number of servos ($num_servos)");
        blkprintstatus("File $blockoutfilename not imported\n");
        return 0;
      }
      if ($ifrommove > $previouscount) {
        err("Error: From Move: is larger than maximal number of moves existing($previouscount)");
        blkprintstatus("File $blockoutfilename not imported\n");
        return 0;
      }
      if ($itomove > $previouscount) {
        err("Error: To Move: is larger than maximal number of moves existing($previouscount)");
        blkprintstatus("File $blockoutfilename not imported\n");
        return 0;
      }
      my $i=0;
      my @blockcontent;
      while ( $data ) {                                      # as long as we have content, read it into array
        $blockcontent[$i]=[unpack ("v[$num_servos]",$data)]; # extract into a separate array @blockcontent to be able to shift the data to the destination
        $data=substr $data,($num_servos)*2;                  # shorten the array after extraction
        $i++;
      }
      iloop: for ($i=0;$i<$nummoves;$i++){                   # transfer the data to the desired destination
        jloop: for (my $j=0;$j<$num_servos;$j++){
          $servocontent[$i+$ifrommove][$j+$ifromservo]=$blockcontent[$i][$j];
          if ($j>=$servorange-1){ last jloop }
        }
        if ($i>=$moverange-1) { last iloop }
      }
     blkprintstatus("$blockoutfilename imported: $moverange moves @ $servorange Servos: $ifromservo to $itoservo Moves: $ifrommove to $itomove\n");
    }
    $cui->nostatus;
  }
  #------------------------------------------------------------
  # print servo array extract for debug purposes
  #------------------------------------------------------------
  sub printarray {
    my $arrayref=shift; 
    my $fromservo=shift;
    my $toservo=shift;
    my $frommove=shift;
    my $tomove=shift;
    print STDERR "fromservo: $fromservo toservo: $toservo frommove: $frommove tomove: $tomove\n"; 
    for (my$i=$frommove;$i<=$tomove;$i++){
      for (my$j=$fromservo;$j<=$toservo;$j++){
        print STDERR sprintf("0x%04X ", $arrayref->[$i]->[$j]);
      }
      print STDERR "\n";
    }
    print STDERR "-----------------------------------------------------------------------------\n";
  }
  #------------------------------------------------------------
  # switch to previous or next block file
  #------------------------------------------------------------
  sub blocknext {
    blockfile(1);   # +1 file
  }
  sub blocknext10 {
    blockfile(10);  # +10 files
  }
  sub blockprev {
    blockfile(-1);
  }
  sub blockprev10 {
    blockfile(-10);
  }
  #------------------------------------------------------------
  # determine the next block file name and output to popup
  #------------------------------------------------------------
  sub blockfile {
    get_blkfilelist();                                          # include previously new created files
    my $move=shift;
    state $blkfilepos+=$move;                                   # update the position in the array we are reading from
    if ($blkfilepos <= 0) { $blkfilepos=0 }                     # do not go beyond first file
    if ($blkfilepos > $maxblkfiles) { $blkfilepos=$maxblkfiles }# and do not exceed last file
    $blockoutfilename=$blkfilelist[$blkfilepos];
    $blockfileentry->text($blockoutfilename); 
    $ff->draw(1);
    loadblockvalues();
  }
  #------------------------------------------------------------
  # set popup block field "toservo" automatically calculated from $fromservo / $numservos
  #------------------------------------------------------------
  sub settosrv {
    if (! $blocks_exist) {                            # dont struggle with nonexisting values
      return 0;
    }
    my $fromservo=$startblksrv->get();                # determine block start servo
    my $toservo=$toblksrv->get();                     # determine block stop servo
    my $num_servos=($toservo-$fromservo);             # number of servos in block
    my $ifromservo=$impstartblksrv->get();            # desired servo start in servoarray
    my $newtext=$ifromservo+$num_servos;              # calc the value from block
    if ($newtext > ($num_servos-1)){                  # value must be lower than max. number of servos in svo file 
      $newtext=$num_servos-1;                         # limit to this value
    } 
    $imptoblksrv->text($newtext);                     # set the itoservo with calculated value
    $ia->draw(1);
  }
  #------------------------------------------------------------
  # set popup block field "tomove" automatically calculated from $frommove / $previouscount
  #------------------------------------------------------------
  sub settomov {
    if (! $blocks_exist) {                            # dont struggle with nonexisting values
      return 0;
    }
    my $frommove=$startblkmov->get();                 # determine block start move
    my $tomove=$toblkmov->get();                      # desired move stop in servoarray
    my $nummoves=($tomove-$frommove);                 # number of moves in block
    my $ifrommove=$impstartblkmov->get();             # desired move start in servoarray
    my $newtext=$ifrommove+$nummoves;                 # calc the value from block
    if ($newtext > $previouscount) {                      # value must be lower than max. number of moves in svo file
      $newtext=$previouscount;                            # limit to this value
    }
    $imptoblkmov->text($newtext);                     # set the itoservo with calculated value
    $ia->draw(1);
  }
  #------------------------------------------------------------
  # output text to block status section
  #------------------------------------------------------------
  sub blkprintstatus {
    state @statuslines;                                         # keep the content of the status window permanently
    state $statpos=0;
    my $spos=0;                                                 # position inside the input string  to insert a newline - applies when a statusline is longer than the popup window
    my $width=$block_popup_width-5;
    my $outline;                                                # the text to pass to the status TextViewer
    my $new_line=(shift);                                       # here comes the staus string in full length
    my $len=length($new_line);                                  # note the length
    my $zeilen=int((length($new_line)+$width -1) / $width);     # determine how many times the full string must be split to fit into the popup
    for (my $i=0;$i<$zeilen;$i++) {                             # number of splits 
      $statpos++;                                               # with each split increase the line counter statuspos
      push (@statuslines,(substr $new_line,$spos,$width));      # add the piece of the full status line to the staus line array
      $spos=+$width;                                            # update where to read next piece
      if ($statpos > $blkstatusheight) {                        # if the last line in the TextViewer has been reached, remove a line at the front - result is scrolling
        shift @statuslines;                                    
      }
    }
    foreach my $statusline (@statuslines) {                     # take the output text form statusarray
      $outline.=$statusline;                                    
    }
    $blkstatus->text($outline);                                 # write text to the TextViewer frame
    $blkstatus->draw(1);                                        # and update the screen
  }
}
#############################################################
# print the active servos as a line with values of move before actual
#############################################################
sub print_activeservos {
  my $n=0;
  print "Start values of active actuators at move $minstep: "; 
  for (my $act=0;$act<$num_actuators;$act++){
    if ($minstep==0){                                  # when recording starts from the first move (0) there is no previous - then show the 0 -move values
      if ($active_x[$act]|$active_y[$act]) {
        if ($actuators->[$act]->[2]==2){                        
          printactuator($act,$minstep);$n=1;           # its a relay  - so print the bitfield of startmove
        } else {
          print"\[$actuators->[$act]->[6]:$servocontent[$minstep][$actuators->[$act]->[6]]\]";$n=1; # its a servo
        }
      }
    } else {                                           # output the active servo value steps before the actual move - allows to move the joystick manually seamless to the previous value                       
      if ($active_x[$act]|$active_y[$act]) {
        if ($actuators->[$act]->[2]==2) {
          printactuator($act,$minstep-1);$n=1;         # its a relay - so print bitfield of startmove
        } else {
          print"\[$actuators->[$act]->[6]:$servocontent[$minstep-1][$actuators->[$act]->[6]]\]";$n=1; # its a servo
        }
      }
    }
  }
  if ($n==1){print "\n";}
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
# output error message to dialog
#############################################################
sub err {
  my $msg=shift;
  $cui->error($msg);
  #exit_dialog();
}
#############################################################
# output path to main file section
#############################################################
sub showpath {
  $fileentry->text(shift); 
  $fileentry->draw(1);
}
#############################################################
# output text to main status section
#############################################################
sub printstatus {
  state $statuspos;                                   # the actual position in the status section to be output to
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
#  make sure never x and y are checked together since only one joystick direction may be bound with the same servo
#############################################################
sub uncheckx {
  for (my $act=0;$act<$num_actuators;$act++){
    if($channely[$act]->get()){
      $channelx[$act]->uncheck();
    }
  } 
}
sub unchecky {
  for (my $act=0;$act<$num_actuators;$act++){
    if($channelx[$act]->get()){
      $channely[$act]->uncheck();
    }
  } 
}
#############################################################
#  saves the recorded data
#############################################################
sub save_file{
  my $bincontent;                                     # this var receives the binary coded servo positions 
  my $j=0;
  $cui->status("Saving file $outfilename - please wait ....");
  foreach my $set (@servocontent) {                   # put the array elements step by step binary coded into the string
    for (my $i=0;$i<$num_servos;$i++) {               
      $bincontent.=pack "v",($set->[$i]);             # save each servo position into a 16 bit word
    }
    if ($j>=$previouscount) { last }                  # only write till the new end
    $j++;
  }
  my $header=pack "vvvv",($previouscount,$stepwidth/1000000,$servores,$num_servos); # binarize the header elements
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
  if ($use_gamepad) {                                 # ----------------------- gamepad handling ---------------------------------
    if (! $js) { err ("No Joystick $joystick_device found\n"); return 0;}
    hsleep ($waittime_serial);
    my $event=$js->nextEvent;
    if ($event){
      if ($event->isButton) {
        if ($event->button == $gamepad_start) {
          if ($event->buttonDown){
            $joy_content[3]=0;
          } else {
            $joy_content[3]=1;
          }
        }
        if ($event->button == $gamepad_stop) {
          if ($event->buttonDown){
            $joy_content[2]=0;
          } else {
            $joy_content[2]=1;
          }
        }
      }
      if ($event->isAxis) {
        if ($event->axis == $gamepad_axis_x) {
          $joy_content[0]=$event->axisValue;
        }
        if ($event->axis == $gamepad_axis_y) {
          $joy_content[1]=$event->axisValue;
        }
      }
    }
    $joy_content[4]=int($servores * ($joy_content[0]-$gamepad_x_start) / ($gamepad_x_end-$gamepad_x_start));
    if ( $joy_content[4] <= 0 ) { $joy_content[4]=1; }
    $joy_content[5]=int($servores * ($joy_content[1]-$gamepad_y_start) / ($gamepad_y_end-$gamepad_y_start));
    if ( $joy_content[5] <= 0 ) { $joy_content[5]=1; }
  } else {                                             # --------------------------- serial joystick handling ----------------------------
    my ($count,$data,$i)=(0,0,0);
    while (! (substr $data,-1 eq "\n")) {
      $serial->write('4');              # sent the command to the arduino to send one set
      hsleep ($waittime_serial);
      ($count,$data)=$serial->read(32);
      if ( $count ) {                   # if we have data, put it into the array
        @joy_content=split / /,$data;
        $joy_content[4]=int($servores * ($joy_content[0]-$joystick_x_start) / ($joystick_x_end-$joystick_x_start));
        if ( $joy_content[4] <= 0 ) { $joy_content[4]=1; }
        $joy_content[5]=int($servores * ($joy_content[1]-$joystick_y_start) / ($joystick_y_end-$joystick_y_start));
        if ( $joy_content[5] <= 0 ) { $joy_content[5]=1; }
      } else { $serial->purge_all(); }  # else try again
      if ($i >= 10) { err "serial device does not respond"; return 0;}
      $i++;
    }
  }
  return 1;
}
#############################################################
#  move one set - send positions to servos
#############################################################
sub put_one_move {
  my $setref=shift;                                           # contains the refereence to one anonymous array containing the moves for one set
  my $i=0;
  my @pcapos=();                                              # contain the data for output to PCA9685
  my @netstream=();                                           # contain the data for network output
  foreach my $servopos (@$setref) {                           # set the positions for all of the servos
    my $way=($servosettings->[$i]->[1]+1)-$servosettings->[$i]->[0];  # the drive way (resolution) of the servo (<= 4096 steps)
    my $resfactor=$way/$servores;                             # calculate the correction factor PCA9685 has 4096 steps
    my $pos;
    if ($servosettings->[$i]->[2]==2) {                       # check the 3rd field in the servosettings array - used for invert and relay servo
      $pos=$servopos;                                         # it is a relay bitfield, so take the value without calc
    } 
    elsif ($servosettings->[$i]->[2]==1) {                    # it is an inverted servo 
      $pos=int(($servores-$servopos)*$resfactor+$servosettings->[$i]->[0]); # take the Servostart from ConfigL::servosettings and invert the direction
    } 
    elsif ($servosettings->[$i]->[2]==0) {                    # it is a non inverted servo
      $pos=int($servopos*$resfactor+$servosettings->[$i]->[0]);  # take the Servostart from ConfigL::servosettings
    }
    else {
      printstatus("Servo $i Field 3(2) in ConfigL.pm has a invalid value. Please correct\n");
      return 0;
    }
    if ($sendtopca ) {
      if ($servosettings->[$i]->[2]==2){
        push (@pcapos,(0,$servosettings->[$i]->[0]));         # put servo to 0 limit position @ PCA, where a relay data is send to the network
      } else {
        push (@pcapos,(0,$pos));                              # regular servo data, not relay
      }
    }
    if ($sendtonet) {push (@netstream,$pos);}
    $i++;
  }
  if ($sendtonet) {
    send_data_broadcast(\@netstream,\$packet_counter);        # output moves via broadcast to network - seems to be quicker, though not parallel
    $packet_counter = ($packet_counter + 1) & 0xFFFF;         # increment packet counter with overflow at 65535
  }
  if ($sendtopca) {
    setChannelPWM(0,\@pcapos);                                # output moves to a directly connected PCA9685 to the Raspi
  }
  return 1;
}
#############################################################
#  ouput the movement data via network as broadcast
#############################################################
sub send_data_broadcast {
  my ($data_array_ref,$pk_ct_ref) = @_;
  my $data_length = scalar(@$data_array_ref);               # determine data length
  my @packet_data = ($data_length, $$pk_ct_ref, @$data_array_ref);# size  + packet counter + data
  socket(my $sock, PF_INET, SOCK_DGRAM, getprotobyname('udp')) or die "Could not create Socket: $!";
  setsockopt($sock, SOL_SOCKET, SO_BROADCAST, 1) or die "Could not activate broadcast: $!";
  my $dest_addr = sockaddr_in($netport, INADDR_BROADCAST);  # set broadcast destination address
  my $packed_data = pack('n*', @packet_data);               # convert data into big endian for the network
  add_crc16_to_scalar(\$packed_data);                       # add the CRC at the end
  send($sock, $packed_data, 0, $dest_addr) or die "Send Error: $!"; # send to the network
  close($sock);
  return 1;
}
#############################################################
# send a register command to the network (nodes)
#############################################################
sub bcast {
  my $packet_data_ref=shift;
  socket(my $sock, PF_INET, SOCK_DGRAM, getprotobyname('udp')) or die "Could not create Socket: $!";
  setsockopt($sock, SOL_SOCKET, SO_BROADCAST, 1) or die "Could not activate broadcast: $!";
  my $dest_addr = sockaddr_in($netport, INADDR_BROADCAST);          # set broadcast destination address
  my $packed_data = pack('n*', @$packet_data_ref);                  # convert data into big endian for the network
  add_crc16_to_scalar(\$packed_data);
  send($sock, $packed_data, 0, $dest_addr) or die "Send Error: $!"; # send to network
  close($sock);
  return 1;
}
#############################################################
#  calculate and add the CRC for the operation datagram
#############################################################
sub add_crc16_to_scalar {
  my ($data_ref) = @_;  # Referenz auf Skalar (Binary String)
  my $crc = 0xFFFF;
  foreach my $byte (unpack('C*', $$data_ref)) {                  # Process string data
    $crc ^= $byte;
    for (my $i = 0; $i < 8; $i++) {
      if ($crc & 0x0001) {
        $crc = ($crc >> 1) ^ 0xA001;
      } else {
        $crc >>= 1;
      }
    }
  }
  $$data_ref .= pack('v', $crc);  # 'v' = 16-bit Little-Endian CRC - add 2 Bytes to the String 
}
#############################################################
#  output the joystick position while waiting for start
#############################################################
sub showjoy {
  syswrite(STDOUT, "X: $joy_content[4] Y: $joy_content[5]                            \r"); 	
}
#############################################################
#  Does a simple hardware test - this routine never stops !!!
#  only to be run on demand for testing purposes
#############################################################
sub hardwaretest {
  $serial->purge_all();                                      # clear the buffers of the serial line 
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
  state $filepos+=$move;                              # update the position in the array we are reading from
  if ($filepos <= 0) { $filepos=0 }                   # do not go beyond first file
  if ($filepos > $maxfiles) { $filepos=$maxfiles }    # and do not exceed last file
  return $filelist[$filepos];                         # return the mp3 file to load
}
#############################################################
#  copy servo move sets to other servos - called via button 'copy'
#############################################################
sub copyservo {
  my $srcsvo=$cpsrc->get();
  my $destsvo=$cpdst->get();
  my $tillsvo=$cptill->get();                                       
  my $strtset=$startset->get();                       # the move number to start copying
  my $stpset=$stopset->get();                         # the move number to stop copying
  my $shift=$cpshift->get();                          # how much to shift within the servo
  my $rotate=$cprot->get();                           # rotate if indicated - means exceeding moves will be wrapped around
  my $invert=$cpinv->get();                           # invert if indicated - the movement direction is inverted
  my $svocopydirection;
  my $movecopydirection;
  my $invtxt="";                                      # inverted text - goes into copy message when inverted
  my $svorange;                                       # How many servos to copy in one go
  my $svospan;                                        # How many servos to copy in one go - alway positive
  my $svodist;                                        # distance in between source and destination servo
  my $exitmarker=0;
  my @copycontent;
  if ( $previouscount==undef ) {                      # if no maxset - exit
    printstatus("Error: No moves defined yet - record at least one time first, to determine the number of moves for this audio file\n");
    $exitmarker =1;
  }
  if ("x$srcsvo" eq "x" or $srcsvo=~/\D/ or $srcsvo >= $num_servos) {    # sourceservo is valid and numeric ?
    printstatus("Error: invalid source servo defined - enter a number into field \"From:\"\n");
    $exitmarker =1;
  }
  if ($destsvo >= $num_servos) {                      # destservo is valid and numeric ?
    printstatus("Error: invalid destination servo - must be below $num_servos\n");
    $exitmarker =1;
  }
  if ("x$destsvo" eq "x" or $destsvo=~/\D/) {         # destservo is valid and numeric ?
    printstatus("Error: invalid destination servo defined - enter a number into field \"To:\"\n");
    $exitmarker =1;
  }
  if ("x$tillsvo" eq "x"){$tillsvo=int($srcsvo);$svorange=0;$svocopydirection=1} else {
    if ($tillsvo=~/\D/){                              # tillservo is not numeric ? 
      printstatus("Error: \"Till:\" must be numeric\n");
      $exitmarker =1;
    } 
    $svorange=$tillsvo-$srcsvo;                       # how many servos to copy
    $svospan=abs($svorange);                          # to make svospan always positive
    if ($tillsvo < $srcsvo){$svocopydirection=0;} else { $svocopydirection=1;}    # determine the servo copy direction
    if ($destsvo + $svospan >= $num_servos){
      printstatus("Error: Copy destination exceeds maximum number of servos\n");
      $exitmarker =1;
    }
  }
  if ("x$shift" eq "x"){$shift=0;}                    # if the shift field has left empty take it as zero
  my $moves;                                          # contains how many moves to copy
  if ($stpset-$strtset >= 0) {$movecopydirection=1;$moves=$stpset-$strtset;}else{$movecopydirection=0;$moves=$strtset-$stpset} # determine the moves copy direction
  $moves++;
  if ($rotate) {
    if ($shift > $previouscount or ($shift * -1)>$previouscount){ # make sure number of shifts is smaller or equal than number of moves
      printstatus("Error: Shift-Rotate for more than $previouscount moves - decrease number of shifts\n");
      $exitmarker=1;
    } 
  } else {
    if ($shift+$strtset+$moves >= $previouscount or $shift+$strtset+$moves <= 0){
      printstatus("Error: Shifting exceeds move 0 or maximum number of moves - decrease number of shifts or change \"Start/Stop at move\"\n");
      $exitmarker=1;
    }  
  }  
  if ($exitmarker) { printstatus("nothing has been copied !\n"); return 0 }
  $svodist=$destsvo-$srcsvo;                          # distance between source and destination servo
  my $jb=0;                                           # buffer counter for Servos
  my $ib;                                             # buffer counter for moves
  my $ii;                                             # read the moves starting from this set
  #-------------------here we first fill the buffer with the servo moves --------- 
  for (my $j=$srcsvo;ckloop($j,$tillsvo,$svocopydirection);$j=crement($j,$svocopydirection)) {
    $ii=$strtset;
    $ib=0;
    for (my $i=0;$i < $moves;$i++) {
      if ($ii < 0) {$ii=$previouscount}               # turn around (rotate) reading when counting down
      if ($ii > $previouscount) {$ii=0}               # turn around (rotate) when counting up
      if ($invert) {
	 my $inverted=$servores-$servocontent[$ii][$j]; # invert the servo pwm value
         $copycontent[$ib][$jb]=$inverted;            # and put into content array
	 $invtxt=" inverted";
      } else {
         $copycontent[$ib][$jb]=$servocontent[$ii][$j]; # use the un-inverted servo PWM value
	 $invtxt="";
      }
      $ii=crement($ii,$movecopydirection);
      $ib++;
    }
    $jb++;
  }                                                   # here the buffer @copycontent is completely filled
  #-------------------here we paste the buffer to the new destination ------------ 
  my $jo=$destsvo;
  my $io;
  for (my $j=0;$j < $jb;$j++) {
    if ($movecopydirection) {
      if ($strtset+$shift < 0) {$io=$previouscount+1+($strtset+$shift);}
      else {$io=$strtset+$shift;} 
    }
    else {
      if ($stpset+$shift < 0) {$io=$previouscount+1+($stpset+$shift);} 
      else {$io=$stpset+$shift;}                      # always start to copy to the lower position 
    }
    if ($io < 0){$io=$previouscount+$shift+1;}        # set turnaround position to next read
    for (my $i=0;$i < $moves;$i++){
      if ($io > $previouscount) {$io=0}               # turn around (rotate) when counting up
      $servocontent[$io][$jo]=$copycontent[$i][$j];
      $io++;
    }	    
    $jo++;
  }	  
  printstatus("Servo $srcsvo till $tillsvo copied$invtxt into Servo $destsvo from move $strtset to $stpset shifted by $shift moves\n");
}
#############################################################
# determine the number of actuators and create a list of them to be uses during note book setup 
#############################################################
sub calc_actuators {
  my $i=0;                                            # counter for actuators lines
  my $j=0;                                            # counter for ConfigL::servosettings lines
svos:  foreach my $line (@$servosettings){                 # determine how many servos are configured
    if ($line->[2]==2) {                           
      my @relais=map { s/^\s+|\s+$//g; $_ } split /,/, $servosettings->[$j]->[5];
      my $k=1;
      foreach my $relaylabel (@relais) {             
        $actuators->[$i]->[5]=$relaylabel;            # these are relais 
        $actuators->[$i]->[6]=$j;                     # note the servo number that contain relay bits
        $actuators->[$i]->[7]=$k;                     # indicates it is a relay if > 0 and contains the bitnumber bit0 =1 - necessary to make a difference to servo
        $actuators->[$i]->[2]=2;                      # indicates it is a relais
        $i++;                                         # increase number of actuators
        $k++;
      }
      if ($j >= $num_servos-1) {                      # we have processed all servo definitions - so continue
        last svos;                                    # stop when the number of servos has reached
      }
      $j++;                                           # Line ready determined - go for the next
    } else {
      $actuators->[$i]=($servosettings->[$j]);        # these are servos
      $actuators->[$i]->[6]=$j;                       # note the servo number that contains the relay bits
      $actuators->[$i]->[7]=0;                        # indicates it is a servo
      if ($j >= $num_servos-1) {
        last svos;                                    # stop when the number of servos has reached
      }
      $i++;
      $j++;
    }
  }  
  $num_actuators=$i;
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
    open (LOG,">>/tmp/bechele.log")||die("Cannot open /tmp/bechele.log $!");
  }
  print LOG shift."\n";
  close LOG;
}
#############################################################
#  initializes the hardware
#############################################################
sub init_ports {
  if ($use_gamepad) {
    @joy_content=(0,0,1,1);
    $js = Linux::Joystick->new(device => $joystick_device,nonblocking => 1);
  } else {
    $serial = Device::SerialPort->new($serialport); # init the serial port at pin 10 (RXD)
    $serial->baudrate(38400);
    $serial->databits(8);
    $serial->stopbits(1);
    $serial->purge_all();
    $serial->rts_active(0);
    $serial->dtr_active(0);
    $serial->purge_all();                             # flush the buffer
  }
# gpio setup
# ----------
  $pwm_en=sub{$api->write_pin($OE,shift)};            # port 0 pin 11 (OE)
  $inext= sub{return ($api->read_pin($NEXT))};        # Port 1 pin 12 (Next mp3)
  $iprev= sub{return ($api->read_pin($PREV))};        # Port 4 pin 16 (Prev mp3)
  # init input for next file activate pulldown
  $api->pin_mode($NEXT,0);                            # port 1 (pin 12) as input
  $api->pull_up_down($NEXT,1);                        # activate pulldown
  # init input for previous/stop file activate pulldown
  $api->pin_mode($PREV,0);                            # port 4 (pin16) as input
  $api->pull_up_down($PREV,1);                        # activate pulldown
  # init pwm enable pin 11 ($pwm_en)as output and set to 1 (inactive)
  $api->pin_mode($OE,1);                              # port 0 (pin 11) as output
  $api->write_pin($OE,1);                             # init port 0 to 1
}
#############################################################
#  Disable network an PCA9685 devices
#############################################################
sub disable_actuators {
  if ($sendtopca) {
    disablePWM();                                     # disable PWM on all PCA devices
  }
  if ($sendtonet) {
    setregister(32767,0,0);                           # disable PWM on all net devices
  }
}
#############################################################
#  Init the i2C device
#############################################################
sub init_i2c {
  logs ("$i2cport,$i2c_address,$i2c_freq,$num_servos");
  my$success=init_PWM($i2cport,$i2c_address,$i2c_freq,$num_servos);
}
#############################################################
# register setup of the node - set MAC and node number
#############################################################
sub setregister{
  my $node=shift;
  my $nodeaddr=$node+32768;
  my @bcastdata=($nodeaddr,$packet_counter,@_);
  bcast(\@bcastdata);
}
#############################################################
# finals
#############################################################
sub ctrlc {
$SIG{INT} = \&ctrlc;
  disable_actuators();
  exit;
}
END {
  disable_actuators();
}

