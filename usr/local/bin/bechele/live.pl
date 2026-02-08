#!/usr/bin/perl -w
#   movement model control program with synchronized audio (mp3) output and servo control
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
use strict;
use warnings;
use vars qw/ $api $total_left $total_right $j $pwm_en $inext $iprev $is1 $is2 $ready $dev $contentcount $filepos $filepos_extra $filepos_repeat $shut $repeatblock @filelist @extralist @repeatlist @servocontent $stepwidth $servores $num_servos $playing $s1p $s2p $nextp $prevp/;
use Socket;
my $mp3dir=$ARGV[0];                                  # the name of the MP3 File to process
if ( ! $mp3dir ) {                                    # stop if no argument has been passed
  print "usage: $0 <mp3_dirname>\n";
  exit 0;
}
$mp3dir=~s/\/$//;                                     # remove trailing / for clean path
use WiringPi::API qw(:wiringPi);
use Data::Dump qw(dump);
require "$mp3dir/ConfigL.pm";                         # load the Config File
my ($netport,$sendtonet,$sendtopca,$use_gamepad,$joystick_device,$serialport,$waittime_serial,$i2cport,$pwm_res,$i2c_address,$i2c_freq,$debug,$servores,$num_servos,$stepwidth,$play_full_mp3,$mp3loop,$block_popup_width,$matrix_popup_width,$max_out_pins,$dboutlist,$joystick_x_start,$joystick_x_end,$joystick_y_start,$joystick_y_end,$gamepad_start,$gamepad_stop,$gamepad_axis_y,$gamepad_axis_x,$gamepad_x_start,$gamepad_x_end,$gamepad_y_start,$gamepad_y_end,$num_servos_per_row,$OE,$NEXT,$PREV,$S1,$S2,$SHUT,$servosettings)=ConfigL::get_vars();
if ($sendtopca) {                            # in case connecting a PCA9695 directly is desired, load the module for it
  eval {use RPi::MultiPCA9685 qw(init_PWM setChannelPWM disablePWM);RPi::MultiPCA9685->import(qw(init_PWM setChannelPWM disablePWM));1} or die "Error loading module RPi::MultiPCA9685 $@";
  init_i2c();
}
$api = WiringPi::API->new;
$api->setup; # use wiringpi port numbers
use Audio::Play::MPG123;
use File::Find::Rule;
$SIG{INT} = \&ctrlc;
#use warnings;
my $player = new Audio::Play::MPG123;
use Time::HR;
my $packet_counter=1;
init_ports();
$filepos=-1;                                          # the first mp 3 - set to -1, so that a press to up (+1) results in 0
@_= File::Find::Rule->file()                          # check the mp3 directory and fill the array with the file names
                           ->name("*.mp3")
                           ->maxdepth(1)
                           ->in( $mp3dir );
@filelist=sort(@_);
@_= File::Find::Rule->file()                   # check the mp3 directory and fill the array with the file names
                           ->name("*.mp3")
                           ->in( "$mp3dir/extra" );
@extralist=sort(@_);
@_= File::Find::Rule->file()                   # check the mp3 directory and fill the array with the file names
                           ->name("*.mp3")
                           ->in( "$mp3dir/repeat" );
@repeatlist=sort(@_);
my $maxfiles=$#filelist;                              # note the number of mp3s in folder
my $maxfiles_extra=$#extralist;                       # note the number of mp3s in extra folder
my $maxfiles_repeat=$#repeatlist;                     # note the number of mp3s in repeat folder
$repeatblock=0;
if ( $debug ) { debug();}                    # run the debug output if configured
if ( $maxfiles == -1) { die "no files to process"}
print "Init ready - program running\n";
$filepos_extra=0;
$filepos_repeat=0;
run_loop();
#inputtest();
#############################################################
#  checks the input states and runs the mp3s according to the 
#  key sets
#############################################################
sub run_loop {
  &$pwm_en(0);                                          # enable the pwm output
  while (1) {                                           # keep the loop always running
    if ( ! $repeatblock ) {
      if (! &$inext )  {                                # if next button is pressed, start the next file 
        $nextp=1;                                       # note that the button is down
        my $mp3=get_mp(1);                              # determinte the next mp3 file to read
        while ( !&$inext ) {
         hsleep (5000000); 
        }
        play ($mp3);                                    # play this file
      }
      if (! &$iprev )  {                                # if previous button has been pressed
        $prevp=1;                                       # note that the button is down
        my $mp3=get_mp(-1);                             # determinte the next mp3 file to read
        while ( !&$iprev ) {
         hsleep (5000000); 
        }
        play ($mp3);                                    # play this file
      }
      if (! &$is1 )  {                                  # if next extra button has been pressed
        $s1p=1;                                         # note that the button is down
        my $mp3=get_repeat();                           # determinte the next mp3 file to read
	$filepos_repeat+=1;
        if ($maxfiles_repeat>0) {
          $repeatblock=1;                               # do not interrupt this play
          play ($mp3)                                   # play this file if repeat files exist
        }          
        $mp3=get_mp(0);                                 # determinte the mp3 file to read
        $repeatblock=0;                                 # do not interrupt this play
        play ($mp3)                                     # play this file again
      }
      if (! &$is2 )  {                                  # if previous extra button has been pressed
        $s2p=1;                                         # note that the button is down
        my $mp3=get_extra();                            # determinte the next mp3 file to read
        $filepos_extra+=1;                              # update the position in the array we are reading from 
        while ( !&$is2 ) {
         hsleep (5000000); 
        }
        if ($maxfiles_extra>0) {play ($mp3)}            # play this file if extra files exist
      }
    }
    if (&$shut==0) {
      my $now=gethrtime();
      while (&$shut==0) {
        if (($now+2000000000) < gethrtime()) {          # if the shutdown button is pressed for more than 2 seconds - run shutdown
          my $exit=`halt`; 
        }
      }
      exec( $^X, $0, $ARGV[0]);                         # re-run this program again
    }
    hsleep (1000000);                                   # do nothing for 1 ms
  }
}
#############################################################
#  get the next mp3 file name to play
#############################################################
sub get_mp {
  my $move=shift;
  $filepos+=$move;                                    # update the position in the array we are reading from 
  if ($filepos <= 0) { $filepos=0 }                   # do not go beyond first file
  if ($filepos > $maxfiles) { 
    if ($mp3loop) {
      $filepos=0;                                     # after the last mp3 continue with the first (loop)
    } else {
      $filepos=$maxfiles;                             # do not exceed last file
    }                                                 
  }
  return $filelist[$filepos];                         # return the mp3 file to load
}
#############################################################
#  get the next extra mp3 file name to play
#############################################################
sub get_extra {
  if ($filepos_extra > $maxfiles_extra) { $filepos_extra=0 }    # and do not exceed lat file
  return $extralist[$filepos_extra];                  # return the mp3 file to load
}
#############################################################
#  get the next repeat mp3 file name to play
#############################################################
sub get_repeat {
  if ($filepos_repeat > $maxfiles_repeat) { $filepos_repeat=0 }    # and do not exceed lat file
  return $repeatlist[$filepos_repeat];                # return the mp3 file to load
}
#############################################################
# output file info if in debug mode
#############################################################
sub debug {
  print "The following MP3 files have been found\n";
  foreach my $file (@filelist) {
    print $file."\n";                                   # tell the user the loaded files
  }
  print "The following extra MP3 files have been found\n";
  foreach my $file (@extralist) {
    print $file."\n";                                   # tell the user the loaded extra files
  }
}
#############################################################
#  test the input pins - normally disabled
#############################################################
sub inputtest {
  while (1) {                        # keep the loop running
    my $a=&$inext;
    my $b=&$iprev;
    my $c=&$is1;
    my $d=&$is2;
    print "Pins 12,16,18,22: ".$a.$b.$c.$d."\n";
  }
}
#############################################################
#  receives a mp3 file, loads the beloning svo file + plays + moves
#############################################################
sub play {
  my $mp3=shift;
  my $infilename=$mp3;
  $infilename=~s/\.mp3//i;
  my $txtfilename=$infilename;
  $txtfilename=$txtfilename.'.txt';
  my $exist = (stat("$txtfilename"))[2];               # check if a servo file exists
  if ( $exist ) {
    open (TXT,"<$txtfilename")||die "cannot read input file $infilename $!";
    my @text=<TXT>;
    print "\033[2J";    #clear the screen
    print "\033[0;0H"; #jump to 0,0
    foreach my $txt (@text ){
      print $txt."\n";
    }
  }
  $infilename=$infilename.'.svo';
  if (load_file($infilename)) {                         # load the servo file 
    $player->load($mp3);                                # start the audio
    $ready=0;
    $playing=1;
    my $periodstart=(gethrtime()-$stepwidth);           # make sure the first move starts right from the music start
    $player->poll(0);
    $j=0;
    while ($j < $contentcount && (! $ready)) {          # move until the mp3 or svo file has been finished
      if ( $playing && (($periodstart + $stepwidth) <= gethrtime())) {
        put_one_move( $servocontent[$j]);               # if the period time has reached, move to the next position
        $j++;
        $periodstart=$periodstart+$stepwidth;           # calculate the time for the next move
      }
      if ( ! hsleep(1000000) ) { last }                 # stop if a button has been pressed
    }
    disable_actuators();
    $playing=0;
    $repeatblock=0;
    if ( $debug) {
     print "File $filelist[$filepos] made $j moves\n";   # tell the use the number of moves
    }
  } 
}  
#############################################################
#  move one set - send positions to servos
#############################################################
sub put_one_move {
  my $setref=shift;                                           # contains the refereence to one anonymous array containing the moves for one set
  my $i=0;
  my @pcapos=();                                              # contain the data for output to PCA9685
  my @netpos=();                                              # contain the data for network output
  foreach my $servopos (@$setref) {                           # set the positions for all of the servos
    my $way=($servosettings->[$i]->[1]+1)-$servosettings->[$i]->[0];  # the drive way (resolution) of the servo (<= 4096 steps)
    my $resfactor=$way/$servores;                    # calculate the correction factor PCA9685 has 4096 steps
    my $pos;
    if ($$servosettings[$i][2]) {
      $pos=int(($servores-$servopos)*$resfactor+$servosettings->[$i]->[0]); # take the Servostart from ConfigL::servosettings and invert the direction
    } else {
      $pos=int($servopos*$resfactor+$servosettings->[$i]->[0]);   # take the Servostart from ConfigL::servosettings
    }
    if ($sendtopca) {push (@pcapos,(0,$pos));}
    if ($sendtonet) {push (@netpos,$pos);}
    $i++;
  }
  if ($sendtonet) {
    send_data_broadcast(\@netpos,\$packet_counter);           # output moves via broadcast to network - seems to be quicker, though not parallel
    $packet_counter = ($packet_counter + 1) & 0xFFFF; # increment packet counter with overflow at 65535
  }
  if ($sendtopca) {
    setChannelPWM(0,\@pcapos);                                # output moves to a directly connected PCA9685 to the Raspi
  }
}
#############################################################
#  initialize all ports
#############################################################
sub init_ports {

# gpio setup
# ----------
  $pwm_en=sub{$api->write_pin($OE,shift)};               # Pin 11 (OE)
  $inext= sub{return !($api->read_pin($NEXT))};          # Pin 12 (NEXT) 
  $iprev= sub{return !($api->read_pin($PREV))};          # Pin 16 (PREV)
  $is1= sub{return !($api->read_pin($S1))};              # Pin 18 (S1)
  $is2= sub{return !($api->read_pin($S2))};              # Pin 22 (S2)
  $shut= sub{return ($api->read_pin($SHUT))};            # Pin 7  (SHUT)
  # init input for next file activate pulldown
  $api->pin_mode($NEXT,0);                               # (pin 12) as input
  $api->pull_up_down($NEXT,1);                           # activate pulldown
  # init input for previous/stop file activate pulldown
  $api->pin_mode($PREV,0);                               # (pin16) as input
  $api->pull_up_down($PREV,1);                           # activate pulldown
  # init pwm enable pin 11 ($pwm_en)as output and set to 1 (inactive)
  $api->pin_mode($OE,1);                                 # (pin 11) as output
  $api->write_pin($OE,1);                                # OE active
  # init input for s1 file activate pulldown
  $api->pin_mode($S1,0);                                 # (pin 18) as input
  $api->pull_up_down($S1,1);                             # activate pulldown
  # init input for s2 file activate pulldown
  $api->pin_mode($S2,0);                                 # (pin 22) as input
  $api->pull_up_down($S2,1);                             # activate pulldown
  # init input for shut file activate pullup
  $api->pin_mode($SHUT,0);                               # (pin 7) as input
  $api->pull_up_down($SHUT,2);                           # activate pullup
  disable_actuators();                                   # safe for the Servos
}
#############################################################
#  initialize i2c
#############################################################
sub init_i2c {
  my$success=init_PWM($i2cport,$i2c_address,$i2c_freq,$num_servos);
}
#############################################################
#  load previously recorded data from file
#############################################################
sub load_file{
  my $infilename=shift;
  my $exist = (stat("$infilename"))[2];               # check if a servo file exists
  if ( $exist ) {                                     # load it, if so
    my $data;
    open (BIN,"<$infilename")||die "cannot read input file $infilename $!";
    while (read BIN,my $chunk,2048) {
      $data.=$chunk;                                  # read the data into var
    }
    close (BIN);
    my $lastbyte=chop $data;                          # cut off the checksum
    my $prelastbyte=chop $data;
    my $sumnum=unpack 'v',($prelastbyte.$lastbyte);   # convert the binary checksum into a number
    my $sum=unpack("%16C*",$data) % 32767;            # calculate the checksum for the data
    (my $dummy,$stepwidth,$servores,$num_servos)=unpack"vvvv",($data); # read the header into vars
    if ($sumnum!=$sum) {                              # if file checksum is incorrect, die
      die "loaded file $infilename has a bad checksum\n";
    }
    $stepwidth*=1000000;                              # convert step duration from ms into ns
    $data=substr $data,8;                             # shorten the file (remove header)
    my $j=0;
    while ( $data ) {                                 # as long as we have content, read it into array
      $servocontent[$j]=[unpack ("v[$num_servos]",$data)];
      $data=substr $data,$num_servos*2;
      $j++;
    }
    $contentcount=$j-1;                               # correct the length, so a direct save after load does not change
    if ( $debug) {
      print "Data sets loaded: $contentcount\n";
    }
    return 1;
  }
  return 0;
}
#############################################################
#  a hires sleep ( in nanoseconds )
#############################################################
sub hsleep {
  my $duration=shift;
  my $now=gethrtime();
  my $now2=$now;
  my $dur=9000000;
  while ($now + $duration >= gethrtime()) {           # As long as the sleep duration is not reached, keep in loop
    if ($playing) {
      $player->poll(0);
      if ( $now2 + $dur >= gethrtime()) { 
        $now2=$now2 + $dur;
        if((! $repeatblock) && (! $play_full_mp3)) {           # make sure, not to interrupt while repeat intro or if configured
          if((! $nextp) && (!&$inext)) {$playing=0;$nextp=1;return 0}   # if key has been pressed again, stop (and continue imm. with new file)
          if(&$inext){$nextp=0}                       # note when a key has been released
          if((! $prevp) && (!&$iprev)) {$playing=0;$prevp=1;return 0}
          if(&$iprev){$prevp=0}
          if((! $s1p) && (!&$is1)) {$playing=0;$s1p=1;return 0}
          if(&$is1){$s1p=0}
          if((! $s2p) && (!&$is2)) {$playing=0;$s2p=1;return 0}
          if(&$is2){$s2p=0}
        }
      }
      if ($player->state == 0) {$playing=0;$ready=1}  # if the MP3 is finished -> loop
    }
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
# register setup of the node - set MAC and node number
#############################################################
sub setregister{
  my $node=shift;
  my $nodeaddr=$node+32768;
  my @bcastdata=($nodeaddr,$packet_counter,@_);
  bcast(\@bcastdata);
}
#############################################################
#  calculate and add the CRC for the datagram
#############################################################
sub add_crc16_to_scalar {
    my ($data_ref) = @_;  # Referenz auf Skalar (Binary String)

    my $crc = 0xFFFF;

    # Bytes aus dem String verarbeiten
    foreach my $byte (unpack('C*', $$data_ref)) {
        $crc ^= $byte;
        for (my $i = 0; $i < 8; $i++) {
            if ($crc & 0x0001) {
                $crc = ($crc >> 1) ^ 0xA001;
            } else {
                $crc >>= 1;
            }
        }
    }

    # CRC als 2 Bytes an den String anhängen (Little-Endian)
    $$data_ref .= pack('v', $crc);  # 'v' = 16-bit Little-Endian
}
#############################################################
#  Disable network an PCA9685 devices
#############################################################
sub disable_actuators {
  if ($sendtopca) {
    disablePWM();                                     # disable PWM on all PCA devices
  }
  if ($sendtonet) {
    setregister(32767,1,1);                           # disable PWM on all net devices
  }
}
#############################################################
sub ctrlc {
  $SIG{INT} = \&ctrlc;
  disable_actuators();
  exit;
}
END {
  disable_actuators();
}

