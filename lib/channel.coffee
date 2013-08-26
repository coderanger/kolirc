EventEmitter = require('events').EventEmitter

User = require('./user')

CHANNELS = ['newbie', 'normal', 'radio']
SHARED_CHANNELS = ['newbie']

class ChannelPoller extends EventEmitter
  constructor: ->
    @conns = []

  # If we don't already have a listener, add this connection as responsible for polling a given channel
  # Returns the relevant channel object
  add: (conn, channel) ->
    existingConn = null
    for c in @conns
      if c.channels[channel.name]
        return c.channels[channel.name] # We already have someone listening on this channel
      if c.conn == conn
        existingConn = c
    if existingConn
      existingConn.channels[channel.name] = channel
    else
      c = {conn, channels: {}, last: 0}
      c.channels[channel.name] = channel
      @conns.push(c)
      c.poll = @poll(c)
    channel

  poll: (connData) ->
    connData.conn.kol.newChatMessages(connData.last)
      .then (chat) =>
        for msgData in chat.msgs
          channel = connData.channels[msgData.channel]
          unless channel
            continue # We aren't responsible for this channel, spin on
          unless msgData.who
            console.log("Who-less message:", msgData)
            continue # Not sure what these are yet
          user = channel.addUser(msgData.who.name)
          channel.emit('privmsg', channel, user, msgData.msg)
        connData.last = chat.last if chat.last
        @.delay(chat.delay or 1000).then(=> @poll(connData))

module.exports = class Channel extends EventEmitter
  @Poller: ChannelPoller
  sharedPoller: new ChannelPoller

  # Modified constructor that might return an existing channel instead
  @join: ->
    newChannel = new Channel(arguments...)
    @poller.add(newChannel.conn, newChannel)

  constructor: (@name, @conn) ->
    throw "Invalid channel name #{@name}" if CHANNELS.indexOf(@name) == -1
    @users = {}
    @poller = if SHARED_CHANNELS.indexOf(@name) == -1
      @conn.channelPoller ||= new ChannelPoller
    else
      @sharedPoller

  addUser: (rawUsername) ->
    username = User.sanitizeName(rawUsername)
    unless @users[username]
      user = new User(username, @conn)
      @users[username] = user
      @emit('join', channel, user)
