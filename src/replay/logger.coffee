debug = require("./debug")
URL   = require("url")


# Simple proxy that spits all request URLs to the console if the debug settings is true.
#
# Example
#   replay.use replay.logger(exports)
logger = (settings)->
  return (request, callback)->
    debug "Requesting #{request.method} #{URL.format(request.url)}"
    request.on "response", (response)->
      debug "Received #{response.statusCode} #{URL.format(request.url)}"
    request.on "error", (error)->
      debug "Error #{error}"

    callback()
    return

module.exports = logger
