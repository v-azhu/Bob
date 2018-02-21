from datetime import timedelta as td,datetime as dt
import os,re,glob
import pyodbc
import logging
import traceback
import exceptions
#-------------------------------------------------------------------------------
# Name:        bobaudit
# Purpose:     EDW Deployment log audit
#
# Author:      Awen Zhu, Quin Arnold
#
# Created:     2014-09-28
# Copyright:   (c) Expedia Inc
#-------------------------------------------------------------------------------
_err_regexp_map={"SN01":{"DB2": {"LogFileNameRegExp":"[DEV|TEST|RC|MLN|PROD]EDW_",
                         "RegexpStart": "(DB\\d{5}E|SQL\d{4,}N)",
                         "RegexpEnd": "(?=\*{31}\\n\ERROR)",
                         "Failure": {"WLM":"SQL4712N",
                                    "MissingObj":"(SQL0204N|SQL2306N)",
                                    "DeadLock":"(SQL0204NW|SQL0911N)",
                                    "InvalidStatment":"(SQL0104N|SQL0198N)",
                                    "DuplicateName":"SQL0612N",
                                    "DuplicateTableNotCreated":"SQL0601N ",
                                    "ValueTooLong":"SQL0433N",
                                    "NoAuthorizedRoutine":"SQL0440N",
                                    "FailedConnectToDB2":"SQL20157N"}}},
                 "SN02":{"DB2": {"LogFileNameRegExp":"[DEV|TEST|RC|MLN|PROD]EDW_",
                         "RegexpStart": "Folder Not Found",
                         "RegexpEnd": "(?=\*{31}\\n\ERROR)",
                         "Failure": {"BadVBSFile":"Folder Not Found"}}},                 
                 "SN03":{"MSSQL": {"LogFileNameRegExp":"SQL",
                         "RegexpStart": "SQL Error!!",
                         "RegexpEnd": "(?=\*{31}\\n\ERROR)",
                         "Failure": {"DuplicateObj":"Native Error: 2714"}}},                 
                 "SN04":{"JIRA": {"LogFileNameRegExp":"BundleScreenOutput",
                         "RegexpStart": "\*{36}\sERROR\s\*{36}",
                         "RegexpEnd": "\\Z",
                         "Failure": {"BadStatus":"is not valid",
                                     "InvalidRequester":"is associated as a developer",
                                     "MadeChangeAfterSignoff":"Changes were made after jira signoff",
                                     "BadHotfixDate":"HotfixDate",
                                     "JiraNotExist":"jira Issue Does Not Exist"}}},                 
                 "SN05":{"Hadoop": {"LogFileNameRegExp":"edwbuild@",
                         "RegexpStart": "(\d{2}.\d{3}\sERROR\s|FAILED:|FATAL:|Exception)",
                         "RegexpEnd": "\\Z",
                         "Failure":{"TimeOut":"SocketTimeoutException",
                                    "MissingObjInHEMS":"There\sis\sno\sdataSource\swith\sname",
                                    "MissingObj":"Table\snot\sfound",
                                    "RunTimeError":"RuntimeException",
                                    "HiveDDLError":"hive\.ql\.exec\.DDLTask",
                                    "SemanticException":"SemanticException",
                                    "AccessControlException":"org\.apache\.hadoop\.security\.AccessControlException|java\.security\.AccessControlException",
                                    "HiveException":"org\.apache\.hadoop\.hive\.ql\.metadata\.HiveException"}}},
                 "SN06":{"InfaRep": {"LogFileNameRegExp":"^InfaLog__",
                         "RegexpStart": "(\.{3}\n\s\[|\*{50,})",
                         "RegexpEnd": "\\Z",
                         "Failure":{"PermissionDenied":"^Permission denied",
                                    "MissingSourceXML":"Unable to open input file",
                                    "Write-IntentLock":"\[REP_12990\]|\[REP_51459\]",
                                    "InvalidSourceParameters":"Invalid source parameters in the foldermap"}}},
                 "SN07":{"InfaLNX": {"LogFileNameRegExp":"infadm@",
                         "RegexpStart": "\\A",
                         "RegexpEnd": "\\Z",
                         "Failure":{"PermissionDenied":"Permission denied"}}},
                 "SN08":{"DB2": {"LogFileNameRegExp":"[DEV|TEST|RC|MLN|PROD]EDW_",
                         "RegexpStart": "File Not Found",
                         "RegexpEnd": "(?=\*{31}\\n\ERROR)",
                         "Failure": {"FileNotExist":"File Not Found"}}},
                 "SN09":{"DAS": {"LogFileNameRegExp":"dasdeploy@",
                         "RegexpStart": "\\A",
                         "RegexpEnd": "\\Z",
                         "Failure":{"PermissionDenied":"Permission denied"}}},
                 "SN10":{"Hadoop": {"LogFileNameRegExp":"edwbuild@",
                         "RegexpStart": "\\A",
                         "RegexpEnd": "\\Z",
                         "Failure":{"HadoopServerDisconnection":"Connection to (.*)? closed by remote host."}}},
                 "SN11":{"Guardian ": {"LogFileNameRegExp":"_BatFileContents",
                         "RegexpStart": "\\A",
                         "RegexpEnd": "\\Z",
                         "Failure":{"ImportRuleFailed":"ERROR: import rules into guardian"}}}
                }
logfile = os.path.basename(__file__).split('.')[0]+dt.strftime(dt.now(),'%Y%m%d')
logging.basicConfig(filename=logfile,
                 filemode='a',
                 format='%(levelname)s : %(asctime)s %(message)s', 
                 datefmt='%Y-%m-%d %H:%M:%S', 
                 level=logging.DEBUG)
class Deployment():  
    def __init__(self, bundleName, dbConn):
        logging.info("Starting process "+bundleName)
        self._bundleName = os.path.basename(bundleName)
        self._dbConn = dbConn
        self._rootCause = None
        self._lastErrorMessage = None
        try:
            #we need to reset _bundleRootDir if scanning Ops's deployment log
            self._bundleRootDir = os.path.abspath(os.path.join(bundleName, os.pardir))
            self._bundleLogDir = self._bundleRootDir +'\\'+ self._bundleName+r'\BusinessSystems\Common\DBBuild\db\release\ApplyBundledHotfixes_LOG'
            self._raidFiles = self._bundleRootDir+'\\'+self._bundleName+r'\BusinessSystems\Common\DBBuild\db\HotFix\Bundles\RaidFiles'
            #this can also scanning ops's deployment log, Ops's bundle name not like ours. We cannot get 
            #values by analyze bundle name.
            r = re.match('^(\d{5,})_(.*)_(.*)_(\d{14})$',self._bundleName)
            if r: 
                self._firstRaid = r.groups()[0]
                self._userId = r.groups()[1] if r.groups()[1] else os.getenv('username')
                self._env = r.groups()[2] if r.groups()[2] else 'PROD'
                self._bundleBuildTime = dt.strptime(r.groups()[3], "%Y%m%d%H%M%S") if r.groups()[3] else dt.fromtimestamp(os.path.getctime(self._bundleRootDir+'\\'+self._bundleName))
            else:
                self._userId = os.getenv('username')
                self._env = 'PROD'
                self._bundleBuildTime = dt.fromtimestamp(os.path.getctime(self._bundleRootDir+'\\'+self._bundleName))
            self._bundleDeployStartTime = dt.fromtimestamp(os.path.getctime(self._bundleLogDir)) if os.path.getctime(self._bundleLogDir) else None
        except Exception:
            self._include = False

    @property
    def bundleName(self):
        return self._bundleName
    @property
    def userId(self):
        return self._userId 
    @property
    def env(self):
        return self._env
    @property
    def createTime(self):
        return self._createTime
    
    @property
    def rootCause(self):
        return self._rootCause
    
    @rootCause.setter
    def rootCause(self,pRootCause):
        self._rootCause = pRootCause
    
    @property
    def lastErrorMessage(self):
        return self._lastErrorMessage
    
    @lastErrorMessage.setter
    def lastErrorMessage(self,plastErrorMessage):
        self._lastErrorMessage = plastErrorMessage
    
    @property
    def raids(self):
        if '_raids' not in self.__dict__:
            self._raids = ""
            _HotFixBundle = open(self._bundleRootDir+'/'+self._bundleName+'/BusinessSystems/Common/DBBuild/db/HotFix/Bundles/19990101DMODSHotFixBundle.bat').read()
            for n,r in enumerate(re.findall('deployment:DEP(\d+)',_HotFixBundle, re.M),start=1):
                self._raids = r if n<2 else self._raids+":"+r
        return self._raids
    
   
    @property
    def status(self):
        if not self.isBuildError():
            self._Status = 'Succeed' if self.isSucceed() else 'Failed'
        else:
            self._Status = 'Unknown'
        return self._Status
    
    @property
    def processID(self):
        if '_processId' not in self.__dict__:
            cursor = self._dbConn.cursor()
            row = cursor.execute("""SELECT Min(processid) processid 
                                    FROM   (SELECT processid 
                                            FROM   dbo.bundle_build_process_hist 
                                            WHERE  bundlename = ? 
                                            UNION 
                                            SELECT Max(processid) + 1 
                                            FROM   dbo.bundle_build_process_hist) t """,
            self._bundleName)
            self._processId = row.fetchone().processid
        return self._processId
    
    @property
    def runOn(self):
        pat=re.compile(r'^\\\\(.*?)\\')
        cn=pat.match(self._bundleRootDir)
        if cn:
            ro = cn.group(1)
        else:
            ro = os.getenv('computername')
        return ro
    
    @property
    def bundleBuildTime(self):
        return self._bundleBuildTime
    
    @property
    def bundleDeployStartTime(self):
        return self._bundleDeployStartTime
    
    def isBuildError(self):
        if os.path.isfile(self._bundleRootDir+'\\'+self._bundleName+'/BusinessSystems/Common/DBBuild/db/release/ApplyBundledHotfixes_LOG/bundleScreenOutput.txt'): 
            return False      
        else:
            self._rootCause = 'Build Error: Output.txt not found'
            self._lastErrorMessage = ''
            return True
    
    def isSucceed(self):
        vStatus=None
        if os.path.isfile(self._bundleLogDir + '/BundleScreenOutput.txt'):
            _bundleScreenOutput = open(self._bundleLogDir + '/BundleScreenOutput.txt','r').read()
        else:
            vStatus= False
        for r in self.raids.split(':'):
            s = re.search('<<<deployment:DEP' + r + ' Starting>>>', _bundleScreenOutput,re.MULTILINE)
            e = re.search('<<<deployment:' + r + ' Success>>>', _bundleScreenOutput, re.MULTILINE)
            olde = re.search('All done[\!]\n$', _bundleScreenOutput, re.MULTILINE)
            if (s and e) \
            or (not s and not e and olde):
                self._rootCause = 'Succeed'
                self._lastErrorMessage = None
                vStatus= True
            else:
                vStatus= False
        return vStatus
    
    def checkErrorLog(self):
        if not self.isSucceed():
            errLogFile = max(glob.iglob(self._bundleLogDir+'\\*.*'), key=os.path.getctime)
            logging.info("Error log file is : "+errLogFile)
            if errLogFile:
                errLogFileHandle = open(errLogFile,'r')
                logFile=errLogFileHandle.read()
                errLogFileHandle.close()
                #decide what kind of error occurred by checking latest log file name
                for ky in _err_regexp_map.iterkeys():
                    for key in _err_regexp_map[ky].iterkeys():     
                        if re.search(_err_regexp_map[ky][key]["LogFileNameRegExp"], os.path.basename(errLogFile), re.M):
                            logging.info("Parsing error for : "+key)
                            pat = re.compile(_err_regexp_map[ky][key]["RegexpStart"]+
                                            '.*?'
                                            +_err_regexp_map[ky][key]["RegexpEnd"],
                                            re.DOTALL)
                            errMsg = pat.search(logFile)
                            if errMsg:
                                vErrorMsgSnapshot = errMsg.group(0)
                                #looking error msg snapshot to find out root cause
                                for k,v in _err_regexp_map[ky][key]["Failure"].items():
                                    patRootCause = re.compile(v, re.M)
                                    vRootCause = patRootCause.search(vErrorMsgSnapshot)
                                    if vRootCause: #Break if matches any pattern of failures
                                        logging.info("Matches failure : "+k)
                                        vRootCause = k
                                        break
                                if vRootCause is None:
                                    vRootCause = "UnknownError"
                                    logging.info("Nothing matched")
                                self._rootCause = "["+key+"]:"+vRootCause
                                self._lastErrorMessage = vErrorMsgSnapshot
                            break
                        else:
                            logging.info(key+" can not matches log file name regexp " )
            else:
                logging.info("There is no log file yet.")
                self._rootCause="NotStarted"
                self._lastErrorMessage=None
      
def get_deployment_stats(pBundleDir):    
    #Bob's bundle
    dbconn = pyodbc.connect('DRIVER={SQL Server};SERVER=blsqldmohf02;DATABASE=applications')
    #d = Deployment(pBundleDir, dbconn)
    #Ops's bundle which manually run on their RDC box
    d = Deployment(pBundleDir,dbconn)
    d.checkErrorLog()
    logging.info("Process ID = %s" % d.processID)
    logging.info("Raids = %s" % d.raids)
    logging.info("BundleName = %s" % d.bundleName)
    logging.info("ENV = %s" % d.env)
    logging.info("Deployer = %s" % d.userId)
    logging.info("Bundle Created Date = %s" % d.bundleBuildTime)
    logging.info("Bundle Deploy Start Date = %s" % d.bundleDeployStartTime)
    logging.info("Root Cause = %s" % d.rootCause)
    logging.info("Last Error Message = %s" % d.lastErrorMessage)
    update_database(d, dbconn)
    dbconn.close()
def update_database(pDeployment,pConn):    
    cursor = pConn.cursor()    
    rows = cursor.execute("""update Bundle_Build_Process_Hist
                             set Status=?,RootCause=?, LastErrorMsg=?, RunOn=? 
                             where BundleName = ?""", 
                          pDeployment.status, 
                          pDeployment.rootCause,
                          pDeployment.lastErrorMessage, 
                          pDeployment.runOn,
                          pDeployment.bundleName).rowcount
    if rows > 1:
        print "Duplicates for bundle" + pDeployment.bundleName + " Bundle_Build_Process_Hist contains: " + str(rows) + " rows"
    elif rows == 0:
        rows = cursor.execute("""insert into Bundle_Build_Process_Hist(PROCESSID, RAID, BUILDBY, 
                                                                      ENV, STATUS, 
                                                                      COMMENTS, OPENEDBY, 
                                                                      OPENDATE, BundleName, 
                                                                      RunOn, RootCause,
                                                                      LastErrorMsg) 
                                select (select max(processid) + 1 from Bundle_Build_Process_Hist), 
                                        ?,?,?,?,?,?,?,?,?,?,?""",
                                pDeployment.raids, 
                                os.getenv('username'), 
                                pDeployment.env, 
                                pDeployment.status,
                                'Recovered by log audit', 
                                pDeployment.userId, 
                                pDeployment.bundleBuildTime, 
                                pDeployment.bundleName, 
                                pDeployment.runOn, 
                                pDeployment.rootCause, 
                                pDeployment.lastErrorMessage).rowcount
    else:
        logging.info("Updated Bundle_Build_Process_Hist table")
    cursor.commit()
if __name__ == '__main__':    
        searchDirs='d:\\raids'
        #searchDir='\\\\chexbldedw001\\raids'
        #serchDir=['\\\\esfvmvi-003\\raids','\\\\chexbldedw001\\raids','\\\\che-rdcedw02\\raids']
        #get_deployment_stats(searchDir+'\\99513_a-vlakshmi_MLN_20141010123154')
        for searchDir in searchDirs:
            logging.info("processing deployments on "+searchDir)
            Dirs = filter(None, glob.glob(searchDir+'\*'))
            Dirs.sort(key = lambda x: os.path.getctime(x),reverse=True)
            twohoursago = dt.now() - td(hours = 12)
            for f in Dirs:
                #utc->local, cannt handle conflicts of variables so hard code time zone here.
                localdate = dt.utcfromtimestamp(os.path.getctime(f)) - td(hours=8)   
                #looking for bundle created newer than 2 hours only
                if localdate > twohoursago:
                    try:
                        get_deployment_stats(f)
                    except IOError:
                        logging.error("Invalid bundle, Mostly reason is file or folder missing in the bundle.")
                        pass
                    except exceptions:
                        logging.error("An error occurred during log recover:\n"+''.join(traceback.format_exc()))