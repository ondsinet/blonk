#!/bin/sh
#
# For the CHIP Computer AXP09 Power mangement IC
#
# Original:
# Jeff Brown http://photonicsguy.ca/projects/chip
# https://github.com/Photonicsguy/CHIP
# Version 1.0 (April 5th, 2016)
#
#
# Improved (?):
# https://github.com/ondsinet/chip/tree/master/Programs/blonk
#  


BATTERY_VALUE=		#%
BATTERY_STATE=		#connected/CHARGING/DISCHARGING/charged
BATTERY_VOLT=		
BATTERY_CURR=

POWER_SOURCE=

USB_VOLT=
USB_CURR=

CHG_VOLT=
CHG_CURR=

TEMPERATURE_VALUE=

UPTIME_VALUE=

RESET_PRESSED=
RESET_GPIO_PRESSED=

BLINK_GPIO_STATE=0

BLINK_FREQUENCY=1			# Period of the blinking in second
SENSOR_FREQUENCY=5
FREQ_DIV=2

REPORT_TXT=


read_config(){

	RESET_ENABLED=
	RESET_GPIO=
	RESET_GPIO_VALUE=0

	BATTERY_SHUT_VALUE=
	BATTERY_WARN_VALUE=
	BATTERY_WARN_GPIO=
	BATTERY_WARN_GPIO_VALUE=0

	TEMPERATURE_SHUT_VALUE=
	TEMPERATURE_WARN_VALUE=
	TEMPERATURE_WARN_GPIO=
	TEMPERATURE_WARN_GPIO_VALUE=0

	BLINK_ENABLED= 
	BLINK_GPIO=

	RESET_GPIO_SET=
	LINK_GPIO_SET=
	BATTERY_WARN_GPIO_SET=
	TEMPERATURE_WARN_GPIO_SET=

	if [ -f /home/ondsi/blonk.cfg ]; then :
		source /home/ondsi/blonk.cfg
	else :
		MON_RESET=1
		BLINK_STATUS=1
	fi
}





check_i2c_installed(){
	# Need to communicate with AXP209 via I2C commands
	if [ ! -x /usr/sbin/i2cget -o ! -x /usr/sbin/i2cset ]; then :
		blonk_error "need i2c-tools for MON_RESET" "Use: sudo apt-get install i2c-tools"
	fi
}

check_gpio_installed(){
	if [ ! -f /usr/local/bin/gpio.sh ]; then :
		blonk_error "need /usr/local/bin/gpio.sh for GPIO feature" "See https://github.com/fordsfords/gpio_sh/tree/gh-pages"
	fi
}

blonk_cleanup(){	#unexports used gpio
	# Only un-export ports that we actually exported.
	if [ -n "$RESET_GPIO" ]; then gpio_unexport $RESET_GPIO; fi
	if [ -n "$BLINK_GPIO" ]; then gpio_unexport $BLINK_GPIO; fi
	if [ -n "$BATTERY_WARN_GPIO" ]; then gpio_unexport $BATTERY_WARN_GPIO; fi
	if [ -n "$TEMPERATURE_WARN_GPIO" ]; then gpio_unexport $TEMPERATURE_WARN_GPIO; fi
}

blonk_stop(){
	blonk_cleanup
	echo "blonk: stopped"
	exit
}

blonk_error(){
	blonk_cleanup
	while [ -n "$1" ]; do :
		echo "blonk: $1"
		shift    # get next error string into $1
	done
exit 1
}

setup_gpio(){
	if [ -n "$RESET_GPIO" ]; then :
		gpio_export $RESET_GPIO; ST=$?
		if [ $ST -ne 0 ]; then :
			blonk_error "cannot export $RESET_GPIO for monitoring"
		fi
		gpio_direction $RESET_GPIO in
	fi
	
	if [ -n "$BLINK_GPIO" ]; then :
		gpio_export $BLINK_GPIO; ST=$?
		if [ $ST -ne 0 ]; then :
			blonk_error "cannot export $BLINK_GPIO for blinking (in use?)"
		fi
		gpio_direction $BLINK_GPIO out

		GPIO_LED=1
		gpio_output $BLINK_GPIO 0
	fi
	
	if [ -n "$BATTERY_WARN_GPIO" ]; then :
		gpio_export $BATTERY_WARN_GPIO; ST=$?
		if [ $ST -ne 0 ]; then :
			blonk_error "cannot export $BATTERY_WARN_GPIO for blinking (in use?)"
		fi
		gpio_direction $BATTERY_WARN_GPIO out

		gpio_output $BATTERY_WARN_GPIO 0
	fi
	
	if [ -n "$TEMPERATURE_WARN_GPIO" ]; then :
		gpio_export $TEMPERATURE_WARN_GPIO; ST=$?
		if [ $ST -ne 0 ]; then :
			blonk_error "cannot export $TEMPERATURE_WARN_GPIO for blinking (in use?)"
		fi
		gpio_direction $TEMPERATURE_WARN_GPIO out

		gpio_output $TEMPERATURE_WARN_GPIO 0
	fi
}


read_AXP(){		#reads values from the power ic
	# Enable ADC registers
	i2cset -y -f 0 0x34 0x82 0xff

##	REGISTER 00	##
	REG=$(i2cget -y -f 0 0x34 0x00)
	STATUS_VCHG=$(($(($REG&0x80))/128))
	STATUS_VCHG_AVAIL=$(($(($REG&0x40))/64))
	STATUS_VUSB=$(($(($REG&0x20))/32))
	STATUS_VUSB_AVAIL=$(($(($REG&0x10))/16))
	#STATUS_VHOLD=$(($(($REG&0x08))/8))
	STATUS_BAT_DIR=$(($(($REG&0x04))/4))
	#ACVB_SHORT=$(($(($REG&0x02))/2))
	#STATUS_BOOT=$(($REG&0x01))

	##POWER_SOURCE= $((STATUS_VCHG_AVAIL+STATUS_VUSB_AVAIL))
	POWER_SOURCE=0
	[ $STATUS_VCHG_AVAIL == 1 ] || [ $STATUS_VUSB == 1 ] && POWER_SOURCE=1


##	REGISTER 01	##
	REG=$(i2cget -y -f 0 0x34 0x01)
	#STATUS_OVRTEMP=$(($(($REG&0x80))/128))
	STATUS_CHARGING=$(($(($REG&0x40))/64))
	STATUS_BATCON=$(($(($REG&0x20))/32))
	#STATUS_=$(($(($REG&0x10))/16))
	#STATUS_ACT=$(($(($REG&0x08))/8))
	#STATUS_CUREXPEC=$(($(($REG&0x04))/4))
	#STATUS_=$(($(($REG&0x02))/2))
	#STATUS_=$(($REG&0x01))

	#if [ $STATUS_OVRTEMP == 1 ]; then
	#	echo "Over Temperature"
	#fi

	#if [ $STATUS_CHARGING == 1 ]; then
	#	echo "Battery charging"
	#fi
	#echo "Battery connected: $STATUS_BATCON"


	if [ $STATUS_VCHG==1 ]; then
		# VCHG voltage
		REG=`i2cget -y -f 0 0x34 0x56 w|awk '{print "0x"substr($0,5,2)substr($0,4,1)}'`
		REG=`printf "%d" "$REG"`
		CHG_VOLT=`echo "$REG*0.0017"|bc`
	# VCHG Current
		REG=`i2cget -y -f 0 0x34 0x58 w|awk '{print "0x"substr($0,5,2)substr($0,4,1)}'`
		REG=`printf "%d" "$REG"`
		CHG_CURR=`echo "$REG*0.375"|bc`
	else
		CHG_VOLT='-'
		CHG_CURR='-'
	fi

	if [ $STATUS_VUSB==1 ]; then
		# VUSB voltage
		REG=`i2cget -y -f 0 0x34 0x5A w|awk '{print "0x"substr($0,5,2)substr($0,4,1)}'`
		REG=`printf "%d" "$REG"`
		USB_VOLT=`echo "$REG*0.0017"|bc`

		# VUSB Current
		REG=`i2cget -y -f 0 0x34 0x5C w|awk '{print "0x"substr($0,5,2)substr($0,4,1)}'`
		REG=`printf "%d" "$REG"`
		USB_CURR=`echo "$REG*0.375"|bc`
	else
		USB_VOLT='-'
		USB_CURR='-'
	fi

	BATTERY_STATE=


	if [ $STATUS_BATCON == 1 ]; then
		# Battery Voltage
		REG=`i2cget -y -f 0 0x34 0x78 w|awk '{print "0x"substr($0,5,2)substr($0,4,1)}'`
		REG=`printf "%d" "$REG"`
		BATTERY_VOLT=`echo "$REG*0.0011"|bc`

		if [ $STATUS_BAT_DIR == 1 ] || [ $POWER_SOURCE == 1 ]; then
			# Battery Charging Current
			REG=`i2cget -y -f 0 0x34 0x7A w|awk '{print "0x"substr($0,5,2)substr($0,4,1)}'`
			REG_C=`printf "%d" "$REG"`
			BATTERY_CURR=`echo "scale=2;$REG_C*0.5"|bc`
			BATTERY_STATE="Charging"
		else
			# Battery Discharge Current
			REG=`i2cget -y -f 0 0x34 0x7C w|awk '{print "0x"substr($0,5,2)substr($0,4,1)}'`
			REG_D=`printf "%d" "$REG"`
			BATTERY_CURR=`echo "scale=2;$REG_D*0.5"|bc`
			BATTERY_STATE="Discharging"
		fi
		# Battery %
		REG=`i2cget -y -f 0 0x34 0xB9`
		BATTERY_VALUE=`printf "%d" "$REG"`
	else
		BATTERY_VOLT='-'
		BATTERY_CURR='-'
		BATT_PERCENT='-'
		BATTERY_STATE="NO "
	fi

	# System (IPSOUT) Voltage (IPS is Intelligent Power Select)
	#REG=`i2cget -y -f 0 0x34 0x7E w|awk '{print "0x"substr($0,5,2)substr($0,4,1)}'`
	#REG=`printf "%d" "$REG"`
	#IPSOUT=`echo "$REG*0.0014"|bc`

	# Temperature
	REG=`i2cget -y -f 0 0x34 0x5E w|awk '{print "0x"substr($0,5,2)substr($0,4,1)}'`
	REG=`printf "%d" "$REG"`
	TEMPERATURE_VALUE=`echo "($REG*0.1)-144.7"|bc`
	#echo "Temperature:	"$THERM"°C (I've seen as high as 65°C)"
		
}

read_reset(){		#reads the reset button
if [ -n "$RESET_ENABLED" ]; then :
    REG=$(i2cget -y -f 0 0x34 0x4a)  # Read AXP209 register 4AH
    BUTTON=$(( $REG & 0x02 ))        # mask off the short press bit
    if [ $BUTTON -eq 0 ]; then :
      RESET_PRESSED=0
    else :
      RESET_PRESSED=1
    fi
  fi
}

read_stats(){		#reads cpu stats
	CPU='-'
	UPTIME_VALUE=$(uptime -p |sed 's/\<up\>/&time:/')

	#CPU=$(cat <(grep 'cpu ' /proc/stat) <(sleep 1 && grep 'cpu ' /proc/stat) | awk -v RS="" '{print ($13-$2+$15-$4)*100/($13-$2+$15-$4+$16-$5)}')

	#CPU= `cat <(grep 'cpu ' /proc/stat) <(sleep 1 && grep 'cpu ' /proc/stat) | awk -v RS="" '{print ($13-$2+$15-$4)*100/($13-$2+$15-$4+$16-$5)}'`
	#echo "${CPU}"
}

read_gpio(){
	echo
}


compile_report(){
	txt_PWR="Not Connected"
	if [ $POWER_SOURCE != 0 ];then 
		txt_PWR="Connected"
	fi
	txt_VCHG="VCHG:	$CHG_VOLT""V"
	if [ $CHG_CURR != 0 ];then 
		txt_VCHG+=" 	  "$CHG_CURR"mA"
	fi
	txt_VUSB="VUSB:	$USB_VOLT""V"
	if [ $USB_CURR != 0 ];then
		txt_VUSB+="		"$USB_CURR"mA"
	fi
	txt_VBAT="VBAT:	$BATTERY_VOLT""V"
	if [ $STATUS_BAT_DIR == 1 ]; then
		txt_VBAT+="		+"$BATTERY_CURR"mA"
	else
		txt_VBAT+="		-"$BATTERY_CURR"mA" 
	fi


read -r -d '' REPORT_TXT << EOM
$UPTIME_VALUE
Temp:	$TEMPERATURE_VALUE°C
Batt:	$BATTERY_VALUE%	$BATTERY_STATE
Power Supply: $txt_PWR

$txt_VCHG
$txt_VUSB
$txt_VBAT
EOM

}


compile_warnings(){
echo 
}
handle_warnings(){
echo 
}

blink(){
gpio_output $BLINK_GPIO $BLINK_GPIO_STATE
BLINK_GPIO_STATE=$((1-BLINK_GPIO_STATE)) 
}


##############--------------------------------------------------------------------------------##############
echo "blonk: starting"
echo	

if [ "$1" == "" ]; then
	SERVICE=true
elif [ "$1" == "-tg" ]; then
	TELEGRAM=true
elif [ "$1" == "-tgW" ]; then
	#TELEGRAM=true
	WARNINGS=true
elif [ "$1" == "-p" ]; then
	PRINT=true
elif [ "$1" == "-r" ]; then
	REBOOT=true
elif [ "$1" == "-h" ]; then
	cat << EOF
Usage: blonk.sh runs as service or [OPTION] 
	-p	Prints information once
	-b	Show only battery percentage
	-v	Version
	-h	Help (This help)
EOF
elif [ "$1" == "-v" ]; then
	echo "Version 1.2 (Feb 28th, 2020)"
	exit 0
fi

	check_i2c_installed
#########################################

	read_config
	read_AXP
	read_stats
	read_gpio

	compile_report
	compile_warnings 

#########################################

	if [ $PRINT ]; then
		echo "$REPORT_TXT"
		exit 0
	fi
	
#########################################
	check_gpio_installed
	
	if [ -f /usr/local/bin/gpio.sh ]; then :
		source /usr/local/bin/gpio.sh
	fi
	
	setup_gpio

	trap "blonk_stop" 1 2 3 15	
#########################################



	if [ $SERVICE ]; then
		while true; do :
			read_AXP
			read_stats
			#read_gpio			
			#compile_warnings
			#handle_warnings
			
			
			for (( c=0; c<=$SENSOR_FREQUENCY; c+=$BLINK_FREQUENCY )); do :
			#for i in {0..$BLINK_FREQUENCY..$SENSOR_FREQUENCY}; do :
				blink
				RESULT=$((${BLINK_FREQUENCY}00/$FREQ_DIV))
				RESULT=$(echo "${RESULT:0:-2}.${RESULT: -2}")
				sleep $RESULT
			done
		done
	fi