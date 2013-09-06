carrier = require('carrier')
Q = require('q')
_ = require('underscore')

Channel = require('./channel')
KolClient = require('./kol')

module.exports = class Connection
  constructor: (@stream, @server) ->
    @kol = new KolClient(@)
    @authenticated = false
    @channels = {}
    carrier.carry @stream, (line) =>
      cmd = @parse(line)
      fn = @["command_#{cmd.command}"]
      if fn
        fn.apply(@, cmd.args)
      else
        @send(undefined, 421, cmd.command, ":Unknown command #{cmd.command}")
    @stream.on('end', => @logout())
    @stream.on 'error', (err) =>
      console.log('Socket error:', err.stack)
      @logout()

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
    if @authenticated
      @send(undefined, 484, ":Your connection is restricted")
    else
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

  command_AWAY: ->
    # no-op, later should reduce polling interval

  command_WHO: ->
    # no-op

  command_QUIT: ->
    p1 = @send(undefined, 'ERROR', ':Goodbye')
    p2 = @logout()
    Q.all([p1, p2])
      .then =>
        @stream.end()

  command_JOIN: (channel) ->
    return
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

  command_PRIVMSG: (target, msg) ->
    msg = msg.replace(/^\x01ACTION(.*?)\x01$/, '/me$1')
    if target[0] == '#'
      # Sending to a channel
      channel = target.substring(1)
      @sendChat("/#{channel} #{msg}")

  authenticate: ->
    @kol.login(@username, @password)
      .then =>
        @authenticated = true
        @password = '*****'
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
        @joinChannels()
      .fail (msg) =>
        console.log("Error: #{msg}")
        @notice("Error: #{msg}")

  joinChannels: ->
    @sendChat('/listen')
      .then (listen) =>
        channels = listen.output.split('<br>')
        # Remove the first and last lines
        channels.shift()
        channels.pop()
        promises = for rawChannel in channels
          rawChannel = rawChannel.replace(/<[^>]*>/g, '').replace(/&nbsp;/g, '')
          console.log("Joining ##{rawChannel}")
          channel = new Channel(@, rawChannel)
          @channels[rawChannel] = channel
          @bindChannel(channel)
          @joinChannel(channel)
        Q.all(promises)

  joinChannel: (channel) ->
    p1 = @send("#{@username}!~#{@username}@#{@stream.remoteAddress}", 'JOIN', '#'+channel.name)
    p2 = channel.who(true)
    Q.all([p1, p2])
      .spread (sent, who) =>
        prefixLength = @server.host.length + @username.length + channel.name.length + 11
        lines = ['']
        for name of who
          if lines[lines.length-1].length + name.length + 1 + prefixLength > 510
            lines.push('')
          lines[lines.length-1] += " #{name}"
        promises = for line in lines
          @send(undefined, 353, @username, '=', '#'+channel.name, ":#{line.substring(1)}")
        Q.all(promises)
      .then =>
        @send(undefined, 366, @username, '#'+channel.name, ':End of /NAMES list.')

  bindChannel: (channel) ->
    channel
      .on 'privmsg', (c, user, msg) =>
        @send(user.origin, 'PRIVMSG', '#'+channel.name, ':'+msg)
      .on 'join', (c, user) =>
        @send(user.origin, 'JOIN', '#'+channel.name)
      .on 'part', (c, user) =>
        @send(user.origin, 'PART', '#'+channel.name, ':Left channel')

  logout: ->
    clearInterval(@channelPoller.timer) if @channelPoller
    for name, channel of @channels
      clearInterval(channel.timer)
    @kol.logout()
