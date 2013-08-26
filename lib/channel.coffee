EventEmitter = require('events').EventEmitter

User = require('./user')

class ChannelPoller extends EventEmitter
  constructor: ->
    @conns = []

  # If we don't already have a listener, add this connection as responsible for polling a given channel
  add: (conn, channel) ->
    existingConn = null
    for c in @conns
      if c.channels[channel.name]
        return # We already have someone listening on this channel
      if c.conn == conn
        existingConn = c
    if existingConn
      existingConn.channels[channel.name] = channel
    else
      c = {conn, channels: {}, last: 0}
      c.channels[channel.name] = channel
      @conns.push(c)

  poll: (connData) ->
    connData.conn.kol.newChatMessages(connData.last)
      .then ->
        for msgData in chat.msgs
          channel = connData.channels[msgData.channel]
          unless channel
            continue # We aren't responsible for this channel, spin on
          unless msgData.who
            console.log("Who-less message:", msgData)
            continue # Not sure what these are yet
          user = channel.addUser(msgData.who.name)


module.exports = class Channel extends EventEmitter
  poller: new ChannelPoller

  constructor: (@name, @conn) ->
    @users = {}
    @poller.add(@conn, @)

  addUser: (rawUsername) ->
    username = User.sanitizeName(rawUsername)
    unless @users[username]
      user = new User(username)
      @users[username] = user
      @emit('join', channel, user)
