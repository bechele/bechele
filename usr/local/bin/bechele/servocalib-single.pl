#!/usr/bin/perl -w
#   Test program for first test of servo movement
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
$| = 1;

use Socket;
use vars qw/@netstream $api $j $resfactor $dev @joy_content $stepwidth $servores $set1 $set2/;
my $cfgdir=$ARGV[0];                                  # the name of the MP3 File to process
if ( ! $cfgdir ) {                                    # stop if no argument has been passed
  print "usage: $0 <cfg_dirname>\n";
  exit 0;
}
$cfgdir=~s/\/$//;                                     # cut off trailing / to keep path clean
require "$cfgdir/ConfigL.pm";                         # load the Config File
my ($netport,$sendtonet,$sendtopca,$use_gamepad,$joystick_device,$serialport,$waittime_serial,$i2cport,$pwm_res,$i2c_address,$i2c_freq,$debug,$servores,$num_servos,$stepwidth,$play_full_mp3,$mp3loop,$block_popup_width,$matrix_popup_width,$max_out_pins,$dboutlist,$joystick_x_start,$joystick_x_end,$joystick_y_start,$joystick_y_end,$gamepad_start,$gamepad_stop,$gamepad_axis_y,$gamepad_axis_x,$gamepad_x_start,$gamepad_x_end,$gamepad_y_start,$gamepad_y_end,$num_servos_per_row,$OE,$NEXT,$PREV,$S1,$S2,$SHUT,$servosettings)=ConfigL::get_vars();
if ($sendtopca) {                            # in case connecting a PCA9695 directly is desired, load the module for it
  eval {use RPi::MultiPCA9685 qw(init_PWM setChannelPWM disablePWM);RPi::MultiPCA9685->import(qw(init_PWM setChannelPWM disablePWM));1} or die "Error loading module RPi::MultiPCA9685 $@";
  init_i2c();
}
if ($use_gamepad) {
  use Linux::Joystick;
} else {
  use Device::SerialPort qw( :PARAM :STAT 0.07 );
}
use WiringPi::API qw(:wiringPi);
$api=WiringPi::API->new;
$api->setup; # use wiringpi port numbers
use Time::HR;
my $currentservo=0;
my $secondservo=1;
$SIG{INT} = \&ctrlc;
system 'tput civis';
init_ports();
print "\n";
sleep 1;
my $packet_counter=1;
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
      if ($currentservo < $num_servos - 1) {
	      #setChannelPWM($currentservo,[0,0]);
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
	      #setChannelPWM($currentservo,[0,0]);
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
  my $pos1=int($joy_content[4]/($servores/($$servosettings[$currentservo][4] - $$servosettings[$currentservo][3]))+$$servosettings[$currentservo][3]);
  my $pcaref=[0,$pos1];
  $netstream[$currentservo]=$pos1;
  if ($sendtopca){
    setChannelPWM($currentservo,$pcaref);
  }
  if ($sendtonet){
    send_data_broadcast(\@netstream,\$packet_counter);    # output moves via broadcast to network - seems to be quicker, though not parallel
    $packet_counter = ($packet_counter + 1) & 0xFFFF; # increment packet counter with overflow at 65535
  }
  system 'tput civis';  
  my $str="\fX-pos(0-$servores)	|Joystick X 	|Servo $currentservo\n-----------------------------------------------\n$joy_content[4]		|$joy_content[0]		| $pos1\n";
  print $str;
  &$pwm_en(0);
}
#############################################################
#  initialize all ports
#############################################################
sub init_ports {
  $api->pin_mode(5,1);                               # port 5 (pin 11) as output
  $api->write_pin(5,1);                              # init port 5 to 1
  $pwm_en=sub{$api->write_pin(5,shift)};
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
    $serial->purge_all();                              # flush the buffer
  }
}
#############################################################
#  initialize the i2c utility
#############################################################
sub init_i2c {
  my $success=init_PWM($i2cport,$i2c_address,$i2c_freq,$num_servos);
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
  if ($use_gamepad) {                       # ----------------------- gamepad handling ---------------------------------
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
      }
    }
    $joy_content[4]=int($servores * ($joy_content[0]-$gamepad_x_start) / ($gamepad_x_end-$gamepad_x_start));
    if ( $joy_content[4] <= 0 ) { $joy_content[4]=0; }
  } else {                                             # --------------------------- serial joystick handling ----------------------------
    my ($count,$data,$i)=(0,0,0);
    while (! (substr $data,-1 eq "\n")) {
      $serial->write('4');              # sent the command to the arduino to send one set
      hsleep ($waittime_serial);
      ($count,$data)=$serial->read(32);
      if ( $count ) {                   # if we have data, put it into the array
        @joy_content=split / /,$data;
        $joy_content[4]=int($servores * ($joy_content[0]-$joystick_x_start) / ($joystick_x_end-$joystick_x_start));
        if ( $joy_content[4] <= 0 ) { $joy_content[4]=0; }
        $joy_content[5]=int($servores * ($joy_content[1]-$joystick_y_start) / ($joystick_y_end-$joystick_y_start));
        if ( $joy_content[5] <= 0 ) { $joy_content[5]=0; }
      } else { $serial->purge_all(); }  # else try again
      if ($i >= 10) { die "serial device does not respond\n";}
      $i++;
    }
  }
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
