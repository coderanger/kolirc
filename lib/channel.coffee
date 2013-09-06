EventEmitter = require('events').EventEmitter

ent = require('ent')

User = require('./user')

class ChannelPoller
  constructor: (@conn) ->
    @last = 0
    @timer = setInterval(@poll.bind(@), 2000)

  poll: ->
    console.log('Polling for messages')
    @conn.kol.newChatMessages(@last)
      .then (chat) =>
        console.log("Chat data: #{JSON.stringify(chat)}")
        for msgData in chat.msgs
          unless msgData.type == 'public' # Not handling private or system for now
            continue
          channel = @conn.channels[msgData.channel]
          unless msgData.who
            console.log("Who-less message:", msgData)
            continue # Not sure what these are yet
          user = channel.addUser(msgData.who.name)
          if user.name == @conn.username
            continue # Don't echo back my own message
          msg = ent.decode(msgData.msg)
          channel.emit('privmsg', channel, user, msg)
        @last = chat.last if chat.last

module.exports = class Channel extends EventEmitter
  constructor: (@conn, @name, @topic) ->
    @users = {}
    @conn.channelPoller ||= new ChannelPoller(@conn)
    @timer = setInterval(@who.bind(@), 10000)

  addUser: (rawUsername, silent = false) ->
    username = User.sanitizeName(rawUsername)
    unless @users[username]
      user = new User(username, @conn)
      @users[username] = user
      @emit('join', @, user) unless silent
    @users[username]

  removeUser: (rawUsername, silent = false) ->
    username = User.sanitizeName(rawUsername)
    if @users[username]
      @emit('part', @, @users[username]) unless silent
      delete @users[username]

  who: (silent = false) ->
    @conn.sendChat("/who #{@name}")
      .then (who) =>
        nameRe = /<a[^>]+showplayer.php.*?a>/g
        currentUsers = {}
        while (name = nameRe.exec(who.output)) != null
          name = name[0].replace(/<[^>]*>/g, '')
          user = @addUser(name, silent)
          currentUsers[user.name] = true
        for name of @users
          unless currentUsers[name]
            @removeUser(name, silent)
        @users
