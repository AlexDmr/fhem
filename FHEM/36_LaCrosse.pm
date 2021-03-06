
# $Id: 36_LaCrosse.pm 5046 2014-02-25 16:21:16Z justme1968 $
#
# TODO:

package main;

use strict;
use warnings;
use SetExtensions;

sub LaCrosse_Parse($$);

sub
LaCrosse_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^\\S+\\s+9 ";
  $hash->{SetFn}     = "LaCrosse_Set";
  #$hash->{GetFn}     = "LaCrosse_Get";
  $hash->{DefFn}     = "LaCrosse_Define";
  $hash->{UndefFn}   = "LaCrosse_Undef";
  $hash->{FingerprintFn}   = "LaCrosse_Fingerprint";
  $hash->{ParseFn}   = "LaCrosse_Parse";
  #$hash->{AttrFn}    = "LaCrosse_Attr";
  $hash->{AttrList}  = "IODev"
                       ." ignore:1"
                       ." doAverage:1"
                       ." doDewpoint:1"
                       ." filterThreshold"
                       ." resolution"
                       ." $readingFnAttributes";
}

sub
LaCrosse_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3 ) {
    my $msg = "wrong syntax: define <name> LaCrosse <addr>";
    Log3 undef, 2, $msg;
    return $msg;
  }

  $a[2] =~ m/^([\da-f]{2})$/i;
  return "$a[2] is not a valid LaCrosse address" if( !defined($1) );

  my $name = $a[0];
  my $addr = $a[2];

  #return "$addr is not a 1 byte hex value" if( $addr !~ /^[\da-f]{2}$/i );
  #return "$addr is not an allowed address" if( $addr eq "00" );

  return "LaCrosse device $addr already used for $modules{LaCrosse}{defptr}{$addr}->{NAME}." if( $modules{LaCrosse}{defptr}{$addr}
                                                                                             && $modules{LaCrosse}{defptr}{$addr}->{NAME} ne $name );

  $hash->{addr} = $addr;

  $modules{LaCrosse}{defptr}{$addr} = $hash;

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  return undef;
}

#####################################
sub
LaCrosse_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  my $addr = $hash->{addr};

  delete( $modules{LaCrosse}{defptr}{$addr} );

  return undef;
}


#####################################
sub
LaCrosse_Get($@)
{
  my ($hash, $name, $cmd, @args) = @_;

  return "\"get $name\" needs at least one parameter" if(@_ < 3);

  my $list = "";

  return "Unknown argument $cmd, choose one of $list";
}

sub
LaCrosse_Fingerprint($$)
{
  my ($name, $msg) = @_;

  return ( "", $msg );
}

sub
LaCrosse_CalcDewpoint (@) {
  my ($temp,$hum) = @_;

  my($SDD, $DD, $a, $b, $v, $DP);

  if($temp>=0) {
    $a = 7.5;
    $b = 237.3;
  } else {
    $a = 7.6;
    $b = 240.7;
  }

  $SDD = 6.1078*10**(($a*$temp)/($b+$temp));
  $DD = $hum/100 * $SDD;
  $v = log($DD/6.1078)/log(10);

  $DP = ($b*$v)/($a-$v);

  return $DP;
}

sub
LaCrosse_RemoveReplaceBattery($)
{
  my $hash = shift;
  delete($hash->{replaceBattery});
}

sub
LaCrosse_Set($@)
{
  my ($hash, $name, $cmd, $arg, $arg2) = @_;

  my $list = "replaceBatteryForSec";

  if( $cmd eq "replaceBatteryForSec" ) {
    foreach my $d (sort keys %defs) {
      next if (!defined($defs{$d}) );
      next if ($defs{$d}->{TYPE} ne "LaCrosse" );
      LaCrosse_RemoveReplaceBattery{$defs{$d}};
    }
    return "Usage: set $name replaceBatteryForSec <seconds_active> [ignore_battery]" if(!$arg || $arg !~ m/^\d+$/ || ($arg2 && $arg2 ne "ignore_battery"));
    $hash->{replaceBattery} = $arg2?2:1;
    InternalTimer(gettimeofday()+$arg, "LaCrosse_RemoveReplaceBattery", $hash, 0);

  } else {
    return "Unknown argument $cmd, choose one of ".$list;
  }

  return undef;
}

sub
LaCrosse_Parse($$)
{
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};

  my( @bytes, $addr, $battery_new, $type, $channel, $temperature, $battery_low, $humidity );
  if( $msg =~ m/^OK/ ) {
    @bytes = split( ' ', substr($msg, 5) );

    $addr = sprintf( "%02X", $bytes[0] );
    $battery_new = ($bytes[1] & 0x80) >> 7;
    $type = ($bytes[1] & 0x70) >> 4;
    $channel = $bytes[1] & 0x0F;
    $temperature = ($bytes[2]*256 + $bytes[3] - 1000)/10;
    $battery_low = ($bytes[4] & 0x80) >> 7;
    $humidity = $bytes[4] & 0x7f;
  } else {
    DoTrigger($name, "UNKNOWNCODE $msg");
    Log3 $name, 3, "$name: Unknown code $msg, help me!";
    return "";
  }

  my $raddr = $addr;
  my $rhash = $modules{LaCrosse}{defptr}{$raddr};
  my $rname = $rhash?$rhash->{NAME}:$raddr;

  if( !$modules{LaCrosse}{defptr}{$raddr} ) {
    foreach my $d (sort keys %defs) {
      next if( !defined($defs{$d}) );
      next if( !defined($defs{$d}->{TYPE}) );
      next if( $defs{$d}->{TYPE} ne "LaCrosse" );
      next if( !$defs{$d}->{replaceBattery} );
      if( $battery_new ||  $defs{$d}->{replaceBattery} == 2 ) {
        $rhash = $defs{$d};
        $raddr = $rhash->{addr};

        Log3 $name, 3, "LaCrosse Changing device $rname from $raddr to $addr";

        delete $modules{LaCrosse}{defptr}{$raddr};
        $rhash->{DEF} = $addr;
        $rhash->{addr} = $addr;
        $modules{LaCrosse}{defptr}{$addr} = $rhash;

        LaCrosse_RemoveReplaceBattery($rhash);

        CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );

        return "";
      }
    }
    Log3 $name, 3, "LaCrosse Unknown device $rname, please define it";

    return "" if( !$hash->{LaCrossePair} );

    return "UNDEFINED LaCrosse_$rname LaCrosse $raddr" if( $battery_new || $hash->{LaCrossePair} == 2 );
    return "";
  }

  $rhash->{battery_new} = $battery_new;

  my @list;
  push(@list, $rname);

  $rhash->{LaCrosse_lastRcv} = TimeNow();

  if( $type == 0x00 ) {
    $channel = "" if( $channel == 1 );

    if( my $resolution = AttrVal( $rname, "resolution", 0 ) ) {
      $temperature = int($temperature*10 / $resolution + 0.5) * $resolution / 10;
      $humidity = int($humidity / $resolution + 0.5) * $resolution;
    }

    if( AttrVal( $rname, "doAverage", 0 )
        && defined($rhash->{"previousT$channel"}) ) {
      $temperature = ($rhash->{"previousT$channel"}*3+$temperature)/4;
    }
    if( AttrVal( $rname, "doAverage", 0 )
        && defined($rhash->{"previousH$channel"}) ) {
      $humidity = ($rhash->{"previousH$channel"}*3+$humidity)/4;
    }

    if( defined($rhash->{"previousT$channel"})
        && abs($rhash->{"previousH$channel"} - $humidity) <= AttrVal( $rname, "filterThreshold", 10 )
        && abs($rhash->{"previousT$channel"} - $temperature) <= AttrVal( $rname, "filterThreshold", 10 ) ) {

      readingsBeginUpdate($rhash);

      my $dewpoint;
      if( AttrVal( $rname, "doDewpoint", 0 ) && $humidity && $humidity <= 99 ) {
        $dewpoint = LaCrosse_CalcDewpoint($temperature,$humidity);
        $dewpoint = int($dewpoint*10 + 0.5) / 10;
        readingsBulkUpdate($rhash, "dewpoint$channel", $dewpoint);
      }

      $temperature = int($temperature*10 + 0.5) / 10;
      $humidity = int($humidity*10 + 0.5) / 10;

      readingsBulkUpdate($rhash, "temperature$channel", $temperature);
      readingsBulkUpdate($rhash, "humidity$channel", $humidity) if( $humidity && $humidity <= 99 );

      if( !$channel ) {
        my $state = "T: $temperature";
        $state .= " H: $humidity" if( $humidity && $humidity <= 99 );
        $state .= " D: $dewpoint" if( $dewpoint );
        readingsBulkUpdate($rhash, "state", $state) if( Value($rname) ne $state );
      }

      readingsBulkUpdate($rhash, "battery$channel", $battery_low?"low":"ok");

      readingsEndUpdate($rhash,1);
    } else {
      readingsSingleUpdate($rhash, "battery$channel", $battery_low?"low":"ok" , 1);
    }

    $rhash->{"previousH$channel"} = $humidity;
    $rhash->{"previousT$channel"} = $temperature;
  }

  return @list;
}

sub
LaCrosse_Attr(@)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  return undef;
}

1;

=pod
=begin html

<a name="LaCrosse"></a>
<h3>LaCrosse</h3>
<ul>

  <tr><td>
  FHEM module for LaCrosse Temperature and Humidity sensors.<br><br>

  It can be integrated in to FHEM via a <a href="#JeeLink">JeeLink</a> as the IODevice.<br><br>

  The JeeNode sketch required for this module can be found in .../contrib/36_LaCrosse-pcaSerial.zip.<br><br>

  <a name="LaCrosseDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; LaCrosse &lt;addr&gt;</code> <br>
    <br>
    addr is a 2 digit hex number to identify the LaCrosse device.<br><br>
    Note: devices are autocreated only if LaCrossePairForSec is active for the <a href="#JeeLink">JeeLink</a> IODevice device.<br>
  </ul>
  <br>

  <a name="LaCrosse_Set"></a>
  <b>Set</b>
  <ul>
    <li>replaceBatteryForSec &lt;sec&gt; [ignore_battery]<br>
    sets the device for &lt;sec&gt; seconds into replace battery mode. the first unknown address that is
    received will replace the current device address. this can be partly automated with a readings group configured
    to show the battery state of all LaCrosse devices and a link/command to set replaceBatteryForSec on klick.
    </li>
  </ul><br>

  <a name="LaCrosse_Get"></a>
  <b>Get</b>
  <ul>
  </ul><br>

  <a name="LaCrosse_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>battery[]<br>
      ok or low</li>
    <li>temperature[]<br>
      Notice: see the filterThreshold attribute.</li>
    <li>humidity</li>
  </ul><br>

  <a name="LaCrosse_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>doAverage<br>
      use an average of the last 4 values for temperature and humidity readings</li>
    <li>doDewpoint<br>
      calculate dewpoint</li>
    <li>filterThreshold<br>
      if the difference between the current and previous temperature is greater than filterThreshold degrees
      the readings for this channel are not updated. the default is 10.</li>
    <li>resolution<br>
      the resolution in 1/10 degree for the temperature reading</li>
    <li>ignore<br>
    1 -> ignore this device.</li>
  </ul><br>
</ul>

=end html
=cut
