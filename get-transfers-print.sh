#!/bin/bash

ACCOUNTNUM=11111111111

BINDIR=/opt/hbci/aqbanking-5.5.0.2git/bin
BASEDIR=$HOME
PINFILE=$BASEDIR/pinlist.txt
AQBANKING=$BINDIR/aqbanking-cli
CONFDIR=$HOME/.aqbanking
DATE=`date +%Y-%m-%d_%H:%M:%S`
DATE_OLD=`date -d '2 weeks ago' +%Y%m%d`
LOGDIR=$BASEDIR/log
if [ ! -d $LOGDIR ] ; then
	echo "Oops, the log directory LOGDIR=$LOGDIR does not exist"
	exit 1
fi
CTXFILE=$LOGDIR/context${ACCOUNTNUM}_${DATE}_$$.ctx
LOGFILE=$LOGDIR/log${ACCOUNTNUM}_${DATE}_$$.log

$AQBANKING -D $CONFDIR -P $PINFILE request --transactions -a $ACCOUNTNUM -c $CTXFILE --fromdate=$DATE_OLD > $LOGFILE 2>&1 || exit 1

$AQBANKING -D $CONFDIR listtrans -c $CTXFILE -a $ACCOUNTNUM

# In case multiple users execute this script, it might be useful to
# reset the ownership of the .aqbanking directory:
#chown -R cs $CONFDIR 2>/dev/null

