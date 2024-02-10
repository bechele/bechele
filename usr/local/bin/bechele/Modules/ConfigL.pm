#!/usr/bin/perl -w
#   Settings file for servo and application specific limits
#   Copyright (C) <2015>  <Rolf Jethon>
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

package ConfigL;
our $VERSION = '0.02';
# common configuration file
#--------------------------------- globally used constants ---------------------------------
$use_gamepad=0;                                 # 0= serial joystick 1= usb gamepad
$joystick_device=0;                             # joystick 0 or 1 - only if gamepad is active
$serialport="/dev/ttyAMA0";                     # serial port to read the joystick from
$i2cport="/dev/i2c-1";                          # i2c port to send the servo movements to
$pwm_res=4096;                                  # the resolution of the PCA9685 PWM
$i2c_address=0x40;                              # the I2C Address of the first PWM Board - subsequent PCBs automatically  +1
$i2c_freq=50;                                   # the frequency of the PWM in Hz
$debug=0;                                       # debug mode switch
$servores=4096;                                 # the virtual resolution of the servos
$num_servos=64;                                 # number of servos in use
$stepwidth=50000000;                            # use a refresh rate of 50 ms (50000000 ns / 20 Hz)
#------- only relevant if joystick is in use ---------------
$joystick_x_start=130;                          # The joystick x mechanical start limit value
$joystick_x_end=628;                            # The joystick x mechanical end limit value
$joystick_y_start=130;                          # The joystick y mechanical start limit value
$joystick_y_end=618;                            # The joystick y mechanical end limit value
#$joystick_x_start=0;                          # The joystick x mechanical start limit value
#$joystick_x_end=2048;                            # The joystick x mechanical end limit value
#$joystick_y_start=0;                          # The joystick y mechanical start limit value
#$joystick_y_end=2048;                            # The joystick y mechanical end limit value
#------- only relevant if gamepad is in use ---------------
$gamepad_start=0;                               # define which gamepad button starts
$gamepad_stop=1;                                # define gamepad button that stops
$gamepad_axis_y=1;                              # define the gamepad axis y
$gamepad_axis_x=2;                              # define the gamepad axis x
$gamepad_x_start=-32767;                        # The axis x mechanical start limit value
$gamepad_x_end=32767;                           # The axis x mechanical end limit value
$gamepad_y_start=32767;                         # The axis y mechanical start limit value
$gamepad_y_end=-32767;                          # The axis y mechanical end limit value
#------- Settings for the trackui.pl screen  ---------------
$num_servos_per_row=25;                         # number of servos shown in each notebook page ( min 25 )
# !!!!!! NOTE: !!!!!!!!!!!! NOTE: !!!!!!!!!!!! NOTE: !!!!!!!
# ! Terminal columns must be at least $num_servos_per_ row + 5, otherwise an error will occur:
# ! Your screen is currently too small....
# ! The number of terminal rows must be at least 147 - otherwise you get the same error....
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#-----------------------------------------------------------
#you need to comment out one of the following blocks to do a correct pin assignment
#-----------------------------------------------------------
#------- Settings for the GPIO pins OrangePI PC ------------
#$OE=5;                                          # pin 11 Output enable for PCA9685
#$NEXT=6;                                        # pin 12 next MP 3 button
#$PREV=9;                                        # pin 16 previous MP3 button
#$S1=10;                                         # pin 18 S1 Button
#$S2=13;                                         # pin 22 S2 Button
#$SHUT=2;                                        # pin 7  SHUT Button
#------- Settings for the GPIO pins RASPI 1B ---------------
$OE=0;                                          # pin 11 Output enable for PCA9685
$NEXT=1;                                        # pin 12 next MP 3 button
$PREV=4;                                        # pin 16 previous MP3 button
$S1=5;                                          # pin 18 S1 Button
$S2=6;                                          # pin 22 S2 Button
$SHUT=7;                                        # pin 7  SHUT Button

# The following anonymous array represents the servo limit positions in pulses of a maximum of $servores
#----------------Servostart,Servoend,invert,servolimit start,servolimit end,label-----------------------
# servolimit is the mechanical stop limit of the servo itself, that must not be exceeded
# servostart and servoend (min. 0 - max. $servores) is the mechanical limit within the application that must not be exceeded
# label refelects the servo function within the application
# The value range of "Servostart","Servoend","servolimit start" and "servolimit end" is 0 to 4096
# If you want to address more than 64 servos, you need to extend the array below accordingly
# read also the README file in /usr/local/bin for details
$servosettings=[[268,423,0,170,600,'EyeRight left/right'],          # Servo 0 
                [270,415,0,170,600,'EyeLeft left/right'],           # Servo 1
                [211,578,1,170,600,'EyeRight up/down'],             # Servo 2
                [208,530,1,170,600,'EyeLeft up/down'],              # Servo 3
                [248,531,1,170,600,'LidRight'],                     # Servo 4
                [239,540,1,170,600,'LidLeft'],                      # Servo 5
                [177,507,0,170,600,'EyeAngle'],                     # Servo 6
                [170,450,0,170,600,'Mouth up/down'],                # Servo 7
                [170,591,1,170,600,'Mouth width'],                  # Servo 8
                [170,600,0,170,600,'Head rotation'],                # Servo 9
                [180,453,1,170,600,'Head left/right'],              # Servo 10
                [186,550,0,170,600,'Head forwar/back'],             # Servo 11
		# [251,459,0,170,600,'EyeRight left/right'],          # Servo 12
		#[304,490,0,170,600,'EyeLeft left/right'],           # Servo 13
                [251,469,0,170,600,'EyeRight left/right'],          # Servo 12
                [304,450,0,170,600,'EyeLeft left/right'],           # Servo 13
                [179,497,1,170,600,'EyeRight up/down'],             # Servo 14
                [196,479,1,170,600,'EyeLeft up/down'],              # Servo 15
                [264,578,1,170,600,'LidRight'],                     # Servo 16
                [222,566,1,170,600,'LidLeft'],                      # Servo 17
                [202,516,0,170,600,'EyeAngle'],                     # Servo 18
                [211,600,0,170,600,'Mouth up/down'],                # Servo 19
                [170,591,1,170,600,'Mouth width'],                  # Servo 20
                [210,577,0,170,600,'Head rotation'],                # Servo 21
                [257,509,0,170,600,'Head left/right'],              # Servo 22
                [203,538,1,170,600,'Head forwar/back'],             # Servo 23
                [380,400,0,170,600,'Servo 24'],                     # Servo 24
                [380,400,0,170,600,'Servo 25'],                     # Servo 25
                [380,400,0,170,600,'Servo 26'],                     # Servo 26
                [380,400,0,170,600,'Servo 27'],                     # Servo 27
                [380,400,0,170,600,'Servo 28'],                     # Servo 28
                [380,400,0,170,600,'Servo 29'],                     # Servo 29
                [380,400,0,170,600,'Servo 30'],                     # Servo 30
                [380,400,0,170,600,'Servo 31'],                     # Servo 31
                [380,400,0,170,600,'Servo 32'],                     # Servo 32
                [380,400,0,170,600,'Servo 33'],                     # Servo 33
                [380,400,0,170,600,'Servo 34'],                     # Servo 34
                [380,400,0,170,600,'Servo 35'],                     # Servo 35
                [380,400,0,170,600,'Servo 36'],                     # Servo 36
                [380,400,0,170,600,'Servo 37'],                     # Servo 37
                [380,400,0,170,600,'Servo 38'],                     # Servo 38
                [380,400,0,170,600,'Servo 39'],                     # Servo 39
                [380,400,0,170,600,'Servo 40'],                     # Servo 40
                [380,400,0,170,600,'Servo 41'],                     # Servo 41
                [380,400,0,170,600,'Servo 42'],                     # Servo 42
                [380,400,0,170,600,'Servo 43'],                     # Servo 43
                [380,400,0,170,600,'Servo 44'],                     # Servo 44
                [380,400,0,170,600,'Servo 45'],                     # Servo 45
                [380,400,0,170,600,'Servo 46'],                     # Servo 46
                [380,400,0,170,600,'Servo 47'],                     # Servo 47
                [380,400,0,170,600,'Servo 48'],                     # Servo 48
                [380,400,0,170,600,'Servo 49'],                     # Servo 49
                [380,400,0,170,600,'Servo 50'],                     # Servo 50
                [380,400,0,170,600,'Servo 51'],                     # Servo 51
                [380,400,0,170,600,'Servo 52'],                     # Servo 52
                [380,400,0,170,600,'Servo 53'],                     # Servo 53
                [380,400,0,170,600,'Servo 54'],                     # Servo 54
                [380,400,0,170,600,'Servo 55'],                     # Servo 55
                [380,400,0,170,600,'Servo 56'],                     # Servo 56
                [380,400,0,170,600,'Servo 57'],                     # Servo 57
                [380,400,0,170,600,'Servo 58'],                     # Servo 58
                [380,400,0,170,600,'Servo 59'],                     # Servo 59
                [380,400,0,170,600,'Servo 60'],                     # Servo 60
                [380,400,0,170,600,'Servo 61'],                     # Servo 61
                [380,400,0,170,600,'Servo 62'],                     # Servo 62
                [380,400,0,170,600,'Servo 63']];                    # Servo 63
