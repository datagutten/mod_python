 #
 # Copyright 2004 Apache Software Foundation 
 # 
 # Licensed under the Apache License, Version 2.0 (the "License"); you
 # may not use this file except in compliance with the License.  You
 # may obtain a copy of the License at
 #
 #      http://www.apache.org/licenses/LICENSE-2.0
 #
 # Unless required by applicable law or agreed to in writing, software
 # distributed under the License is distributed on an "AS IS" BASIS,
 # WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 # implied.  See the License for the specific language governing
 # permissions and limitations under the License.
 #
 # Originally developed by Gregory Trubetskoy.
 #
 # $Id$

"""
  This handler is conceputally similar to Zope's ZPublisher, except
  that it:

  1. Is written specifically for mod_python and is therefore much faster
  2. Does not require objects to have a documentation string
  3. Passes all arguments as simply string
  4. Does not try to match Python errors to HTTP errors
  5. Does not give special meaning to '.' and '..'.
"""

import apache
import util

import sys
import os
import imp
import re
import base64

import new
import types
from types import *

imp_suffixes = " ".join([x[0][1:] for x in imp.get_suffixes()])

from cache import ModuleCache, NOT_INITIALIZED

class PageCache(ModuleCache):
    """ This is the cache for page objects. Handles the automatic reloading of pages. """
    
    def key(self,req):
        """ Extracts the filename from the request """
        return req.filename
    
    def check(self,req,entry):
        config = req.get_config()
        autoreload=int(config.get("PythonAutoReload", 1))
        if autoreload==0 and entry._value is not NOT_INITIALIZED:
            # if we don't want to reload and we have a value,
            # then we consider it fresh
            return None
        else:
            return ModuleCache.check(self,req.filename,entry)

    def build(self,req,opened,entry):
        config = req.get_config()
        log=int(config.get("PythonDebug", 0))
        if log:
            if entry._value is NOT_INITIALIZED:
                req.log_error('Publisher loading page %s'%req.filename,apache.APLOG_NOTICE)
            else:
                req.log_error('Publisher reloading page %s'%req.filename,apache.APLOG_NOTICE)        
        return ModuleCache.build(self,req,opened,entry)

page_cache = PageCache()

def handler(req):

    req.allow_methods(["GET", "POST", "HEAD"])
    if req.method not in ["GET", "POST", "HEAD"]:
        raise apache.SERVER_RETURN, apache.HTTP_METHOD_NOT_ALLOWED

    # if the file exists, req.finfo is not None
    if req.finfo:
        
        # The file exists, so we have a request of the form :
        # /directory/[module][/func_path]
        
        # we check whether there is a file name or not
        path, filename = os.path.split(req.filename)
        if not filename:
            
            # if not, we look for index.py
            req.filename = os.path.join(path,'index.py')

        # Now we build the function path
        if not req.path_info or req.path_info=='/':

            # we don't have a path info, or it's just a slash,
            # so we'll call index
            func_path = 'index'

        else:

            # we have a path_info, so we use it, removing the first slash
            func_path = req.path_info[1:]
    
    else:
        
        # First we check if there is a Python module with that name
        # just by adding a .py extension
        if os.path.isfile(req.filename+'.py'):

            req.filename += '.py'
            
            # Now we build the function path
            if not req.path_info or req.path_info=='/':
    
                # we don't have a path info, or it's just a slash,
                # so we'll call index
                func_path = 'index'
    
            else:
    
                # we have a path_info, so we use it, removing the first slash
                func_path = req.path_info[1:]
        else:

            # The file does not exist, so it seems we are in the 
            # case of a request in the form :
            # /directory/func_path
    
            # we'll just insert the module name index.py in the middle
            path, func_path = os.path.split(req.filename)
            req.filename = os.path.join(path,'index.py')
    
            # I don't know if it's still possible to have a path_info
            # but if we have one, we append it to the filename which
            # is considered as a path_info.
            if req.path_info:
                func_path = func_path + req.path_info

    # Now we turn slashes into dots
    func_path = func_path.replace('/','.')    
    
    # We remove the last dot if any
    if func_path[-1:] == ".":
        func_path = func_path[:-1] 

    # We use the page cache to load the module
    module = page_cache[req]

    # does it have an __auth__?
    realm, user, passwd = process_auth(req, module)

    # resolve the object ('traverse')
    object = resolve_object(req, module, func_path, realm, user, passwd)

    # publish the object
    published = publish_object(req, object)
    
    # we log a message if nothing was published, it helps with debugging
    if (not published) and (req.bytes_sent==0) and (req.next is None):
        log=int(req.get_config().get("PythonDebug", 0))
        if log:
            req.log_error("mod_python.publisher: nothing to publish.")

    return apache.OK

def process_auth(req, object, realm="unknown", user=None, passwd=None):

    found_auth, found_access = 0, 0

    # because ap_get_basic insists on making sure that AuthName and
    # AuthType directives are specified and refuses to do anything
    # otherwise (which is technically speaking a good thing), we
    # have to do base64 decoding ourselves.
    #
    # to avoid needless header parsing, user and password are parsed
    # once and the are received as arguments
    if not user and req.headers_in.has_key("Authorization"):
        try:
            s = req.headers_in["Authorization"][6:]
            s = base64.decodestring(s)
            user, passwd = s.split(":", 1)
        except:
            raise apache.SERVER_RETURN, apache.HTTP_BAD_REQUEST

    if hasattr(object, "__auth_realm__"):
        realm = object.__auth_realm__

    if type(object) is FunctionType:
        # functions are a bit tricky

        if hasattr(object, "func_code"):
            func_code = object.func_code

            if "__auth__" in func_code.co_names:
                i = list(func_code.co_names).index("__auth__")
                __auth__ = func_code.co_consts[i+1]
                if hasattr(__auth__, "co_name"):
                    __auth__ = new.function(__auth__, globals())
                found_auth = 1

            if "__access__" in func_code.co_names:
                # first check the constant names
                i = list(func_code.co_names).index("__access__")
                __access__ = func_code.co_consts[i+1]
                if hasattr(__access__, "co_name"):
                    __access__ = new.function(__access__, globals())
                found_access = 1

            if "__auth_realm__" in func_code.co_names:
                i = list(func_code.co_names).index("__auth_realm__")
                realm = func_code.co_consts[i+1]

    else:
        if hasattr(object, "__auth__"):
            __auth__ = object.__auth__
            found_auth = 1
        if hasattr(object, "__access__"):
            __access__ = object.__access__
            found_access = 1

    if found_auth:

        if not user:
            # note that Opera supposedly doesn't like spaces around "=" below
            s = 'Basic realm="%s"' % realm
            req.err_headers_out["WWW-Authenticate"] = s
            raise apache.SERVER_RETURN, apache.HTTP_UNAUTHORIZED    

        if callable(__auth__):
            rc = __auth__(req, user, passwd)
        else:
            if type(__auth__) is DictionaryType:
                rc = __auth__.has_key(user) and __auth__[user] == passwd
            else:
                rc = __auth__
            
        if not rc:
            s = 'Basic realm = "%s"' % realm
            req.err_headers_out["WWW-Authenticate"] = s
            raise apache.SERVER_RETURN, apache.HTTP_UNAUTHORIZED    

    if found_access:

        if callable(__access__):
            rc = __access__(req, user)
        else:
            if type(__access__) in (ListType, TupleType):
                rc = user in __access__
            else:
                rc = __access__

        if not rc:
            raise apache.SERVER_RETURN, apache.HTTP_FORBIDDEN

    return realm, user, passwd

### Those are the traversal and publishing rules ###

# tp_rules is a dictionary, indexed by type, with tuple values.
# The first item in the tuple is a boolean telling if the object can be traversed (default is True)
# The second item in the tuple is a boolen telling if the object can be published (default is True)
tp_rules = {}

# by default, built-in types cannot be traversed, but can be published
default_builtins_tp_rule = (False,True)
for t in types.__dict__.values():
    if isinstance(t, type):
        tp_rules[t]=default_builtins_tp_rule

# those are the exceptions to the previous rules
tp_rules.update({
    # Those are not traversable nor publishable
    ModuleType          : (False, False),
    BuiltinFunctionType : (False, False),
    
    # This may change in the near future to (False, True)
    ClassType           : (False, False),
    TypeType            : (False, False),
    
    # Publishing a generator may not seem to makes sense, because
    # it can only be done once. However, we could get a brand new generator
    # each time a new-style class property is accessed.
    GeneratorType       : (False, True),
    
    # Old-style instances are traversable
    InstanceType        : (True, True),
})

# types which are not referenced in the tp_rules dictionary will be traversable
# AND publishables 
default_tp_rule = (True, True)

def resolve_object(req, obj, object_str, realm=None, user=None, passwd=None):
    """
    This function traverses the objects separated by .
    (period) to find the last one we're looking for.
    """
    parts = object_str.split('.')
        
    for i, obj_str in enumerate(parts):
        # path components starting with an underscore are forbidden
        if obj_str[0]=='_':
            req.log_error('Cannot traverse %s in %s because '
                          'it starts with an underscore'
                          % (obj_str, req.unparsed_uri), apache.APLOG_WARNING)
            raise apache.SERVER_RETURN, apache.HTTP_FORBIDDEN

        # if we're not in the first object (which is the module)
        if i>0:
        
            # we're going to check whether be can traverse this type or not
            rule = tp_rules.get(type(obj), default_tp_rule)
            if not rule[0]:
                req.log_error('Cannot traverse %s in %s because '
                              '%s is not a traversable object'
                              % (obj_str, req.unparsed_uri, obj), apache.APLOG_WARNING)
                raise apache.SERVER_RETURN, apache.HTTP_FORBIDDEN
        
        # we know it's OK to call getattr
        # note that getattr can really call some code because
        # of property objects (or attribute with __get__ special methods)...
        try:
            obj = getattr(obj, obj_str)
        except AttributeError:
            raise apache.SERVER_RETURN, apache.HTTP_NOT_FOUND

        # we process the authentication for the object
        realm, user, passwd = process_auth(req, obj, realm, user, passwd)
    
    # we're going to check if the final object is publishable
    rule = tp_rules.get(type(obj), default_tp_rule)
    if not rule[1]:

         req.log_error('Cannot publish %s in %s because '
                       '%s is not publishable'
                       % (obj_str, req.unparsed_uri, obj), apache.APLOG_WARNING)
         raise apache.SERVER_RETURN, apache.HTTP_FORBIDDEN

    return obj

# This regular expression is used to test for the presence of an HTML header
# tag, written in upper or lower case.
re_html = re.compile(r"</HTML\s*>\s*$",re.I)
re_charset = re.compile(r"charset\s*=\s*([^\s;]+)",re.I);

def publish_object(req, object):
    if callable(object):
        req.form = util.FieldStorage(req, keep_blank_values=1)
        return publish_object(req,util.apply_fs_data(object, req.form, req=req))
    elif hasattr(object,'__iter__'):
        result = False
        for item in object:
            result |= publish_object(req,item)
        return result
    else:
        if object is None:
            return False
        elif isinstance(object,UnicodeType):
            # We try to detect the character encoding
            # from the Content-Type header
            if req._content_type_set:
                charset = re_charset.search(req.content_type)
                if charset:
                    charset = charset.group(1)
                else:
                    charset = 'UTF8'
                    req.content_type += '; charset=UTF8'
            else:
                charset = 'UTF8'
                
            result = object.encode(charset)
        else:
            charset = None
            result = str(object)
            
        if not req._content_type_set:
            # make an attempt to guess content-type
            # we look for a </HTML in the last 100 characters.
            # re.search works OK with a negative start index (it starts from 0
            # in that case)
            if re_html.search(result,len(result)-100):
                req.content_type = 'text/html'
            else:
                req.content_type = 'text/plain'
            if charset is not None:
                req.content_type += '; charset=UTF8'
        
        if req.method!='HEAD':
            req.write(result)

        return True
