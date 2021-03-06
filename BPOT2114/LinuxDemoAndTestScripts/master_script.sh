#!/bin/ksh


getJobNumber(){
oralog=`pwd`/`basename $0`.getJobNumber.$$.`timestamp`.log

sql2run="select count(*)  from rt_job_info"

#echo -e "sql2run=$sql2run\n"

# Execute sql
sqlplus -s $CONNSTRG >> $oralog << ZZZ
    set head off;
    $sql2run;
ZZZ

# Check for sql errors
if [ -n "`cat $oralog | grep ORA-`" ]; then
    echo -e "\nERROR: Found ORA- error(s) in $oralog"
    cat $oralog
    echo -e "\nScript exiting...\n"
    /bin/rm -f $oralog
    exit 1
fi

retvalue=`cat $oralog`


/bin/rm -f $oralog
job_number=$retvalue

}


getJobInfo(){
oralog=`pwd`/`basename $0`.getJobInfo.$$.`timestamp`.log

sql2run="select  Job_Id||'~'||Job_Type||'~'||Job_Name||'~'||Qualifier||'~'||Predecessor_IDs||'~'||Predecessor_Condition||'~'||Successor_IDs||'~'||to_char(Schedule_Time, 'yyyy-mm-dd hh24:mi:ss')||'~'||Start_Time||'~'||End_Time||'~'||State||'~'||tag_for_wait_states||'~'||tag_for_run_states||'~'||Agent_Name||'~'||Event_Name||'~'||Application_Name||'~'||Script||'~'||Arguments_Of_Script||'~'||process_info||'~'||return_code||'~'||spool_info||'~'||general_runtime_info||'~'||Completion_Code||'~'||Description from rt_job_info  where TO_NUMBER(job_id)=$1"

#echo -e "sql2run=$sql2run\n"

# Execute sql
sqlplus -s $CONNSTRG >> $oralog << ZZZ
    set head off;
    $sql2run;
ZZZ

# Check for sql errors
if [ -n "`cat $oralog | grep ORA-`" ]; then
    echo -e "\nERROR: Found ORA- error(s) in $oralog"
    cat $oralog
    echo -e "\nScript exiting...\n"
    /bin/rm -f $oralog
    exit 1
fi

retvalue=`cat $oralog`


/bin/rm -f $oralog
job_info=$retvalue

}

process_wait_state(){
echo " [01] when job state is 01 ... process_wait_state..."
# there are many checks here : hold/release, check time/time arrived 
# now only check the predecessors 
#
echo "....[A]..............check if job in hold state..........."
tag_for_wait_state=`echo $job_info|awk -F~ '{print $12}'`
echo "....... checking tag_for_wait_state if it has 01(hold tag)"

checkpos=`echo $tag_for_wait_state  | awk '{print match($0, "01")}'`
if [  $checkpos -gt 0  ]; then
  echo "hold tag set ... nothing happen ..."
  return
else
  echo " no hold tag ... continue next check ..."
fi 

echo "....[B]..............check if job in time schedule, then check the time......."
time_schedule=`echo $job_info|awk -F~ '{print $8}'`
checkpos=`echo $time_schedule  | awk '{print match($0, ":")}'`  # using this to avod the empty stuff
if [ $checkpos -gt 0 ]; then 

     stime=$(date -d "$time_schedule" +%s)         
     now=$(date  +%s)
     if [ $stime -gt $now ]; then
              echo ".... scheduleed time is: $time_schedule  , now is: `date` still need to wait ...."
     return
     else
             echo " .... scheduled time reached, do further checking ....."
     fi
else 
     echo " .... no scheduled time set, do further checking ...."
fi 
 
#  continue
echo "....[C]..............within check the predecessor states..........."
predecessor_ids=`echo $job_info|awk -F~ '{print $5}'`

#echo "predecessor ids: $predecessor_ids"
#if all predecessor  completed,then set job state to ready06 

separated_predecessor_ids=`echo $predecessor_ids|sed 's/,/ /g'`
#echo "separated predecessor_ids are: $separated_predecessor_ids"
all_completed=0
for item in $separated_predecessor_ids
do 
    echo "predecessor of job $1 is :  $item " 
   #check the state of all predecessor if completed 
    check_if_job_completed $item
    #echo "... new value is $new_value ..."
    ##all_completed=` expr $all_completed + $new_value ` 
done  

echo "....... value of all_completed of predecessor is: ...$all_completed..." 
if [ $all_completed -eq 0 ]; then
   echo "all predecessor of job $icount completed, ready to set the ready state:"
   set_job__state $icount 06 
fi
}
set_job__state(){
oralog=`pwd`/`basename $0`.set_job__state.$$.`timestamp`.log

sql2run="update rt_job_info set state='$2'  where TO_NUMBER(job_id)=$1"

echo -e "sql2run=$sql2run\n"

# Execute sql
sqlplus -s $CONNSTRG >> $oralog << ZZZ
    set head off;
    $sql2run;
ZZZ

# Check for sql errors
if [ -n "`cat $oralog | grep ORA-`" ]; then
    echo -e "\nERROR: Found ORA- error(s) in $oralog"
    cat $oralog
    echo -e "\nScript exiting...\n"
    /bin/rm -f $oralog
    exit 1
fi

retvalue=`cat $oralog`


/bin/rm -f $oralog
 
}

check_if_job_completed(){

oralog=`pwd`/`basename $0`.check_if_job_completed.$$.`timestamp`.log

sql2run="select count(*) from  rt_job_info where  TO_NUMBER(job_id)=$1 and state <> 20"  
 # now temp exclude state 15 which is fake complete

#echo -e "sql2run=$sql2run\n"

# Execute sql
sqlplus -s $CONNSTRG >> $oralog << ZZZ
    set head off;
    $sql2run;
ZZZ

# Check for sql errors
if [ -n "`cat $oralog | grep ORA-`" ]; then
    echo -e "\nERROR: Found ORA- error(s) in $oralog"
    cat $oralog
    echo -e "\nScript exiting...\n"
    /bin/rm -f $oralog
    exit 1
fi

retvalue=`cat $oralog`


/bin/rm -f $oralog

echo " .... all_completed is $all_completed and retValue of query is: $retvalue "
all_completed=` expr $all_completed + $retvalue ` 
           # if one incomplete then the value will be gt 0  
return $retvalue
}

process_ready_state(){
echo " [06] when job state is 06 ... process_ready_state..."
# 1 update to run state
# it is important to set the run state in first place, as if system down when process triggered 
#  but not update to run state, then the process will be triggered again and again
#  if set to run state first, then system down, then people can still find that the actuall process
#  is not running , and correct them 
echo "....first of all, setting the job to running state ...."
set_job__state $icount 10     



# 2 trigger the job with nohup 
echo ".... now trigger the acutual process as it is ready ..."
job_script=`echo $job_info|sed 's/ //g'|awk -F'~' '{print $17}'`
echo -e "...job script is:  $job_script"

# trigger the job now 
# unique string for this job
job_name=`echo $job_info|sed 's/ //g'|awk -F'~' '{print $3}'`
job_token=$job_name.$$.`timestamp`
#  now trigger the job .............. spool could be kept here temporarily 
echo "... triggering the actual job with nohup ......"
/usr/bin/nohup $job_script >nohup_$job_token.out&
echo $! >  /home/pin211/billy/151112-1-CAWARun/save_pid_$job_token.txt
# saving the pid and spool location to db , this is important for the other 
# monitoring tasks 
spoolname=nohup_$job_token.out
process_id=`cat /home/pin211/billy/151112-1-CAWARun/save_pid_$job_token.txt`
# saving the spoolname and process_id to db
echo ".... saving the spoolname and process_id to db ..."
update_spoolname_and_process_id $icount $spoolname $process_id

echo "... done with the ready state processing"




# 2 check the job running
# no longer to check the job running state here, let it check in run state 

# 3 update to run state 




}


process_failed_state(){
echo " [11] ... process_failed_state..."
# 1  first check if there is a resumit tag ...
echo ".....[A] if there is a resubmit tag set  ..."

tag_for_run_states=`echo $job_info|awk -F~ '{print $13}'`

checkpos=`echo $tag_for_run_states  | awk '{print match($0, "16")}'`                               
echo "checkpos is: $checkpos"
if [  $checkpos -gt 0  ]; then                                                            
  echo "found resubmit tag, set the job to ready state ..."                                         
  # direct set the ready, no need to check the others 
  set_job__state $icount 06 
  echo "... as the runtime tag is used, clean up the runtime tag ..."
  clean_up_runtime_tag $icount   
  return                                                                             
else
   echo "no resubmit tag found, continue checking ..."
fi                                                                                   
echo ".....[B] if there is are  a FC  tag set  ..."

checkpos=`echo $tag_for_run_states  | awk '{print match($0, "19")}'`
if [  $checkpos -gt 0  ]; then
  echo "found FC tag, set the job to complete  state ..."
  set_job__state $icount 20 
  echo "... as the runtime tag is used, clean up the runtime tag ..."
  clean_up_runtime_tag $icount

  return
else
   echo "no FC tag found, nothing happen ..."
fi
}

update_spoolname_and_process_id(){
oralog=`pwd`/`basename $0`.update_spoolname_and_process_id.$$.`timestamp`.log

sql2run="update rt_job_info set spool_info='$2', process_info='$3'   where TO_NUMBER(job_id)=$1"

echo -e "sql2run=$sql2run\n"

# Execute sql
sqlplus -s $CONNSTRG >> $oralog << ZZZ
    set head off;
    $sql2run;
ZZZ

# Check for sql errors
if [ -n "`cat $oralog | grep ORA-`" ]; then
    echo -e "\nERROR: Found ORA- error(s) in $oralog"
    cat $oralog
    echo -e "\nScript exiting...\n"
    /bin/rm -f $oralog
    exit 1
fi

retvalue=`cat $oralog`


/bin/rm -f $oralog


}
process_running_state(){
echo " [10] ... process_running_state..."
# 1 check pid 
running_pid=`echo $job_info|awk -F~ '{print $19}'`
#spool_info=`echo $job_info|awk -F~ '{print $21}'`   # if we this way , there is always a space inserted
 spool_info=`echo $job_info|sed 's/ //g'|awk -F~ '{print $21}'`
echo "....[A] checking if the saved pid exists .... "
echo "........ saved pid: $running_pid   spool : $spool_info"
/bin/ps -fu $LOGNAME | grep -v "ps -fu"|/usr/bin/awk '{print $2}'|grep $running_pid
if [ $? -eq 0 ]; then 
  # the pid existing and running
  echo ".... saved pid is still running , checking if the cancel tag exists ...."
  tag_for_run_states=`echo $job_info|awk -F~ '{print $13}'`

  checkpos=`echo $tag_for_run_states  | awk '{print match($0, "11")}'`
  echo "checkpos is: $checkpos"
  if [  $checkpos -gt 0  ]; then
  echo "found cancel  tag,  prepare to kill the process ..."
  # we just kill the process here, no need to update the state, as next time the running state will check this 
  echo ".... killing the process :  kill -9 $running_pid ..."
  /usr/bin/kill -9  $running_pid 
  if [ $? -eq 0 ]; then 
     echo "...process : $running_pid killed ..."
  else 
     echo "... problem with the killing process:  $running_pid , please check ..."
  fi
  echo "... now clean up the runtime tag as the process is already tried the kill ...."
  clean_up_runtime_tag $icount 
  return
else
   echo "no resubmit tag found, continue checking ..."
fi

  return
else
   echo ".... saved pid not existing, the job could be compeltd or failed, do further checking...."
fi
# 2 when the pid not running, check if completed or failed 
echo "....[C] as the pid is not active  checking if the saved pid exits 0 (completed) or non-zero (failed).... "
# a temp solution is to check the spool if there is an "exiting 0" there 
 /usr/bin/tail -1 $spool_info |grep "exiting 0"
if [ $? -eq 0 ]; then
  # the job complete successfully 
  echo ".... the job completed successfully and now save the return code and update the state to completed ...."
  set_job__state $icount 20  
  # set_job_return_code $icount 0 # so far we do not implement this detail as the return code not so gracefully got
  return
else
  # the job should be failed 
  echo ".... the job does not have a existing 0 in the spool,suppose the job failed ...."
  set_job__state $icount 11  
  # set_job_return_code $icount 0 # so far we do not implement this detail as the return code not so gracefully got
  return
fi
}

clean_up_runtime_tag(){
oralog=`pwd`/`basename $0`.clean_up_runtime_tag.$$.`timestamp`.log

sql2run="update rt_job_info set tag_for_run_states=''  where TO_NUMBER(job_id)=$1"

echo -e "sql2run=$sql2run\n"

# Execute sql
sqlplus -s $CONNSTRG >> $oralog << ZZZ
    set head off;
    $sql2run;
ZZZ

# Check for sql errors
if [ -n "`cat $oralog | grep ORA-`" ]; then
    echo -e "\nERROR: Found ORA- error(s) in $oralog"
    cat $oralog
    echo -e "\nScript exiting...\n"
    /bin/rm -f $oralog
    exit 1
fi

retvalue=`cat $oralog`


/bin/rm -f $oralog

}

echo 
all_completed=0
CONNSTRG="pin211/pin211@brm"
getJobNumber
#echo "the job count is : $job_number"
while true 
do 
   echo "[  `date`   ] Master script running  at  ...."
   icount=0
   while [ $icount -lt $job_number ]
   do 
      #echo $icount 
      echo "==================the job count(job id)  is : $icount"

      getJobInfo $icount
      #echo $job_info

      job_state=`echo $job_info|awk -F~ '{print $11}'`
      echo "job state is: $job_state"

      case $job_state in 
      01) process_wait_state ;;
      06) process_ready_state ;;
      10) process_running_state ;;
      11) process_failed_state ;;
      20);;
      *);;
      esac
      icount=` expr $icount + 1 `
   done 
   echo "[ `date`  ] this round of master script running done ... sleep 2 seconds ..."
   sleep 4
done
