winston = require 'winston'

logger = null

log = () ->
	if not logger
		logger = new winston.Logger
			level     : 'debug'
			transports: [
				new winston.transports.Console
					level: 'error'
				new winston.transports.File
					level   : 'info'
					name    : 'file-info'
					filename: 'logs/server.log'
				new winston.transports.File
					level   : 'debug'
					name    : 'file-debug'
					filename: 'logs/server.dbg'
			]
		logger.debug 'Logging subsystem initialized'
	return logger

module.exports = log