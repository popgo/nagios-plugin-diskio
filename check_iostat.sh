#!/bin/sh
###############################################
#
# Nagios script to check I/O statistics
#
# NOTE: Requires kernel 2.4 or higher 
# 
# See usage for command line switches
# 
# Created: 2007-06-27 (i.yates@uea.ac.uk)
# Updated: 2007-07-27 (i.yates@uea.ac.uk)
# Updated: 2007-10-29 (i.yates@uea.ac.uk) - Fixed typos in usage!
# Updated: 2008-03-26 (i.yates@uea.ac.uk) - Fixed bug in critical/warning level checking which could result in erroneous results.  Thanks to Drew Sudell for pointing this out!
# Updated: 2008-11-27 (i.yates@uea.ac.uk) - Added GPLv3 licence
# Updated: 2009-02-15 (ak@agnitas.de) - Write IO Stats with PNP Graf. and Read / Write output
# Updated: 2009-02-16 (ak@agnitas.de) - Delete "test" and make [
# Updated: 2009-02-17 (ak@agnitas.de) - Make Average from Count 
# Updated: 2008-11-27 (i.yates@uea.ac.uk) - 1.4.3 - Minor bugfix in "-a" check logic
# Updated: 2008-11-27 (i.yates@uea.ac.uk) - 1.4.4 - Usage refinements
# Updated: 2008-11-27 (i.yates@uea.ac.uk) - Release 1.4.5 - Thanks to Alexander Kaufmann for updates!
# Updated: 2010-11-04 (os@ciphron.de) - 1.4.6 - Fixed little bug (CAT <-> cat), added check if device exist (return: UNKNOWN)
# Updated: 2010-11-12 (os@ciphron.de) - 1.4.7 - Added check if iostat is installed, added sudo for iostat
# Updated: 2013-01-28 (unidba@gmail.com) - 1.4.8 - Added I/O util% feature by iostat -x
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
# 
###############################################

#. ./utils.sh

VERSION="1.4.8"

IOSTAT=`which iostat 2>/dev/null`
GREP=`which grep 2>/dev/null`
AWK=`which awk 2>/dev/null`
TAIL=`which tail 2>/dev/null`

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATE_DEPENDENT=4

FLAG_VERBOSE=FALSE
FLAG_UTIL=FALSE
FLAG_TPS=FALSE
FLAG_READS=FALSE
FLAG_WRITES=FALSE
FLAG_READWRITES=FALSE
TMP="/tmp/iostat.`date +'%s'`"
COUNT=2
LEVEL_WARN=""
LEVEL_CRIT=""
RESULT=""
EXIT_STATUS=$STATE_OK

###############################################
#
## FUNCTIONS 
#

## Print usage
usage() {
	echo " check_iostat $VERSION - Nagios I/O statistics check script"
	echo ""
	echo " Usage: check_iostat -w <warning value> -c <critical value> -l <Number of samples> -u|t|i|o|a <device> [ -v ] [ -h ]"
	echo ""
	echo " NOTE: When specifying device, /dev/ is assumed, e.g. for /dev/sda you should just enter sda for the device"
	echo ""
	echo "		-w  Warning trigger level"
	echo "		-c  Critical trigger level"
	echo "		-u  I/O util% on <device>"
	echo "		-t  I/O transactions per second (TPS/IOPS) on <device>"
	echo "		-i  Kilobytes read IN per second on <device>"
	echo "		-o  Kilobytes written OUT per second on <device>"
	echo "		-a  Kilobytes written OUT and read IN per Second on <device>"
	echo " 		-l  Number of samples to take (must be greater than 1)"
	echo "		-v  Verbose output (ignored for now)"
	echo "		-h  Show this page"
	echo ""
}
 
## Process command line options
doopts() {
	if ( `test 0 -lt $#` )
	then
		while getopts w:c:l:u:t:i:o:a:vh myarg "$@"
		do
			case $myarg in
				h|\?)
					usage
					exit;;
				w)
					LEVEL_WARN=$OPTARG;;
				c)
					LEVEL_CRIT=$OPTARG;;
                                u)
                                        FLAG_UTIL=TRUE
                                        DEVICE=$OPTARG;;
				t)
					FLAG_TPS=TRUE
					DEVICE=$OPTARG;;
				i)
					FLAG_READS=TRUE
					DEVICE=$OPTARG;;
				o)
					FLAG_WRITES=TRUE
					DEVICE=$OPTARG;;
				a)	
					FLAG_READWRITES=TRUE
					DEVICE=$OPTARG;;
				l)
					COUNT=$OPTARG;;
				v)
					FLAG_VERBOSE=TRUE;;
				*)	# Default
					usage
					exit;;
			esac
		done
	else
		usage
		exit
	fi
}

# Write output and return result
theend() {
	rm -f $TMP
	echo $RESULT
	exit $EXIT_STATUS
}


#
## END FUNCTIONS 
#

#############################################
#
## MAIN 
#


# Handle command line options
doopts $@

# OS at ciphron.de: 2010-11-04
# - Added check if device exists
if [ ! -b /dev/$DEVICE ] ; then
        RESULT="ERROR Device does not exist!"
        EXIT_STATUS=$STATE_UNKNOWN
        theend
fi 

# OS at ciphron.de: 2010-11-12
# - Added check if iostat exists
if [ ! -f $iostat ] ; then
	RESULT="ERROR: You must have iostat installed in order to run this plugin!"
	EXIT_STATUS=$STATE_UNKNOWN
	theend
fi


# Do the do
# OS at ciphron.de: 2010-11-04 
# - Added sudo
if [ $COUNT -ge 2 ] ; then
	if [ $FLAG_UTIL = "TRUE" ] ; then
		$IOSTAT -x -d $DEVICE 1 $COUNT | $GREP $DEVICE| $TAIL -`expr $COUNT - 1` > $TMP
	else
		#sudo $IOSTAT -k -d $DEVICE 1 $COUNT | $GREP $DEVICE| $TAIL -`expr $COUNT - 1` > $TMP
		$IOSTAT -k -d $DEVICE 1 $COUNT | $GREP $DEVICE| $TAIL -`expr $COUNT - 1` > $TMP
	fi
else
	RESULT="ERROR Count must be > 1!"
	EXIT_STATUS=$STATE_UNKNOWN
	theend
fi

## General sanity check
if [ -n "$LEVEL_WARN" -a -n "$LEVEL_CRIT" -a "$LEVEL_WARN" -lt "$LEVEL_CRIT" ]; then
	## I/O Util% per second
	if [ $FLAG_UTIL = "TRUE" ] ; then
		UTIL=`cat $TMP | $AWK '{ sum += $12 } END { print sum / NR } '`
		UTIL_ABS=`echo $UTIL | $AWK '{printf "%d",$1}'`
		RESULTPERF="on $DEVICE util%:$UTIL/% | util%=$UTIL;$LEVEL_WARN;$LEVEL_CRIT;0;;"
		if [ "$UTIL_ABS" -lt "$LEVEL_WARN" ] ; then
			RESULT="OK - $RESULTPERF"
			EXIT_STATUS=$STATE_OK
		else
			if [ "$UTIL_ABS" -ge "$LEVEL_CRIT" ] ; then
				RESULT="CRITICAL - $RESULTPERF"
				EXIT_STATUS=$STATE_CRITICAL
			else
				if [ "$UTIL_ABS" -ge "$LEVEL_WARN" ] ; then
					RESULT="WARNING - $RESULTPERF"
					EXIT_STATUS=$STATE_WARNING
				fi
			fi
		fi
	fi

	## Handle Transactions per second
	if [ $FLAG_TPS = "TRUE" ] ; then
		TPS=`cat $TMP | $AWK '{ sum += $2 } END { print sum / NR } '`
		TPS_ABS=`echo $TPS | $AWK '{printf "%d",$1}'`
		#RESULTPERF="on $DEVICE| io=$TPS;$LEVEL_WARN;$LEVEL_CRIT;0;"
		RESULTPERF="on $DEVICE tps:$TPS/s | tps=$TPS;$LEVEL_WARN;$LEVEL_CRIT;0;;"
		if [ "$TPS_ABS" -lt "$LEVEL_WARN" ] ; then
			#RESULT="IOSTAT OK - $RESULTPERF"
			RESULT="OK - $RESULTPERF"
			EXIT_STATUS=$STATE_OK
		else
			if [ "$TPS_ABS" -ge "$LEVEL_CRIT" ] ; then 
				#RESULT="IOSTAT CRITICAL - $RESULTPERF"
				RESULT="CRITICAL - $RESULTPERF"
				EXIT_STATUS=$STATE_CRITICAL
			else
				if [ "$TPS_ABS" -ge "$LEVEL_WARN" ] ; then 
					#RESULT="IOSTAT WARNING - $RESULTPERF"
					RESULT="WARNING - $RESULTPERF"
					EXIT_STATUS=$STATE_WARNING
				fi
			fi
		fi
	fi

	## Handle Reads per second
	if [ $FLAG_READS = "TRUE" ] ; then
		READSS=`cat $TMP | $AWK '{ sum += $3} END { print sum / NR } '`
		READSS_ABS=`echo $READSS | $AWK '{printf "%d",$1}'`
		#RESULTPERF="on $DEVICE| read=$READSS;$LEVEL_WARN;$LEVEL_CRIT;0;"
		RESULTPERF="on $DEVICE read:$READSS KB/s | read=$READSS;$LEVEL_WARN;$LEVEL_CRIT;0;;"
		if [ "$READSS_ABS" -lt "$LEVEL_WARN" ] ; then
			#RESULT="IOSTAT OK $RESULTPERF"
			RESULT="OK $RESULTPERF"
			EXIT_STATUS=$STATE_OK
		else
			if [ "$READSS_ABS" -ge "$LEVEL_CRIT" ] ; then 
				#RESULT="IOSTAT CRITICAL $RESULTPERF"
				RESULT="CRITICAL $RESULTPERF"
				EXIT_STATUS=$STATE_CRITICAL
			else
				if [ "$READSS_ABS" -ge "$LEVEL_WARN" ] ; then 
					#RESULT="IOSTAT WARNING $RESULTPERF"
					RESULT="WARNING $RESULTPERF"
					EXIT_STATUS=$STATE_WARNING
				fi
			fi
		fi
	fi

	## Handle Writes per second
	if [ $FLAG_WRITES = "TRUE" ] ; then
		WRITESS=`cat $TMP | $AWK '{ sum += $4} END { print sum / NR } '`
		WRITESS_ABS=`echo $WRITESS | $AWK '{printf "%d",$1}'`
		#RESULTPERF="on $DEVICE| write=$WRITESS;$LEVEL_WARN;$LEVEL_CRIT;0;"
		RESULTPERF="on $DEVICE write:$WRITESS KB/s | write=$WRITESS;$LEVEL_WARN;$LEVEL_CRIT;0;;"
		if [ "$WRITESS_ABS" -lt "$LEVEL_WARN" ] ; then
			#RESULT="IOSTAT OK $RESULTPERF"
			RESULT="OK $RESULTPERF"
			EXIT_STATUS=$STATE_OK
		else
			if [ "$WRITESS_ABS" -ge "$LEVEL_CRIT" ] ; then 
				#RESULT="IOSTAT CRITICAL $RESULTPERF "
				RESULT="CRITICAL $RESULTPERF "
				EXIT_STATUS=$STATE_CRITICAL
			else
				if [ "$WRITESS_ABS" -ge "$LEVEL_WARN" ] ; then 
					#RESULT="IOSTAT WARNING $RESULTPERF"
					RESULT="WARNING $RESULTPERF"
					EXIT_STATUS=$STATE_WARNING
				fi
			fi
		fi
	fi

       ## Handle Reads and Writes per second
       if [ $FLAG_READWRITES = "TRUE" ] ; then
		READSS=`cat $TMP | $AWK '{ sum += $3 } END { print sum / NR } '`
		READSS_ABS=`echo $READSS | $AWK '{printf "%d",$1}'`
		WRITESS=`cat $TMP | $AWK '{ sum += $4 } END { print sum / NR } '`
		WRITESS_ABS=`echo $WRITESS | $AWK '{printf "%d",$1}'`
		#RESULTPERF="on $DEVICE| read=$READSS;$LEVEL_WARN;$LEVEL_CRIT;0; write=$WRITESS;$LEVEL_WARN;$LEVEL_CRIT;0 "
		RESULTPERF="on $DEVICE read:$READSS KB/s write:$WRITESS KB/s| read=$READSS;$LEVEL_WARN;$LEVEL_CRIT;0;; write=$WRITESS;$LEVEL_WARN;$LEVEL_CRIT;0;;"
		if [ "$READSS_ABS" -lt "$LEVEL_WARN" ] && [ "$WRITESS_ABS" -lt "$LEVEL_WARN" ]  ; then
			#RESULT="IOSTAT OK $RESULTPERF"
			RESULT="OK $RESULTPERF"
			EXIT_STATUS=$STATE_OK
		else
			if [ "$READSS_ABS" -ge "$LEVEL_CRIT" ] || [ "$WRITESS_ABS" -ge "$LEVEL_CRIT" ] ; then
				#RESULT="IOSTAT CRITICAL $RESULTPERF"
				RESULT="CRITICAL $RESULTPERF"
				EXIT_STATUS=$STATE_CRITICAL
			else
				if [ "$READSS_ABS" -ge "$LEVEL_WARN" ] || [ "$WRITESS_ABS" -ge "$LEVEL_WARN" ] ; then
					#RESULT="IOSTAT WARNING $RESULTPERF"
					RESULT="WARNING $RESULTPERF"
					EXIT_STATUS=$STATE_WARNING
				fi
			fi
		fi
	fi
else
	echo "ERROR: Invalid warning/critical values"
	usage
	exit $STATE_UNKNOWN
fi	

# Quit and return information and exit status
theend
