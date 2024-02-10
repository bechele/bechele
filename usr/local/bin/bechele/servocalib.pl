#!/usr/bin/perl -w
#   Test program for first test of servo movement
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

use lib '/usr/local/bin/bechele/Modules';
use vars qw/$api $j $resfactor $dev @joy_content $stepwidth $servores $set1 $set2/;
if ($ConfigL::use_gamepad) {
  use Linux::Joystick;
} else {
  use Device::SerialPort qw( :PARAM :STAT 0.07 );
}
use ConfigL;
use RPi::MultiPCA9685 qw(init_PWM setChannelPWM disablePWM);
init_i2c();
use WiringPi::API qw(:wiringPi);
$api=WiringPi::API->new;
$api->setup; # use wiringpi port numbers
use warnings;
use Time::HR;
my $waittime_serial=8000000;                          # wait for 8 ms (8000000 ns)
my $currentservo=0;
my $secondservo=1;
$SIG{INT} = \&ctrlc;
system 'tput civis';
init_ports();
print "\n";
sleep 1;
run_loop();
#############################################################
#  checks the input states and runs the mp3s according to the 
#  key sets
#############################################################
sub run_loop {
  while (1) {                                         # keep the loop always running
    get_one_read();
    my $next=$joy_content[3];
    my $prev=$joy_content[2];
    if ($next==0) {
      if ($currentservo < $ConfigL::num_servos - 2) {
	setChannelPWM($currentservo,[0,0]);      
        $currentservo++;
        while ($next==0) {                            # wait until the button is released
          get_one_read();                             # read one joy set
          $next=$joy_content[3];
          put_one_move();
          hsleep (20000000);                          # do nothing for 20 ms
        }
        next;
      }
    }
    if ($prev==0) {
      if ($currentservo > 0) {
	setChannelPWM($currentservo+1,[0,0]);      
        $currentservo--;
        while ($prev==0) {                            # wait until the button is released
          get_one_read();                             # read one joy set
          $prev=$joy_content[2];
          put_one_move();
          hsleep (20000000);                          # do nothing for 20 ms
        }
        next;
      }
    }
    put_one_move();
    hsleep (20000000);                                # do nothing for 20 ms
  }
}
#############################################################
#  move one set - send positions to servos
#############################################################
sub put_one_move {
  $secondservo=$currentservo+1;
  my $pos1=int($joy_content[4]/($ConfigL::servores/($$ConfigL::servosettings[$currentservo][4] - $$ConfigL::servosettings[$currentservo][3]))+$$ConfigL::servosettings[$currentservo][3]);
  my $pos2=int($joy_content[5]/($ConfigL::servores/($$ConfigL::servosettings[$secondservo][4] - $$ConfigL::servosettings[$secondservo][3]))+$$ConfigL::servosettings[$secondservo][3]);
  my $mref=[0,$pos1,0,$pos2];
  setChannelPWM($currentservo,$mref);
  system 'tput civis';                               # hide the cursor
  print "\fX-pos(0-$ConfigL::servores)	|Y-Pos(0-$ConfigL::servores)	|Joystick X 	|Joystick Y	|Servo $currentservo	|Servo $secondservo\n";
  print "------------------------------------------------------------------------------------------------\n";
  print "$joy_content[4]		| $joy_content[5]		| $joy_content[0]		| $joy_content[1]		| $pos1		| $pos2  \n";
  &$pwm_en(0);
}
#############################################################
#  initialize all ports
#############################################################
sub init_ports {
  $api->pin_mode(5,1);                               # port 5 (pin 11) as output
  $api->write_pin(5,1);                              # init port 5 to 1
  $pwm_en=sub{$api->write_pin(5,shift)};
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
}
#############################################################
#  initialize the i2c utility
#############################################################
sub init_i2c {
  my$success=init_PWM($ConfigL::i2cport,$ConfigL::i2c_address,$ConfigL::i2c_freq,$ConfigL::num_servos);
}
#############################################################
#  a hires sleep ( in nanoseconds )
#############################################################
sub hsleep {
  my $duration=shift;
  $now=gethrtime();
  while ($now + $duration >= gethrtime()) {           # As long as the sleep duration is not reached, keep in loop
  }
  return 1;
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
    if ( $joy_content[4] <= 0 ) { $joy_content[4]=0; }
    $joy_content[5]=int($ConfigL::servores * ($joy_content[1]-$ConfigL::gamepad_y_start) / ($ConfigL::gamepad_y_end-$ConfigL::gamepad_y_start));
    if ( $joy_content[5] <= 0 ) { $joy_content[5]=0; }
  } else {                                             # --------------------------- serial joystick handling ----------------------------
    my ($count,$data,$i)=(0,0,0);
    while (! (substr $data,-1 eq "\n")) {
      $serial->write('4');              # sent the command to the arduino to send one set
      hsleep ($waittime_serial);
      ($count,$data)=$serial->read(32);
      if ( $count ) {                   # if we have data, put it into the array
        @joy_content=split / /,$data;
        $joy_content[4]=int($ConfigL::servores * ($joy_content[0]-$ConfigL::joystick_x_start) / ($ConfigL::joystick_x_end-$ConfigL::joystick_x_start));
        if ( $joy_content[4] <= 0 ) { $joy_content[4]=0; }
        $joy_content[5]=int($ConfigL::servores * ($joy_content[1]-$ConfigL::joystick_y_start) / ($ConfigL::joystick_y_end-$ConfigL::joystick_y_start));
        if ( $joy_content[5] <= 0 ) { $joy_content[5]=0; }
      } else { $serial->purge_all(); }  # else try again
      if ($i >= 10) { die "serial device does not respond\n";}
      $i++;
    }
  }
}
#############################################################
# quit an clean up
#############################################################
sub ctrlc {
  $SIG{INT} = \&ctrlc;
  disablePWM();
  system 'tput cnorm';
  exit;
}
END {
  disablePWM();
  system 'tput cnorm';
}
1;
