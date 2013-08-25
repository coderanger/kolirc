net = require('net')
os = require('os')

moment = require('moment')

Connection = require('./connection')

module.exports = class Server
  constructor: (@port) ->
    @host = os.hostname()
    @started = moment()
    @server = net.createServer(@handleConnection.bind(@))
    @server.listen(@port)

  handleConnection: (stream) ->
    new Connection(stream, @)
