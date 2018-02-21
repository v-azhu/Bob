from Queue import Queue
from SchedulingService import *
from flask import Flask, current_app
import traceback

class BobWSException(Exception):
    def __init__(self,message,returnCode):
        Exception.__init__(self,message,returnCode)
    
    @property
    def message(self):
        return self.args[0]
    
    @property
    def returnCode(self):
        return self.args[1]

app = Flask(__name__)

@app.before_first_request
def initialize():
    current_app.deploy_reqs = Queue()
    SchedulingService(current_app.requests)
    
@app.route('/BuildRequest', methods = ['POST'])
def deploy_request():
    try:
        #Check parameters
        if set([i for i in request.json.keys() if i in ('raids', 'env')]) != set(('raids', 'env')):
            raise BobWSException(
                """BuildRequest requires {'raids':raids, env:'env'} parameters to be specified""" \
                + str(request) + " was requested", 1)
        #Add checking for optional parameter 'Release=True' (out of scope)
        #normal deploy is a snapshot, relase deploy will have a release number (out of scope) 
        #for the purposes of this release all builds will be snapshot builds
        pass

        #Build single-jira bundles return the results
        #Update the database and get an id/build number back for each raid submitted
        #update database and include an id for each build 
        _result = {}
        for i in request.json['raids'].split(':'):
            if requset.json['env'].lower() in ('dev', 'test'):
                _result.update={i:'build results for raid'}
                pass

        return {'ReturnCode':0, 'Log':'BuildRequest Complete', 'result':_result}

    except Exception as e:
        
        return jsonify({ "ReturnCode":e.returnCode if e is BobWSException else 999, "Log":traceback.format_exc() })

@app.route('/DeployRequest', methods = ['POST'])
def deploy_request():
    try:
        check_parameters(parameters=request.json, required=('raids', 'env'), optional=('cc'))

        #Future enhancement - allow each raid to have a release number

        #Schedule the successful build
        _responseQ = Queue()
        current_app.deploy_reqs.add({'func':request.path, 'parameters':request.json, 'responseQ':_responseQ})
        _DeployResponse = _responseQ.get()
        #inspect.getframeinfo(frame)[2]
        return _DeployResponse

    except Exception as e:
        
        return jsonify({ "ReturnCode":e.returnCode if e is BobWSException else 999, "Log":traceback.format_exc() })

def check_parameters(function, parameters, required, optional):
    """
        Check required and optional parameters
    """
    _parameters = set(parameters)
    _required=set(required)
    _optional=set(optional)

    if _required.difference(_parameters) != set():
        raise BobWSException(
            Function + " requires " + ', '.join(_required) + "parameter" + ("s" if len(_required) > 1 else "") + "s to be specified")

    _invalid = _parameters.difference(_required.union(_optional))
    if _invalid != set():
        raise BobWSException(
            "Invalid optional parameter" + 's' if len(_invalid) else '' + ": " + ', '.join(_invalid))

if __name__ == '__main__':
    app.run()

