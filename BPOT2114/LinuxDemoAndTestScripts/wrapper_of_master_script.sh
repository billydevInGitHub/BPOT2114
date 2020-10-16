#!/bin/ksh
/usr/bin/nohup  master_script.sh >nohup_master_process&
echo $! >  /home/pin211/billy/151104-1-MasterProcess/save_pid_master_process.txt

