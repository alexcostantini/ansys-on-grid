#!/bin/bash
# Script to run ANSYS from bash -- by Alessandro Costantini

echo ""
echo "Script ANSYS start"
echo "Set variables"
echo ""

#assign arguments to variable name
output=$1
userfolder=$2
url=$3

# variables
#output_last
outputl=$1"_last"


# APDL
if [ "x$url" == "x" ]; then
 APDL="APDL"
else
 APDL="Restart Job; APDL not neened"
 rm -rf input.tar
 rm -rf APDL
fi

#get the ncpus from PBS
ncpus=$(wc -l $PBS_NODEFILE | awk '{print $1}')

#get walltime from PBS
maxtimequeue=$(qmgr -c "list queue "$PBS_QUEUE |grep default.walltime |awk '{print $3}'| awk -F\: '{print $1 *3600}')
#set it if not specified
if [ "x$maxtimequeue" == "x" ]
then
maxtimequeue=43200
fi


################

#comment for test-sart#
#maxtime=$maxtimequeue
#let runtime=$maxtime-7200
#comment for test-stop#

#set time variables -- enable only for test
#12h
maxtime=43200
#5h 
runtime=18000

#control
#comment for test-sart#
#ctrltime=3600
#comment for test-stop#

#set ctrltime variable -- enable only for test
#30min
ctrltime=1800

################



#killing time
killtime=$runtime

#ansys bynary
progID="/opt/exp_soft/gridit/ansys_inc/v130/ansys/bin/ansys130 "
bynID="ansys.e130"

#closese=$SE_HOST
closese="darkstorm.cnaf.infn.it"

#clientSRM
clientSRM="/usr/bin/clientSRM"

#print variables
echo "APLD: " $APDL
echo "output: " $output
echo "user folder: " $userfolder
echo "cpu unumber: " $ncpus
echo "max runtime queue: " $maxtimequeue
echo "max runtime imposed: " $maxtime
echo "effective runtime: " $runtime
echo "kill time: " $killtime
echo "control time: "$ctrltime
echo "ansys path: "$progID
echo "ansys binary: "$bynID
echo "used SE: "$closese

# Set automatic resubmission to FALSE by default
touch rstauto
echo "FALSE" > rstauto





# FUNCTIONS

##USERFOLDER
#check if userfolder exists via clientSRM
function user_folder()
{
echo ""
echo "Check if folder "$userfolder" exists"
#
ufexist=$($clientSRM Ls -e httpg://$closese:8444/ -s srm://$closese:8444/ansys/$userfolder | grep "status: statusCode=" | head -n 1 | awk -F\( '{print $NF}' | awk -F\) '{print $1}')

if [ "$ufexist" -ne "0" ]; then
 echo "Dir "$userfolder" do not exist... creating"
 $clientSRM Mkdir -e httpg://$closese:8444/ -s srm://$closese:8444/ansys/$userfolder

 try=1
 while [ "$try" -lt "4" ]; do  
  ufexist=$($clientSRM Ls -e httpg://$closese:8444/ -s srm://$closese:8444/ansys/$userfolder | grep "status: statusCode=" | head -n 1 | awk -F\( '{print $NF}' | awk -F\) '{print $1}') 

  if [ "$ufexist" -ne "0" ]; then
    if [ "$try" -lt "4" ]; then
     echo "Problem creating dir "$userfolder" ... retry in few seconds"
     $clientSRM Mkdir -e httpg://$closese:8444/ -s srm://$closese:8444/ansys/$userfolder
	 let try=$try+1
    else
     echo "Problem creating dir "$userfolder" ... no more tentatives"
     echo "Exit script Err. 113"
     echo ""
     exit 113
    fi
  else
   echo $userfolder" succesfully created in the SE:"$closese
   echo ""
  try=5
  fi
 done
else
echo $userfolder" already present in the SE:"$closese
echo ""
fi 
}


##PREPARETOPUT
#PreparetoPut function
function ptp_log()
{
#remove file, if exists in the SE
echo ""
echo "Remove "$output".log on the SE "$closese
$clientSRM rm -e httpg://$closese:8444/ -s srm://$closese:8444/ansys/$userfolder/$output".log"
echo "Done"
#log file -- 24h lifetime
echo ""
echo "Create file "$output".log on the SE "$closese
touch $output".log"
echo "File ready to be copyed" > $output".log"
$clientSRM PtP -e httpg://$closese:8444/ -w 1 -c 86400 -p -s srm://$closese:8444/ansys/$userfolder/$output".log" > ptp_log.txt
#extract turl
turllog=$(cat ptp_log.txt |grep "TURL" | awk -F\" '{print $2}')
#"#extract token
tokenlog=$(cat ptp_log.txt | grep "requestToken" | awk -F\" '{print $2}')
#"#
try=1
while [ "$try" -lt "4" ]; do
 globus-url-copy file:`pwd`/$output".log" $turllog
 if [ "$?" -ne "0" ]; then
  let try=$try+1
  if [ "$try" -lt "4" ]; then
   echo "Problem copying file "$output".log ... retry in few seconds"
  else
   echo "Problem copying file "$output".log ... no more tentatives"
   echo "Exit script Err. 114"
   $clientSRM pd -e httpg://$closese:8444 -s srm://$closese:8444/ansys/$userfolder/$output".log" -t $tokenlog
   echo ""
   exit 114
  fi
 else
  echo "File "$output".log successfully copied to the SE "$closese
  echo ""
  try=5
 fi 
done

$clientSRM pd -e httpg://$closese:8444 -s srm://$closese:8444/ansys/$userfolder/$output".log" -t $tokenlog
}


#PREPAREINPUT
#prepare input
function pre_input()
{
#check if url is present... no: run is a first run
if [ "x$url" == "x" ]; then
#untar input files
 tar -xf input.tar
 ls -la
 echo "******"
#resubmission, extract endtime
 endtime=$(cat $APDL |grep "TIME," |awk '{print $1}' |awk -F, '{print $2}')
 if [ "x$endtime" == "x" ]; then
  echo ""
  echo "******" 
  echo "TIME variable not correctly set in the "$APDL" file."
  echo "Please, set it as in the following example and resubmit"
  echo "******"
  echo "TIME,23000                    !sets the time for a load step"
  echo "******"
  echo "######"
  echo "Job aborted"
  echo "######"
  echo "Exit script Err. 115"
  exit 115
 fi
 touch end_TIME
 echo $endtime > end_TIME
 
# yes: run is a reboot after failure
else
#
 echo ""
 echo "Trasnfering file "$url" from the SE "$closese
 try=1
 while [ "$try" -lt "4" ]; do
#globus - old
# globus-url-copy gsiftp://darkstorm.cnaf.infn.it:2811//storage/ansys/$userfolder/$url  file:`pwd`/input.tar.gz
#
#curl
 prehttps="https://darkstorm.cnaf.infn.it:8443/storageArea/ansys"
#uncomment for CLI use only
#curl --cert $X509_USER_PROXY --capath /etc/grid-security/certificates -o `pwd`/input.tar.gz $prehttps/$userfolder/$url
#uncomment for portal use only
curl --cert $X509_USER_PROXY --capath /etc/grid-security/certificates -o `pwd`/input.tar.gz $url 
#
 if [ "$?" -ne "0" ]; then
   let try=$try+1
   if [ "$try" -lt "4" ]; then
    echo "Problem transfering file "$url" ... retry in few seconds"
   else
    echo "Problem transfering file "$url" ... no more tentatives"
    echo "Exit script Err. 114"
    echo ""
    exit 114
   fi
  else
   echo "File "$url" successfully transferred from the SE "$closese
   echo ""
   try=5
  fi 
 done
#
#echo "Untar input file"
##untar input files
 tar -zxf input.tar.gz
 echo "List content"
 ls -la
#only if needed
#remove lock
#echo "Remove file.lock"
#rm -f file.lock
#
# Control for resubmission: endtime
 endtime=$(cat end_TIME)
fi
}



##RUNNINGAPP
#sample script to start a program, permit it to run for a predefined amount of CPU time, then kill it.
function ansys_run()
{
# generation of input commands file used to tun ansys
echo ""
echo "Preparing command file"
#
if [ "x$url" == "x" ]; then
#
 echo "/INPUT,'"$APDL"','','',1,0" >> commands
 echo "FINISH" >> commands
 echo "! /EXIT,ALL" >> commands
#
else
# generation of command file used to tun ansys
 echo "y" >> commands
 echo "FINISH" >> commands
 echo "RESUME,file,db" >> commands
 echo "/CONFIG,NRES,1000000" >> commands
 echo "/POST1" >> commands
 echo "SET,LAST" >> commands
 echo "*GET,nsub,ACTIVE,0,SET,SBST" >> commands
 echo "*GET,nloa,ACTIVE,0,SET,LSTP" >> commands
 echo "/SOLU" >> commands
 echo "ANTYPE,TRANS,REST,nloa,nsub-1,CONTINUE" >> commands
 echo "OUTRES,NSOL,ALL" >> commands
 echo "VFOPT,READ" >> commands
 echo "SOLVE" >> commands
 echo "y" >> commands
 echo "SAVE" >> commands
fi
#
echo "Command file ready"
echo""

ansys=" -np "$ncpus" < commands > "$output".log"

#run it!
#
echo "Running program: ANSYS"
#
echo $progID $ansys
$progID $ansys & echo $! > ansyspid
#application pid
mypid=$(cat ansyspid)
#
echo "PID ansys130 is "$mypid
#
sleep 60
mypidchild=$(ps --ppid $mypid | grep -iv "PID" | awk '{print $1}')
echo "PID ansys.e130 is "$mypidchild
#first check log
echo "Starting check at runtime..."
log_check

#start time
secs=0

#control loop
while [ $secs -lt $killtime ]; do
 sleep $ctrltime
#check if the application is running
 mypidcontrol=$(eval ps --ppid $mypid |grep -iv "PID" | awk '{print $1}')
 echo "PID ansys.e130 is "$mypidcontrol
 if [ "x$mypidcontrol" == "x" ]; then
  echo ""
  echo "Simulation ended before the assigned time"
  echo ""
  let secs=$killtime+1
 else
#
#check curhour
  curhour=$(eval ps --ppid $mypid |grep -iv "PID" | awk '{print $3}' |awk -F\: '{print $1}')
  time1=$(echo $curhour |awk '{print substr($0,0,1)}')
  if [ "$time1" -eq "0" ]; then
   curhour=$(echo $curhour |awk '{print substr($0,2,1)}')
  fi
  let secs1=$curhour*3600
#
#check curmin
  curmin=$(eval ps --ppid $mypid |grep -iv "PID" | awk '{print $3}' |awk -F\: '{print $2}')
  time2=$(echo $curmin |awk '{print substr($0,0,1)}')
  if [ "$time2" -eq "0" ]; then
   curmin=$(echo $curmin |awk '{print substr($0,2,1)}')
  fi
  let secs2=$curmin*60
#
#check cursec
  cursec=$(eval ps --ppid $mypid |grep -iv "PID" | awk '{print $3}' |awk -F\: '{print $3}')
  time3=$(echo $cursec |awk '{print substr($0,0,1)}')
  if [ "$time3" -eq "0" ]; then
   cursec=$(echo $cursec |awk '{print substr($0,2,1)}')
  fi
  let secs3=$cursec
# sum time
  let secs=$secs1+$secs2+$secs3

  #output_log check
  #
  echo ""
  echo "Starting check at runtime; "$secs " seconds elapsed time"
  #
  log_check
 fi
#
#end
done
#
#last check if the application is running
mypidcontrol=$(eval ps --ppid $mypid |grep -iv "PID" | awk '{print $1}')
if [ -n "$mypidcontrol" ]; then
# kill the application
 echo ""
 echo "The job reached the CPU time assigned to the simulation "
 echo "The job will be killed"
 echo "The above errors are armless..."
 echo "Kill ANSYS. PID: "$mypidchild
 kill -s 2 "$mypidchild"
 sleep 10
 echo ""
fi
# wait until the application is running
echo "Check il the application is really terminated"
check=1
while [ "$check" -eq "1" ]; do
 mypidcheck=$(eval ps --pid $mypid |grep -iv "PID" | awk '{print $1}')
 if [ -n "$mypidcheck" ]; then
  echo "Application still up... retry in 10 min."
  sleep 600
 else
  echo "Application terminated."
  check=4
 fi
done
}


##CHECKLOGS
# check logs
function log_check()
{
#
echo "Copy file "$output".log to the SE "$closese
#
try=1
while [ "$try" -lt "4" ]; do
 globus-url-copy file:`pwd`/$output".log" $turllog
 if [ "$?" -ne "0" ]; then
  let try=$try+1
  if [ "$try" -lt "4" ]; then
   echo "Problem copying file "$output".log ... retry in few seconds"
  else
   echo "Problem copying file "$output".log ... no more tentatives"
  fi
 else
  echo "File "$output".log successfully copied to the SE "$closese
  echo ""
  echo ""
  try=5
 fi 
done
}



##PREPAREOUTPUT
#prepare output
function ansys_out()
{
echo "Simulation ended, preparing output file..."
echo "Update file "$output".log to the SE "$closese
log_check
#
#
# test if input.tar.gz exists
if [ -e input.tar.gz ];then
#
#remove file input.tar.gz
 rm input.tar.gz
#
#remove file output_last, if exists in the SE
 echo ""
 echo "Remove "$outputl".tar.gz on the SE "$closese
 $clientSRM rm -e httpg://$closese:8444/ -s srm://$closese:8444/ansys/$userfolder/$outputl".tar.gz"
#
#insert control...to do 
#
 echo "Done"
 echo ""
#
#move file output to output_last in the SE
 echo ""
 echo "Move "$output".tar.gz on the SE "$closese" to "$outputl".tar.gz"
 $clientSRM mv -e httpg://$closese:8444/ -s srm://$closese:8444/ansys/$userfolder/$output".tar.gz" -t srm://$closese:8444/ansys/$userfolder/$outputl".tar.gz"
#
#insert control...to do 
#
 echo "Done"
 echo ""
#
# tar outputs
 echo "Tar outputs into "$output".tar.gz"
 tar -zcf $output.tar.gz --exclude='stdout.log' --exclude='stderr.log' --exclude='gridnfo.log'  --exclude='execute.bin' --exclude='wrapper.sh' --exclude='commands' --exclude='ansys.out' --exclude='ansys.err' --exclude='ansys1srm_restart5.sh' --exclude='ansyspid' --exclude='rstauto' *
#
else
#
#remove file output_last, if exists in the SE
 echo ""
 echo "Remove "$outputl".tar.gz on the SE "$closese
 $clientSRM rm -e httpg://$closese:8444/ -s srm://$closese:8444/ansys/$userfolder/$outputl".tar.gz"
#
#insert control...to do 
#
 echo "Done"
 echo ""
#
# tar outputs
 echo "Tar outputs into "$output".tar.gz"
 tar -zcf $output.tar.gz --exclude='stdout.log' --exclude='stderr.log' --exclude='gridnfo.log'  --exclude='execute.bin' --exclude='wrapper.sh' --exclude='commands' --exclude='input.tar' --exclude='ansys.out' --exclude='ansys.err' --exclude='ansys1srm_restart5.sh' --exclude='ansyspid' --exclude='rstauto' *
#
fi
#
#
echo "Output file "$output".tar.gz ready"
#
#remove file output, if exists in the SE
 echo ""
 echo "Remove "$output".tar.gz on the SE "$closese
 $clientSRM rm -e httpg://$closese:8444/ -s srm://$closese:8444/ansys/$userfolder/$output".tar.gz"
#
#insert control...to do 
#
 echo "Done"
 echo ""
#
echo "Prepare to copy "$output".tar.gz on the SE "$closese
#PtP and output transfer -- 7days lifetime
$clientSRM PtP -e httpg://$closese:8444/ -w 1 -c 604800 -p -s srm://$closese:8444/ansys/$userfolder/$output".tar.gz" > ptp_out.txt
#TURL
turlout=$(cat ptp_out.txt |grep "TURL" | awk -F\" '{print $2}')
#"Token
tokenout=$(cat ptp_out.txt | grep "requestToken" | awk -F\" '{print $2}')
#"
try=1
while [ "$try" -lt "4" ]; do
 globus-url-copy file:`pwd`/$output".tar.gz" $turlout
 if [ "$?" -ne "0" ]; then
  let try=$try+1
  if [ "$try" -lt "4" ]; then
   echo "Problem copying file "$output".tar.gz ... retry in few minutes"
   sleep 300
  else
   echo "Problem copying file "$output".tar.gz ... no more tentatives"
   echo "Exit script Err. 114"
   echo ""
   exit 114
  fi
 else
  echo "File "$output".tar.gz successfully copied to the SE "$closese
  try=5
 fi 
done
#
$clientSRM pd -e httpg://darkstorm.cnaf.infn.it:8444 -s srm://darkstorm.cnaf.infn.it:8444/ansys/$userfolder/$output".tar.gz" -t $tokenout




# Stop automatic resubmission if endtime is not set
if [ "x$endtime" == "x" ]; then
 echo ""
 echo "******"
 echo "TIME variable has not been correctly set from the previous run."
 echo "Automatic resubmission aborted. Set rstauto to FALSE"
 echo "******"
 echo ""
 echo "FALSE" > rstauto
else

# Control for resubmission
realtime=$(cat $output".log" |grep "TIME =" |tail -n1 | awk '{print $4}' |awk -F. '{print $1}')

# Stop automatic resubmission if realtime is not set
 if [ "x$realtime" == "x" ]; then
  echo ""
  echo "******"
  echo "It has not been possible extract the actual TIME value from the "$output".log file."
  echo "Automatic resubmission aborted. Set rstauto to FALSE"
  echo "Please, have a look to the "$output".log for more details"
  echo "******"
  echo ""
  echo "FALSE" > rstauto
 else
# realtime is set, evaluating...
  echo ""
  echo "******"
  echo "Calculation ended at TIME = "$realtime" of "$endtime
  if [ "$realtime" -lt "$endtime" ]; then
   echo "Resubmission in progress. Set rstauto to TRUE"
   echo "******"
   echo ""
   echo "TRUE" > rstauto
   echo $realtime >> rstauto
   echo $endtime >> rstauto
  else
   echo "Resubmission not needed. Set rstauto to FALSE"
   echo "******"
   echo ""
   echo "FALSE" > rstauto
   echo $realtime >> rstauto
   echo $endtime >> rstauto
  fi
 fi
fi
}


#
# REAL RUN
#

#invoke user_folder function
user_folder
#invoke ptp_log function
ptp_log
#invoke pre_input function
pre_input
#invoke running function
ansys_run
#invoke output function
ansys_out

echo ""
echo "Job "$output" terminated with success!"
echo ""

exit 0


