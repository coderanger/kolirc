crypto = require('crypto')
querystring = require('querystring')

Q = require('q')

request = require('./request')

# MD5 helper
md5 = (data) ->
  crypto.createHash('md5').update(data).digest().toString('hex')

module.exports = class KolClient
  constructor: (@conn) ->
    @urlBase = 'http://www.kingdomofloathing.com/'
    @jar = request.jar()

  login: (username, password) ->
    loginUrl = "#{@urlBase}login.php"
    request.get({url: loginUrl, jar: @jar})
      .then ([response, body]) =>
        throw 'Nightly maintenance' if response.request.path == '/maint.php'
        challenge = /name="?challenge"?\s+value="?([0-9a-f]+)"?/.exec(body)[1]
        formData = {
          loggingin: 'Yup.',
          loginname: username,
          secure: '1',
          challenge: challenge,
          response: md5(md5(password) + ':' + challenge),
        }
        request.post({url: loginUrl, jar: @jar, form: formData})
      .then ([response, body]) =>
        waitTime = 1 # Default in case of weirdness
        if response.statusCode == 302 and response.headers.location == '/game.php'
          return true # Login successful
        else if /<b>Login failed\. Bad password\.<\/b>/.test(body)
          throw 'Password incorrect'
        else if /Please wait a minute/.test(body)
          waitTime = 1
        else if /you'll need to wait a couple of minutes before you can log in again\./.test(body)
         waitTime = 2
        else if /Please wait five minutes and try again\./.test(body)
          waitTime = 5
        else if /Please wait fifteen minutes and try again\./.test(body)
          waitTime = 15
        else if /Too many login failures from this IP/.test(body)
          waitTime = 15
        else
          throw 'Unknown login failure'
        @conn.notice("Waiting #{waitTime} minute(s) and then trying again")
          .then -> Q.delay(waitTime*60*1000)
          .then -> @login(username, password)

  api: (what = 'status', count, id, since) ->
    data = {what: what, for: 'KoLIRC by coderanger'}
    data.count = count if count
    data.id = id if id
    data.since = since if since
    request.get({url: "#{@urlBase}api.php?#{querystring.stringify(data)}", jar: @jar})
      .then ([response, body]) ->
        throw 'Nightly maintenance' if response.request.path == '/maint.php'
        JSON.parse(body)

  newChatMessages: (since = 0) ->
    request.get({url: "#{@urlBase}newchatmessages.php?j=1&lasttime=#{since}", jar: @jar})
      .then ([response, body]) ->
        throw 'Nightly maintenance' if response.request.path == '/maint.php'
        JSON.parse(body)

  submitNewChat: (playerId, pwd, msg) ->
    data = {j: '1', playerid: playerId, pwd: pwd, graf: msg}
    request.get({url: "#{@urlBase}submitnewchat.php?#{querystring.stringify(data)}", jar: @jar})
      .then ([response, body]) ->
        throw 'Nightly maintenance' if response.request.path == '/maint.php'
        JSON.parse(body)
