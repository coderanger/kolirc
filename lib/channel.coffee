EventEmitter = require('events').EventEmitter

ent = require('ent')

User = require('./user')

regexpEscape = (s) ->
  s.replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&')

cleanMessage = (msg) ->
  # Decode HTML entities
  msg = ent.decode(msg)
  # Convert /me messages to match IRC format
  msg = msg.replace(/^<b><i><a target=mainpane href="showplayer\.php\?who=\d+"><font color="black">[^<]+<\/b><\/font><\/a>(.*?)<\/i>$/, '\x01ACTION$1\x01')
  # Remove the odd comment, possibly an old keepalive system
  msg = msg.replace(/<!--viva-->/, '')
  # Clean up link rendering
  links = []
  msg = msg.replace /<a target=_blank href="([^"]+)"><font color=blue>\[link\]<\/font><\/a> /g, (match, p1) ->
    links.push(p1)
    ''
  for link in links
    linkChars = for c in link.split('')
      regexpEscape(c)
    linkRe = new RegExp(linkChars.join(' ?'), 'g')
    msg = msg.replace(linkRe, link)
  msg

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
          channel.emit('privmsg', channel, user, cleanMessage(msgData.msg))
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
