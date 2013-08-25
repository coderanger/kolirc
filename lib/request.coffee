Q = require('q')
request = require('request')

module.exports = Q.denodeify(request)
for method in ['get', 'post', 'put', 'delete', 'head', 'patch']
  module.exports[method] = Q.denodeify(request[method])
module.exports.jar = request.jar
module.exports.cookie = request.cookie
