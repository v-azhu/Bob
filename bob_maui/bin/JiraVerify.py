#-------------------------------------------------------------------------------
# Name:        JiraVerify
# Purpose:     Verify the list of given deployments are ready to deploy to the given environment
#
# Author:      Awen Zhu, Quin Arnold
#
# Created:     2014-04-21
# Copyright:   (c) Expedia Inc
#Change History:
#  Date        Author         Description
#  ----------  -------------- ------------------------------------
#  2014-07-10  qarnold        Allow Code Reviewers to deploy
#                             Change error to warning for changes message
#  2014-07-28  v-azhu         Add project FSIT for jira issue looking up
#-------------------------------------------------------------------------------
import argparse
from jira.client import JIRA
from jira.exceptions import JIRAError
import subprocess,shlex,re
from datetime import timedelta,datetime as dt
import sys,os,traceback,getpass
from random import randrange
P4 = None
try:
    from P4 import P4, P4Exception
except:
    pass

import uuid
import pytz
from pytz import utc
pt = pytz.timezone('US/Pacific')

edw = "//depot/edw/Common/DBBuild/DEV/db/HotFix/Bundles/RaidFiles"
ldw = "//depot/dmo/Common/DBBuild/DEV/db/HotFix/Bundles/RaidFiles"

def parse_args():
    try:
        _parser = argparse.ArgumentParser(description='Verify the list of given deployments via Jira to see if they are ready to deploy to the given environment')
        _parser.add_argument('-u', '--p4user', type=str, default=None, 
                            help='Perforce user id')
        _parser.add_argument('-p', '--p4password', type=str, default=None, 
                            help='Perfore password')
        _parser.add_argument('-e', '--envName', type=str, default=os.getenv('envName', 'prod'),
                            help='Deployment environment (dev, test, maui, milan, prod)')
        _group = _parser.add_mutually_exclusive_group(required=False)
        _group.add_argument('-verbose', action='store_const', const=True, dest="verbose", default=False,
                            help="Turn debugging on with verbose messages")
        _group.add_argument('-debug', action="store_const", const=True, dest="debug", default=False,
                            help="Turn debug messages on")
        _parser.add_argument('deployments', nargs='+', 
                            type=int,
                            help="List of deployment reference numbers (raid, jira)" )

        _args = _parser.parse_args()
        if _args.verbose: _args.debug=True

    except Exception as e:
        _parser.parse_args(['--help'])
        raise e

    return _args 

"""
Print out standard alert with traceback  for unknown errors
"""
def _alert(messages, e, code0, code1, header, known):
    print header.center(79,"*")
    print "\n".join(messages)
    if not known:
        print "     " + str(type(e)) + ": " + str(e)
        print " "
        for tb in traceback.format_tb(sys.exc_info()[2]):
            for _ in tb.split('\n'):
                print "    " + _
    print header.center(79,"*")
    return code1 if code1 > code0 else code0
        
"""
for each of the given deployments,
get last updated timestamp of raidxxx.txt then compare with the signoff date for the given environment
check for a jira system error
check the signoff for each raid given
return the error level (if any)
"""
def checkSignoffs(p4user, p4password, envName, deployments):
    _errorlevel = 0
    
    for _depNbr in deployments:    
        try:
            _P4Results = \
                getLastUpdate(_depNbr, p4user, p4password) \
                if P4 else \
                cli_getLastUpdate(_depNbr, p4user, p4password) 
            _jiraResults = \
                getJiraData(_depNbr, envName)
    
            _user = getpass.getuser()
            if _user == 's-edwdeploy':
                _releasefolders = os.getcwd().split('\\')
                _buildFolder = _releasefolders[_releasefolders.index('release')-5]
                _user = _buildFolder.split('_')[1]
        
        except JIRAError as e:
            _known=e.status_code == 404
            _errorlevel = _alert(
                messages=["Deployment " + str(_depNbr) + ": jira " + e.text], 
                e=e, 
                code0=_errorlevel, 
                code1=e.status_code, 
                header=" ERROR ",
                known=_known)
            continue

        except Exception as e:
            if P4 and type(e) == P4Exception:
                _err_code,_invalid_password=(999, len(e.errors)==1 and 'password' in e.errors[0])
                _err_code, _file_not_found=(2, len(e.warnings)==1 and 'no such file' in e.warnings[0])
                _errorlevel = _alert(
                    messages=["Deployment " + str(_depNbr) + ": perforce:"] + e.errors + e.warnings,
                    e=e, 
                    code0=_errorlevel, 
                    code1=_err_code, 
                    header=" ERROR ",
                    known=_invalid_password or _file_not_found)
                if _errorlevel > 2: return _errorlevel
                continue

            if not P4 \
            and 'password' in e.message \
              or 'no such file' in e.message:
                _err_code, _invalid_password=(999, 'password' in e.message)
                _err_code, _file_not_found=(2, 'no such file' in e.message)
                _errorlevel = _alert(
                    messages=["Deployment " + str(_depNbr) + ": perforce:" + e.message],
                    e=e, 
                    code0=_errorlevel, 
                    code1=_err_code, 
                    header=" ERROR ",
                    known=_invalid_password or _file_not_found)
                if _errorlevel > 2: return _errorlevel
                continue

            _errorlevel = _alert(
                messages=["Deployment " + str(_depNbr) + ":"], 
                e=e, 
                code0=_errorlevel, 
                code1=999, 
                header=" ERROR ",
                known=False)
            continue

        _errorlevel = checkSignoff(_errorlevel, envName, _depNbr, _user, _P4Results, _jiraResults)

    return _errorlevel

"""
Check for any problems with the signoff and return the maximum errorlevel.
    jira hasn't been signed off
    raid.txt not found
    raid file was updated after sign off
    incorrect hotfix date
"""
def checkSignoff(errorlevel, envName, depNbr, user, P4Results, jiraResults):
    _warning = envName.lower() in ['dev', 'test']
    if not jiraResults:
        errorlevel = _alert(
            messages=[
                "Deployment " + str(depNbr) + ":",
                " Jira is down" + (". bypassing signoff check for " + envName  if _warning else ", please try again later")
                ], 
            e=None, 
            code0=errorlevel, 
            code1=0 if _warning else 1,
            header=" WARNING " if _warning else " ERROR ",
            known=True)
    
    if jiraResults \
    and user in [i.name for i in jiraResults.developerIds.values()] \
    and envName.lower() not in ['dev', 'test']:
        errorlevel = _alert(
            messages=[
                "Deployment " + str(depNbr) + ":",
                " The userid: " + user + " is associated as a developer for this deployment",
                " " + ', '.join([jiraResults.developerIds[i].displayName + '(' + i + ')'  for i in jiraResults.developerIds]),
                " Please have someone NOT in this list submit the deployment"
                ], 
            e=None, 
            code0=errorlevel, 
            code1=1,
            header=" ERROR ",
            known=True)
        
    if jiraResults \
    and jiraResults.statusFound \
    and jiraResults.statusFound not in jiraResults.statusValid:
        errorlevel = _alert(
            messages=[
                "Deployment " + str(depNbr) + ":",
                " Jira last deployment status:" + jiraResults.statusFound + " is not valid for " + envName + " environment",
                " Valid statuses are:" + ', '.join(jiraResults.statusValid)
                ], 
            e=None, 
            code0=errorlevel, 
            code1=0 if _warning else 1,
            header=" WARNING " if _warning else " ERROR ",
            known=True)

    if not jiraResults \
    or not jiraResults.signoff \
    or (jiraResults.statusFound == 'Deployment' \
    and envName.lower() == 'dev'):
        pass
    elif P4Results.LastUpdate > jiraResults.signoff:
        errorlevel = _alert(
            messages=[
                "Deployment " + str(depNbr) + ":",
                " Changes were made after jira signoff",
                " jira signoff for " + ', '.join(jiraResults.statusValid) + " at:"+str(jiraResults.signoff),
                " But it changed at:"+str(P4Results.LastUpdate)
                ],
            e=None, 
            code0=errorlevel, 
            code1=0 if _warning else 1,
            header=" WARNING " if _warning else " ERROR ",
            known=True)

    if envName.lower() in ['milan', 'prod'] \
    and str(jiraResults.hotfixDate) != str(dt.now().strftime('%Y-%m-%d 00:00:00')):
        errorlevel = _alert(
            messages=[
                "Deployment " + str(depNbr) + ":",
                " HotfixDate should be today, But is set :"+str(jiraResults.hotfixDate) 
                ],
            e=None, 
            code0=errorlevel, 
            code1=2,
            header=" ERROR ",
            known=True)

    return errorlevel

"""
Get perforce object
"""
def getP4(p4user, p4password):

    os.environ['p4config'] = ''
    os.environ['p4charset'] = ''
    
    _p4client=str(uuid.uuid4())
    _errorlevel = 0
    _p4 = P4(user=p4user, password=p4password, port='perforce:1985',charset='utf8', client=_p4client)
    return _p4
      
"""
get time for the most recent _P4Result for the given raid from perforce
"""
def getLastUpdate(depNbr, p4user, p4password):
    try:
        _p4 = getP4(p4user, p4password)
        _p4.connect()

    except Exception as e:
        raise exception("Error logging into perforce:\n" + e.message)
                
    _errors=[]
    for branch in (edw, ldw):
        try:
            _P4Results = _p4.run_filelog(branch + "/raid" + str(depNbr) + ".txt")[0].revisions

        except P4Exception as e:
            if len(e.warnings) == 1 and 'no such file' in e.warnings[0]:
                _errors.append(e)
                continue
            raise e
            
        if _P4Results and 'delete' not in _P4Results[0].action:
            _P4Result = _P4Results[0]
            _timeUTC = utc.localize(_P4Results[0].time)
            _timePT =  _timeUTC.astimezone(pt)
            _P4Result.depNbr = depNbr
            _P4Result.LastUpdate = _timePT
            return _P4Result

    raise _errors[0]
    return None, None

"""
support for w3k (or p4python not installed) - run perforce from commandline
get time for the most recent _P4Result for the given raid from perforce
"""
def cli_getLastUpdate(depNbr, p4user, p4password):
    p4client = str(uuid.uuid4())
    if p4user: 
        _cmd, _returncode, _stdout, _stderr = \
            _callcmd("echo " + p4password + " | p4 -u" + p4user + " -Hperforce -pperforce:1985 login", p4user, p4password)
        if _stderr:
            raise exception("Error logging into perforce:\n    " + _stderr)

    _errors=[]
    for branch in (edw, ldw):
        _cmd, _returncode, _stdout, _stderr = \
            _callcmd("p4 -c" + p4client + " -Hperforce -pperforce:1985" + " -Cutf8" + " filelog -m1 -t " + branch + "/raid" + str(depNbr) + ".txt")
        if _stderr:
            _errors.append(Exception("Error fetching raid" + str(depNbr) + " from perforce:\n    " + _stderr))
            continue

        reP4 = r'^//.*/raid(.*)\.txt\n... #\d* change (\d*) ([^\s]*) on ([^\s]*) ([^\s]*) by ([^\s]*)@[^\s]* .*$'
        r = re.match(reP4, _stdout, re.I |re.M)
    
        if not r:
            raise Exception("\nPerforce filelog command output:\n    " \
                + _stdout + "\n" \
                + "Did not match regular expression:\n    " \
                + reP4)
    
        rg = r.groups()
                
        _latest=_stdout.split(' ')
        _timeUTC = utc.localize(dt.strptime(rg[3] + 'T' + rg[4], "%Y/%m/%dT%H:%M:%S"))
        _timePT =  _timeUTC.astimezone(pt)
        _P4Results = lambda: None
        _P4Results.depNbr = int(rg[0])
        _P4Results.change = int(rg[1])
        _P4Results.time = rg[3]+'T'+rg[4]
        _P4Results.LastUpdate = _timePT
        _P4Results.action = rg[2]
        _P4Results.user = rg[5]
        return _P4Results

    raise _errors[0]
    return None

"""
support for w3k (or p4python not installed) - run perforce from commandline
Standard commandline call
"""
def _callcmd(cmd, user=None, password=None):
    cmdClean = cmd.replace(user, '@@@').replace(password,'@@@') if user else cmd
    _stdout=''
    p = None
    try:
        if debug: print 'Executing command:\n' + cmdClean
    
        args = shlex.split(cmd)
        p = subprocess.Popen(args, 
                             stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, 
                             universal_newlines=True)
        result = p.communicate(input=None)
        for out in result:
            if password and out: out = out.replace(user, '@@@').replace(password,'@@@')
    
        if debug: 
            print 'ReturnCode=' + str(p.returncode)
            for out in result:
                print out
    except Exception as e:
        raise e
        if p.returncode == 0: p.returncode = 999
        _alert(
            messages=['Command failed: ' + cmdClean], 
            e=e, 
            code0=0, 
            code1=p.returncode, 
            header=" ERROR ",
            known=False)
    
    return (cmdClean, p.returncode, result[0], result[1])

"""
get jira status being checked, when it was signed off for deployment for the given
environment, and the planned hotfixDate for the given itemKey and deployment environment
"""            
def getJiraData(depNbr, envName):
    _jira = JIRA(options={'server':'https://jira/jira', 'verify':False}
              ,basic_auth=('svc.edw.queryservice','changeme'))
    
    try:
        _issue = _jira.issue('EDW-' + str(depNbr), expand='changelog', fields='customfield_10406,customfield_11814,customfield_11843,customfield_11839')
    except JIRAError as e:
        if e.status_code == 503:
            _jiraResults = lambda: None
            return None
        elif e.status_code == 404:
            _issue = _jira.issue('FSIT-' + str(depNbr), expand='changelog', fields='customfield_10406,customfield_11814,customfield_11843,customfield_11839')
        else:
            raise e
            
    _statusAll = ['Development', 'Code Review', '2nd Code Review', 'QA', 'Deployment']
    _statusValid = ['Development', 'Code Review', '2nd Code Review', 'QA', 'Deployment'] if envName.lower() == 'dev' \
         else ['QA', 'Deployment'] if envName.lower() in ['test'] \
         else ['Deployment']
    _jiraResults = getSignoff(_issue.changelog.histories, _statusValid, _statusAll)
    _jiraResults.statusValid = _statusValid
    _jiraResults.developerIds = {}
    if _issue.fields.customfield_11814 is not None:
        _jiraResults.developerIds.update({'Developer':_issue.fields.customfield_11814})
#    if _issue.fields.customfield_11843 is not None:
#        _jiraResults.developerIds.update({'Code Review':_issue.fields.customfield_11843})
#    if _issue.fields.customfield_11839 is not None:
#        _jiraResults.developerIds.update({'2nd Code Review':_issue.fields.customfield_11839})
    _jiraResults.hotfixDate=dt.strptime(_issue.fields.customfield_10406, "%Y-%m-%d") if _issue.fields.customfield_10406 else None
    return _jiraResults

"""
get the signoff date(the date a history log entry was made) when the status was changed
"""
def getSignoff(histories, statusValid, statusAll):
    _jiraResults = lambda: None
    _jiraResults.signoff = None
    _jiraResults.statusFound = None
    for i in reversed(histories):
        for j in i.items:
            if j.field == 'status':
                _jiraResults.statusFound = j.toString
                if j.toString in statusValid:
                    _jiraResults.signoff = pt.localize(
                        dt.strptime(i.created[:19], "%Y-%m-%dT%H:%M:%S")
                        )
                    return _jiraResults
                if j.toString in statusAll:
                    return _jiraResults
    return _jiraResults

"""
main routine verify the list of given deployments are ready for the given environment
"""
if __name__ == '__main__':
    try:
        _args = parse_args()
        debug = _args.debug
        verbose = _args.verbose
    
    except Exception as e:
        sys.exit(_alert(
            messages=[
                "Error parsing arguments:",
                str(dir(e))], 
            e=e, 
            code0=_errorlevel, 
            code1=999, 
            header=" ERROR ",
            known=True))
    
    if debug: 
        for k,v in _args.__dict__.items():
            print k, (v if 'password' not in k else '@@@')

    sys.exit(checkSignoffs(_args.p4user, _args.p4password, _args.envName, _args.deployments))

"""
To get a list of test deployments:
workon Deploy
cd <JiraVerify folder>
python
import JiraVerify
from JiraVerify import *
JiraVerify.debug = False
def raidsGt90000(rg):
    return int(rg['depNbr']) > 90000

issues = JiraVerify._randomJiraList(20, raidsGt90000)
print ' '.join([i['depNbr'] for i in issues])
"""
def _randomJiraList(ct, selectRoutine=None):
    issues=[]
    for branch in (edw, ldw):
        for i in _callcmd('p4 files ' + branch + '/raid....txt')[2] \
            .split('\n'):
            r = re.match('^//.*/[Ra][Aa][Ii][Dd](\d{5})\.txt#\d* - ([a-z/]*) change (\d*) .*$', i, re.M)
            if r:
                rg = {'depNbr':r.groups()[0], 'action':r.groups()[1], 'change':r.groups()[2]}
                if selectRoutine == None \
                or  selectRoutine(rg):
                    issues.append(rg)
    
    randomIssues=[]
    for j in range(0,ct):
        idx = randrange(1,len(issues))
        if debug: print str(idx) + ', ' + str(issues[idx])
        randomIssues.append(issues[idx])
        issues.remove(issues[idx])
    
    return randomIssues


"""
Sample selection routine - gets dictionary with DepNbr, Type, and Changelist
"""
def selectRoutine(rg):
    return True