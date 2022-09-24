[oracle@xhydra ~]$ cat dfadder.sh
#!/bin/bash
#++++++++++++++++++++++++++++++++++++++++++#
# dfadder (v1) script for adding datafile automatically by kishan
#++++++++++++++++++++++++++++++++++++++++++#

#Set the environment variables and file variables
_env(){
touch /home/oracle/spacecrunch.out
touch /home/oracle/dfadd.sql
NOSPACE=/home/oracle/spacecrunch.out
ORACLE_SID=db9zx
export ORACLE_SID
ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export ORACLE_HOME
PATH=/usr/sbin:/usr/local/bin:/usr/bin:$PATH:$ORACLE_HOME/bin:/u01/app/oracle/product/19.0.0/dbhome_1/bin
export PATH
LD_LIBRARY_PATH=$ORACLE_HOME/lib
DFPATH=$(echo "/apps01/oradata/DB9ZX/datafile/")
DFADD=$(echo "/home/oracle/dfadd.sql")
}
#Function to check space in the filesystem
_fsspace(){
SPACE=$(df -hk $DFPATH|awk '{print $4}'|grep -v 'Available'|xargs -I {} expr {} / 1024)
if [ $((SPACE)) -ge 1000 ];
then
_check_space_crunch
fi
}
#Function to check free space in tablespace
_check_space_crunch(){
sqlplus -S "/ as sysdba" <<EOF > log_for_reference_1
spool spacecrunch.out
set heading off
set lines 200  pages 1000
col TABLESPACE_NAME for a20
col TOTAL_FREE_SPACE_MB for 99999999999
with TABLESPACE_V
as
(
select x.TABLESPACE_NAME as TBLSPC,
       round(sum(x.bytes/1048576)) as TOTAL_SPACE_MB
from
    dba_data_files x
    group by x.TABLESPACE_NAME
order by 1
),
SEGMENT_V as
(
select y.tablespace_name as TBLSEG,
       round(sum(y.bytes/1048576)) as TOTAL_SIZE_OCCUPIED
from
    dba_segments y
    group by y.tablespace_name
order by 1
)
select TBLSPC,
       TOTAL_SPACE_MB,
       sum(TOTAL_SPACE_MB - TOTAL_SIZE_OCCUPIED) as TOTAL_FREE_SPACE,
       round(100*((TOTAL_SPACE_MB - TOTAL_SIZE_OCCUPIED) / TOTAL_SPACE_MB)) as PCT
from
    TABLESPACE_V a
    inner join SEGMENT_V b on (a.TBLSPC=b.TBLSEG)
group by TBLSPC,
         TOTAL_SPACE_MB,
         round(100*((TOTAL_SPACE_MB - TOTAL_SIZE_OCCUPIED) / TOTAL_SPACE_MB))
having
    sum(TOTAL_SPACE_MB - TOTAL_SIZE_OCCUPIED) < 1000
and
    round(100*((TOTAL_SPACE_MB - TOTAL_SIZE_OCCUPIED) / TOTAL_SPACE_MB))  < 5
order by 4 desc;
spool off
exit;
EOF
}
#Check if space is needed by tablespace
_is_space_need(){
limit=$SPACE
dfminsize=50M
DFMAXSIZE=30000M
if [[ $(cat spacecrunch.out|sed '/^$/d'|awk '{print $3}') -le 10 ]] && [[ $(cat spacecrunch.out|sed '/^$/d'|awk '{print $4}') -le 5 ]] && [[ -n $TSPACE ]] && [[ $(echo $dfminsize|grep -Eo '[0-9]{0,9}') -le `expr $((limit)) - 200` ]]
then
        _dfadd
        echo "Datafile of size $dfminsize has been added to $TSPACE tablespace with autoextend disabled"
elif [[ $(echo $dfminsize|grep -Eo '[0-9]{0,9}') -ge `expr $((limit)) - 200` ]]
then
        echo "Space crunch from OS mount! Add more storage for datafiles"
else
        echo "All tablespaces has sufficient space"
fi
}
TSPACE=$(cat spacecrunch.out|grep -v 'no rows'|awk '{print $1}'|sed '/^$/d'|head -1)

#If space is less than threshold, then add datafile if necessary
_dfadd(){
if [[ -n $TSPACE ]]
then
        RAND=$(shuf -i 0-10000 -n 1)
        RAND1=$(shuf -i 0-10000 -n 1)
        echo -e "def SIZE=$dfminsize\ndef TSPACE=$TSPACE\ndef DFPATH=$DFPATH\ndef RAND=$RAND\ndef RAND1=$RAND1\nalter tablespace &TSPACE add datafile '&DFPATH/&TSPACE&RAND&RAND1.dbf' size &SIZE autoextend off;" > $DFADD
sqlplus "/ as sysdba" @$DFADD <<EOF
exit;
EOF
else
        echo "exiting..."
fi
}
#Execution of all functions
_env
_fsspace
_is_space_need
