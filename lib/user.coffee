module.exports = class User
  @sanitizeName: (rawUsername) ->
    rawUsername.replace(/\s+/g, '_')

  constructor: (@name) ->
    @origin = "#{@name}!~#{@name}@#{@server.host}"
