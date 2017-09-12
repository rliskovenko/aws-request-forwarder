cluster = require 'cluster'
os = require 'os'
http = require 'http'
url = require 'url'

_= require 'lodash'
uuid = require 'uuid/v4'
R = require 'request-promise'
P = require 'bluebird'
retry = require 'bluebird-retry'

numCores = os.cpus().length;
proxyTo = 'test.com'

P.config
  warnings: true
  longStackTraces: true
    

Logger = require './logger'
log = new Logger()

processRequest = ( req, id ) ->
	return retry () ->
					log.debug "Trying request id: #{id}"
					R
						url: "http://#{proxyTo}#{req.url}"
						headers: req.headers
						method: req.method
				, { interval: 50, backoff: 1.5, max_tries: 10, throw_original: true }


if cluster.isMaster
	log.info "Master process started, #{numCores} planned"
	for i in [0..numCores]
		cluster.fork()
		cluster.on 'exit', ( worker, code, signal) ->
												 log.info "Worker #{worker.process.pid} died, respawning..."
												 setTimeout () ->
												              cluster.fork()
												            , 1000
else
	srv = http.createServer ( req, res ) ->
		id = uuid()
		log.info "Got request: #{id}, Params: #{url.parse(req.url).href}"
		processRequest req, id
		.then ( reply ) ->
			log.info "Succeed request id: #{id}"
			res.statusCode= 200
			res.setHeader 'Content-Type', 'application/json;charset=utf-8'
			res.write reply
		.catch ( err ) ->
			log.warn "Failed request id: #{id}", err
			res.statusCode = err.statusCode
			res.write err.stack
		.finally () ->
			res.end()

	srv.on 'clientError', ( err, sock ) ->
							sock.end 'HTTP/1.1 400 Bad Request\r\n\r\n'

	srv.listen 8888
	log.info "Process #{process.pid} started..."
