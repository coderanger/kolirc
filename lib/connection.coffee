carrier = require('carrier')
Q = require('q')
_ = require('underscore')

KolClient = require('./kol')

module.exports = class Connection
  constructor: (@stream, @server) ->
    @kol = new KolClient(@)
    @authenticated = false
    carrier.carry @stream, (line) =>
      cmd = @parse(line)
      fn = @["command_#{cmd.command}"]
      if fn
        fn.apply(@, cmd.args)
      else
        @send(undefined, 421, cmd.command, ":Unknown command #{cmd.command}")

  parse: (data) ->
    parts = data.trim().split(/[ ]:/)
    args = parts[0].split(' ')

    parts = [parts.shift(), parts.join(' :')]

    if parts.length > 0
      args.push(parts[1])

    if data.match(/^:/)
      args[1] = args.splice(0, 1, args[1])
      args[1] = (args[1] + '').replace(/^:/, '')

    {
      command: args[0].toUpperCase(),
      args: args.slice(1),
    }

  send: (prefix, args...) ->
    unless prefix?
      prefix = @server.host
    if prefix
      args.unshift(':'+prefix)
    dfd = Q.defer()
    @stream.write(args.join(' ') + '\r\n', dfd.resolve.bind(dfd))
    dfd.promise

  notice: (msg) ->
    @send(undefined, 'NOTICE', '*', ":#{msg}")

  command_PASS: (password) ->
    @password = password

  command_NICK: (username) ->
    @username = username
    if @password
      @authenticate()
    else
      @send(undefined, 437, username, ":Password is required")

  command_USER: ->
    # no-op

  command_MODE: ->
    # no-op

  command_ISON: ->
    # no-op

  command_PING: (time) ->
    @send(undefined, 'PONG', @server.host, time)

  authenticate: ->
    @kol.login(@username, @password)
      .then =>
        @authenticated = true
        @welcomeBanner()
      .fail (msg) =>
        console.log("Login error: #{msg}")
        @send(undefined, 464, ":#{msg}")
          .then => @stream.end()

  welcomeBanner: ->
    @send(undefined, '001', @username, ":Welcome to KoLIRC #{@username}@#{@stream.remoteAddress}")
      .then =>
        @send(undefined, '002', @username, ":Your host is #{@server.host}")
      .then =>
        @send(undefined, '003', @username, ":This server was created #{@server.started.format()}")
      .then =>
        @send(undefined, '004', @username, ":KoLIRC")
