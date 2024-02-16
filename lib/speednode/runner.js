'use strict';

const vm = require('vm');
const net = require('net');
const os = require('os');
const fs = require('fs');
let crypto_var = null;
try {
  crypto_var = require('crypto');
} catch (err) {}
const crypto = crypto_var;
let contexts = {};
let scripts = {};
let process_exit = false;

/*** circular-json, originally taken from https://raw.githubusercontent.com/WebReflection/circular-json/
 Copyright (C) 2013-2017 by Andrea Giammarchi - @WebReflection

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.

 ***

 the original version has been restructured and modified to fit in here,
 only stringify is used, unused parts removed.

 */

const CircularJSON = {};
CircularJSON.specialChar = '~';
CircularJSON.safeSpecialChar =  '\\x' + ('0' + CircularJSON.specialChar.charCodeAt(0).toString(16)).slice(-2);
CircularJSON.escapedSafeSpecialChar = '\\' + CircularJSON.safeSpecialChar;
CircularJSON.specialCharRG = new RegExp(CircularJSON.safeSpecialChar, 'g');
CircularJSON.indexOf = [].indexOf || function(v){
    for(let i=this.length;i--&&this[i]!==v;);
    return i;
  };

CircularJSON.generateReplacer = function (value, replacer, resolve) {
    let
        doNotIgnore = false,
        inspect = !!replacer,
        path = [],
        all  = [value],
        seen = [value],
        mapp = [resolve ? CircularJSON.specialChar : '[Circular]'],
        last = value,
        lvl  = 1,
        i, fn
    ;
    if (inspect) {
      fn = typeof replacer === 'object' ?
          function (key, value) {
            return key !== '' && CircularJSON.indexOf.call(replacer, key) < 0 ? void 0 : value;
          } :
          replacer;
    }
    return function(key, value) {
      // the replacer has rights to decide
      // if a new object should be returned
      // or if there's some key to drop
      // let's call it here rather than "too late"
      if (inspect) value = fn.call(this, key, value);

      // first pass should be ignored, since it's just the initial object
      if (doNotIgnore) {
        if (last !== this) {
          i = lvl - CircularJSON.indexOf.call(all, this) - 1;
          lvl -= i;
          all.splice(lvl, all.length);
          path.splice(lvl - 1, path.length);
          last = this;
        }
        // console.log(lvl, key, path);
        if (typeof value === 'object' && value) {
          // if object isn't referring to parent object, add to the
          // object path stack. Otherwise it is already there.
          if (CircularJSON.indexOf.call(all, value) < 0) {
            all.push(last = value);
          }
          lvl = all.length;
          i = CircularJSON.indexOf.call(seen, value);
          if (i < 0) {
            i = seen.push(value) - 1;
            if (resolve) {
              // key cannot contain specialChar but could be not a string
              path.push(('' + key).replace(CircularJSON.specialCharRG, CircularJSON.safeSpecialChar));
              mapp[i] = CircularJSON.specialChar + path.join(CircularJSON.specialChar);
            } else {
              mapp[i] = mapp[0];
            }
          } else {
            value = mapp[i];
          }
        } else {
          if (typeof value === 'string' && resolve) {
            // ensure no special char involved on deserialization
            // in this case only first char is important
            // no need to replace all value (better performance)
            value = value
                .replace(CircularJSON.safeSpecialChar, CircularJSON.escapedSafeSpecialChar)
                .replace(CircularJSON.specialChar, CircularJSON.safeSpecialChar);
          }
        }
      } else {
        doNotIgnore = true;
      }
      return value;
    };
  };
CircularJSON.stringify = function stringify(value, replacer, space, doNotResolve) {
    return JSON.stringify(
        value,
        CircularJSON.generateReplacer(value, replacer, !doNotResolve),
        space
    );
  };
/*** end of circular-json ***/

// serialize Map as Object, also below in attach
function simple_map_replacer(key, value) {
  if (value && typeof value === 'object' && value.constructor.name === "Map")
    return Object.fromEntries(value);
  return value;
}

function attachFunctionSource(responder_path, context, func) {
  return `${func} = async function(...method_args) {
    let context = '${context}';
    let func = '${func}';
    let request = [context, func, method_args];
    let responder_path = '${responder_path}';
    if (!global.__responder_socket) {
      return new Promise(function(resolve, reject) {
        setTimeout(function(){
          if (os.platform() == 'win32') {
            let socket = net.connect(responder_path);
            socket.on('connect', function(){
              global.__responder_socket = true;
              socket.destroy();
              resolve(${func}(...method_args));
            })
            socket.on('error', function (err) {
              resolve(${func}(...method_args));
            });
          } else {
            if (fs.existsSync(responder_path)) { global.__responder_socket = true; }
            resolve(${func}(...method_args));
          }
        }, 10)
      });
    }
    function simple_map_replacer(key, value) {
      if (value && typeof value === 'object' && value.constructor.name === "Map")
        return Object.fromEntries(value);
      return value;
    }
    return new Promise(function(resolve, reject) {
      let request_json = JSON.stringify(request, simple_map_replacer);
      let buffer = Buffer.alloc(0);
      let socket = net.connect(responder_path);
      socket.setTimeout(2000);
      socket.on('error', function (err) {
          if (err.syscall === 'connect') {
            // ignore, close will handle
          } else if ((os.platform() == 'win32') && err.message.includes('read EPIPE')) {
            // ignore, close will handle
          } else if ((os.platform() == 'win32') && err.message.includes('write EPIPE')) {
            // ignore, close will handle
          } else { reject(err); }
      });
      socket.on('ready', function () {
          socket.write(request_json + "\x04");
      });
      socket.on('data', function (data) {
          buffer = Buffer.concat([buffer, data]);
      });
      socket.on('timeout', function() {
          socket.destroy();
          reject();
      });
      socket.on('close', function() {
        if (buffer.length > 0) {
            let method_result = JSON.parse(buffer.toString('utf8'));
            if (method_result[0] == 'err') {
              reject(method_result);
            } else {
              resolve(method_result[1]);
            }
        } else {
          resolve(null);
        }
      });
    });
  }`;
}

function createCompatibleContext(uuid, options) {
    let c = vm.createContext();
    vm.runInContext('delete this.console', c, "(execjs)");
    vm.runInContext('delete this.gc', c, "(execjs)");
    contexts[uuid] = { context: c, options: options };
    return c;
}

function createPermissiveContext(uuid, options) {
    let c = vm.createContext({ __responder_socket: false, process: { release: { name: "node" }, env: process.env }, Buffer, clearTimeout, crypto, fs, net, os, require, setTimeout });
    vm.runInContext('global = globalThis;', c);
    contexts[uuid] = { context: c, options: options };
    return c;
}

function formatResult(result) {
  if (typeof result === 'undefined' && result !== null) { return ['ok']; }
  else {
      try { return ['ok', result]; }
      catch (err) { return ['err', ['', err].join(''), err.stack]; }
  }
}

function getContext(uuid) {
  if (contexts[uuid]) { return contexts[uuid].context; }
  else { return null; }
}

function getContextOptions(uuid) {
  let options = { filename: "(execjs)", displayErrors: true };
  if (contexts[uuid].options.timeout)
    options.timeout = contexts[uuid].options.timeout;
  return options;
}

function massageStackTrace(stack) {
  if (stack && stack.indexOf("SyntaxError") == 0)
      return "(execjs):1\n" + stack;
  return stack;
}

let socket_path = process.env.SOCKET_PATH;
if (!socket_path) { throw 'No SOCKET_PATH given!'; };
let debug_contexts = [];
let commands_swapped = false;

function swap_commands(c) {
  c.oexec = c.exec;
  c.exec = c.execd;
  c.oeval = c.eval;
  c.eval = c.evald;
  c.oevsc = c.evsc;
  c.evsc = c.evscd;
  commands_swapped = true;
}

let commands = {
    attach: function(input) {
      let context = getContext(input.context);
      let responder_path;
      if (process.platform == 'win32') { responder_path = '\\\\\\\\.\\\\pipe\\\\' + socket_path + '_responder'; }
      else { responder_path = socket_path + '_responder' }
      let result = vm.runInContext(attachFunctionSource(responder_path, input.context, input.func), context, { filename: "(execjs)", displayErrors: true });
      return formatResult(result);
    },
    bench: function (input) {
      if (typeof global.gc === "function") { global.gc(); }
      let context = getContext(input.context);
      let options = getContextOptions(input.context);
      performance.mark('start_bench');
      let result = vm.runInContext(input.source, context, options);
      performance.mark('stop_bench');
      let duration = performance.measure('bench_time', 'start_bench', 'stop_bench').duration;
      performance.clearMarks();
      performance.clearMeasures();
      if (typeof global.gc === "function") { global.gc(); }
      return formatResult({ result: result, duration: duration });
    },
    create: function (input) {
      let context = createCompatibleContext(input.context, input.options);
      let result = vm.runInContext(input.source, context, getContextOptions(input.context));
      return formatResult(result);
    },
    created: function (input) {
      debug_contexts.push(input.context);
      if (!commands_swapped) {
        swap_commands(commands);
        let result = eval(input.source);
        return formatResult(result);
      } else { return formatResult(true) }
    },
    createp: function (input) {
      let context = createPermissiveContext(input.context, input.options);
      let result = vm.runInContext(input.source, context, getContextOptions(input.context));
      return formatResult(result);
    },
    deleteContext: function(uuid) {
        delete contexts[uuid];
        delete scripts[uuid]
        return ['ok', Object.keys(contexts).length];
    },
    exit: function(code) {
        process_exit = code;
        return ['ok'];
    },
    exec: function (input) {
        let result = vm.runInContext(input.source, getContext(input.context), getContextOptions(input.context));
        return formatResult(result);
    },
    execd: function(input) {
      if (debug_contexts.includes(input.context)) {
        let result = eval(input.source);
        return formatResult(result);
      } else {
        return commands.oexec(input);
      }
    },
    eval: function (input) {
      if (input.source.match(/^\s*{/)) { input.source = `(${input.source})`; }
      else if (input.source.match(/^\s*function\s*\(/)) { input.source = `(${input.source})`; }
      let result = vm.runInContext(input.source, getContext(input.context), getContextOptions(input.context));
      return formatResult(result);
    },
    evald: function(input) {
      if (debug_contexts.includes(input.context)) {
        if (input.source.match(/^\s*{/)) { input.source = `(${input.source})`; }
        else if (input.source.match(/^\s*function\s*\(/)) { input.source = `(${input.source})`; }
        let result = eval(input.source);
        return formatResult(result);
      } else {
        return commands.oeval(input);
      }
    },
    scsc: function (input) {
      if (!scripts[input.context]) { scripts[input.context] = {}; }
      scripts[input.context][input.key] = new vm.Script(input.source);
      return formatResult(true);
    },
    evsc: function(input) {
      let result = scripts[input.context][input.key].runInContext(getContext(input.context));
      return formatResult(result);
    },
    evscd: function(input) {
      if (debug_contexts.includes(input.context)) {
        let result = scripts[input.context][input.key].runInThisContext();
        return formatResult(result);
      } else {
        return commands.oevsc(input);
      }
    }
    // ctxo: function (input) {
    //   return formatResult(getContextOptions(input.context));
    // },
};

let server = net.createServer(function(s) {
    let received_data = [];

    s.on('data', function (data) {
        received_data.push(data);
        if (data[data.length - 1] !== 4) { return; }

        let request = received_data.join('').toString('utf8');
        request = request.substring(0, request.length - 1);
        received_data = [];

        let input, result;
        let outputJSON = '';

        try { input = JSON.parse(request); }
        catch(err) {
          outputJSON = JSON.stringify(['err', ['', err].join(''), err.stack]);
          s.write([outputJSON, "\x04"].join(''));
          return;
        }

        try { result = commands[input.cmd](input.args); }
        catch (err) {
          outputJSON = JSON.stringify(['err', ['', err].join(''), massageStackTrace(err.stack)]);
          s.write([outputJSON, "\x04"].join(''));
          return;
        }

        try { outputJSON = JSON.stringify(result, simple_map_replacer); }
        catch(err) {
            if (err.message.includes('circular')) { outputJSON = CircularJSON.stringify(result, simple_map_replacer); }
            else { outputJSON = JSON.stringify([['', err].join(''), err.stack]); }
            s.write([outputJSON, "\x04"].join(''));
            if (process_exit !== false) { process.exit(process_exit); }
            return;
        }

        try { s.write([outputJSON, "\x04"].join('')); }
        catch (err) {}
        if (process_exit !== false) { process.exit(process_exit); }
    });
});

if (process.platform == 'win32') { server.listen('\\\\.\\pipe\\' + socket_path); }
else { server.listen(socket_path); }
