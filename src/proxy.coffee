cluster = require 'cluster'
os = require 'os'
http = require 'http'
url = require 'url'
events = require 'events'
util = require 'util'

_= require 'lodash'
uuid = require 'uuid/v4'
R = require 'request-promise'
P = require 'bluebird'
retry = require 'bluebird-retry'
EE = events.EventEmitter

numCores = os.cpus().length;
proxyTo = 'test.com'

P.config
  warnings: true
  longStackTraces: true
    

Logger = require './logger'
log = new Logger()

InfoJob = () ->
						EE.call @
						@_whatsup = { in_: 0, out_ok: 0, out_err: 0, tries: 0, started: _.now() }
						@lastInfo = {}

						@on 'in', () ->
														@_whatsup.in_++
						@on 'out_ok', () ->
														 @_whatsup.out_ok++
						@on 'out_err', () ->
														@_whatsup.out_err++
						@on 'try', () ->
															@_whatsup.tries++
						@resetCounters = () ->
							{ in_, out_ok, out_err, tries, started } = @_whatsup
							now = _.now()
							period = now - started
							@_whatsup = { in_: 0, out_ok: 0, out_err: 0, tries: 0, started: _.now() }
							@lastInfo =
								in_s: in_ / period * 1000
								out_ok_s: out_ok / period * 1000
								out_err_s: out_err / period * 1000
								tries_s: tries / period * 1000

						@dumpInfo = () -> @lastInfo


						@resetCounters()
						return @


processRequest = ( req, id, notifier ) ->
	return retry () ->
					log.debug "Trying request id: #{id}"
					notifier.emit 'try'
					hdrKey = _.filter req.rawHeaders, ( v, i ) -> i % 2 == 0
					hdrVal = _.filter req.rawHeaders, ( v, i ) -> i % 2 != 0
					hdrs = _.zipObject hdrKey, hdrVal
					R
						url: "http://#{proxyTo}#{req.url}"
						headers: hdrs
						method: req.method
				, { interval: 50, backoff: 1.5, max_tries: 10, throw_original: true }


## MAIN
util.inherits InfoJob, EE
infoJob = new InfoJob()
setInterval () ->
							infoJob.resetCounters()
						, 60000

if cluster.isMaster
	log.info "Master process started, #{numCores} planned"
	for i in [0..numCores]
		cluster.fork()
		cluster.on 'exit', ( worker, code, signal) ->
												 log.info "Worker #{worker.process.pid} died, respawning..."
												 setTimeout () ->
												              cluster.fork()
												            , 100
else
	srv = http.createServer ( req, res ) ->
		if req.method is 'GET' and req.url is '/stats'
			res.statusCode = 200
			res.setHeader 'Content-Type', 'application/json;charset=utf-8'
			res.write JSON.stringify infoJob.dumpInfo()
			res.end()
		else
			id = uuid()
			log.info "Got request: #{id}, Params: #{url.parse(req.url).href}"
			infoJob.emit 'in'
			processRequest req, id, infoJob
			.then ( reply ) ->
				log.info "Succeed request id: #{id}"
				res.statusCode = 200
				res.setHeader 'Content-Type', 'application/json;charset=utf-8'
				res.write reply
				infoJob.emit 'out_ok'
			.catch ( err ) ->
				log.warn "Failed request id: #{id}", err
				res.statusCode = err.statusCode || 400
				res.write err.stack
				infoJob.emit 'out_err'
			.finally () ->
				res.end()

	srv.on 'clientError', ( err, sock ) ->
							sock.end 'HTTP/1.1 400 Bad Request\r\n\r\n'

	srv.listen 8888
	log.info "Process #{process.pid} started..."
