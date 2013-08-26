carrier = require('carrier')
Q = require('q')
_ = require('underscore')

KolClient = require('./kol')

module.exports = class Connection
  constructor: (@stream, @server) ->
    @kol = new KolClient(@)
    @authenticated = false
    @lastChat = 0
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

  sendChat: (msg) ->
    @kol.submitNewChat(@status.playerid, @status.pwd, msg)

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

  command_JOIN: (channel) ->
    rawChannel = channel.substring(1) # Sans #
    @send("#{@username}!~#{@username}@#{@stream.remoteAddress}", 'JOIN', channel)
      .then =>
        @sendChat("/who #{rawChannel}")
      .then (who) =>
        # The following complex-as-balls code breaks up the list of names into 512-byte chunks
        prefixLength = @server.host.length + @username.length + channel.length + 11
        nameRe = /<a[^>]+showplayer.php.*?a>/g
        names = while (name = nameRe.exec(who.output)) != null
          name[0].replace(/<[^>]*>/g, '').replace(/\s+/g, '_')
        lines = ['']
        for name in names
          if lines[lines.length-1].length + name.length + 1 + prefixLength > 510
            lines.push('')
          lines[lines.length-1] += " #{name}"
        promises = for line in lines
          @send(undefined, 353, @username, '=', channel, ":#{line}")
        Q.all(promises)
      .then =>
        @send(undefined, 366, @username, channel, ':End of /NAMES list.')

  authenticate: ->
    @kol.login(@username, @password)
      .then =>
        @authenticated = true
        @kol.api('status')
      .then (status) =>
        @status = status
        @welcomeBanner()
      .fail (msg) =>
        console.log("Login error: #{msg}")
        @send(undefined, 464, ":#{msg}")
          .then => @stream.end()

  welcomeBanner: ->
    @send(undefined, '001', @username, ":Welcome to KoLIRC #{@username}!~#{@username}@#{@stream.remoteAddress}")
      .then =>
        @send(undefined, '002', @username, ":Your host is #{@server.host}")
      .then =>
        @send(undefined, '003', @username, ":This server was created #{@server.started.format()}")
      .then =>
        @send(undefined, '004', @username, ":KoLIRC")
      .then =>
        @pollNewMessages()
      .fail (msg) =>
        console.log("Error: #{msg}")
        @notice("Error: #{msg}")

  pollNewMessages: ->
    @kol.newChatMessages(@lastChat)
      .then (chat) =>
        for msg in chat.msgs
          name = msg.who.name.replace(/\s+/g, '_')
          @send("#{name}!~#{name}@#{@server.host}", 'PRIVMSG', "##{msg.channel}", ":#{msg.msg}")
        @lastChat = chat.last if chat.last
        Q.delay(chat.delay or 1000).then(=> @pollNewMessages())
