JobName="Initialize"
echo "Job =========== $JobName ===========  started at `date`"
echo "Parameters: (1)... $1    (2) $2 "
while true
do
echo "within the job <  $JobName > ..."

file_pattern=$0.exit
echo "file pattern is: $file_pattern" 
echo "exit 0 pattern: ${file_pattern}_0"
echo "exit 1 pattern: ${file_pattern}_1"
echo "exit 20 pattern: ${file_pattern}_20"

if [ -f ${file_pattern}_0  ]; then
   echo "exiting 0 ..."
   exit 0 
elif   [ -f ${file_pattern}_1 ]; then
   echo "exiting 1 ..." 
   exit 1 
elif [ -f ${file_pattern}_20 ]; then
   echo "exitting ... 20"
   exit 20 
fi
echo "sleep 5 seconds ..."
sleep 5

done  
exit 0
