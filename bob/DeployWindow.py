from crontab import CronTab
import inspect
from datetime import datetime as dt, timedelta
import time

class DeployWindow():
    _cron_format = None
    _year = None
    _duration = None
    _types = None 
    _env = None
    _block = None
    _name = None
    _limit = None
    _instances = {}
    
    def __init__ (self, cron_format, duration, types=['All'], available = None, block = None, name = None, year=None, limit=None, env=None):
        self._cron_format = cron_format
        self._duration = timedelta(seconds=duration)
        if (available and block) or (available == False and block == False):
            raise Exception('a window can either be available or blocked for deployments; not both or niether')
        self._block = not available if available != None else block if block != None else False
        self._types=types
    
        if year == None or year in range(dt.now().year,dt.now().year + 3):
            self._year=year
        else:
            raise ValueError('Deployment window can only be specified for up to 3 years')

        if type(name) not in [str, NoneType]:
            raise ValueError('name must be a string')

        self._name = name

        self._limit=int(limit) if limit else None

        if lower(env) not in [None, 'dev', 'test', 'rc', 'mln', 'prod']:
            raise ValueError('Environment must be dev, test, rc, mln, or prod')

        if not env: env='prod'

        
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
                
    def cancel(idt):
        self._instances[idt] -= 1

    def get_time(idt):
        _cronEval = croniter(_cron_format, idt)
        _current = _cronEval.get_curr(datetime)
        if self._block:
            return _curr + duration
        
        _window = _current \
            if (_now - _current).minutes <= self._duration \
            else _cronEval.get_next(datetime)

        if self._limit:
            while True:
                if _window not in self._instances:
                    instances.update({_window:self._limit})

                for k,v in [(k,v) for k,v in self._instances if v]:
                    return _window

                _window = _cronEval.get_next(datetime)

    def reserve(window):
        if not self.limit: return

        #lock:
        _instance = self._instances[window]
        if _instance.limit == 0:
            raise Exception('No more jobs are available for the requested deployment date:' + self.name)
        _instance.limit -= 1
        #unlock

