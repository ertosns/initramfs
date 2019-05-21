#/!/bin/bash


#TODO  set escape characters for fansy colours of supported kernel terminal
LOG=/tmp/xweser.log
rm $LOG
touch $LOG


INF () { echo -e $@ >> $LOG; }

ERR () { echo -e $@; exit; }

WRN () { echo -e $@; }

#[ $DEBUG = true ] && [ -f "$DEBUG_FILE" ] && echo "[DBG] $@" >> $DEBUG_FILE
DBG () { INF $@;}

QST () { echo -e $@; }
