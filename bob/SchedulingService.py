from crontab import croniter
import inspect
from datetime import datetime as dt, timedelta
from Queue import Queue, Empty
from threading import Thread

_deployWindows = None
_scheduleDeploys = None
_requests = Queue()
_stop = object()

class DeployWindow():
    """
        DeployWindow:
            Describes a time frame given by a cron expression and a duration where a deployment window is either available for
            or blocked from any deployments of the given type.

            A deployment window can also have a limit to the number of deployments associated with the same window.  So for example
            if there is a limit of 4 long running jiras on any given day, if 4 have already been deployed, the next deployment time 
            given would be for the next following day.
    """
    _cmds = None
    
    def __init__ (self, cron_format, duration, types=['All'], available = None, block = None, name = None, year=None, limit=None, env=None):
        self._cron_format = cron_format
        self._duration = timedelta(seconds=duration)
        if (available and block) or (available == False and block == False):
            raise Exception('a window can either be available or blocked for deployments; not both or niether')
        self._block = not available if available != None else block if block != None else False
        self._types=types
        self._now = dt.now()
    
        if year == None or year in range(self._now.year,self._now.year + 3):
            self._year=year
        else:
            raise ValueError('Deployment window can only be specified for up to 3 years')

        if type(name) not in [str, type(None)]:
            raise ValueError('name must be a string')

        self._name = name

        self._limit=int(limit) if limit else None

        #pull from configuration
        if env.lower() not in [None, 'dev', 'test', 'rc', 'mln', 'prod']:
            raise ValueError('Environment must be dev, test, rc, mln, or prod')

        if not env: env='prod'

        _cmds=dict([(k,v) for k,v in inspect.getmembers(self, inspect.ismethod) if k.startswith('cmd_')])

        
    @property
    def __name__(self):
        frame = inspect.currentframe().f_back
        return [k for k,v in dict(frame.f_globals.items() + frame.f_locals.items()).items() if v is self][0]
    
    @property
    def types(self):
        return self._types
                
    @property
    def block(self):
        return self._block
                
    @property
    def available(self):
        return not self._block
    
    @property
    def duration(self):
        return  self._duration.minutes()
    
    @property
    def year(self):
        return self._year
                
    @property
    def env(self):
        return self._env
                
    def cancel(self,idt):
        self._instances[idt] -= 1

    def get_time(self,idt):
        _cronEval = croniter(self._cron_format, idt)
        _current = _cronEval.get_curr(dt)
        if self._block:
            return self._curr + self._duration
        
        _window = _current \
            if (self._now - _current).minutes <= self._duration \
            else _cronEval.get_next(dt)

        if self._limit:
            while True:
                if _window not in self._instances:
                    self.instances.update({_window:self._limit})

                for k,v in [(k,v) for k,v in self._instances if v]:
                    return _window

                _window = _cronEval.get_next(dt)

    def reserve(self, window):
        if not self.limit: return

        #lock:
        _instance = self._instances[window]
        if _instance.limit == 0:
            raise Exception('No more jobs are available for the requested deployment date:' + self.name)
        _instance.limit -= 1

class DeployWindows(dict):
    """
        DeployWindows:
            This is a dictionary of deployment windows with a function to get the time for deployment.

            new windows can also be added; whereopon all of the scheduled deployments must be re-evaluated for 
            schedule changes.
    """

    def __init__(self):
        dict.__init__()
        
    def getTime(self, deployWindows, env):
        _time = dt.now()
        while True:
            _restart = False
            for k,v in [(k,v) for k,v in self.items()
                if (len(set(v.types) & set(deployWindows)) > 0 or 'All' in v.types)
                and (v.year == None or v.year == _time.year)
                and (v.env == env)]:
    
                if v.get_time(_time) != _time:                
                    _time = v.get_time(_time)
                    _restart=True
                    break
            if not _restart:
                break
    
        return _time
    
    @staticmethod
    def load(obj=None):
        # load schedules from database and return DeploymentWindows object
        pass
    
    def write(self, obj=None):
        # write schedules to file
        pass
    
    def add(self, deployWindow, q):
        # add a new deployment window (check any existing instances to see if they need to be cancelled 
        # or a message might be sent when an earlier window opens up)
        # a deployment may also be moved forward
        # scheduling results need to be written to the given queue instance q
        pass

class ScheduledDeploy():
    """
    ScheduledDeploy:
        Describes a time when a particular deployment will be run
    """
    def __init__(self, user, deployWindows, jira, deployScheduledTime):
        self._user = user
        self._deployWindowNames = deployWindows
        self._jira = jira
        self._deployScheduledTime = deployScheduledTime
        self._deployId, self._time = self.addDeployment(user, deployWindows, jira)

    @property
    def user(self):
        return self._name

    @property
    def jira(self):
        return self._jira

    @property
    def deployWindowNames(self):
        return self._deployWindowNames

    @property
    def deployScheduledTime(self):
        return self._deployScheduledTime

    @property
    def status(self):
        #format a status message as to when the deployer can expect jira to run.
        pass

    @property
    def deployId(self):
    #go fetch a sequence from the db
        return self._deployId
    
    #add logic to insert the deployment and populate _deployId
    #returns deploId and time
    def addDeployment(self):
        self._time = _deployWindows.getTime(self._deployWindows, self.env)
        pass

    def cancel(self):
        self._deployWindow.cancel()

class ScheduledDeploys(dict):
    """
        ScheduldDeploys:
            Dictionary of all scheduled deployments.
    """

    #add logic to add a deployment to the schedule
    def add(self, req):
        dups = dict([(k,v) for k, v in self.items() if k == req['jira']])
        if len(dups) > 1:
            raise Exception("Unexpected condition, there should only be at most 1 duplicate since a new deployment can't be added if it is already there")
        
        if len(dups.len) > 0:
            raise Exception("jira: " + req['jira'] + " has already been scheduled for " + dups[0].deployScheduledTime.isoformat(' '))

        self.update(ScheduledDeploy(req))

    # load scheduled deployments from database
    # make sure to re-evaluate the execution time for cancellations same as adding/removing a deployment window
    @staticmethod
    def load(obj=None):
        _scheduledDeployments = ScheduledDeploys()
        
        return _scheduledDeployments
    

def _schedulingServiceThread(bld_reqs, _q):
    """
        main loop to process queue
    """
    _cmds = 
    _scheduleDeploys = ScheduledDeploys.load('figure out where to load/save from and tie this to the load method')
    _deployWindows = DeployWindows.load('figure out where to load/save from and tie this to the load method')
    while True:
        #process build requests
        _req = None
        try:
            _req = bld_reqs.get(timeout=5)
        except Empty:
            pass

        #process shutdown
        if _req != None:
            if _req == 'stop':
                _q.put('stopped')
                break
            if _req is not dict:
                raise Exception("Invalid request type: " + str(_req))
            if 'cmd' not in _req.keys():
                raise Exception("missing command entry: " + str(_req))
            if _req['cmd'] not in  _deployWindows._cmds
                raise Exception("Invalid command: " + str(_req[cmd]) + '/nValid commands are: ' + ', '.join(_cmds.keys())


        #change to check the data type; there can be a number of messages to process
        #including a routine to list the calendar, list the pending jobs, add deployment window, add/change/delete deployment window, 
        #cancel existing deployment
        #the example here is to add a deployment
def cmd_add_deployment(req):
    _scheduleDeploys.add(req)

    _bld_req[1].put(_scheduledDeploy.status)


def SchedulingService(bld_reqs):
    t1 = Thread(target=run,args=(bld_reqs,))
    t1.start()

