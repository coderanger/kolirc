module.exports = class User
  @sanitizeName: (rawUsername) ->
    rawUsername.replace(/\s+/g, '_')

  constructor: (@name, @conn) ->
    @origin = "#{@name}!~#{@name}@#{@conn.server.host}"
