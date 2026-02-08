#!/usr/bin/perl -w
#------------------------------------------------------------
#   Program to configure ESP32 PWM/Binary hardware nodes using udp broadcasts
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
use feature 'state';                                               # allow static variables
use Data::Dump qw(dump);
use Socket;                                                        # use in any case - not expensive, even if network is not desired
use IO::Socket::INET;
use POSIX qw/ceil floor/;
use DBI;
use Time::HR;
use File::Spec;
use File::Copy;
use File::Find::Rule;
use File::Temp qw( :POSIX );
use Text::Table;
my $cfgdir=$ARGV[0];                                               # the name of the MP3 dir to process
#----------------- check if called correctly ----------------
if ( ! $cfgdir ) {                                                 # stop if no argument has been passed
  print "usage: $0 <cfg_dirname>\n";
  exit 0;
}
$cfgdir=~s/\/$//;                                                  # remove the trailing / if there to make path nice
#-------- check/copy config file in target dir --------------
if ( ! (-e "$cfgdir/ConfigL.pm" && -f "$cfgdir/ConfigL.pm" && -r "$cfgdir/ConfigL.pm")) {     #Make sure the ConfigL.pm file exists in the source directory
  copy ("/usr/local/bin/bechele/Modules/ConfigL.pm", "$cfgdir/ConfigL.pm") or die "copy of ConfigL.pm to $cfgdir failed: $!";   #otherwise copy from Modules directory
}
require "$cfgdir/ConfigL.pm";                                      # load the Config File
my ($netport,$sendtonet,$sendtopca,$use_gamepad,$joystick_device,$serialport,$waittime_serial,$i2cport,$pwm_res,$i2c_address,$i2c_freq,$debug,$servores,$num_servos,$stepwidth,$play_full_mp3,$mp3loop,$block_popup_width,$matrix_popup_width,$max_out_pins,$dboutlist,$joystick_x_start,$joystick_x_end,$joystick_y_start,$joystick_y_end,$gamepad_start,$gamepad_stop,$gamepad_axis_y,$gamepad_axis_x,$gamepad_x_start,$gamepad_x_end,$gamepad_y_start,$gamepad_y_end,$num_servos_per_row,$OE,$NEXT,$PREV,$S1,$S2,$SHUT,$servosettings)=ConfigL::get_vars();
use Curses::UI;
use Curses::UI::Mousehandler::GPM;
$SIG{INT} = \&ctrlc;
use vars qw/$boxes_exist @cbox_x_saved @cbox_y_saved $lastkey $blocks_open $matrix_open $nbx $nby $in_popup $absmaxmov $maxblkfiles $full_range $maxstep $minstep $nummoves $saved @channely @channelx @active_x @active_y $justview $api $serial $mp3 $maxfiles $recording $inext $iprev $outfilename @servocontent $previouscount $contentcount $pwm_en $periodstart @filelist @joy_content $js $wincnt/;
my $statuspos=0;
my $nodeinf= '"Node Address" is the unique number of the network or wlan box (node), you may connect servos or relais to. The node address can be only transferred, if the "Base Conf" jumper is set on the node. Make sure not to give two nodes the same node number ! 
!!!!!! Otherwise you mess up your configuration !!!!!!'; 
my $macinf= '"MAC Address" is the network address of the node, that must be unique within your ethernet network segment. The last two bytes of the MAC address are the node number in hexadecimal format. To change the Base, press the button "New_MAC_Base". The MAC can be only transferred, if the "Base Conf" jumper is set on the node. Make sure to set only one node jumper at a time!
!!!!!! Otherwise you mess up your network !!!!!!';
my $pwmcountinf= '"Number of Servos" defines how many Servos are connected to this node. The range is 0 to 16. If a node shares its ouput pins with relay outputs, the pins must not overlap. Servo outputs and relay outputs may start at higher numbers. So both, relais and servos may be connected to same node.';
my $pwmstartinf= '"SVO # is SVO at pin" Servo numbers defined in ConfigL.pm are mapped to the pins of your node. Where ConfigL.pm servo number entered here, will be mapped to the servo connected to pin "1st SVO starts at pin"  and automatically all subsequent servo numbers will be mapped to the next pins, until the "Number of servos" defined in the previous field is reached.';     
my $pwmstartpininf='"1st SVO starts at pin" The Servo number set in "SVO # is SVO at pin" will be mapped to this pin of your box. The range is: 0 to 15. For example: If you set "Number of Servos" to 5 and  "SVO #..." to 10 and "1st SVO..." to 4, then Servo10 configured in ConfigL will be mapped to Pin 4 of your box, Servo11 to Pin5 .. and Servo14 to Pin 8.';
my $binoutcountinf='"Number of Relais" defines how many relais are connected to this node. The range is 0 to 16. If a node shares its ouput pins with servo outputs, the pins must not overlap. Servo and relay outputs may start at higher numbers. So both, relais and servos may be connected to same node.';
my $binoutstartinf='"SVO # keeps Relais data" Relais are controlled out of servo data, where one servo position contains 16 bit = maximum 16 relais. This servo number defined in ConfigL.pm will be mapped to the pins of your node. If a node has only relay outputs, and the "Number of Relais" is 16, Each bit of the servo data word will be output to its referred pin of the node.';    
my $binoutstartpininf='"1st Relay starts at pin:" This value is important, if a node shares servo and relay pins. It defines where the relay bit data will be mapped onto the output pins. For example: If you have 12 servos and 4 relais for your node, then the "Number of Servos" becomes 12, the "Number of Relais" becomes 4 and the "1st Relay starts at Pin:" becomes 13.';
my $blnkbtninf='Pressing this button will send a blink command to the node. This is to be able to identify a node, in environments where several nodes are installed.';
#my $blnkdurationinf='"Blink speed in ms:" Here you may change the default 250ms to a different value.';
my $rebootbtninf='Forces to reboot the node.';
my $rebootnetbtninf='Forces to reboot all nodes in the whole Network.';
my $resetbtninf='Unconfigures all values of the node. Keep in mind you need to re-configure all node parameters, including the need to set the bas conf jumper after this command. Use with care !!!!';
my $basicbtninf='Sends the node address and MAC to all nodes with set "Bas Conf" jumper. ! Warning !: only one Bas Conf jumper must be set at a time.
!!!!!! Otherwise you mess up your network !!!!!!';
my $getstatusbtninf='Requests the configuration status from the node and displays it if received.';
my $sendbtninf='Sends all node specific configuration data at once, of course excluding node address and MAC';
my $notesinf='In "Notes" you should enter some description about the node you just configure. This is to recognize the node and its purpose after some time, or when a different operator needs to maintain the configuration.'; 
my $outdbbtninf='This button outputs a database list to file or screen using the checkbox options provided.';
#---------------- Data base init ----------------------------
my $config_db = "$cfgdir"."/nodeconfig.db";
my $dbh = DBI->connect("dbi:SQLite:dbname=$config_db", "", "", {   #create data base for config storage
    RaiseError => 1,
    PrintError => 0,
    AutoCommit => 1,
});
if ( ! table_exists($dbh,"config"))  {                             #Make sure table config exists
  $dbh->do(" CREATE TABLE IF NOT EXISTS config (
    node INTEGER NOT NULL,
    mac INTEGER NOT NULL,
    pwmCount INTEGER,
    pwmStartWord INTEGER,
    pwmStartpin INTEGER,
    binOutCount INTEGER,
    binOutStartWord INTEGER,
    binOutStartpin INTEGER,
    notes TEXT,
    confirmed INTEGER,
    updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (node)
    )");                                                           # create data base in case it did not exist
}
#------------------------------------------------------------
my $macstring="DE:AD:BE:EF:00:01";
my $fh = tmpfile();
open STDERR, ">&fh";                                               # redirect Standard error to file
system 'clear';                                                    # clear the screen
my $packet_counter=1;                                              # begin packet counting with 1
my $timeout_ms=700;                                                # timeout for status request 
#---------------------- set up the main Curses::UI dialog -----------------------------------
my $cui = new Curses::UI( -color_support => 1, -clear_on_exit => 1, -key_support => 1);
my @statuslines;                                                   # keeps the status messages (ring buffer)
my $notebookheight=40;
my $win = $cui->add(                 # The base window
                    undef, 'Window',
                     -border => 0,
                     -y    => 0,
                     -bfg  => 'red',
                     -height => $notebookheight,
                     -width => 120,
                     -title => 'Settings',
                     -releasefocus =>1,
                   );
my $nf = $win->add(                # The node setup frame
                    'fra0', 'Container',
                     -border => 1,
                     -y    => 0,
                     -bfg  => 'red',
                     -title => 'Node Setup',
                     -height => 10,
                     -width => 60,
                     -releasefocus =>1
                   );
my $if = $win->add(                # The field info frame
                    'fra1', 'Container',
                     -border => 1,
                     -y    => 10,
                     -bfg  => 'red',
                     -title => 'field info',
                     -height => 10,
                     -width => 60,
                     -focusable => 0,
                     -releasefocus =>1
                   );
my $cf = $win->add(               # The command frame
                     'fra2', 'Container',
                     -border => 1,
                     -x    => 60,
                     -bfg  => 'red',
                     -title => 'Commands',
                     -height => 10,
                     -releasefocus =>1
                   );
my $of = $win->add(               # The notes frame
                     'fra3', 'Container',
                     -border => 1,
                     -x    => 60,
                     -y    => 10,
                     -bfg  => 'red',
                     -title => 'Notes',
                     -height => 10,
                     -releasefocus =>1
                   );
my $lf = $win->add(               # Log frame
                     'fra4', 'Container',
                     -border => 1,
                     -y    => 20,
                     -bfg  => 'red',
                     -title => 'Logs',
                     -focusable => 0,
                     -releasefocus =>1
                   );
$cui->set_binding(\&exit_dialog,"\cq");
my $fieldinfo = $if->add('fieldinfotext','TextViewer',-fg=>'yellow',-wrapping=>1);
my $nodelabel=$nf->add('mynodelabel','Label', -text=>'Node Address:', -bold=>1);
my $nodefield=$nf->add('mynodefield','TextEntry',-sbborder=>1,-x=>26,-width=>8,-text=>"1",-onfocus=>\&nodeinfo,-onchange=>\&checknode); 
my $nodebutton = $nf->add('mynodebutton','Buttonbox', -buttons => [
                            { -label => '+', -value=>1, -shortcut=>'+',-onpress=>\&incnode},
                            { -label => '-', -value=>2, -shortcut=>'-',-onpress=>\&decnode},
                            { -label => 'Basic_Config', -value=>2, -shortcut=>'-',-onpress=>\&sendbasic}
                          ],-fg=>'yellow',-bg=>'blue',-x=>35,-onfocus=>\&basicbtninfo,-width=>17);
my $maclabel=$nf->add('mymaclabel','Label', -text=>'MAC Address:', -bold=>1,-y=>1);
my $macfield=$nf->add('mymacfield','TextEntry', -text=>$macstring,-y=>1,-x=>17,-width=>18,-onfocus=>\&macinfo,-readonly=>1);
my $macchgbtn=$nf->add('mymmacchgbtn','Buttonbox', -buttons=> [
                            { -label => 'New_MAC_Base',-value=>1,-onpress=>\&chgmac}
                          ],-fg=>'yellow',-bg=>'blue',-x=>35,-y=>1,-onfocus=>\&macinfo,-width=>17);
my $pwmcountlabel=$nf->add('mypwmcountlabel','Label', -text=>'Number of Servos:',-bold=>1,-y=>2);
my $pwmcountfield=$nf->add('mypwmcountfield','TextEntry',-sbborder=>1,-text=>16,-y=>2,-x=>26,-width=>5,-onfocus=>\&pwmcountinfo,-onchange=>\&checkpwmcount);
my $pwmstartlabel=$nf->add('mypwmstartlabel','Label', -text=>'SVO # is SVO at pin 1:', -bold=>1,-y=>3);
my $pwmstartfield=$nf->add('mypwmstartfield','TextEntry',-sbborder=>1,-text=>0,-y=>3,-x=>26,-width=>8,-onfocus=>\&pwmstartinfo,-onchange=>\&checkpwmstart);
my $pwmstartpinlabel=$nf->add('mypwmStartsfpinlabel','Label', -text=>'1st SVO starts at pin:', -bold=>1,-y=>4);
my $pwmstartpinfield=$nf->add('mypwmStartsfpinfield','TextEntry',-text=>0,-sbborder=>1,-y=>4,-x=>26,-width=>5,-onfocus=>\&pwmstartpininfo,-onchange=>\&checkpwmstartpin);
my $relaiscountlabel=$nf->add('myrelaiscountlabel','Label', -text=>'Number of Relais:', -bold=>1,-y=>5);
my $relaiscountfield=$nf->add('myrelaiscountfield','TextEntry',-text=>0,-sbborder=>1,-y=>5,-x=>26,-width=>5,-onfocus=>\&binoutcountinfo,-onchange=>\&checkrelaiscount);
my $relaisstartlabel=$nf->add('myrelaisstartlabel','Label', -text=>'SVO # keeps Relais data:', -bold=>1,-y=>6);
my $relaisstartfield=$nf->add('myrelaisstartfield','TextEntry',-text=>0,-sbborder=>1,-y=>6,-x=>26,-width=>8,-onfocus=>\&binoutstartinfo,-onchange=>\&checkrelaisstart);
my $relaypinlabel=$nf->add('myrelaisfpinlabel','Label', -text=>'1st Relay starts at pin:', -bold=>1,-y=>7);
my $relaypinfield=$nf->add('myrelaisfpinfield','TextEntry',-text=>0,-sbborder=>1,-y=>7,-x=>26,-width=>5,-onfocus=>\&binoutstartpininfo,-onchange=>\&checkrelaypin);
my $status = $lf->add('statustext','TextViewer',-fg=>'yellow',-wrapping=>1);
my $blinkbtn=$cf->add('mymblinkbtn','Buttonbox', -buttons=> [
                            { -label => 'Identify_node',-value=>1,-onpress=>\&findnode}
                          ],-fg=>'yellow',-bg=>'blue',-onfocus=>\&blnkbtninfo,-width=>16);
my $quitinfo=$cf->add('myquitinfo','Label', -text=>'Type Ctrl-Q to Quit', -bold=>1,-x=>24,-fg=>'yellow');
my $rebootbtn=$cf->add('myrebootbtn','Buttonbox', -buttons=> [
                            { -label => 'Reboot_Node',-value=>1,-onpress=>\&rebootnode}
                          ],-fg=>'yellow',-bg=>'blue',-onfocus=>\&rebootbtninfo,-y=>1,-width=>16);
my $rebootnetbtn=$cf->add('myrebootnetbtn','Buttonbox', -buttons=> [
                            { -label => 'Reboot_Network',-value=>1,-onpress=>\&rebootnet}
                          ],-fg=>'yellow',-bg=>'blue',-onfocus=>\&rebootnetbtninfo,-y=>2,-width=>16);
my $resetbtn=$cf->add('myresetbtn','Buttonbox', -buttons=> [
                            { -label => 'Unconfigure_Node',-value=>1,-onpress=>\&unconfignode}
                          ],-fg=>'yellow',-bg=>'blue',-onfocus=>\&resetbtninfo,-y=>3,-width=>16);
my $getstatusbtn=$cf->add('mygetstatusbtn','Buttonbox', -buttons=> [
                            { -label => 'Get_Node_Status',-value=>1,-onpress=>\&getstatus}
                          ],-fg=>'yellow',-bg=>'blue',-onfocus=>\&getstatusbtninfo,-y=>4,-width=>16);
my $sendbtn=$cf->add('mysendbtn','Buttonbox', -buttons=> [
                            { -label => 'Send_Node_Setup',-value=>1,-onpress=>\&sendspecific}
                          ],-fg=>'yellow',-bg=>'blue',-onfocus=>\&sendbtninfo,-y=>5,-width=>16);
my $outdbbtn=$cf->add('myoutdbbtn','Buttonbox', -buttons=> [
                            { -label => 'Output_DB',-value=>1,-onpress=>\&outdb}
                          ],-fg=>'yellow',-bg=>'blue',-onfocus=>\&outdbbtninfo,-y=>6,-width=>16);
my $outdbbox1=$cf->add('myoutdbbox1','Checkbox',-label=>"To File/Screen",-checked=>1,-y=>6,-x=>17);
my $outdbbox2=$cf->add('myoutdbbox2','Checkbox',-label=>"incl. descr.",-checked=>1,-y=>6,-x=>37);
my $outdbbox3=$cf->add('myoutdbbox3','Checkbox',-label=>"confirmed",-checked=>1,-y=>7,-x=>2);
my $outdbbox4=$cf->add('myoutdbbox4','Checkbox',-label=>"unconfirmed",-checked=>1,-y=>7,-x=>18);
my $notesfield=$of->add('mynotesfield','TextEditor',-vscrollbar=>1, -wrapping=>0,-onfocus=>\&notesinfo);
my $statusheight=$status->height();
$nf->focus();
if ( my $latest= get_latest_config($dbh)) {
  my ($node, $mac, $pwmCount, $pwmStartWord, $pwmStartpin, $binOutCount, 
    $binOutStartWord, $binOutStartpin, $notes, $confirmed, $updated) = @$latest;
  $nodefield->text($node);
  my $mac_hex=intmac2hexmac($mac);
  $macfield->text($mac_hex);
  $pwmcountfield->text($pwmCount);
  $pwmstartfield->text($pwmStartWord);
  $pwmstartpinfield->text($pwmStartpin);
  $relaiscountfield->text($binOutCount);
  $relaisstartfield->text($binOutStartWord);
  $relaypinfield->text($binOutStartpin);
  $notesfield->text($notes);
  if ($confirmed) {
    printstatus("Newest node is $node. It has CONFIRMED status, written at $updated\n");
  } else {
    printstatus("Newest node is $node. It has status UNCONFIRMED, written at $updated\n");
  }
} else {
  printstatus("No Entries in database - will be created by saving your first node !\n"); 
}
$cui->mainloop;
$dbh->disconnect;
exit 0;

#############################################################
# print - output the data base content to file
#############################################################
sub outdb{
  my $where='';                                                    # get all entries from DB
  my $wantconfirmed=$outdbbox3->get();
  my $wantunconfirmed=$outdbbox4->get();
  my $wantdescription=$outdbbox2->get();
  if ($wantconfirmed) { $where=" WHERE confirmed = 1";}
  if ($wantunconfirmed) { $where=" WHERE confirmed = 0";}
  if ($wantconfirmed && $wantunconfirmed || ((! $wantconfirmed) && (! $wantunconfirmed))) { $where=""; }
  my $wantfile=$outdbbox1->get();
  my $outfile=$dboutlist .time();
  my ($table,$mx,$fsep);
  my $sep=\'|';
  if ($wantfile) {$fsep=\"|"} else {$fsep=\"|\r"} 
  if ($wantdescription) {
    $table=Text::Table->new($sep,"Node",$sep,"MAC Address",$sep,"# SVOs",$sep,"SVO @ Strtpin",$sep,"SVO Strtpin",$sep,"# REL",$sep,"REL @ SVO",$sep,"1st REL @ pin",$sep,"Confirmed",$sep,"Last Update",$sep,"Description",$fsep);
    $mx=multirow("SELECT node,mac,pwmCount,pwmStartWord,pwmStartpin,binOutCount,binOutStartWord,binOutStartpin,confirmed,updated,notes FROM config $where"); 
    chgmacdb($mx);
  } else {
    $table=Text::Table->new($sep,"Node",$sep,"MAC Address",$sep,"# SVOs",$sep,"SVO @ Strtpin",$sep,"SVO Strtpin",$sep,"# REL",$sep,"REL @ SVO",$sep,"1st REL @ pin",$sep,"Confirmed",$sep,"Last Update",$fsep);
    $mx=multirow("SELECT node,mac,pwmCount,pwmStartWord,pwmStartpin,binOutCount,binOutStartWord,binOutStartpin,confirmed,updated FROM config $where"); 
    chgmacdb($mx);
  }
  $table->load(@$mx);
  my $rule=$table->rule('-','+');
  if ($wantfile) {
    open (TXT,">$outfile")||err ("File $outfile coud not be opened for writing $!");
    $_=$table->title();
    print TXT $rule;
    print TXT $_;
    print TXT $rule;
    $_=$table->body();
    print TXT $_;
    print TXT $rule;
    print TXT "\n";
    close TXT;
    printstatus("Text output of data base content written to file: $outfile\n");
  } else {
    $cui->leave_curses();
    system 'clear';
    $_=$table->title();
    print "$rule\r";
    print $_;
    print "$rule\r";
    $_=$table->body();
    print $_;
    print "$rule\r";
    print "Press ENTER to close the view\n";
    <STDIN>;
    while ($cui->get_key(0) != -1) {}                              # flush all keystrokes to not confuse curses
    $cui->reset_curses();
  }
}
#############################################################
# change the MAC address in the DB result
#############################################################
sub chgmacdb{
  my $dbref=shift;
  my $lines=scalar(@$dbref);
  for (my $i=0;$i<$lines;$i++){
    $dbref->[$i]->[1]=intmac2hexmac($dbref->[$i]->[1]);
  }
}
#############################################################
# open the MAC address setup window
#############################################################
sub chgmac{
  mac_ui();
}
#############################################################
# find a node physically by sending a blink command - toggle blinking
#############################################################
sub findnode {
  state $is_on;
  my $node=$nodefield->get();
  if ($is_on) {
    $is_on=0;
    setregister($node,128,0);
    printstatus("Sent >>STOP<< blink command to node $node \n"); 
  } else {
    $is_on=1;
    setregister($node,128,1);
    printstatus("Sent >>START<< blink command to node $node \n"); 
  }
}
#############################################################
# extend 2 digit dirty hex code into clean hexcode
#############################################################
sub extended_hex {
  my ($code) = @_;
  $code = uc(substr($code =~ s/[^0-9A-Fa-f]/0/gr, 0, 2));
  return length($code) == 1 ? "0$code" : $code;
}
#############################################################
# read the first four MAC Bytes from field and update field with new node
# use this also for updating all other fields from the data base
# because the nodeaddress is the key for all data in the DB
#############################################################
sub node2mac{
  my $node=shift;
  if (my $configref=singlerow("SELECT * FROM config WHERE node='$node'")){           # in case there is a line in the DB for this node, read the db content into the fields
    my $macstring=intmac2hexmac($configref->[1]);
    $macfield->text($macstring);                                                     # if a DB entry exists, take the MAC from the DB
    $pwmcountfield->text($configref->[2]);                                           # set the number of servos field
    $pwmstartfield->text($configref->[3]);                                           # set the servo in the servo array as first servo on this box (node) 
    $pwmstartpinfield->text($configref->[4]);
    $relaiscountfield->text($configref->[5]);                                        # set the number of relais field
    $relaisstartfield->text($configref->[6]);                                        # takes this servo in the servo array as the one holding the relay bits (16)
    $relaypinfield->text($configref->[7]);                                           # the first bit of the relay bits data will be mapped to this pin (1-16)
    $notesfield->text($configref->[8]);                                              # text notes containing hints for the node
    if ($configref->[9]){
      printstatus ("Node $node is marked as CONFIRMED in the Data base\n");
    } else {
      printstatus ("Node $node is in DB but UNCONFIRMED! Do 'Send_Node_Setup' to make it confirmed\n");
    }
  } else { 
    printstatus("Node $node not in DB - Do Basic_Config + Send_Node_Setup to make it confirmed\n");
    my $nodeh=$node;
    my $hexmac=$macfield->get();
    my $basemac=substr $hexmac,0,11;
    my $mac=mountmac($basemac,$node);
    $macfield->text($mac);
  }
  $nf->draw;
}
#############################################################
# set the mac according to base and node
#############################################################
sub calcmac{
  my ($m1,$m2,$m3,$m4)=@_;
  if (! $m1) {$m1="A2";} 
  if (! $m2) {$m2="00";} 
  if (! $m3) {$m3="00";} 
  if (! $m4) {$m4="00";} 
  $m1=extended_hex($m1);
  $m2=extended_hex($m2);
  $m3=extended_hex($m3);
  $m4=extended_hex($m4);
  my $mac=mountmac("$m1:$m2:$m3:$m4",$nodefield->get());
  $macfield->text($mac);
  $macfield->draw;
}
#############################################################
# mount a mac string out of the first four Hexbytes (basemac) and the node number
#############################################################
sub mountmac{
  my $basemac=shift;
  my $nodeh=shift;
  if (! $nodeh) {$nodeh="0";}
  my $nodel=sprintf("%02X",$nodeh & 0x00FF);
  $nodeh=sprintf("%02X",($nodeh & 0xFF00) >> 8);
  my $mac="$basemac:$nodeh:$nodel";
  return $mac;
}
#############################################################
# open the MAC address setup window
#############################################################
sub mac_ui{
  our $popup = $cui->add(
      'macwin', 'Window',
      -border => 1,
      -centered => 1,
      -width => 39,
      -height => 10,
      -title => 'Base MAC address configuration',
      -releasefocus=>0
  );
  my $label=$popup->add('mylabel','Label',-text=>'Please enter a MAC as Hex numbers',-bold=>1,-x=>1,-y=>2);
  our $m1=$popup->add('mym1','TextEntry',-width=>5, -x=>1, -y=>4,-sbborder=>1);
  my $m1c=$popup->add('mym1c','Label',-text=>':',-y=>4,-x=>6,-bold=>1);
  our $m2=$popup->add('mym2','TextEntry',-width=>5, -x=>7,-y=>4,-sbborder=>1);
  my $m2c=$popup->add('mym2c','Label',-text=>':',-y=>4,-x=>12,-bold=>1);
  our $m3=$popup->add('mym3','TextEntry',-width=>5, -x=>13,-y=>4,-sbborder=>1);
  my $m3c=$popup->add('mym3c','Label',-text=>':',-y=>4,-x=>18,-bold=>1);
  our $m4=$popup->add('mym4','TextEntry',-width=>5, -x=>19, -y=>4,-sbborder=>1);
  my $m5=$popup->add('mym5','Label',-text=>": XX : XX", -x=>24, -y=>4,-bold=>1);
  my $retbtn=$popup->add('myretbtn','Buttonbox', -buttons=> [
                    { -label => 'Save_and_close',-value=>1,-onpress=>\&savemac},
                    { -label => 'Cancel_and_close',-value=>2,-onpress=>\&savemac},
                    ],-fg=>'yellow',-bg=>'blue',-y=>6);
  $popup->modalfocus();
  $popup->draw();
  #------------------------------------------------------------
  # save or cancel mac address
  #------------------------------------------------------------
  sub savemac {
    $popup->loose_focus();
    $cui->delete('macwin');
    $cui->draw;
    calcmac($m1->get(),$m2->get(),$m3->get(),$m4->get());          # calc the mac and output to main window
  }
}
#############################################################
# show the info text
#############################################################
sub outdbbtninfo {
  $fieldinfo->text($outdbbtninf);
  $fieldinfo->draw;
}#--------------------
sub notesinfo {
  $fieldinfo->text($notesinf);
  $fieldinfo->draw;
}#--------------------
sub sendbtninfo {
  $fieldinfo->text($sendbtninf);
  $fieldinfo->draw;
}#--------------------
sub getstatusbtninfo {
  $fieldinfo->text($getstatusbtninf);
  $fieldinfo->draw;
}#--------------------
sub basicbtninfo {
  $fieldinfo->text($basicbtninf);
  $fieldinfo->draw;
}#--------------------
sub resetbtninfo {
  $fieldinfo->text($resetbtninf);
  $fieldinfo->draw;
}#--------------------
sub rebootbtninfo {
  $fieldinfo->text($rebootbtninf);
  $fieldinfo->draw;
}#--------------------
sub rebootnetbtninfo {
  $fieldinfo->text($rebootnetbtninf);
  $fieldinfo->draw;
}#--------------------
#sub blnkdurationinfo {
#  $fieldinfo->text($blnkdurationinf);
#  $fieldinfo->draw;
#}#--------------------
sub blnkbtninfo {
  $fieldinfo->text($blnkbtninf);
  $fieldinfo->draw;
}#--------------------
sub binoutstartpininfo {
  $fieldinfo->text($binoutstartpininf);
  $fieldinfo->draw;
}#--------------------
sub binoutcountinfo {
  $fieldinfo->text($binoutcountinf);
  $fieldinfo->draw;
}#--------------------
sub binoutstartinfo {
  $fieldinfo->text($binoutstartinf);
  $fieldinfo->draw;
}#--------------------
sub pwmstartinfo {
  $fieldinfo->text($pwmstartinf);
  $fieldinfo->draw;
}#--------------------
sub pwmstartpininfo {
  $fieldinfo->text($pwmstartpininf);
  $fieldinfo->draw;
}#--------------------
sub pwmcountinfo {
  $fieldinfo->text($pwmcountinf);
  $fieldinfo->draw;
}#--------------------
sub macinfo {
  $fieldinfo->text($macinf);
  $fieldinfo->draw;
}#--------------------
sub nodeinfo {
  $fieldinfo->text($nodeinf);
  $fieldinfo->draw;
}
#############################################################
# sends reboot command to all nodes in the network
#############################################################
sub rebootnet {
  my $answer=$cui->dialog(-message => "Do you really want to reboot all nodes in the network?\n",
         -buttons=>[
        { -label => 'No', -value=>0, -shortcut=>'n'},
        { -label => 'Yes', -value=>1, -shortcut=>'y'}
        ]);
  if ( $answer!=1) {
    printstatus("Reboot all Nodes cancelled !\n");
    return 0;
  }
  setregister(32766,0,0);                                          # disable PWM
  printstatus("Reboot of all nodes sent! Takes a few seconds till they can respond\n");
}
#############################################################
# sends reboot command to a specific node
#############################################################
sub rebootnode {
  my $node=$nodefield->get();
  setregister($node,130,1);
  printstatus("Reboot node $node sent! Takes a few seconds till it can respond\n");
}
#############################################################
# sends unconfigure command to a specific node
#############################################################
sub unconfignode {
  my $node=$nodefield->get();
  my $answer=$cui->dialog(-message => "Do you really want to unconfigure node $node completely?\n",
         -buttons=>[
        { -label => 'No', -value=>0, -shortcut=>'n'},
        { -label => 'Yes', -value=>1, -shortcut=>'y'}
        ]);
  if ( $answer!=1) {
    printstatus("Unconfigure node $node cancelled !\n");
    return 0;
  }
  setregister($node,132,1);
  printstatus("Unconfigure node $node done! Box lost address - Base Conf. needed\n");
  $dbh->do("DELETE FROM config WHERE node=?",undef,$node);
}
#############################################################
# converts a colon separated mac sting into an array
#############################################################
sub mac_to_arrayref {
    my $mac = shift;
    return [ map { hex($_) } split /:/, $mac ];
}
#############################################################
# converts a int mac to a mac hex string
#############################################################
sub intmac2hexmac {
  my $mac_hex = sprintf("%012X", shift);                           # convert hex mac into int mac
  $mac_hex =~ s/(..)(?=.)/$1:/g;                                   # Add the colon in between the number
  return($mac_hex);
}
#############################################################
# converts a hex mac to a int mac 
#############################################################
sub hexmac2intmac {
  my $hexmac=shift;
  no warnings 'portable';
  my $intmac=hex($hexmac =~ s/://gr); 
  return($intmac);
}
#############################################################
# sends the basic setup to all nodes with set jumper
#############################################################
sub sendbasic {
  my $hexmac=$macfield->get();
  my $node=$nodefield->get();
  my $intmac=hexmac2intmac($hexmac);
  my $answer=$cui->dialog(-message => "Do you really want to configure node $node \n for all boxes with set Conf. Jumper ?\n",
         -buttons=>[
        { -label => 'No', -value=>0, -shortcut=>'n'},
        { -label => 'Yes', -value=>1, -shortcut=>'y'}
        ]);
  if ( $answer!=1) {
    printstatus("Basic config node $node cancelled !\n");
    return 0;
  }
upsert_config($dbh,
    node => $node,
    mac => $intmac,
    confirmed => 0
  );
  basicCommand(mac_to_arrayref($hexmac),$node); 
  printstatus("Basic setup sent - Node: $node MAC: $hexmac\n");
}
#############################################################
# send node specific command to ESP and to DB
#############################################################
sub sendspecific {
  my $node=$nodefield->get();
  my $pwm_count=$pwmcountfield->get();
  my $pwm_start=$pwmstartfield->get();
  my $pwm_bit=$pwmstartpinfield->get();
  my $bin_count=$relaiscountfield->get();
  my $bin_start=$relaisstartfield->get();
  my $bin_startpin=$relaypinfield->get();
  my $intmac=hexmac2intmac($macfield->get()); 
  my $notes=$notesfield->get();
  my $confirmed=0;
  setregister($node,1,$pwm_count,2,$pwm_start,3,$pwm_bit,4,$bin_count,5,$bin_start,6,$bin_startpin,131,1);
  msleep(800);
  if (my $rref=recv_status($node)) {
    $confirmed=1;
    if ($rref->[2] != $node){$confirmed=0;}    
    if ($rref->[3] != $pwm_count){$confirmed=0;}    
    if ($rref->[4] != $pwm_start){$confirmed=0;}    
    if ($rref->[5] != $pwm_bit){$confirmed=0;}    
    if ($rref->[6] != $bin_count){$confirmed=0;}    
    if ($rref->[7] != $bin_start){$confirmed=0;}    
    if ($rref->[8] != $bin_startpin){$confirmed=0;}    
for (my $i=2;$i<9;$i++){
}
  }
  upsert_config($dbh,
    node => $node,
    mac => $intmac,
    pwmCount => $pwm_count,
    pwmStartWord => $pwm_start,
    pwmStartpin => $pwm_bit,
    binOutCount => $bin_count,
    binOutStartWord => $bin_start,
    binOutStartpin => $bin_startpin,
    notes => $notes,
    confirmed => $confirmed
  );
  if ($confirmed){
    printstatus("Node setup written to node and DB and is confirmed\n"); 
  } else { printstatus("Attempted to write setup to node $node, Setup is in DB, but not confirmed\n");}
}
#############################################################
# read the node status via network and display it
#############################################################
sub getstatus {
  my $node=$nodefield->get();
  statusrequest($node,131,1);
  if (my $rref=recv_status($node)) {
    my $counter=$rref->[1];
    my $node_addr=$rref->[2];
    my $pwm_count=$rref->[3];
    my $pwm_start=$rref->[4];
    my $pwm_startpin=$rref->[5];
    my $bin_count=$rref->[6];
    my $bin_start=$rref->[7];
    my $bin_startpin=$rref->[8];
    my $esp_IP=$rref->[9];
    my $inport=$rref->[10];
    my $runtime=sprintf("%.2f",$rref->[11]/1000000);
    printstatus("---------------------------------\n");
    printstatus("Node $node has responded:\n");
    printstatus("Reads since last boot:   $counter\n");
    printstatus("Node address:            $node_addr\n");
    printstatus("Number of Servos:        $pwm_count\n");
    printstatus("SVO # is SVO at pin:     $pwm_start\n");
    printstatus("1st SVO starts at pin:   $pwm_startpin\n");
    printstatus("Number of Relais:        $bin_count\n");
    printstatus("SVO # keeps Relais data: $bin_start\n");
    printstatus("1st Relay starts at pin: $bin_startpin\n");
    printstatus("Node has IP:             $esp_IP\n");
    printstatus("Conf. recvd. on Port:    $inport\n");
    printstatus("Response took:           $runtime ms\n");
    printstatus("---------------------------------\n");
    $nodefield->text($node_addr);
    
  } else {
    printstatus("Timeout while trying to receive the status for node $node\n");
  }
}
#############################################################
# increments / decrements the node number in the IF
#############################################################
sub incnode {
  my $val=$nodefield->get();
  $val++;
  if ($val > $num_servos){printstatus("Warning: Node Number is larger than the maximum number of servos in ConfigL ($num_servos)\n");}
  $nodefield->text($val);
  node2mac($val);
}#---------------------------------
sub decnode {
  my $val=$nodefield->get();
  if ($val > 1) {$val--;}
  if ($val > $num_servos){printstatus("Warning: Node Number is larger than the maximum number of servos in ConfigL ($num_servos)\n");}
  $nodefield->text($val);
  node2mac($val);
}
#############################################################
# checks if the relais start number is in range
#############################################################
sub checkrelaisstart {
  my $relaissf=$relaisstartfield->get();
  if ($relaissf=~s/\D//g) { err("Field must contain only numbers"); $relaisstartfield->text($relaissf);} 
  if (($relaissf=~/\d/) && ($relaissf > $num_servos)) {printstatus("Warning: \"SVO # keeps Relais data\" field is larger than the maximum number of servos in ConfigL ($num_servos)\n");}  
}
#############################################################
# checks if the pwm start number is in range
#############################################################
sub checkpwmstart {
  my $pwmst=$pwmstartfield->get();
  if ($pwmst=~s/\D//g) { err("Field must contain only numbers"); $pwmstartfield->text($pwmst);} 
  if (($pwmst=~/\d/) && ($pwmst > $num_servos)) {printstatus("Warning: \"SVO # is SVO at pin 1\" field is larger than the maximum number of servos in ConfigL ($num_servos)\n");}  
}
#############################################################
# checks if the relais start pin number is in range
#############################################################
sub checkrelaypin {
  my $pwmsp=$pwmstartpinfield->get();
  my $pwmct=$pwmcountfield->get();
  my $binsp=$relaypinfield->get();
  my $binct=$relaiscountfield->get();
  if ($pwmct >= $max_out_pins) {$pwmct=0;}
  if ($binsp=~s/\D//g) { err("field must contain only numbers"); $relaypinfield->text($binsp);} 
  if ($binsp=~/\d/){ 
    if($binsp > $max_out_pins) {err("Error: \"1st Relay starts at pin\" field is larger than the maximum number of pins in ConfigL ($max_out_pins)\n");}
    if ($binsp+$binct > $max_out_pins) { printstatus("Warning: Servo start pin plus Servo count exceed the available pins of the box\n");}
    if ( $pwmct=~/\d/ && $binsp=~/\d/ && $binct=~/\d/ && $pwmsp=~/\d/) {
      if ($pwmsp+$pwmct - 1 >= $binsp && $binsp + $binct - 1 >= $pwmsp){ printstatus("Warning: Servo and relay pins overlap. Make sure not to overlap pin definitions\n");}
    }
  }  
}
#############################################################
# checks if the pwm start pin number is in range
#############################################################
sub checkpwmstartpin {
  my $pwmsp=$pwmstartpinfield->get();
  my $pwmct=$pwmcountfield->get();
  my $binsp=$relaypinfield->get();
  my $binct=$relaiscountfield->get();
  if ($pwmsp=~s/\D//g) { err("Field must contain only numbers"); $pwmstartfield->text($pwmsp);} 
  if ($pwmsp=~/\d/) {
    if ($pwmsp > $num_servos) {printstatus("Warning: \"SVO # is SVO at pin\" field is larger than the maximum number of servos in ConfigL ($num_servos)\n");}  
    if ($pwmsp+$pwmct > $max_out_pins) { printstatus("Warning: Servo start pin plus Servo count exceed the available pins of the box\n");}
    if ( $pwmct=~/\d/ && $binsp=~/\d/ && $binct=~/\d/ && $pwmsp=~/\d/) {
      if ($pwmsp+$pwmct - 1 >= $binsp && $binsp + $binct - 1 >= $pwmsp){ printstatus("Warning: Servo and relay pins overlap. Make sure not to overlap pin definitions\n");}
    }
  }
}
#############################################################
# checks if the node number is in range
#############################################################
sub checknode {
  my $node=$nodefield->get();
  if ($node=~s/\D//g) { err("Field must contain only numbers"); $nodefield->text($node);} 
  if (($node=~/\d/) && ($node > $num_servos)) {printstatus("Warning: Node Number is larger than the maximum number of servos in ConfigL ($num_servos)\n");}  
  if (($node=~/\d/) && ($node < 1)) {printstatus("Warning: Node Number is smaller than 1\n"); $node=1; $nodefield->text($node);}  
  node2mac($node);
}
#############################################################
# checks if the number of relais is in range
#############################################################
sub checkrelaiscount {
  my $pwmsp=$pwmstartpinfield->get();
  my $pwmct=$pwmcountfield->get();
  my $binsp=$relaypinfield->get();
  my $binct=$relaiscountfield->get();
  if ($binct=~s/\D//g) { err("Field must contain only numbers"); $relaiscountfield->text($binct)} 
  if ($binct=~/\d/) {
    if ($binct>$max_out_pins) { err("Number of relais must be smaller or equal to $max_out_pins");$binct=$max_out_pins;$relaiscountfield->text($binct)}    
    if (($pwmsp=~/\d/) && ($binct=~/\d/) && $binct + $pwmsp > $max_out_pins) { $_=$pwmsp + $binct; printstatus("Warning: Number of Relais + Servos ($_) is larger than the max. number of pins available ($max_out_pins)\n");}  
    if ( $pwmct=~/\d/ && $binsp=~/\d/ && $binct=~/\d/ && $pwmsp=~/\d/) {
      if ($pwmsp+$pwmct - 1 >= $binsp && $binsp + $binct - 1 >= $pwmsp){ printstatus("Warning: Servo and relay pins overlap. Make sure not to overlap pin definitions\n");}
    }
  }
}
#############################################################
# checks if the number of servos is in range
#############################################################
sub checkpwmcount {
  my $pwmsp=$pwmstartpinfield->get();
  my $pwmct=$pwmcountfield->get();
  my $binsp=$relaypinfield->get();
  my $binct=$relaiscountfield->get();
  if ($pwmsp=~s/\D//g) { err("Field must contain only numbers"); $pwmcountfield->text($pwmsp)} 
  if ($pwmsp=~/\d/ ){
    if ($pwmsp>$max_out_pins) { err("Number of servos must be smaller or equal to $max_out_pins");$pwmsp=$max_out_pins;$pwmcountfield->text($pwmsp)}    
    if (($binct=~/\d/)  && ($pwmct=~/\d/) && $pwmct + $binct > $max_out_pins) {$_=$pwmsp + $binct; printstatus("Warning: Number of Relais + Servos ($_) is larger than the max. number of pins available ($max_out_pins)\n");}  
    if ( $pwmct=~/\d/ && $binsp=~/\d/ && $binct=~/\d/ && $pwmsp=~/\d/) {
      if ($pwmsp+$pwmct - 1 >= $binsp && $binsp + $binct - 1 >= $pwmsp){ printstatus("Warning: Servo and relay pins overlap. Make sure not to overlap pin definitions\n");}
    }
  }
}
#############################################################
# checks if table exists
#############################################################
sub table_exists {
  my ($dbh, $tablename) = @_;                                      # SQLite: table_info returns empty result if table does not exist
  my $sth = $dbh->table_info(undef, undef, $tablename, 'TABLE');
  my $info = $sth->fetchall_arrayref;
  return scalar(@$info) > 0;
}
#############################################################
# write configuration to DB
#############################################################
sub set_config {
  my ($category, $key, $value) = @_;
  $dbh->do( "INSERT OR REPLACE INTO config (category, key, value) VALUES (?, ?, ?)", undef, $category, $key, $value);
}
#############################################################
# read configuration from DB
#############################################################
sub get_config {
  my ($category, $key) = @_;
  my ($value) = $dbh->selectrow_array( "SELECT value FROM config WHERE category = ? AND key = ?", undef, $category, $key);
  return $value;
}
#############################################################
#  calculate and add the CRC for the datagram
#############################################################
sub crc16 {
  my ($data_ref) = @_;  # Referenz auf Skalar (Binary String)
  my $crc = 0xFFFF;
  foreach my $byte (unpack('C*',$$data_ref)) {                     # Bytes aus dem String verarbeiten
  $crc ^= $byte;
    for (my $i = 0; $i < 8; $i++) {
      if ($crc & 0x0001) {
        $crc = ($crc >> 1) ^ 0xA001;
      } else {
        $crc >>= 1;
      }
    }
  }
  return $crc;
}
#############################################################
#  a ms sleep ( in milliseconds )
#############################################################
sub msleep {
  my $duration=shift;
  hsleep($duration * 1000000);
  return;
}
#############################################################
#  a hires sleep ( in nanoseconds )
#############################################################
sub hsleep {
  my $duration=shift;
  my $now=gethrtime();
  while ($now + $duration >= gethrtime()) {                        # As long as the sleep duration is not reached, keep in loop
  }
  return;
}
#############################################################
#  receive the ESP status and return as array reference
#############################################################
sub recv_status {
  my ($expected_node) = @_;
  socket(my $recv_sock, PF_INET, SOCK_DGRAM, getprotobyname('udp')) # Create UDP socket
    or die "socket: $!";
  setsockopt($recv_sock, SOL_SOCKET, SO_REUSEADDR, 1)
    or die "setsockopt: $!";
  my $recv_addr = sockaddr_in($netport, INADDR_ANY);
  bind($recv_sock, $recv_addr)
    or die "bind: $!";
  my $start_ns = gethrtime();                                      # Nanoseconds
  my $timeout_ns = $timeout_ms * 1000000;                          # Convert ms to ns
  my $response_data;
  while ((gethrtime() - $start_ns) < $timeout_ns) {
    my $rin='';
    vec($rin, fileno($recv_sock), 1) = 1;
    my $remaining_ns = $timeout_ns - (gethrtime() - $start_ns);    # calc remaining timeout
    my $remaining_sec = $remaining_ns / 1000000000;
    my $nfound = select($rin, undef, undef, $remaining_sec);               
    if ($nfound > 0) {                                             # select() with timeout
      my $buffer;
      my $peer_addr = recv($recv_sock, $buffer, 1500, 0);
      if ($peer_addr) {
        my ($peer_port, $peer_ip) = sockaddr_in($peer_addr);
        my $peer_ip_str = inet_ntoa($peer_ip);
        my $data_len = length($buffer);
        if ($data_len < 6) {                                       # Check minimum length
          printstatus ("Received Packet too short: $data_len bytes\n"); next;
        }
        my $received_crc = unpack('n', substr($buffer, -2, 2));    # Extract CRC
        my $crc_data = substr($buffer, 0, -2);                     # Calculate CRC - exclude crc word from data
        my $calculated_crc = crc16(\$crc_data);
        if ($received_crc != $calculated_crc) {
          printstatus(sprintf("CRC error from %s: got 0x%04X expected 0x%04X\n",$peer_ip_str, $received_crc, $calculated_crc)); next;
        }
        my @words;                                                 # Byte swap (16-bit little to big endian)
        for (my $i = 0; $i < length($crc_data); $i += 2) {
          my $word = unpack('n', substr($crc_data, $i, 2));
          push @words, $word;
        }
        if ($words[0] == 0 || $words[0] > scalar(@words)) {        # Validate length word (first word)
          $_=scalar(@words);
          printstatus ("Invalid length word $words[0] shoud be $_\n"); next;
        }
        my $node_addr = $words[2];                                 # Word 2 = node address Check node address if specified
        if ($expected_node > 0 && $node_addr != $expected_node) { next;}   # A Different node responded
        push @words,$peer_ip_str;                                  # counter      = $words[1],
        push @words,$peer_port;                                    # node_addr    = $words[2],
        push @words,(gethrtime() - $start_ns);                     # pwm_count    = $words[3],
                                                                   # pwm_start    = $words[4],
                                                                   # bin_count    = $words[5],
                                                                   # bin_start    = $words[6],
                                                                   # bin_startpin = $words[7],
        close($recv_sock);                                         # peer_ip      = $peer_ip_str,[8],
        return \@words;                                            # peer_port    = $peer_port,[9],
      }                                                            # response_ns  = gethrtime() - $start_ns,[10]
    } elsif ($nfound == 0) {                                              
      last;
    } else {
      printstatus("select error: $!\n");
      last;
    }
  }
  close($recv_sock);
  return 0;                                                        # undef if timeout/no valid response
}
#############################################################
# send a status request to node
#############################################################
sub statusrequest{
  my $node=shift;
  my $regadr=shift;
  my $regcont=shift;
  my $nodeaddr=$node+32768;
  my @bcastdata=($nodeaddr,$packet_counter,$regadr,$regcont);
  bcast(\@bcastdata);
}
#############################################################
# register setup of the node - set MAC and node number
#############################################################
sub setregister{
  my $node=shift;
  #my $regadr=shift;
  #my $regcont=shift;
  my $nodeaddr=$node+32768;
  my @bcastdata=($nodeaddr,$packet_counter,@_);
  bcast(\@bcastdata);
}
#############################################################
# basic setup of the node - set MAC and node number
#############################################################
sub basicCommand{
  my $macref=shift;
  my $node=shift;
  my @bcastdata=(32768,$packet_counter,@$macref,$node);
  bcast(\@bcastdata);
}
#############################################################
# adds packet counter, 
#############################################################
sub send_data_broadcast {
  my ($data_array_ref) = @_;
  my $data_length = scalar(@$data_array_ref);                      # determine data length
  my @packet_data = ($data_length, $packet_counter, @$data_array_ref);# size  + packet counter + data
  bcast(\@packet_data);                                            # send broadcast array
  $packet_counter = ($packet_counter + 1) & 0xFFFF;                # increment packet counter with overflow at 65535
}
#############################################################
# really sends the data to the network
#############################################################
sub bcast {
  my $packet_data_ref=shift;
  socket(my $sock, PF_INET, SOCK_DGRAM, getprotobyname('udp')) or die "Could not create Socket: $!";
  setsockopt($sock, SOL_SOCKET, SO_BROADCAST, 1) or die "Could not activate broadcast: $!";
  my $dest_addr = sockaddr_in($netport, INADDR_BROADCAST);          # set broadcast destination address
  my $packed_data = pack('n*', @$packet_data_ref);                  # convert data into big endian for the network
  my $crc=crc16(\$packed_data);
  $packed_data .= pack('v', $crc);                                  # CRC als 2 Bytes an den String anhängen (Little-Endian)
  send($sock, $packed_data, 0, $dest_addr) or die "Send Error: $!"; # send to network
  close($sock);
  return 1;
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
# exit the script
#############################################################
sub exit_dialog{
  $cui->mainloopExit();
  exec 'reset';
}
#############################################################
# output text to main status section
#############################################################
sub printstatus {
  if ($statuspos >= $statusheight) {
    $statuspos=0;
  }
  $statuslines[$statuspos]=shift;
  $statuspos++;
  my $statusline='';
  for (my $a=$statuspos;$a<$statusheight;$a++) {
    if ($statuslines[$a]) {$statusline.=$statuslines[$a];}
  }
  for (my $a=0;$a<$statuspos;$a++){
    $statusline.=$statuslines[$a];
  }
  $status->text($statusline);
  $status->draw(1);
}
#############################################################
# update/insert table config
#############################################################
sub upsert_config {
  my ($dbh, %values) = @_;
  if ($dbh->selectrow_array("SELECT 1 FROM config WHERE node=?", undef, $values{node})) {
    my @cols = grep { $_ ne 'node' } keys %values;                 # UPDATE mit Timestamp
    my $sql = "UPDATE config SET " . join(',', map {"$_=?"} @cols) . ", updated=CURRENT_TIMESTAMP WHERE node=?";
    $dbh->do($sql, undef, @values{@cols}, $values{node});
  } else {
    my @cols = keys %values;                                       # INSERT (wird automatisch mit CURRENT_TIMESTAMP gefüllt)
    my $sql = "INSERT INTO config (" . join(',', @cols) . ") VALUES (" . join(',', ('?') x @cols) . ")";
    $dbh->do($sql, undef, @values{@cols});
  }
}
#############################################################
# update table config 
#############################################################
sub update_config {
  my ($dbh, $node, %values) = @_;
  my @cols = keys %values;
  my $sql = "UPDATE config SET " . join(',', map {"$_=?"} @cols) . " WHERE node=?";
  $dbh->do($sql, undef, @values{@cols}, $node);
}
#############################################################
# inseert into table config 
#############################################################
sub insert_config {
  my ($dbh, %values) = @_;
  my @cols = keys %values;
  my $sql = "INSERT INTO config (" . join(',', @cols) . ") VALUES (" . join(',', ('?') x @cols) . ")";
  $dbh->do($sql, undef, @values{@cols});
}
#############################################################
# read multiple rows from the data base
#############################################################
sub multirow {
  my $rows = $dbh->selectall_arrayref( shift );
  return $rows;  # Arrayref or undef if Table empty
}
#############################################################
# read a row from the data base
#############################################################
sub singlerow {
  my $row = $dbh->selectrow_arrayref( shift );
  return $row;  # Arrayref or undef if Table empty
}
#############################################################
# read a column from the data base
#############################################################
sub singlecol {
  my $col = $dbh->selectcol_arrayref( shift );
  return $col;  # Arrayref or undef if Table empty
}
#############################################################
# read last entry from data base
#############################################################
sub get_latest_config {
  my $dbh = shift;
  my $row = $dbh->selectrow_arrayref(
    "SELECT node, mac, pwmCount, pwmStartWord, pwmStartpin, binOutCount, 
     binOutStartWord, binOutStartpin, notes, confirmed, updated
     FROM config 
     ORDER BY updated DESC 
     LIMIT 1"
  );
  return $row;  # Arrayref or undef if Table empty
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
sub ctrlc {
$SIG{INT} = \&ctrlc;
  disablePWM();
  $dbh->disconnect;
  exit;
}
#############################################################
sub test {
  my @mac=(0xde,0xad,0xbe,0xef,0x01,0x71);                         # use some coincidential mac
  my $node=113;
  #basicCommand(\@mac,$node);
  #setregister(113,1,16);                                          # set register 1 =16 PWMs
  #setregister(113,1,0);                                           # set register 1 =0 PWMs
  #sleep 1;
  #setregister(113,2,0);                                           # set register 2 =0 startword in datastream
  #setregister(32767,0,0);                                         # disable PWM
  #setregister(113,128,1);                                         # start blinking 
  #sleep 10;
  #setregister(113,128,0);                                         # stop blinking 
  #setregister(113,3,16);                                          # 16 digital ports
  #sleep 1;
  #setregister(113,4,1);                                           # take bitmap of Servo1
  #sleep 1;
  #setregister(113,5,0);                                           # start at bit 0
  #exit 0;
  #statusrequest(113,131,1,10,0,1,191);
  statusrequest(113,131,1,255,255,255,255);
  my $responseref=recv_status(113);
  printresponse($responseref);
}
#------------------------------------------------------------
sub printresponse {
  my $ref=shift;
  foreach my $cont (@$ref) {
    print "$cont ";
  }
  print "\n";
}
#############################################################
END {
  $dbh->disconnect;
}

