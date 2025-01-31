#!/bin/ksh
#############################################################################
echo "----------------------------------------------------------------------"
echo "exglobal_dump.sh - Global (GDAS, GFS) network data dump processing"
echo "----------------------------------------------------------------------"
echo "History: Jan 18 2000 - Original script.                               "
echo "         May 16 2007 - Added DBNet alerts for GFS products.           "
echo "            Apr 2014 - Pick up grib files for planned GFS upgrade.    "
echo "            Oct 2014 - Remove attempts to dump obsolete sources.      "
echo "            Nov 2014 - Use parallel scripting to process dump groups. "
echo "                       Widen hourly satwnd dump window for GFS/GDAS.  "
echo "                       Add new satwnd subtypes for GFS & GDAS.        "
echo "                       GFS/GDAS continue if surface file unavailable. "
echo "                       Remove DBNet alerts for old surface files.     "
echo "         Dec  3 2014 - CDAS network, split off into its own script    "
echo "                       excdas_dump.sh.ecf.  This script now tailored  "
echo "                       exclusively to GDAS and GFS.                   "
echo "         Feb  2 2015 - Dump window for new satwnd type NC005090 set   "
echo "                       to 3.00 to +2.99 hours about center dump time. "
echo "                       Removed ADD_satwnd=\"005019 005080\" since     "
echo "                       types are now part of "satwnd" dump group      "
echo "                       mnemonic in bufr_dumplist.                     "
echo "         Aug 22 2016 - GSPIPW dump window reset for new data stream   "
echo "                         (moved to dump group #4 where TIME_TRIM=on)  "
echo "         Jan  5 2017 - Dump new satellite data types. Reordered to    "
echo "                       improve run time with all the new data.        "
echo "         Feb  8 2017 - Update to run on Cray-XC40 or IBM iDataPlex    "
echo "         Nov 13 2017 - Add dump of GOES-16 AMV's in tanks b005/xx030, "
echo "                       b005/xx031, b005/xx032, b005/xx034 and         "
echo "                       b005/xx039.  Set dump window to -3.00 to +2.99 "
echo "                       hours for these 5 new GOES-16 tanks.           "
echo "         Aug 10 2018 - Updated to run on Dell-p3 (as well as Cray-XC40"
echo "                       and IBM iDataPlex.                             "
echo "         Oct 24 2018 - Add dump of OMPS VSN8 nadir profile (NP) and   "
echo "                       total column (TC), Indiasat AMV's in tanks     "
echo "                       b005/xx024 b005/xx025 b005/xx026.              "
echo "         Mar 15 2019 - Add dumps of BUFR-feed drifting (NC001102) &   "
echo "                       moored (NC001203) buoys to DUMP group #2       "
echo "         Aug 15 2019 - rm'd background threads; now run serially;     "
echo "                       added "./" on "thread_*", needed for Dell/ph3  "
echo "                       Disabled processing that copies sstoi files to "
echo "                       COMSP.                                         "
echo "         Oct 15 2019 - set DTIM_LATEST_00110[23]=+2.99, as in sfcshp  "
echo "         Oct 26 2019 - set DTIM_EARLIEST_005091=-3.00 and             "
echo "                       DTIM_LATEST_005091=+2.99.  DTIM_* settings for "
echo "                       005090 are obsolete; added SKIP_005090=YES     "
echo "         Jan 03 2020 - turn on gdas.tCCz.saphir.tm00.bufr_d alerts,   "
echo "                       per DF request                                 "
echo "         Apr 06 2020 - Update to remove crisdb and escris and replace "
echo "                       with crsfdb and escrsf.  On Apr 22, 2020, NSR  "
echo "                       CrIS data from NPP is being replaced by FSR.   "
echo "                       The cris dump group is obsolete with the change"
echo "                       to FSR.                                        "
echo "         Aug 20 2020 - Incremented subsets for the adpsfc and sfcshp  "
echo "                       dump groups to match bufr_dumplist.            "
echo "                       Removed mbuoyb and dbuoyb from dump group #2.  "
echo "                       Removed obsolete dump groups escrsf and goesfv "
echo "                       from dump group #7.                            "
echo "                     - In Dump group #8, disabled processing of legacy"
echo "                       EUMETSAT AMV subsets 005064, 005065, and       "
echo "                       005066. Added DTIM settings for new WMO BUFR   "
echo "                       format EUMETSAT AMV subsets 005067, 005068, and"
echo "                       005069. On Oct 6, 2020, EUMETSAT AMV format    "
echo "                       changes to use new WMO BUFR sequence, 3-10-077."
echo "         Oct 09 2020 - Update to dump gsrcsr, gsrasr, ompslp, ahicsr, "
echo "                       sstvcw, sstvpw, leogeo, hdob                   "
echo "                       Update to remove obsolete GOES-15 data.        "
echo "                       Update to remove legacy VIIRS AMV data.        "
echo "         Feb 22 2021 - Disabled DBN alerts for gpsro dump files.      "
echo "                       These gpsro dump files have the potential to   "
echo "                       contain commercial data.  The equivalent       "
echo "                       non-restricted gpsro dump files are alerted    "
echo "                       instead.                                       "
echo "         Sep 21 2020 - Incremented subsets for the sfcshp dump groups "
echo "                       to match bufr_dumplist. Removed tideg from     "
echo "                       sfcshp dump group to make individual dump file."
echo "                     - Copy bufr_dumplist to COMOUT.                  "
echo "         Dec 16 2021 - modified to work on WCOSS2                     "
echo "         Mar 09 2022 - Enable the dumping of 002017 in vadwnd dump    "
echo "                       group.                                         "
echo "         Aug 10 2022 - subpfl and saldrn added to dump group #1.      "
echo "                       gmi1cr added to dump group #9                  "
echo "                       snocvr added to dump group #2                  "
echo "                       b005/xx081 added to satwnd                     "
echo "                       subpfl aadded to nsstbufr file                 "
echo "	                     DBN alerts are also enabled for subpfl,saldrn, "
echo "                       gmi1cr,and snocvr                              "
echo "         Oct 17 2022 - Split up groups 1 and 10 into a new group 12   "
echo "                       for better optimization.                       "
echo "         Sep 30 2022 - Enable dumping of UPRAIR data in group #3.     "
#############################################################################

# NOTE: NET is changed to gdas in the parent Job script for the gdas RUN 
#       (was gfs - NET remains gfs for gfs RUN)
# -----------------------------------------------------------------------

set -xau

# function to highlight an echoed msg with surrounding hashed separator lines.
   echo_hashed_msg () {
     set +x
     msg=$*
     echo -e "\n ${msg//?/#}"
     echo " ${msg}"
     echo -e " ${msg//?/#}\n"
     set -x
   }
# end of function setup
#
# set some variables if they have not already been set

set +u

# JOB_NUMBER = 1 indicates the prepbufr dump job.
# JOB_NUMBER = 2 indicates the non-prepbufr dump job.
# JOB_NUMBER not present indicates dump BOTH prepbufr and non-prepbufr data.
# -----------------------------------------------------------------------------
# Dump group #1 (non-pb, TIME_TRIM defaults to OFF) =
#               avcsam eshrs3 ssmisu 1bhrs4 tesac mls
#               esatms gsrcsr ahicsr sstvcw subpfl saldrn
#               Stop: sevcsr, saphir in v1.2.0 
# Dump group #2 (pb, TIME_TRIM defaults to OFF) =
#               sfcshp tideg atovs* adpsfc ascatt snocvr
#                   * - for GDAS only
#
# Dump group #3 (pb, TIME_TRIM defaults to OFF) =
#               adpupa
#
# Dump group #4 (pb, TIME_TRIM defaults to ON) =
#               aircar aircft proflr vadwnd rassda gpsipw hdob 
#
# Dump group #5 (pb, TIME_TRIM defaults to OFF) =
#               msonet
#
# Dump group #6 (non-pb, TIME_TRIM defaults to OFF) =
#               nexrad
#
# Dump group #7 (non-pb, TIME_TRIM defaults to OFF) =
#               avcspm esmhs 1bmhs airsev atmsdb gome omi trkob gpsro
#               crisf4
#
# Dump group #8 (pb, TIME_TRIM defaults to ON) =
#               satwnd
#
# Dump group #9 (non-pb, TIME_TRIM defaults to ON) =
#               geoimr gmi1cr satwhr
# Dump group #10 (non-pb, TIME_TRIM defaults to OFF) =
#               esiasi mtiasi esamua sevasr 1bamua bathy
#               osbuv8 ompst8 ompsn8 gsrasr ompslp sstvpw
#
# Dump group #11 (non-pb, TIME_TRIM defaults to OFF) =
#               amsr2
#
# Dump group #12 crisfs atms (previously group1)
#                crsfdb iasidb (previously group10)
# Dump group #13 (pb, TIME_TRIM defaults to OFF) = 
#                uprair
#
# Dump group #14 STATUS FILE
# -----------------------------------------------------------------------------

#VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
# The settings below are based on a future change when the DUMP job will dump
#  only types that go into PREPBUFR and the DUMP2 job will dump only types that
#  do not go into PREPBUFR.  This will speed up the DUMP + PREP processing.
# Although the logic is in place to now do this (see below), for now we will
#  continue to run only a DUMP job which will dump ALL types (no DUMP2 job) -
#  since JOB_NUMBER is not imported to this script, the logic below will dump
#  all types ...
# -----------------------------------------------------------------------------
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

if [ -n "$JOB_NUMBER" ]; then
set -u
   if [ $JOB_NUMBER = 2 ]; then
      dump_ind=DUMP2
      DUMP_group1=${DUMP_group1:-"YES"}
      DUMP_group2=${DUMP_group2:-"NO"}
      DUMP_group3=${DUMP_group3:-"NO"}
      DUMP_group4=${DUMP_group4:-"NO"}
      DUMP_group5=${DUMP_group5:-"NO"}
      DUMP_group6=${DUMP_group6:-"NO"}
      DUMP_group7=${DUMP_group7:-"YES"}
      DUMP_group8=${DUMP_group8:-"NO"}
      DUMP_group9=${DUMP_group9:-"YES"}
      DUMP_group10=${DUMP_group10:-"YES"}
      DUMP_group11=${DUMP_group11:-"YES"}
      DUMP_group12=${DUMP_group12:-"YES"}
      DUMP_group13=${DUMP_group13:-"NO"}
   else
      dump_ind=DUMP
      DUMP_group1=${DUMP_group1:-"NO"}
      DUMP_group2=${DUMP_group2:-"YES"}
      DUMP_group3=${DUMP_group3:-"YES"}
      DUMP_group4=${DUMP_group4:-"YES"}
      DUMP_group5=${DUMP_group5:-"NO"}
      DUMP_group6=${DUMP_group6:-"NO"}
      DUMP_group7=${DUMP_group7:-"NO"}
      DUMP_group8=${DUMP_group8:-"YES"}
      DUMP_group9=${DUMP_group9:-"NO"}
      DUMP_group10=${DUMP_group10:-"NO"}
      DUMP_group11=${DUMP_group11:-"NO"}
      DUMP_group12=${DUMP_group12:-"NO"}
      DUMP_group13=${DUMP_group13:-"YES"}
   fi
else
   dump_ind=DUMP
   DUMP_group1=${DUMP_group1:-"YES"}
   DUMP_group2=${DUMP_group2:-"YES"}
   DUMP_group3=${DUMP_group3:-"YES"}
   DUMP_group4=${DUMP_group4:-"YES"}
   DUMP_group5=${DUMP_group5:-"NO"}
   DUMP_group6=${DUMP_group6:-"NO"}
   DUMP_group7=${DUMP_group7:-"YES"}
   DUMP_group8=${DUMP_group8:-"YES"}
   DUMP_group9=${DUMP_group9:-"YES"}
   DUMP_group10=${DUMP_group10:-"YES"}
   DUMP_group11=${DUMP_group11:-"YES"}
   DUMP_group12=${DUMP_group12:-"YES"}
   DUMP_group13=${DUMP_group13:-"YES"}
fi

# NAP and NAP_adpupa instroduced so that uprair can run early on his own
NAP=${NAP:-600} #b/c cron is moved to run 10min (600s) early
if [ "$NET" = 'gfs' ]; then
   ADPUPA_wait=${ADPUPA_wait:-"YES"}
   NAP_adpupa=${NAP_adpupa:-800} #600s(compensate early cron) + 300s(for adpupa data to come)
########ADPUPA_wait=${ADPUPA_wait:-"NO"} # saves time if ADPUPA_wait=NO
else
   ADPUPA_wait=${ADPUPA_wait:-"NO"}
   NAP_adpupa=${NAP_adpupa:-600} #like other dump groups
fi

# send extra output of DUMP2 for monitoring purposes.
set +u
if [ -n "$JOB_NUMBER" ]; then
   [ $JOB_NUMBER = 2 ]  && export PS4='$SECONDS + '
fi
set -u

# Make sure we are in the $DATA directory
cd $DATA

msg="HAS BEGUN on `hostname`"
$DATA/postmsg "$jlogfile" "$msg"

cat break > $pgmout

export dumptime=`cut -c7-16 ncepdate`
export cycp=`echo $dumptime|cut -c9-10`

export NET_uc=$(echo $NET | tr [a-z] [A-Z])
export tmmark_uc=$(echo $tmmark | tr [a-z] [A-Z])

msg="$NET_uc ANALYSIS TIME IS $PDY$cyc"
$DATA/postmsg "$jlogfile" "$msg"

set +x
echo
echo "CENTER DATA DUMP DATE-TIME FOR $tmmark_uc $NET_uc IS $dumptime"
echo
set -x

export COMSP=$COMOUT/$RUN.${cycle}.

if [ "$PROCESS_GRIBFLDS" = 'YES' ]; then

########################################################
########################################################
## The following files are not *required* but will still
#   be processed here for the near term (missing files
#   will not cause job to fail)
# 
#  copy snogrb (0.5 deg) from $TANK_GRIBFLDS
#  copy snogrb_t574      from $TANK_GRIBFLDS
#  copy engicegrb        from $COM_ENGICE
#  copy sstgrb           from $COM_SSTOI
#  generate sstgrb index file
########################################################
########################################################

   # JY - 05/02: remove the dependency of snowdepth files created from isnowgrib job
   #snogrb=$TANK_GRIBFLDS/$PDY/wgrbbul/snowdepth.global.grb
   #snoold=$TANK_GRIBFLDS/$PDYm1/wgrbbul/snowdepth.global.grb

   #if [ -s $snogrb ]; then
   #   cp $snogrb ${COMSP}snogrb
   #   msg="todays 0.5 degree snow grib file located and copied to ${COMSP}snogrb"
   #   $DATA/postmsg "$jlogfile" "$msg"
   #elif [ -s $snoold ]; then
   #   cp $snoold ${COMSP}snogrb
   #   msg="**todays 0.5 degree snow grib file not located - copy 1-day old file"
   #   $DATA/postmsg "$jlogfile" "$msg"
   #else
   #   set +x
   #   echo " "
   #   echo " #####################################################"
   #   echo " cannot locate 0.5 degree snow grib file"
   #   echo " #####################################################"
   #   echo " "
   #   set -x
   #   msg="***WARNING: CANNOT LOCATE 0.5 DEGREE SNOW GRIB FILE.  Not critical."
   #   $DATA/postmsg "$jlogfile" "$msg"
   #fi

   #snogrb_t574=$TANK_GRIBFLDS/$PDY/wgrbbul/snowdepth.t574.grb
   #snoold_t574=$TANK_GRIBFLDS/$PDYm1/wgrbbul/snowdepth.t574.grb

   #if [ -s $snogrb_t574 ]; then
   #   cp $snogrb_t574 ${COMSP}snogrb_t574
   #   msg="todays T574 snow grib file located and copied to ${COMSP}snogrb_t574"
   #   $DATA/postmsg "$jlogfile" "$msg"
   #elif [ -s $snoold_t574 ]; then
   #   cp $snoold_t574 ${COMSP}snogrb_t574
   #   msg="**todays T574 snow grib file not located - copy 1-day old file"
   #   $DATA/postmsg "$jlogfile" "$msg"
   #else
   #   set +x
   #   echo " "
   #   echo " ###############################################"
   #   echo " cannot locate T574 snow grib file"
   #   echo " ###############################################"
   #   echo " "
   #   set -x
   #   msg="***WARNING: CANNOT LOCATE T574 SNOW GRIB FILE.  Not critical."
   #   $DATA/postmsg "$jlogfile" "$msg"
   #fi

   engicegrb=${COM_ENGICE}.$PDY/engice.t00z.grb
   engiceold=${COM_ENGICE}.$PDYm1/engice.t00z.grb

   if [ -s $engicegrb ]; then
      cp $engicegrb ${COMSP}engicegrb
      msg="todays engice grib file located and copied to ${COMSP}engicegrb"
      $DATA/postmsg "$jlogfile" "$msg"
   elif [ -s $engiceold ]; then
      cp $engiceold ${COMSP}engicegrb
      msg="**todays engice grib file not located - copy 1-day old file"
      $DATA/postmsg "$jlogfile" "$msg"
   else
      set +x
      echo " "
      echo " ############################################"
      echo " cannot locate engice grib file"
      echo " ############################################"
      echo " "
      set -x
      msg="***WARNING: CANNOT LOCATE LOW RES ENGICE GRIB FILE.  Not critical."
      $DATA/postmsg "$jlogfile" "$msg"
   fi

# Disabled w/ GFSv15.2 b/c sstoi file no longer needed
#  sstgrb=${COM_SSTOI}.$PDY/sstoi_grb
#  sstold=${COM_SSTOI}.$PDYm1/sstoi_grb

#  if [ -s $sstgrb ]; then
#     cp $sstgrb ${COMSP}sstgrb
#     msg="todays lowres sst grib file located and copied to ${COMSP}sstgrb"
#     $DATA/postmsg "$jlogfile" "$msg"
#  elif [ -s $sstold ]; then
#     cp $sstold ${COMSP}sstgrb
#     msg="**todays lowres sst grib file not located - copy 1-day old file"
#     $DATA/postmsg "$jlogfile" "$msg"
#  else
#     set +x
#     echo " "
#     echo " #########################################"
#     echo " cannot locate lowres sst grib file"
#     echo " #########################################"
#     echo " "
#     set -x
#     msg="***WARNING: CANNOT LOCATE LOW RES SST GRIB FILE.  Not critical."
#     $DATA/postmsg "$jlogfile" "$msg"
#  fi

#  if [ -s ${COMSP}sstgrb ]; then
#     rm errfile
#     $GRBINDEX ${COMSP}sstgrb ${COMSP}sstgrb.index 2> errfile
#     errindx=$?
#     [ "$errindx" -ne '0' ] && cat errfile
#     rm errfile
#  else
#     echo_hashed_msg "cannot create grib index since sst file does not exist"
#  fi

#  The following may no longer be needed, but leave them in place for now.
#  Print msg in the rare case the grib2 files cannot be created.
   if [ "$NET" = 'gdas' ]; then
      if [ -s ${COMSP}engicegrb ]; then
         $CNVGRIB -g12 -p40 ${COMSP}engicegrb ${COMSP}engicegrb.grib2
      else
         echo_hashed_msg "Skip engicegrb.grib2 since grib1 file does not exist"
      fi
      # Disabled w/ GFSv15.2 b/c sstoi file no longer needed
      #if [ -s ${COMSP}sstgrb ]; then
      #   $CNVGRIB -g12 -p40 ${COMSP}sstgrb ${COMSP}sstgrb.grib2
      #else
      #   echo_hashed_msg "Skip sstgrb.grib2 since grib1 file does not exist"
      #fi
      #if [ -s ${COMSP}snogrb ]; then
      #   $CNVGRIB -g12 -p40 ${COMSP}snogrb ${COMSP}snogrb.grib2
      #else
      #   echo_hashed_msg "Skip snogrb.grib2 since grib1 file does not exist"
      #fi
   fi


######################################################################
######################################################################
#  For the following, try as far as $ndaysback to find recent file.  #
#  Post warning if no file found for $ndaysback_warn or beyond.      #
#  The job will continue if no suitable file is available.           #
#  ----------------------------------------------------------------  #
#  copy NPR.SNWN.SP.S1200.MESH16   from $TANK_GRIBFLDS               #
#  copy NPR.SNWS.SP.S1200.MESH16   from $TANK_GRIBFLDS               #
#  copy imssnow96.grb.grib2        from $TANK_GRIBFLDS               #
#  copy seaice.t00z.5min.grb       from $COM_ICE5MIN                 #
#  copy seaice.t00z.5min.grb.grib2 from $COM_ICE5MIN                 #
#  copy rtgssthr_grb_0.083         from $COM_SSTRTG                  #
#  copy rtgssthr_grb_0.083.grib2   from $COM_SSTRTG                  #
######################################################################
######################################################################
   for gribfile in  \
    NPR.SNWN.SP.S1200.MESH16   \
    NPR.SNWS.SP.S1200.MESH16   \
    imssnow96.grb.grib2        \
    seaice.t00z.5min.grb       \
    seaice.t00z.5min.grb.grib2 \
    rtgssthr_grb_0.083         \
    rtgssthr_grb_0.083.grib2
   do
# set the values specific to each file
      case $gribfile in
         NPR.SNWN.SP.S1200.MESH16 | NPR.SNWS.SP.S1200.MESH16 )    # AFWA snow
          grib_source='$TANK_GRIBFLDS/$DDATE/wgrbbul';
          target_filename=$gribfile.grb
          ndaysback=1;
          ndaysback_warn=1;;
         imssnow96.grb.grib2 )                     # IMS snow
          grib_source='$TANK_GRIBFLDS/$DDATE/wgrbbul';
          target_filename=imssnow96.grib2
          ndaysback=1;
          ndaysback_warn=1;;
         seaice.t00z.5min.grb )
          grib_source='${COM_ICE5MIN}.$DDATE';
          target_filename=seaice.5min.grb
          ndaysback=7;
          ndaysback_warn=1;;
         seaice.t00z.5min.grb.grib2 )
          grib_source='${COM_ICE5MIN}.$DDATE';
          target_filename=seaice.5min.grib2
          ndaysback=7;
          ndaysback_warn=1;;
         rtgssthr_grb_0.083 )
          grib_source='${COM_SSTRTG}.$DDATE';
          target_filename=rtgssthr.grb
          ndaysback=10;
          ndaysback_warn=1;;
         rtgssthr_grb_0.083.grib2 )
          grib_source='${COM_SSTRTG}.$DDATE';
          target_filename=rtgssthr.grib2
          ndaysback=10;
          ndaysback_warn=1;;
         *) 
         msg="***FATAL ERROR: unexpected grib field file $gribfile"; 
         echo_hashed_msg "$msg"
         $DATA/postmsg "$jlogfile" "$msg"
         $DATA/err_exit;;
      esac
# set up string of dates to check
      if [ $ndaysback -gt 0 ];then
set +x; echo -e "\n---> path to finddate.sh below is: `which finddate.sh`"; set -x
         CHECK_DATES="$PDY $(finddate.sh $PDY s-$ndaysback)"
      else
         CHECK_DATES=$PDY
      fi
      set +x; 
      echo -e "\nWill check as far back as ${CHECK_DATES##* } for $gribfile"
      set -x
      ndtry=0
      found=false
# loop through dates to check for this file type
      for DDATE in $CHECK_DATES;do
         ndtry=`expr $ndtry + 1`
         eval tryfile=$grib_source/$gribfile
         if [ -s $tryfile ];then
            set +x; echo -e "\nPicking up file $tryfile\n"; set -x
            cp $tryfile ${COMSP}$target_filename
            found=true
            break
         fi
         if [ $DDATE -ne ${CHECK_DATES##* } ]; then
            set +x;echo -e "\n$tryfile not available. Try previous day.\n"
            set -x
         else
            set +x;echo -e "\n$tryfile not available.\n";set -x
         fi
         if [ $ndtry -gt $ndaysback_warn ];then
            msg="***WARNING: INVESTIGATE UNEXPECTED ABSENCE OF $tryfile"
            echo_hashed_msg "$msg"
            $DATA/postmsg "$jlogfile" "$msg"
         fi   
      done
      if [ $found != true ]; then
         msg="***WARNING: NO USEFUL RECENT FILES FOUND FOR $gribfile!!!"
         echo_hashed_msg "$msg"
         $DATA/postmsg "$jlogfile" "$msg"
      fi    
   done
   if [ "$SENDECF" = "YES" ]; then
      ecflow_client --event=release_sfcprep
   fi

#  endif loop $PROCESS_GRIBFLDS
fi


echo "=======> Dump group 1 (thread_1) not executed." > $DATA/1.out
echo "=======> Dump group 2 (thread_2) not executed." > $DATA/2.out
echo "=======> Dump group 3 (thread_3) not executed." > $DATA/3.out
echo "=======> Dump group 4 (thread_4) not executed." > $DATA/4.out
echo "=======> Dump group 5 (thread_5) not executed." > $DATA/5.out
echo "=======> Dump group 6 (thread_6) not executed." > $DATA/6.out
echo "=======> Dump group 7 (thread_7) not executed." > $DATA/7.out
echo "=======> Dump group 8 (thread_8) not executed." > $DATA/8.out
echo "=======> Dump group 9 (thread_9) not executed." > $DATA/9.out
echo "=======> Dump group 10 (thread_10) not executed." > $DATA/10.out
echo "=======> Dump group 11 (thread_11) not executed." > $DATA/11.out
echo "=======> Dump group 12 (thread_12) not executed." > $DATA/12.out
echo "=======> Dump group 13 (thread_13) not executed." > $DATA/13.out

err1=0
err2=0
err3=0
err4=0
err5=0
err6=0
err7=0
err8=0
err9=0
err10=0
err11=0
err12=0
err13=0
if [ "$PROCESS_DUMP" = 'YES' ]; then

####################################
####################################
#  The data "dump" script for tm00
####################################
####################################

msg="START THE $tmmark_uc $NET_uc DATA $dump_ind CENTERED ON $dumptime"
$DATA/postmsg "$jlogfile" "$msg"

set +x
#----------------------------------------------------------------
cat<<\EOF>thread_1; chmod +x thread_1
set -uax

cd $DATA

{ echo
set +x
echo "********************************************************************"
echo Script thread_1
echo Executing on node  `hostname`
echo Starting time: `date -u`
echo "********************************************************************"
echo
set -x

sleep ${NAP} # to reverse 10min early start of jglobal_dump in cron
export STATUS=NO
export DUMP_NUMBER=1

#=========================================================================
# NOTES ABOUT THIS DUMP GROUP:
#   (1) time window radius is -3.00 to +2.99 hours on all types
#   (2) TIME TRIMMING IS NOT DONE IN THIS DUMP (default, unless overridden)
#
#--------------------------------------------------------------------------
# Dump # 1 : AVCSAM: 1 subtype(s)
#            ESHRS3: 1 subtype(s)
#            SSMISU: 1 subtype(s)
#            SAPHIR: 1 subtype(s)
#            1BHRS4: 1 subtype(s)
#            SEVCSR: 1 subtype(s)
#            TESAC:  1 subtype(s)
#            MLS:    1 subtype(s) (if present in past 10 days of tanks)
#            ESATMS: 1 subtype(s) (if present in past 10 days of tanks)
#            GSRCSR: 1 subtype(s)
#            AHICSR: 1 subtype(s)
#            SSTVCW: 1 subtype(s)
#            SUBPFL: 1 subtype(s)
#            SALDRN: 1 subtype(s)
#            --------------------
#            TOTAL NUMBER OF SUBTYPES = 14
#
#=========================================================================

DTIM_latest_avcsam=${DTIM_latest_avcsam:-"+2.99"}
DTIM_latest_eshrs3=${DTIM_latest_eshrs3:-"+2.99"}
DTIM_latest_ssmisu=${DTIM_latest_ssmisu:-"+2.99"}
#DTIM_latest_saphir=${DTIM_latest_saphir:-"+2.99"}
DTIM_latest_saldrn=${DTIM_latest_saldrn:-"+2.99"}
DTIM_latest_1bhrs4=${DTIM_latest_1bhrs4:-"+2.99"}
#DTIM_latest_sevcsr=${DTIM_latest_sevcsr:-"+2.99"}
DTIM_latest_tesac=${DTIM_latest_tesac:-"+2.99"}
#-----------------------------------------------
# check for mls tank presence in past 10 days
mls=""
err_check_tanks=0
sh $USHbufr_dump/check_tanks.sh mls
err_check_tanks=$?
if [ $err_check_tanks -eq 0 ];then
   mls=mls
   DTIM_latest_mls=${DTIM_latest_mls:-"+2.99"}
fi
#-----------------------------------------------
#-----------------------------------------------
# check for esatms tank presence in past 10 days
esatms=""
err_check_tanks=0
sh $USHbufr_dump/check_tanks.sh esatms
err_check_tanks=$?
if [ $err_check_tanks -eq 0 ];then
   esatms=esatms
   DTIM_latest_esatms=${DTIM_latest_esatms:-"+2.99"}
fi
#-----------------------------------------------
DTIM_latest_gsrcsr=${DTIM_latest_gsrcsr:-"+2.99"}
DTIM_latest_ahicsr=${DTIM_latest_ahicsr:-"+2.99"}
DTIM_latest_sstvcw=${DTIM_latest_sstvcw:-"+2.99"}

TIME_TRIM=${TIME_TRIM:-${TIME_TRIM1:-off}}

$ushscript_dump/bufr_dump_obs.sh $dumptime 3.0 1 avcsam eshrs3 ssmisu \
 1bhrs4 tesac $mls $esatms gsrcsr ahicsr sstvcw subpfl saldrn
error1=$?
echo "$error1" > $DATA/error1

if [ "$SENDDBN" = "YES" ]; then
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_avcsam $job \
    ${COMSP}avcsam.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_eshrs3 $job \
    ${COMSP}eshrs3.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_ssmisu $job \
    ${COMSP}ssmisu.tm00.bufr_d
#   if [ "${NET}" = "gdas" ]; then
#      $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_saphir $job \
#       ${COMSP}saphir.tm00.bufr_d    ### restricted, only GDAS, turn on 01/13/2020
#   fi
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_1bhrs4 $job \
    ${COMSP}1bhrs4.tm00.bufr_d
#   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_sevcsr $job \
#    ${COMSP}sevcsr.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_tesac $job \
    ${COMSP}tesac.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_saldrn $job \
    ${COMSP}saldrn.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_subpfl $job \
    ${COMSP}subpfl.tm00.bufr_d
   if [ "$mls" = mls ];then
      $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_mls $job \
       ${COMSP}mls.tm00.bufr_d
   fi
   if [ "$esatms" = esatms ];then
      $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_esatms $job \
       ${COMSP}esatms.tm00.bufr_d
   fi
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_gsrcsr $job \
    ${COMSP}gsrcsr.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_ahicsr $job \
    ${COMSP}ahicsr.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_sstvcw $job \
    ${COMSP}sstvcw.tm00.bufr_d
fi

set +x
echo "********************************************************************"
echo Script thread_1
echo Finished executing on node  `hostname`
echo Ending time  : `date -u`
echo "********************************************************************"
set -x
} > $DATA/1.out 2>&1
EOF
set -x

set +x
#----------------------------------------------------------------
cat<<\EOF>thread_2; chmod +x thread_2
set -uax

cd $DATA

{ echo
set +x
echo "********************************************************************"
echo Script thread_2
echo Executing on node  `hostname`
echo Starting time: `date -u`
echo "********************************************************************"
echo
set -x

sleep ${NAP} # to reverse 10min early start of jglobal_dump in cron
export STATUS=NO
export DUMP_NUMBER=2

#==========================================================================
# NOTES ABOUT THIS DUMP GROUP:
#   (1) time window radius is -3.00 to +2.99 hours on all types
#   (2) TIME TRIMMING IS NOT DONE IN THIS DUMP (default, unless overridden)
#   (3) GDAS GSI doesn't use ATOVS, but NASA/GSFC is pulling them off our
#       server, also CDAS may be running special tests using data from GDAS
#       cutoff time (ATOVS is not dumped in GFS)
#
#--------------------------------------------------------------------------
# GDAS:
# Dump # 2 : SFCSHP: 11 subtype(s) (added shipsb & shipub in dumplist)
#            TIDEG:  1 subtype(s)
#            ATOVS:  1 subtype(s)
#            ADPSFC: 7 subtype(s)
#            ASCATT: 1 subtype(s)
#            SNOCVR: 1 subtype(s)
#  xxxxxxxxx WNDSAT: 1 subtype(s) (if present in past 10 days of tanks)
# ===> Dumping of WNDSAT removed from here until new ingest feed is established
#      (had been dumped with a time window radius of -3.00 to +2.99 hours)
#            --------------------
#            TOTAL NUMBER OF SUBTYPES = 21 - 22
#
#--------------------------------------------------------------------------
# GFS:
# Dump # 2 : SFCSHP: 11 subtype(s) (added shipsb & shipub in dumplist)
#            TIDEG:  1 subtype(s)
#            ADPSFC: 7 subtype(s)
#            ASCATT: 1 subtype(s)
#            SNOCVR: 1 subtype(s)
#  xxxxxxxxx WNDSAT: 1 subtype(s) (if present in past 10 days of tanks)
# ===> Dumping of WNDSAT removed from here until new ingest feed is established
#      (had been dumped with a time window radius of -3.00 to +2.99 hours)
#            --------------------
#            TOTAL NUMBER OF SUBTYPES =  21 - 22
#
#==========================================================================
DTIM_latest_snocvr=${DTIM_latest_snocvr:-"+2.99"}
DTIM_latest_sfcshp=${DTIM_latest_sfcshp:-"+2.99"}
DTIM_latest_tideg=${DTIM_latest_tideg:-"+2.99"}

atovs=""
if [ "$NET" = 'gdas' ]; then
   atovs=atovs
   DTIM_latest_atovs=${DTIM_latest_atovs:-"+2.99"}
fi

DTIM_latest_adpsfc=${DTIM_latest_adpsfc:-"+2.99"}
DTIM_latest_ascatt=${DTIM_latest_ascatt:-"+2.99"}
#-----------------------------------------------
# check for wndsat tank presence in past 10 days
wndsat=""
err_check_tanks=0
##########sh $USHbufr_dump/check_tanks.sh wndsat
##########err_check_tanks=$?
err_check_tanks=99 # comment out 2 lines above & add this line to ensure wndsat
                   # is not ever dumped
if [ $err_check_tanks -eq 0 ];then
   wndsat=wndsat
   DTIM_latest_wndsat=${DTIM_latest_wndsat:-"+2.99"}
fi
#-----------------------------------------------

TIME_TRIM=${TIME_TRIM:-${TIME_TRIM2:-off}}

$ushscript_dump/bufr_dump_obs.sh $dumptime 3.0 1 sfcshp tideg $atovs adpsfc snocvr ascatt $wndsat
error2=$?
echo "$error2" > $DATA/error2

if [ "$SENDDBN" = "YES" ]; then
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_sfcshp $job \
    ${COMSP}sfcshp.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_tideg $job \
    ${COMSP}tideg.tm00.bufr_d
   [ -f ${COMSP}atovs.tm00.bufr_d ]  &&  \
    $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_atovs $job \
    ${COMSP}atovs.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_adpsfc $job \
    ${COMSP}adpsfc.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_ascatt $job \
    ${COMSP}ascatt.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_snocvr $job \
    ${COMSP}snocvr.tm00.bufr_d
   if [ "$NET" = 'gdas' ]; then
    ####### ALERT TURNED ON for GDAS only ########################
      $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_ascatw $job \
       ${COMSP}ascatw.tm00.bufr_d
   fi
   if [ "$wndsat" = wndsat ];then
      $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_wndsat $job \
       ${COMSP}wndsat.tm00.bufr_d
      $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_wdsatr $job \
       ${COMSP}wdsatr.tm00.bufr_d
   fi
fi

set +x
echo "********************************************************************"
echo Script thread_2
echo Finished executing on node  `hostname`
echo Ending time  : `date -u`
echo "********************************************************************"
set -x
} > $DATA/2.out 2>&1
EOF
set -x

set +x
#----------------------------------------------------------------
cat<<\EOF>thread_3; chmod +x thread_3
set -uax

cd $DATA

{ echo
set +x
echo "********************************************************************"
echo Script thread_3
echo Executing on node  `hostname`
echo Starting time: `date -u`
echo "********************************************************************"
echo
set -x

sleep ${NAP_adpupa} # to reverse 10min early start of jglobal_dump in cron
export STATUS=NO
export DUMP_NUMBER=3

#====================================================================
# NOTES ABOUT THIS DUMP GROUP:
#   (1) time window radius is -3.00 to +2.99 hours on all types
#   (2) TIME TRIMMING IS NOT DONE IN THIS DUMP (default, unless overridden)
#
#--------------------------------------------------------------------------
# Dump #3:   ADPUPA: 6 subtype(s)
#            --------------------
#            TOTAL NUMBER OF SUBTYPES = 6
#
#====================================================================

DTIM_latest_adpupa=${DTIM_latest_adpupa:-"+2.99"}

TIME_TRIM=${TIME_TRIM:-${TIME_TRIM3:-off}}

$ushscript_dump/bufr_dump_obs.sh $dumptime 3.0 1 adpupa
error3=$?
echo "$error3" > $DATA/error3

if [ "$SENDDBN" = "YES" ]; then
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_adpupa $job \
    ${COMSP}adpupa.tm00.bufr_d
fi

set +x
echo "********************************************************************"
echo Script thread_3
echo Finished executing on node  `hostname`
echo Ending time  : `date -u`
echo "********************************************************************"
set -x
} > $DATA/3.out 2>&1
EOF
set -x

set +x
#----------------------------------------------------------------
cat<<\EOF>thread_4; chmod +x thread_4
set -uax

cd $DATA

{ echo
set +x
echo "********************************************************************"
echo Script thread_4
echo Executing on node  `hostname`
echo Starting time: `date -u`
echo "********************************************************************"
echo
set -x

sleep ${NAP} # to reverse 10min early start of jglobal_dump in cron
export STATUS=NO
export DUMP_NUMBER=4

#=======================================================================
# NOTES ABOUT THIS DUMP GROUP:
#   (1) time window radius is -3.00 to +2.99 hours on all types
#       EXCEPT: AIRCFT where it is +/- 3.25 hours
#               AIRCAR where it is +/- 3.25 hours
#               PROFLR where it is -4.00 to +3.99 hours
#               GSPIPW where it is +/- 0.05 hours (+/- 3min)
#   (2) TIME TRIMMING IS DONE IN THIS DUMP (default, unless overridden)
#
#--------------------------------------------------------------------------
# Dump # 4 : AIRCAR: 2 subtype(s)
#            AIRCFT: 8 subtype(s)
#            PROFLR: 4 subtype(s)
#            VADWND: 1 subtype(s)
#            RASSDA: 1 subtype(s)
#            GPSIPW: 1 subtype(s)
#            HDOB  : 1 subtype(s)
#            -------------------- 
#            TOTAL NUMBER OF SUBTYPES = 18
#
#=======================================================================

# Skip NeXRaD VAD WINDS FROM LEVEL 2 DECODER (not ready to be handled in GSI) (002017)
# 3/9/2022 -- enable the dumping of 002017 in the vadwnd dump group.
#export SKIP_002017=YES

# Dump AIRCFT and AIRCAR with wide time window to improve PREPOBS_PREPACQC
#  track-check performance
#  (time window will be winnowed down to +/- 3.00 hours in output from
#   PREPOBS_PREPACQC)

# Dump PROFLR with wide time window to improve PREPOBS_PROFCQC performance
#  (time window will be winnowed down in output from PREPOBS_PROFCQC, see
#   parm cards for output time window)

# Dump GPSIPW with narrow (+/- 3-min) time window since new Ground Based
#  GPS-IPW/ZTD (from U.S.-ENI and foreign GNSS providers) is currently limited
#  to obs only at cycle-time

DTIM_earliest_aircft=${DTIM_earliest_aircft:-"-3.25"}
DTIM_latest_aircft=${DTIM_latest_aircft:-"+3.25"}

DTIM_earliest_aircar=${DTIM_earliest_aircar:-"-3.25"}
DTIM_latest_aircar=${DTIM_latest_aircar:-"+3.25"}

DTIM_earliest_proflr=${DTIM_earliest_proflr:-"-4.00"}
DTIM_latest_proflr=${DTIM_latest_proflr:-"+3.99"}

DTIM_latest_vadwnd=${DTIM_latest_vadwnd:-"+2.99"}
DTIM_latest_rassda=${DTIM_latest_rassda:-"+2.99"}

DTIM_earliest_gpsipw=${DTIM_latest_gpsipw:-"-0.05"}
DTIM_latest_gpsipw=${DTIM_latest_gpsipw:-"+0.05"}

TIME_TRIM=${TIME_TRIM:-${TIME_TRIM4:-on}}

$ushscript_dump/bufr_dump_obs.sh $dumptime 3.0 1 aircar aircft proflr vadwnd \
 rassda gpsipw hdob 
error4=$?
echo "$error4" > $DATA/error4

if [ "$SENDDBN" = "YES" ]; then
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_aircar $job \
    ${COMSP}aircar.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_aircft $job \
    ${COMSP}aircft.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_proflr $job \
    ${COMSP}proflr.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_vadwnd $job \
    ${COMSP}vadwnd.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_rassda $job \
    ${COMSP}rassda.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_gpsipw $job \
    ${COMSP}gpsipw.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_hdob $job \
    ${COMSP}hdob.tm00.bufr_d
fi

set +x
echo "********************************************************************"
echo Script thread_4
echo Finished executing on node  `hostname`
echo Ending time  : `date -u`
echo "********************************************************************"
set -x
} > $DATA/4.out 2>&1
EOF
set -x

set +x
#----------------------------------------------------------------
cat<<\EOF>thread_5; chmod +x thread_5
set -uax

cd $DATA

{ echo
set +x
echo "********************************************************************"
echo Script thread_5
echo Executing on node  `hostname`
echo Starting time: `date -u`
echo "********************************************************************"
echo
set -x

sleep ${NAP} # to reverse 10min early start of jglobal_dump in cron
export STATUS=NO
export DUMP_NUMBER=5

#===================================================================
# NOTES ABOUT THIS DUMP GROUP:
#   (1) time window radius is -3.00 to +2.99 hours on all types 
#   (2) TIME TRIMMING IS NOT DONE IN THIS DUMP (default, unless overridden)
#
#--------------------------------------------------------------------------
# Currently not executed in GDAS or GFS:
# Dump # 5 : MSONET: 30 subtype(s)
#            ---------------------
#            TOTAL NUMBER OF SUBTYPES = 30
#
#===================================================================

DTIM_latest_msonet=${DTIM_latest_msonet:-"+2.99"}

TIME_TRIM=${TIME_TRIM:-${TIME_TRIM5:-off}}

$ushscript_dump/bufr_dump_obs.sh $dumptime 3.0 1 msonet
error5=$?
echo "$error5" > $DATA/error5

set +x
echo "********************************************************************"
echo Script thread_5
echo Finished executing on node  `hostname`
echo Ending time  : `date -u`
echo "********************************************************************"
set -x
} > $DATA/5.out 2>&1
EOF
set -x

set +x
#----------------------------------------------------------------
cat<<\EOF>thread_6; chmod +x thread_6
set -uax

cd $DATA

{ echo
set +x
echo "********************************************************************"
echo Script thread_6
echo Executing on node  `hostname`
echo Starting time: `date -u`
echo "********************************************************************"
echo
set -x

sleep ${NAP} # to reverse 10min early start of jglobal_dump in cron
export STATUS=NO
export DUMP_NUMBER=6

#===================================================================
# NOTES ABOUT THIS DUMP GROUP:
#   (1) time window radius is -3.00 to +2.99 hours on all types
#   (2) TIME TRIMMING IS NOT DONE IN THIS DUMP (default, unless overridden)
#
#--------------------------------------------------------------------------
# Currently not executed in GDAS or GFS:
# Dump # 6 : NEXRAD: 8 subtype(s)
#            --------------------
#            TOTAL NUMBER OF SUBTYPES = 8
#
#===================================================================

DTIM_latest_nexrad=${DTIM_latest_nexrad:-"+2.99"}

TIME_TRIM=${TIME_TRIM:-${TIME_TRIM6:-off}}

# NEXRAD tanks are hourly
# Process only those hourly tanks w/i requested dump center cycle time window

SKIP_006010=YES # radial wind  00Z
SKIP_006011=YES # radial wind  01Z
SKIP_006012=YES # radial wind  02Z
SKIP_006013=YES # radial wind  03Z
SKIP_006014=YES # radial wind  04Z
SKIP_006015=YES # radial wind  05Z
SKIP_006016=YES # radial wind  06Z
SKIP_006017=YES # radial wind  07Z
SKIP_006018=YES # radial wind  08Z
SKIP_006019=YES # radial wind  09Z
SKIP_006020=YES # radial wind  10Z
SKIP_006021=YES # radial wind  11Z
SKIP_006022=YES # radial wind  12Z
SKIP_006023=YES # radial wind  13Z
SKIP_006024=YES # radial wind  14Z
SKIP_006025=YES # radial wind  15Z
SKIP_006026=YES # radial wind  16Z
SKIP_006027=YES # radial wind  17Z
SKIP_006028=YES # radial wind  18Z
SKIP_006029=YES # radial wind  19Z
SKIP_006030=YES # radial wind  20Z
SKIP_006031=YES # radial wind  21Z
SKIP_006032=YES # radial wind  22Z
SKIP_006033=YES # radial wind  23Z

SKIP_006040=YES # reflectivity 00Z
SKIP_006041=YES # reflectivity 01Z
SKIP_006042=YES # reflectivity 02Z
SKIP_006043=YES # reflectivity 03Z
SKIP_006044=YES # reflectivity 04Z
SKIP_006045=YES # reflectivity 05Z
SKIP_006046=YES # reflectivity 06Z
SKIP_006047=YES # reflectivity 07Z
SKIP_006048=YES # reflectivity 08Z
SKIP_006049=YES # reflectivity 09Z
SKIP_006050=YES # reflectivity 10Z
SKIP_006051=YES # reflectivity 11Z
SKIP_006052=YES # reflectivity 12Z
SKIP_006053=YES # reflectivity 13Z
SKIP_006054=YES # reflectivity 14Z
SKIP_006055=YES # reflectivity 15Z
SKIP_006056=YES # reflectivity 16Z
SKIP_006057=YES # reflectivity 17Z
SKIP_006058=YES # reflectivity 18Z
SKIP_006059=YES # reflectivity 19Z
SKIP_006060=YES # reflectivity 20Z
SKIP_006061=YES # reflectivity 21Z
SKIP_006062=YES # reflectivity 22Z
SKIP_006063=YES # reflectivity 23Z

if [ $cycp -eq 00 ]; then   # (22.5 - 01.5 Z)
   unset SKIP_006032 # radial wind  22Z
   unset SKIP_006033 # radial wind  23Z
   unset SKIP_006010 # radial wind  00Z
   unset SKIP_006011 # radial wind  01Z
   unset SKIP_006062 # reflectivity 22Z
   unset SKIP_006063 # reflectivity 23Z
   unset SKIP_006040 # reflectivity 00Z
   unset SKIP_006041 # reflectivity 01Z
elif [ $cycp -eq 06 ]; then # (04.5 - 07.5 Z)
   unset SKIP_006014 # radial wind  04Z
   unset SKIP_006015 # radial wind  05Z
   unset SKIP_006016 # radial wind  06Z
   unset SKIP_006017 # radial wind  07Z
   unset SKIP_006044 # reflectivity 04Z
   unset SKIP_006045 # reflectivity 05Z
   unset SKIP_006046 # reflectivity 06Z
   unset SKIP_006047 # reflectivity 07Z
elif [ $cycp -eq 12 ]; then # (10.5 - 13.5 Z)
   unset SKIP_006020 # radial wind  10Z
   unset SKIP_006021 # radial wind  11Z
   unset SKIP_006022 # radial wind  12Z
   unset SKIP_006023 # radial wind  13Z
   unset SKIP_006050 # reflectivity 10Z
   unset SKIP_006051 # reflectivity 11Z
   unset SKIP_006052 # reflectivity 12Z
   unset SKIP_006053 # reflectivity 13Z
elif [ $cycp -eq 18 ]; then # (16.5 - 19.5 Z)
   unset SKIP_006026 # radial wind  16Z
   unset SKIP_006027 # radial wind  17Z
   unset SKIP_006028 # radial wind  18Z
   unset SKIP_006029 # radial wind  19Z
   unset SKIP_006056 # reflectivity 16Z
   unset SKIP_006057 # reflectivity 17Z
   unset SKIP_006058 # reflectivity 18Z
   unset SKIP_006059 # reflectivity 19Z
fi

$ushscript_dump/bufr_dump_obs.sh $dumptime 3.0 1 nexrad
error6=$?
echo "$error6" > $DATA/error6

set +x
echo "********************************************************************"
echo Script thread_6
echo Finished executing on node  `hostname`
echo Ending time  : `date -u`
echo "********************************************************************"
set -x
} > $DATA/6.out 2>&1
EOF
set -x

set +x
#------------------------------------------------------------------------------
cat<<\EOF>thread_7; chmod +x thread_7
set -uax

cd $DATA

{ echo
set +x
echo "********************************************************************"
echo Script thread_7
echo Executing on node  `hostname`
echo Starting time: `date -u`
echo "********************************************************************"
echo
set -x

sleep ${NAP} # to reverse 10min early start of jglobal_dump in cron
export STATUS=NO
export DUMP_NUMBER=7

#=========================================================================
# NOTES ABOUT THIS DUMP GROUP:
#   (1) time window radius is -3.00 to +2.99 hours on all types
#   (2) TIME TRIMMING IS NOT DONE IN THIS DUMP (default, unless overridden)
#
#--------------------------------------------------------------------------
# Dump # 7 : AVCSPM: 1 subtype(s)
#            ESMHS:  1 subtype(s)
#            1BMHS:  1 subtype(s)
#            AIRSEV: 1 subtype(s)
#            ATMSDB: 1 subtype(s)
#            GOME:   1 subtype(s)
#            OMI:    1 subtype(s)
#            TRKOB:  1 subtype(s)
#            GPSRO:  1 subtype(s)
#            CRISF4: 1 subtype(s) (if present in past 10 days of tanks)
#            --------------------
#            TOTAL NUMBER OF SUBTYPES = 10
#
#=========================================================================

DTIM_latest_avcspm=${DTIM_latest_avcspm:-"+2.99"}
DTIM_latest_esmhs=${DTIM_latest_esmhs:-"+2.99"}
DTIM_latest_1bmhs=${DTIM_latest_1bmhs:-"+2.99"}
DTIM_latest_airsev=${DTIM_latest_airsev:-"+2.99"}
DTIM_latest_atmsdb=${DTIM_latest_atmsdb:-"+2.99"}
DTIM_latest_gome=${DTIM_latest_gome:-"+2.99"}
DTIM_latest_omi=${DTIM_latest_omi:-"+2.99"}
DTIM_latest_trkob=${DTIM_latest_trkob:-"+2.99"}
DTIM_latest_gpsro=${DTIM_latest_gpsro:-"+2.99"}
#-----------------------------------------------
# check for crisf4 tank presence in past 10 days
crisf4=""
err_check_tanks=0
sh $USHbufr_dump/check_tanks.sh crisf4
err_check_tanks=$?
if [ $err_check_tanks -eq 0 ];then
   crisf4=crisf4
   DTIM_latest_crisf4=${DTIM_latest_crisf4:-"+2.99"}
fi
#-----------------------------------------------

TIME_TRIM=${TIME_TRIM:-${TIME_TRIM7:-off}}

$ushscript_dump/bufr_dump_obs.sh $dumptime 3.0 1 avcspm esmhs 1bmhs \
 airsev atmsdb gome omi trkob gpsro $crisf4
error7=$?
echo "$error7" > $DATA/error7

if [ "$SENDDBN" = "YES" ]; then
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_avcspm $job \
    ${COMSP}avcspm.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_esmhs $job \
    ${COMSP}esmhs.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_1bmhs $job \
    ${COMSP}1bmhs.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_airsev $job \
    ${COMSP}airsev.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_atmsdb $job \
    ${COMSP}atmsdb.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_gome $job \
    ${COMSP}gome.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_omi $job \
    ${COMSP}omi.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_trkob $job \
    ${COMSP}trkob.tm00.bufr_d
# gpsro dump file has nr version which is alerted from
# exdump_post.sh.ecf
  $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_gpsro $job \
   ${COMSP}gpsro.tm00.bufr_d
   if [ "$crisf4" = crisf4 ];then
      $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_crisf4 $job \
       ${COMSP}crisf4.tm00.bufr_d
   fi
fi

set +x
echo "********************************************************************"
echo Script thread_7
echo Finished executing on node  `hostname`
echo Ending time  : `date -u`
echo "********************************************************************"
set -x
} > $DATA/7.out 2>&1
EOF
set -x

set +x
#----------------------------------------------------------------
cat<<\EOF>thread_8; chmod +x thread_8
set -uax

cd $DATA

{ echo
set +x
echo "********************************************************************"
echo Script thread_8
echo Executing on node  `hostname`
echo Starting time: `date -u`
echo "********************************************************************"
echo
set -x

sleep ${NAP} # to reverse 10min early start of jglobal_dump in cron
export STATUS=NO
export DUMP_NUMBER=8

#=======================================================================
# NOTES ABOUT THIS DUMP GROUP:
#   (1) time window radius is +/- 1.5 hrs for all SATWND types
#       EXCEPT: SATWND subtypes 005/030, 005/031, 005/032, 005/034, 005/039,
#               005/064, 005/065, 005/066, 005/067, 005/068, 005/069,
#               005/070, 005/071, 005/072, 005/080 and 005/091
#               where it is
#               -3.00 to +2.99 hours.
#   (2) TIME TRIMMING IS DONE IN THIS DUMP (default, unless overridden)
#
#--------------------------------------------------------------------------
# Dump # 8 : SATWND: 16 subtype(s)  (bufr_dumplist.v2.3.0)
#            --------------------- 
#            TOTAL NUMBER OF SUBTYPES = 25
#
#=======================================================================

ADD_satwnd="005024 005025 005026 005030 005031 005032 005034 005039 005072"

# Skip old bufr METEOSAT AMVs; for testing skip in trigger or version file
#export SKIP_005064=YES
#export SKIP_005065=YES
#export SKIP_005066=YES

# satwnd types
# ------------
DTIM_earliest_005024=${DTIM_earliest_005024:-"-3.00"}
DTIM_latest_005024=${DTIM_latest_005024:-"+2.99"}
DTIM_earliest_005025=${DTIM_earliest_005025:-"-3.00"}
DTIM_latest_005025=${DTIM_latest_005025:-"+2.99"}
DTIM_earliest_005026=${DTIM_earliest_005026:-"-3.00"}
DTIM_latest_005026=${DTIM_latest_005026:-"+2.99"}
DTIM_earliest_005030=${DTIM_earliest_005030:-"-3.00"}
DTIM_latest_005030=${DTIM_latest_005030:-"+2.99"}
DTIM_earliest_005031=${DTIM_earliest_005031:-"-3.00"}
DTIM_latest_005031=${DTIM_latest_005031:-"+2.99"}
DTIM_earliest_005032=${DTIM_earliest_005032:-"-3.00"}
DTIM_latest_005032=${DTIM_latest_005032:-"+2.99"}
DTIM_earliest_005034=${DTIM_earliest_005034:-"-3.00"}
DTIM_latest_005034=${DTIM_latest_005034:-"+2.99"}
DTIM_earliest_005039=${DTIM_earliest_005039:-"-3.00"}
DTIM_latest_005039=${DTIM_latest_005039:-"+2.99"}
DTIM_earliest_005064=${DTIM_earliest_005064:-"-3.00"}
DTIM_latest_005064=${DTIM_latest_005064:-"+2.99"}
DTIM_earliest_005065=${DTIM_earliest_005065:-"-3.00"}
DTIM_latest_005065=${DTIM_latest_005065:-"+2.99"}
DTIM_earliest_005066=${DTIM_earliest_005066:-"-3.00"}
DTIM_latest_005066=${DTIM_latest_005066:-"+2.99"}
DTIM_earliest_005067=${DTIM_earliest_005067:-"-3.00"}
DTIM_latest_005067=${DTIM_latest_005067:-"+2.99"}
DTIM_earliest_005068=${DTIM_earliest_005068:-"-3.00"}
DTIM_latest_005068=${DTIM_latest_005068:-"+2.99"}
DTIM_earliest_005069=${DTIM_earliest_005069:-"-3.00"}
DTIM_latest_005069=${DTIM_latest_005069:-"+2.99"}
DTIM_earliest_005070=${DTIM_earliest_005070:-"-3.00"}
DTIM_latest_005070=${DTIM_latest_005070:-"+2.99"}
DTIM_earliest_005071=${DTIM_earliest_005071:-"-3.00"}
DTIM_latest_005071=${DTIM_latest_005071:-"+2.99"}
DTIM_earliest_005072=${DTIM_earliest_005072:-"-3.00"}
DTIM_latest_005072=${DTIM_latest_005072:-"+2.99"}
DTIM_earliest_005080=${DTIM_earliest_005080:-"-3.00"}
DTIM_latest_005080=${DTIM_latest_005080:-"+2.99"}
DTIM_earliest_005081=${DTIM_earliest_005081:-"-3.00"}
DTIM_latest_005081=${DTIM_latest_005081:-"+2.99"}
DTIM_earliest_005091=${DTIM_earliest_005091:-"-3.00"}
DTIM_latest_005091=${DTIM_latest_005091:-"+2.99"}



TIME_TRIM=${TIME_TRIM:-${TIME_TRIM8:-on}}

$ushscript_dump/bufr_dump_obs.sh $dumptime 1.5 1 satwnd
error8=$?
echo "$error8" > $DATA/error8

if [ "$SENDDBN" = "YES" ]; then
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_satwnd $job \
    ${COMSP}satwnd.tm00.bufr_d
fi

set +x
echo "********************************************************************"
echo Script thread_8
echo Finished executing on node  `hostname`
echo Ending time  : `date -u`
echo "********************************************************************"
set -x
} > $DATA/8.out 2>&1
EOF
set -x

set +x
#----------------------------------------------------------------
cat<<\EOF>thread_9; chmod +x thread_9
set -uax

cd $DATA

{ echo
set +x
echo "********************************************************************"
echo Script thread_9
echo Executing on node  `hostname`
echo Starting time: `date -u`
echo "********************************************************************"
echo
set -x

sleep ${NAP} # to reverse 10min early start of jglobal_dump in cron
export STATUS=NO
export DUMP_NUMBER=9

#=======================================================================
# NOTES ABOUT THIS DUMP GROUP:
#   (1) time window radius is -3.00 to +2.99 hours on all types
#       EXCEPT:  GEOIMR where it is -0.50 to +0.50 hour
#   (2) TIME TRIMMING IS DONE IN THIS DUMP (default, unless overridden)
#
#--------------------------------------------------------------------------
# Dump # 9 : GEOIMR: 1 subtype(s)
#            GMI1CR: 1 subtype(s)
#            SATWHR: 1 subtype(s)
#            -------------------- 
#            TOTAL NUMBER OF SUBTYPES = 3
#
#=======================================================================
DTIM_earliest_gmi1cr=${DTIM_earliest_gmi1cr:-"-3.00"}
DTIM_latest_gmi1cr=${DTIM_latest_gmi1cr:-"+2.99"}

DTIM_earliest_satwhr=${DTIM_earliest_satwhr:-"-3.00"}
DTIM_latest_satwhr=${DTIM_latest_satwhr:-"+2.99"}

DTIM_earliest_geoimr=${DTIM_earliest_geoimr:-"-0.50"}
DTIM_latest_geoimr=${DTIM_latest_geoimr:-"+0.50"}

TIME_TRIM=${TIME_TRIM:-${TIME_TRIM9:-on}}

$ushscript_dump/bufr_dump_obs.sh $dumptime 3.0 1 geoimr gmi1cr satwhr

error9=$?
echo "$error9" > $DATA/error9

if [ "$SENDDBN" = "YES" ]; then
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_geoimr $job \
    ${COMSP}geoimr.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_gmi1cr $job \
    ${COMSP}gmi1cr.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_satwhr $job \
    ${COMSP}satwhr.tm00.bufr_d
fi

set +x
echo "********************************************************************"
echo Script thread_9
echo Finished executing on node  `hostname`
echo Ending time  : `date -u`
echo "********************************************************************"
set -x
} > $DATA/9.out 2>&1
EOF
set -x

set +x
#------------------------------------------------------------------------------
cat<<\EOF>thread_10; chmod +x thread_10
set -uax

cd $DATA

{ echo
set +x
echo "********************************************************************"
echo Script thread_10
echo Executing on node  `hostname`
echo Starting time: `date -u`
echo "********************************************************************"
echo
set -x

sleep ${NAP} # to reverse 10min early start of jglobal_dump in cron
export STATUS=NO
export DUMP_NUMBER=10

#=========================================================================
# NOTES ABOUT THIS DUMP GROUP:
#   (1) time window radius is -3.00 to +2.99 hours on all types
#   (2) TIME TRIMMING IS NOT DONE IN THIS DUMP (default, unless overridden)
#
#--------------------------------------------------------------------------
# Dump #10 : ESIASI: 1 subtype(s)
#            MTIASI: 1 subtype(s)
#            ESAMUA: 1 subtype(s)
#            SEVASR: 1 subtype(s)
#            1BAMUA: 1 subtype(s)
#            BATHY:  1 subtype(s)
#            OSBUV8: 1 subtype(s)
#            OMPSN8: 1 subtype(s)
#            OMPST8: 1 subtype(s)
#            GSRASR: 1 subtype(s)
#            OMPSLP: 1 subtype(s)
#            --------------------
#            TOTAL NUMBER OF SUBTYPES = 13
#
#=========================================================================

DTIM_latest_esiasi=${DTIM_latest_esiasi:-"+2.99"}
DTIM_latest_mtiasi=${DTIM_latest_mtiasi:-"+2.99"}
DTIM_latest_esamua=${DTIM_latest_esamua:-"+2.99"}
DTIM_latest_sevasr=${DTIM_latest_sevasr:-"+2.99"}
DTIM_latest_1bamua=${DTIM_latest_1bamua:-"+2.99"}
DTIM_latest_bathy=${DTIM_latest_bathy:-"+2.99"}
DTIM_latest_osbuv8=${DTIM_latest_osbuv8:-"+2.99"}
DTIM_latest_ompsn8=${DTIM_latest_ompsn8:-"+2.99"}
DTIM_latest_ompst8=${DTIM_latest_ompst8:-"+2.99"}
DTIM_latest_gsrasr=${DTIM_latest_gsrasr:-"+2.99"}
DTIM_latest_ompslp=${DTIM_latest_ompslp:-"+2.99"}
DTIM_latest_sstvpw=${DTIM_latest_sstvpw:-"+2.99"}

TIME_TRIM=${TIME_TRIM:-${TIME_TRIM10:-off}}

$ushscript_dump/bufr_dump_obs.sh $dumptime 3.0 1 esiasi mtiasi esamua \
 sevasr 1bamua bathy osbuv8 ompsn8 ompst8 gsrasr ompslp sstvpw
error10=$?
echo "$error10" > $DATA/error10

if [ "$SENDDBN" = "YES" ]; then
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_esiasi $job \
    ${COMSP}esiasi.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_mtiasi $job \
    ${COMSP}mtiasi.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_esamua $job \
    ${COMSP}esamua.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_sevasr $job \
    ${COMSP}sevasr.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_1bamua $job \
    ${COMSP}1bamua.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_bathy $job \
    ${COMSP}bathy.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_osbuv8 $job \
    ${COMSP}osbuv8.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_ompsn8 $job \
    ${COMSP}ompsn8.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_ompst8 $job \
    ${COMSP}ompst8.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_gsrasr $job \
    ${COMSP}gsrasr.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_ompslp $job \
    ${COMSP}ompslp.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_sstvpw $job \
    ${COMSP}sstvpw.tm00.bufr_d
fi

set +x
echo "********************************************************************"
echo Script thread_10
echo Finished executing on node  `hostname`
echo Ending time  : `date -u`
echo "********************************************************************"
set -x
} > $DATA/10.out 2>&1
EOF
set -x

set +x
#------------------------------------------------------------------------------
cat<<\EOF>thread_11; chmod +x thread_11
set -uax

cd $DATA

{ echo
set +x
echo "********************************************************************"
echo Script thread_11
echo Executing on node  `hostname`
echo Starting time: `date -u`
echo "********************************************************************"
echo
set -x

sleep ${NAP} # to reverse 10min early start of jglobal_dump in cron
export STATUS=NO
export DUMP_NUMBER=11

#=========================================================================
# NOTES ABOUT THIS DUMP GROUP:
#   (1) time window radius is -3.00 to +2.99 hours on all types
#   (2) TIME TRIMMING IS NOT DONE IN THIS DUMP (default, unless overridden)
#
#--------------------------------------------------------------------------
# Dump #11 : AMSR2:  1 subtype(s)
#            --------------------
#            TOTAL NUMBER OF SUBTYPES = 1
#
#=========================================================================

DTIM_latest_amsr2=${DTIM_latest_amsr2:-"+2.99"}

TIME_TRIM=${TIME_TRIM:-${TIME_TRIM11:-off}}

$ushscript_dump/bufr_dump_obs.sh $dumptime 3.0 1 amsr2
error11=$?
echo "$error11" > $DATA/error11

if [ "$SENDDBN" = "YES" ]; then
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_amsr2 $job \
    ${COMSP}amsr2.tm00.bufr_d
fi

set +x
echo "********************************************************************"
echo Script thread_11
echo Finished executing on node  `hostname`
echo Ending time  : `date -u`
echo "********************************************************************"
set -x
} > $DATA/11.out 2>&1
EOF
set -x

set +x
#----------------------------------------------------------------
cat<<\EOF>thread_12; chmod +x thread_12
set -uax

cd $DATA

{ echo
set +x
echo "********************************************************************"
echo Script thread_12
echo Executing on node  `hostname`
echo Starting time: `date -u`
echo "********************************************************************"
echo
set -x

sleep ${NAP} # to reverse 10min early start of jglobal_dump in cron
export STATUS=NO
export DUMP_NUMBER=12

#=========================================================================
# NOTES ABOUT THIS DUMP GROUP:
#   (1) time window radius is -3.00 to +2.99 hours on all types
#   (2) TIME TRIMMING IS NOT DONE IN THIS DUMP (default, unless overridden)
#
#--------------------------------------------------------------------------
# Dump # 12 : ATMS:   1 subtype(s) (if present in past 10 days of tanks)
#             CRISFS: 1 subtype(s) (if present in past 10 days of tanks)
#             CRSFDB: 1 subtype(s)
#             IASIDB: 1 subtype(s)
#             --------------------
#             TOTAL NUMBER OF SUBTYPES = 4
#
#=========================================================================
#-----------------------------------------------
#-----------------------------------------------
# check for atms tank presence in past 10 days
atms=""
err_check_tanks=0
sh $USHbufr_dump/check_tanks.sh atms
err_check_tanks=$?
if [ $err_check_tanks -eq 0 ];then
   atms=atms
   DTIM_latest_atms=${DTIM_latest_atms:-"+2.99"}
fi
#-----------------------------------------------
#-----------------------------------------------
# check for crisfs tank presence in past 10 days
crisfs=""
err_check_tanks=0
sh $USHbufr_dump/check_tanks.sh crisfs
err_check_tanks=$?
if [ $err_check_tanks -eq 0 ];then
   crisfs=crisfs
   DTIM_latest_crisfs=${DTIM_latest_crisfs:-"+2.99"}
fi
#-----------------------------------------------

DTIM_latest_crsfdb=${DTIM_latest_crsfdb:-"+2.99"}
DTIM_latest_iasidb=${DTIM_latest_iasidb:-"+2.99"}

TIME_TRIM=${TIME_TRIM:-${TIME_TRIM1:-off}}

$ushscript_dump/bufr_dump_obs.sh $dumptime 3.0 1 $atms $crisfs crsfdb iasidb
error12=$?
echo "$error12" > $DATA/error12

if [ "$SENDDBN" = "YES" ]; then
   if [ "$atms" = atms ];then
      $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_atms $job \
       ${COMSP}atms.tm00.bufr_d
   fi
####### ALERTS TURNED OFF UNTIL REQUESTED BY USER #########################
#  if [ "$crisfs" = crisfs ];then
#     $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_crisfs $job \
#      ${COMSP}crisfs.tm00.bufr_d
#  fi
###########################################################################
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_crsfdb $job \
    ${COMSP}crsfdb.tm00.bufr_d
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_iasidb $job \
    ${COMSP}iasidb.tm00.bufr_d
fi

set +x
echo "********************************************************************"
echo Script thread_12
echo Finished executing on node  `hostname`
echo Ending time  : `date -u`
echo "********************************************************************"
set -x
} > $DATA/12.out 2>&1
EOF
set -x

set +x
#----------------------------------------------------------------
cat<<\EOF>thread_13; chmod +x thread_13
set -uax

cd $DATA

{ echo
set +x
echo "********************************************************************"
echo Script thread_13
echo Executing on node  `hostname`
echo Starting time: `date -u`
echo "********************************************************************"
echo
set -x

# UPRAIR requires early start, no need to NAP
#sleep ${NAP} # to reverse 10min early start of jglobal_dump in cron
export STATUS=NO
export DUMP_NUMBER=13

#====================================================================
# NOTES ABOUT THIS DUMP GROUP:
#   (1) time window radius is -3.00 to +2.99 hours on all types
#   (2) TIME TRIMMING IS NOT DONE IN THIS DUMP (default, unless overridden)
#
#--------------------------------------------------------------------------
# Dump #13:   UPRAIR: 5 subtype(s)
#            --------------------
#            TOTAL NUMBER OF SUBTYPES = 5
#
#====================================================================

DTIM_latest_uprair=${DTIM_latest_uprair:-"+2.99"}

TIME_TRIM=${TIME_TRIM:-${TIME_TRIM13:-off}}

$ushscript_dump/bufr_dump_obs.sh $dumptime 3.0 1 uprair 
error13=$?
echo "$error13" > $DATA/error13

if [ "$SENDDBN" = "YES" ]; then
   $DBNROOT/bin/dbn_alert MODEL ${NET_uc}_BUFR_uprair $job \
    ${COMSP}uprair.tm00.bufr_d
fi

set +x
echo "********************************************************************"
echo Script thread_13
echo Finished executing on node  `hostname`
echo Ending time  : `date -u`
echo "********************************************************************"
set -x
} > $DATA/13.out 2>&1
EOF
set -x


#----------------------------------------------------------------
# Now launch the threads

#  determine local system name and type if available
#  -------------------------------------------------

SITE=${SITE:-""}

set +u
launcher=${launcher:-"cfp"}  # if not "cfp", threads will be run serially.

if [ "$launcher" = cfp ]; then
   > $DATA/poe.cmdfile
   echo "Running threads in parallel IG2023"
   myPDY=`date +\%Y\%m\%d\%H\%M\%S`
   echo "DATE IG2023 start " $myPDY
# To better take advantage of cfp, execute the longer running commands first.
# Some reordering was done here based on recent sample runtimes.

   #[ $DUMP_group3 = YES -a $ADPUPA_wait != YES ]  &&  echo ./thread_3 >> $DATA/poe.cmdfile
   [ $DUMP_group3 = YES ]  &&  echo ./thread_3 >> $DATA/poe.cmdfile # NAP_adpupa covers for ADPUPA_wait 
   [ $DUMP_group13 = YES ]  &&  echo ./thread_13 >> $DATA/poe.cmdfile
   [ $DUMP_group7 = YES ]  &&  echo ./thread_7 >> $DATA/poe.cmdfile  # moved up
   [ $DUMP_group1 = YES ]  &&  echo ./thread_1 >> $DATA/poe.cmdfile
   [ $DUMP_group5 = YES ]  &&  echo ./thread_5 >> $DATA/poe.cmdfile  # moved up
   [ $DUMP_group6 = YES ]  &&  echo ./thread_6 >> $DATA/poe.cmdfile  # moved up
   [ $DUMP_group8 = YES ]  &&  echo ./thread_8 >> $DATA/poe.cmdfile  # moved up
   [ $DUMP_group11 = YES ] &&  echo ./thread_11 >> $DATA/poe.cmdfile # moved up
   [ $DUMP_group10 = YES ] &&  echo ./thread_10 >> $DATA/poe.cmdfile # moved up
   [ $DUMP_group2 = YES ]  &&  echo ./thread_2 >> $DATA/poe.cmdfile
   [ $DUMP_group4 = YES ]  &&  echo ./thread_4 >> $DATA/poe.cmdfile
   [ $DUMP_group9 = YES ]  &&  echo ./thread_9 >> $DATA/poe.cmdfile
   [ $DUMP_group12 = YES ]  &&  echo ./thread_12 >> $DATA/poe.cmdfile

   if [ -s $DATA/poe.cmdfile ]; then
      export MP_CSS_INTERRUPT=yes
      launcher_DUMP=${launcher_DUMP:-mpiexec}
      NPROCS=${NPROCS:-14} # was 12
      $launcher_DUMP -np ${NPROCS} --cpu-bind verbose,core cfp $DATA/poe.cmdfile 2>&1 
      #$launcher_DUMP -np 14 --cpu-bind core cfp $DATA/poe.cmdfile 2>&1 # 1) 3)
      #$launcher_DUMP -np ${NPROCS} cfp $DATA/poe.cmdfile 2>&1 # 4) Carolyn Pasti suggestions
      errpoe=$?
      if [ $errpoe -ne 0 ]; then
         $DATA/err_exit "***FATAL: EXIT STATUS $errpoe RUNNING POE COMMAND FILE"
      fi
   else
      echo
      echo "==> There are no tasks in POE Command File - POE not run"
      echo
   fi
else
   echo "Running threads serially"
   [ $DUMP_group3 = YES -a $ADPUPA_wait != YES ]  &&  ./thread_3
   [ $DUMP_group1 = YES ]  &&  ./thread_1 
   [ $DUMP_group2 = YES ]  &&  ./thread_2 
   [ $DUMP_group4 = YES ]  &&  ./thread_4 
   [ $DUMP_group5 = YES ]  &&  ./thread_5 
   [ $DUMP_group6 = YES ]  &&  ./thread_6 
   [ $DUMP_group7 = YES ]  &&  ./thread_7 
   [ $DUMP_group8 = YES ]  &&  ./thread_8 
   [ $DUMP_group9 = YES ]  &&  ./thread_9 
   [ $DUMP_group10 = YES ]  &&  ./thread_10 
   [ $DUMP_group11 = YES ]  &&  ./thread_11 
   [ $DUMP_group12 = YES ]  &&  ./thread_12 
   [ $DUMP_group13 = YES ]  &&  ./thread_13
#     wait
fi

# long run times for uprair lead to use of NAP and NAP_adpupa variables (see code above) instead of this code
#
##  if ADPUPA_wait is YES, adpupa and uprair are dumped AFTER all other dump
##   threads have run (normally done in real-time GFS runs to dump as late as
##   possible in order to maximize data availability in GFS network,
##   particularly DROPs)
##  --------------------------------------------------------------------------
##
#[ $DUMP_group3 = YES -a $ADPUPA_wait  = YES ]  &&  ./thread_3

cat $DATA/1.out $DATA/2.out $DATA/3.out $DATA/4.out $DATA/5.out $DATA/6.out $DATA/7.out $DATA/8.out $DATA/9.out $DATA/10.out $DATA/11.out $DATA/12.out $DATA/13.out

set +x
echo " "
echo " "
set -x

[ -s $DATA/error1 ] && err1=`cat $DATA/error1`
[ -s $DATA/error2 ] && err2=`cat $DATA/error2`
[ -s $DATA/error3 ] && err3=`cat $DATA/error3`
[ -s $DATA/error4 ] && err4=`cat $DATA/error4`
[ -s $DATA/error5 ] && err5=`cat $DATA/error5`
[ -s $DATA/error6 ] && err6=`cat $DATA/error6`
[ -s $DATA/error7 ] && err7=`cat $DATA/error7`
[ -s $DATA/error8 ] && err8=`cat $DATA/error8`
[ -s $DATA/error9 ] && err9=`cat $DATA/error9`
[ -s $DATA/error10 ] && err10=`cat $DATA/error10`
[ -s $DATA/error11 ] && err11=`cat $DATA/error11`
[ -s $DATA/error12 ] && err12=`cat $DATA/error12`
[ -s $DATA/error13 ] && err13=`cat $DATA/error13`


#===============================================================================

export STATUS=YES
export DUMP_NUMBER=14
$ushscript_dump/bufr_dump_obs.sh $dumptime 3.00 1 null

#  endif loop $PROCESS_DUMP
fi

echo " " >> $pgmout
echo "##################################################################\
####################"  >> $pgmout
echo " " >> $pgmout

#================================================================
#================================================================


if [ "$PROCESS_DUMP" = 'YES' ]; then

   if [ "$err1" -gt '5' -o "$err2" -gt '5' -o "$err3" -gt '5' -o \
        "$err4" -gt '5' -o "$err5" -gt '5' -o "$err6" -gt '5' -o \
        "$err7" -gt '5' -o "$err8" -gt '5' -o "$err9" -gt '5' -o \
        "$err10" -gt '5' -o "$err11" -gt '5' -o "$err12" -gt '5' -o "$err13" -gt '5']; then
      for n in $err1 $err2 $err3 $err4 $err5 $err6 $err7 $err8 $err9 $err10 $err11 $err12 $err13
      do
         if [ "$n" -gt '5' ]; then
            if [ "$n" -ne '11' -a "$n" -ne '22' ]; then
       
## fatal error in dumping of BUFR obs. files
       
               set +x
echo
echo " ###################################################### "
echo " --> > 22 RETURN CODE FROM DATA DUMP, $err1, $err2, $err3, $err4, \
$err5, $err6, $err7, $err8, $err9, $err10, $err11, $err12, $err13 "
echo " --> @@ F A T A L   E R R O R @@   --  ABNORMAL EXIT    "
echo " ###################################################### "
echo
               set -x
               $DATA/err_exit
               exit 9
            fi
         fi
      done

## a status code of 11 or 22 from dumping of BUFR obs. files
## is non-fatal but still worth noting

      set +x
      echo
      echo " ###################################################### "
      echo " --> > 5 RETURN CODE FROM DATA DUMP, $err1, $err2, $err3, $err4, \
$err5, $err6, $err7, $err8, $err9, $err10, $err11, $err12, $err13 "
      echo " --> NOT ALL DATA DUMP FILES ARE COMPLETE - CONTINUE    "
      echo " ###################################################### "
      echo
      set -x
   fi

#  endif loop $PROCESS_DUMP
fi

#
# copy bufr_dumplist to $COMOUT per NCO SPA request
# -------------------------------------------------
echo "Copy bufr_dumplist to comout"
LIST_cp=$COMOUT/${RUN}.t${cyc}z.bufr_dumplist.${tmmark}
cp ${FIXbufr_dump}/bufr_dumplist $LIST_cp 
chmod 644 $LIST_cp

# GOOD RUN
set +x
echo " "
echo " ****** PROCESSING COMPLETED NORMALLY"
echo " ****** PROCESSING COMPLETED NORMALLY"
echo " ****** PROCESSING COMPLETED NORMALLY"
echo " ****** PROCESSING COMPLETED NORMALLY"
echo " "
set -x


# save standard output
cat  break $pgmout break > allout
cat allout
# rm allout

sleep 10

msg='ENDED NORMALLY.'
$DATA/postmsg "$jlogfile" "$msg"

################## END OF SCRIPT #######################
