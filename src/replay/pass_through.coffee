HTTP = require("http")


ClientRequest = HTTP.ClientRequest

passThrough = (passThrough)->
  if arguments.length == 0
    passThrough = -> true
  else if typeof passThrough == "string"
    [hostname, passThrough] = [passThrough, (request)-> request.hostname == hostname]
  else unless typeof passThrough == "function"
    [boolean, passThrough] = [passThrough, (request)-> !!boolean]

  return (request, callback)->
    if passThrough(request)
      options =
        protocol:           request.url.protocol
        hostname:           request.url.hostname
        port:               request.url.port
        path:               request.url.path
        method:             request.method
        headers:            request.headers
        agent:              request.agent
        auth:               request.auth
        key:                request.key
        cert:               request.cert
        secureOptions:      request.secureOptions
        secureProtocol:     request.secureProtocol
        rejectUnauthorized: request.rejectUnauthorized

      http = new ClientRequest(options)
      if (request.trailers)
        http.addTrailers(request.trailers)
      http.on "error", (error)->
        callback error
      http.on "response", (response)->
        captured =
          version:        response.httpVersion
          statusCode:     response.statusCode
          statusMessage:  response.statusMessage
          headers:        response.headers
          rawHeaders:     response.rawHeaders
          body:    []
        response.on "data", (chunk, encoding)->
          captured.body.push([chunk, encoding])
        response.on "end", ->
          captured.trailers     = response.trailers
          captured.rawTrailers  = response.rawTrailers
          callback null, captured

      if request.body
        for part in request.body
          http.write(part[0], part[1])
      http.end()
    else
      callback null


module.exports = passThrough
