#!/usr/bin/perl -w 

use Linux::Joystick;
 
my $js = new Linux::Joystick;
my $event;
print "Program to figure out the buttons and axes of an unknown gamepad\n"; 
print "Joystick has " . $js->buttonCount() . " buttons ".
        "and " . $js->axisCount() . " axes.\n";
 
# blocking reads:
while( $event = $js->nextEvent ) {
 
        print "Event type: " . $event->type . ", ";
        if($event->isButton) {
                print "Button " . $event->button;
                if($event->buttonDown) {
                        print " pressed";
                } else {
                        print " released";
                } 
        } elsif($event->isAxis) {
                print "Axis " . $event->axis . ", value " . $event->axisValue . ", ";
                print "UP" if $event->stickUp;
                print "DOWN" if $event->stickDown;
                print "LEFT" if $event->stickLeft;
                print "RIGHT" if $event->stickRight;
        } else { # should never happen
                print "Unknown event " . $event->hexDump;
        }
 
        print "\n";
}
 
# if the while loop terminates, we got a false (undefined) event:
die "Error reading joystick: " . $js->errorString;
