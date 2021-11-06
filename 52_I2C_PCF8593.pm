##############################################
# $Id$
#
package main;

use strict;
use warnings;
use SetExtensions;
use Scalar::Util qw(looks_like_number);

my %I2C_PCF8593_Config =
(
	'Control' => 
		{
			'TIMER_FLAG' => 1 , 
			'ALARM_FLAG' => 2 ,
			'ALARM_ENABLE' => 4,
			'MASK_FLAG' => 8 ,
			'FUNCTION_MODE_MASK' => 0x30 ,
			'FUNCTION_MODE_CLOCK32' => 0x00 ,
			'FUNCTION_MODE_CLOCK50' => 0x10 ,
			'FUNCTION_MODE_EVCOUNT' => 0x20 , # This is what we use
			'FUNCTION_MODE_TEST' => 0x30 ,
			'HOLD_LAST_COUNT' => 0x40,
			'STOP_COUNTING' => 0x80,  
		},
);

sub I2C_PCF8593_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}     = 	"I2C_PCF8593_Define";
  $hash->{UndefFn}   = 	"I2C_PCF8593_Undef";
  $hash->{NotifyFn}  =  'I2C_PCF8593_Notify';
  $hash->{AttrFn}    = 	"I2C_PCF8593_Attr";
  $hash->{SetFn}     = 	"I2C_PCF8593_Set";
  $hash->{GetFn}     = 	"I2C_PCF8593_Get";
  $hash->{I2CRecFn}  = 	"I2C_PCF8593_I2CRec";
  $hash->{AttrList}  = 	"IODev do_not_notify:1,0 ignore:1,0 showtime:1,0 ".
												"poll_interval ".
												"$readingFnAttributes";
}

sub I2C_PCF8593_Notify {
	my ($hash, $dev_hash) = @_;
	my $ownName = $hash->{NAME}; # own name / hash
	return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled
	my $devName = $dev_hash->{NAME}; # Device that created the events
	my $events = deviceEvents($dev_hash,1);
	my $def=$hash->{DEF};
	$def="" if (!defined $def); 
	if ($devName eq "global" and grep(m/^INITIALIZED|REREADCFG$/, @{$events})) {
		#GetDevices is triggering the autocreate calls, but this is not yet working (autocreate not ready?) so delay this by 10 seconds
		I2C_PCF8593_Init($hash,$def);
	} elsif ($devName eq "global" and grep(/^(DELETEATTR|ATTR).$ownName.poll_interval/, @{$events})) {
		#Restart timer with new pollingInterval
		I2C_PCF8593_Init($hash,$def);
	}
}


################################### 
sub I2C_PCF8593_Set($@) {					#
	my ($hash, @a) = @_;
	my $name =$a[0];
	my $cmd = $a[1];
	my $val = $a[2];	

	if (!defined $hash->{IODev}) {
		readingsSingleUpdate($hash, 'state', 'No IODev defined',0);
		return "$name: no IO device defined";
	}
	return if !$cmd;
 
	if ($cmd eq "update") {
		#Make sure there is no reading cycle running and re-start polling (which starts with an inital read)
		RemoveInternalTimer($hash) if ( defined (AttrVal($hash->{NAME}, "poll_interval", undef)) ); 
		Log3 $hash->{NAME}, 4, $hash->{NAME}." => Update";
		I2C_PCF8593_Execute($hash);
		return undef;
	} elsif ($cmd eq "clear") {
		I2C_PCF8593_SetCounter($hash,0);
	} elsif ($cmd eq "counter" && defined $val) {
		I2C_PCF8593_SetCounter($hash,$val);
	} else {
		my $list = "counter:textField clear:noArg update:noArg";
		return "Unknown argument $a[1], choose one of " . $list if defined $list;
		return "Unknown argument $a[1]";
	}
  	return undef;
}
sub I2C_PCF8593_SetCounter($$) {
	my ($hash, $val) = @_;
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	my $val1=$val & 0xff;
	my $val2=($val >> 8) & 0xff;
	my $val3=($val >> 16) & 0xff;
	my %sendpackage = ( i2caddress => $hash->{I2C_Address}, direction => "i2cbytewrite", reg=> 1, nbyte => 3, data => "$val1 $val2 $val3");
	Log3 $hash->{NAME}, 4, $hash->{NAME}." => $pname CLEAR adr:".$hash->{I2C_Address};
	CallFn($pname, "I2CWrtFn", $phash, \%sendpackage);
	readingsSingleUpdate($hash, "counter", $val,1);
}

################################### 
sub I2C_PCF8593_Get($@) {
	#Nothing to be done here, let all updates run asychroniously with timers
	return undef;
}

sub I2C_PCF8593_Execute($@) {
	my ($hash) = @_;
	my $nexttimer=AttrVal($hash->{NAME}, 'poll_interval', 60);
	Log3 $hash->{NAME}, 4, $hash->{NAME}." => Execute";
	I2C_PCF8593_InitConfig($hash);
	I2C_PCF8593_ReadData($hash);
	RemoveInternalTimer($hash);
	#Initalize next Timer for Reading Results in 8ms (time required for conversion to be ready)
	InternalTimer(gettimeofday()+$nexttimer, \&I2C_PCF8593_Execute, $hash,0) unless $nexttimer<=0;
	return undef;
}

sub I2C_PCF8593_InitConfig(@) {
	my ($hash) = @_;
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};

	my $config = $I2C_PCF8593_Config{'Control'}{FUNCTION_MODE_EVCOUNT};
	my %sendpackage = ( i2caddress => $hash->{I2C_Address}, direction => "i2cbytewrite", reg=> 0, nbyte => 1, data => $config);
	Log3 $hash->{NAME}, 4, $hash->{NAME}." => $pname CONFIG adr:".$hash->{I2C_Address}." Data:$config";
	CallFn($pname, "I2CWrtFn", $phash, \%sendpackage);
	%sendpackage = ( i2caddress => $hash->{I2C_Address}, direction => "i2cbytewrite", reg=> 8, nbyte => 1, data => 1);
	Log3 $hash->{NAME}, 4, $hash->{NAME}." => $pname CONFIG adr:".$hash->{I2C_Address}." Data:1";
	CallFn($pname, "I2CWrtFn", $phash, \%sendpackage);
}

sub I2C_PCF8593_ReadData(@) {
	my ($hash) = @_;
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	#Gain needs to be passed through for calculation
	my %sendpackage = ( i2caddress => $hash->{I2C_Address}, direction => "i2cbyteread", reg=> 1, nbyte => 3);
	Log3 $hash->{NAME}, 5, $hash->{NAME}." => $pname READ adr:".$hash->{I2C_Address};
	CallFn($pname, "I2CWrtFn", $phash, \%sendpackage);
}

################################### 
sub I2C_PCF8593_Attr(@) {					#
 my ($command, $name, $attr, $val) = @_;
 my $hash = $defs{$name};
 my $msg = undef;
  if ($command && $command eq "set" && $attr && $attr eq "IODev") {
		if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $val)) {
			main::AssignIoPort($hash,$val);
			my @def = split (' ',$hash->{DEF});
			I2C_PCF8593_Init($hash,\@def) if (defined ($hash->{IODev}));
		}
	}
  if ($attr eq 'poll_interval') {
    if ( defined($val) ) {
      if ( looks_like_number($val) && $val >= 0) {
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday()+1, 'I2C_PCF8593_Execute', $hash, 0) if $val>0;
      } else {
        $msg = "$hash->{NAME}: Wrong poll intervall defined. poll_interval must be a number >= 0";
      }    
    } else {
      RemoveInternalTimer($hash);
    }
  } 
  return $msg;	
}
################################### 
sub I2C_PCF8593_Define($$) {			#
 my ($hash, $def) = @_;
 readingsSingleUpdate($hash, 'state', 'Defined',0);

	$hash->{NOTIFYDEV} = "global";
		if ($init_done) {
			Log3 $hash->{NAME}, 2, "Define init_done: $def";
			$def =~ s/^\S+\s*\S+\s*//; #Remove devicename and type
			my $ret=I2C_PCF8593_Init($hash,$def);
			return $ret if $ret;
	}
  return undef;
}
################################### 
sub I2C_PCF8593_Init($$) {				#
	my ( $hash, $args ) = @_;
	my @a = split("[ \t]+", $args);
	my $name = $hash->{NAME};
	if (defined $args && int(@a) != 1)	{
		return "Define: Wrong syntax. Usage:\n" .
		       "define <name> I2C_PCF8593 <i2caddress>";
	}
	if (defined (my $address = shift @a)) {
		$hash->{I2C_Address} = $address =~ /^0.*$/ ? oct($address) : $address; 
	} else {
		readingsSingleUpdate($hash, 'state', 'Invalid I2C Adress',0);
 		return "$name: I2C Address not valid";
	}
  	AssignIoPort($hash, "RPII2C");
	readingsSingleUpdate($hash, 'state', 'Initialized',0);
	I2C_PCF8593_Set($hash, $name, "setfromreading");
	RemoveInternalTimer($hash);
	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 60);
	InternalTimer(gettimeofday() + $pollInterval, 'I2C_PCF8593_Execute', $hash, 0) if ($pollInterval > 0);
	return;
}

################################### 
sub I2C_PCF8593_Undef($$) {				#
	my ($hash, $name) = @_;
	RemoveInternalTimer($hash); 
	return undef;
}

################################### 
sub I2C_PCF8593_I2CRec($@) {				# ueber CallFn vom physical aufgerufen
	my ($hash, $clientmsg) = @_;
	my $name = $hash->{NAME};
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	my $clientHash = $defs{$name};
	my $msg = "";
	while ( my ( $k, $v ) = each %$clientmsg ) { 	#erzeugen von Internals fuer alle Keys in $clientmsg die mit dem physical Namen beginnen
		$hash->{$k} = $v if $k =~ /^$pname/ ;
		$msg = $msg . " $k=$v";
	} 
	Log3 $hash,5 , "$name: I2C reply:$msg";
	my $sval;	
	if ($clientmsg->{direction} && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok") {
		readingsBeginUpdate($hash);
		if ($clientmsg->{direction} eq "i2cbyteread" && defined($clientmsg->{received})) {
			my ($byte1,$byte2, $byte3) = split(/ /, $clientmsg->{received});
			my $value= $byte3<<16|$byte2<<8|$byte1;
			my $prevval=ReadingsVal($name,"counter",0);
			my $delta=0;
			if ($prevval>$value) {
				$delta=0xffffff-$prevval+$value;
			} else {
				$delta=$value-$prevval;
			}
			readingsBulkUpdate($hash, "delta", $delta);
			readingsBulkUpdate($hash, "counter", $value);
		}
    	readingsEndUpdate($hash, 1);
	}
}

1;

#Todo Write update documentation

=pod
=item device
=item summary reads/resets the counter of a I2C connected PCF8593 counter
=item summary_DE liest/resetted den Zähler eines mit I2C angeschlossenen PCF8593 Zählers
=begin html

<a name="I2C_PCF8593"></a>
<h3>I2C_PCF8593</h3>
(en | <a href="commandref_DE.html#I2C_PCF8593">de</a>)
<ul>
	<a name="I2C_PCF8593"></a>
		Provides an interface to an PCF8593 counter via I2C.<br>
		The I2C messages are send through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br><br>
		<b>Limitations:</b><br>
		The PCF8593 chip is mainly designed as a timer/calendar and alarm chip. Since these functions are not really meaningful when running FHEM, the module focusses on the built-in event counter.<br>
		<br>
		<br><b>Circuit:</b><br>
		The chip needs to be wired like this (for Raspberry):<br>
		Pin 5 (SDA) to SDA-Port<br>
		Pin 6 (SCL) to SCL-Port<br>
		Pin 8 (VDD) to 3.3V<br>
		Pin 4 (VSS) to GND<br>
		Pin 3 (RESET) to 3.3V (potentially with a Pullup resistor, so it can still be connected to GND for I2C reset)<br>
		Pin 1 (OSCI) to the signal source<br>
		<br>
		<br><b>Attribute <a href="#IODev">IODev</a> must be set. This is typically the name of a defined <a href="#RPII2C">RPII2C</a> device.</b><br>
		If there is a valid RPII2C device defined it gets picked automatically.<br>
	<a name="I2C_PCF8593-define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_PCF8593 &lt;I2C Address&gt;</code><br>
		where <code>&lt;I2C Address&gt;</code> is the chip adress as e.g. displayed by i2cdetect (which displays hex-values, so use e.g. 0x51)<br>
		<br>
	</ul>

	<a name="I2C_PCF8593-set"></a>
	<b>Set</b>
	<ul>
		<li><b>set update</b><br>
		<a name="I2C_PCF8593-set-update"></a>
		Trigger an instant reading and resets the timer to the current polling_interval<br>
		<li><b>set clear</b><br>
		<a name="I2C_PCF8593-set-clear"></a>
		Reset the counter to zero<br>
		<li><b>set counter &lt;value&gt</b><br>
		<a name="I2C_PCF8593-set-counter"></a>
		Set the counter to a specific value<br>
		<br>
		"clear" and "counter" do not trigger a new delta calculation.
		<br>
		</li>
	</ul>

	<a name="I2C_PCF8593-attr"></a>
	<b>Attributes</b>
	<ul>
		<li><b>poll_interval</b><br>
			<a name="I2C_PCF8593-attr-poll_interval"></a>
			Set the polling interval in seconds to query a new reading from enabled channels<br>
			By setting this number to 0, the device can be set to manual mode (new readings only by "set update").<br>
			<b>Default:</b> 60, valid values: decimal number<br>
		</li>
		<br>
		<br><br>
	</ul>	
	<br>
	<a name="I2C_PCF8593-readings"></a>
	<b>Readings</b>
	The readings are update for every polling interval - even if nothing changed. It is recommended to set event-on-change-reading to avoid unnecessary events unless they are needed.<br>
	<ul>
		<li><b>counter</b><br>
		Last queried counter value<br>
		<li><b>delta</b><br>
		Delta between last query and current value (0 if not changed since last polling)<br>
		If there is an overflow of the counter at 0xffffff (16.777.216), this value will still be correct<br>
	</ul>	
	<br>
	<br>
</ul>

=end html

=cut
