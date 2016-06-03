# The Replay module holds global configution properties and methods.


Catalog           = require("./catalog")
Chain             = require("./chain")
debug             = require("./debug")
{ EventEmitter }  = require("events")
logger            = require("./logger")
passThrough       = require("./pass_through")
recorder          = require("./recorder")


# Supported modes.
MODES = ["bloody", "cheat", "record", "replay"]

# Headers that are recorded/matched during replay.
MATCH_HEADERS = [/^accept/, /^authorization/, /^body/, /^content-type/, /^host/, /^if-/, /^x-/]


# Instance properties:
#
# catalog   - The catalog is responsible for loading pre-recorded responses
#             into memory, from where they can be replayed, and storing captured responses.
#
# chain     - The proxy chain.  Essentially an array of proxies through which
#             each request goes, from first to last.  You generally don't need
#             to use this unless you decide to reconstruct your own chain.
#
#             When adding new proxies, you probably want those executing ahead
#             of any existing proxies (certainly the pass-through proxy), so
#             you'll want to prepend them.  The `use` method will prepend a
#             proxy to the chain.
#
# headers   - Only these headers are matched when recording/replaying.  A list
#             of regular expressions.
#
# fixtures  - Main directory for replay fixtures.
#
# mode      - The mode we're running in, one of:
#   bloody  - Allow outbound HTTP requests, don't replay anything.  Use this to
#             test your code against changes to 3rd party API.
#   cheat   - Allow outbound HTTP requests, replay captured responses.  This
#             mode is particularly useful when new code makes new requests, but
#             unstable yet and you don't want these requests saved.
#   record  - Allow outbound HTTP requests, capture responses for future
#             replay.  This mode allows you to capture and record new requests,
#             e.g. when adding tests or making code changes.
#   replay  - Do not allow outbound HTTP requests, replay captured responses.
#             This is the default mode and the one most useful for running tests
class Replay extends EventEmitter
  constructor: (mode)->
    unless ~MODES.indexOf(mode)
      throw new Error("Unsupported mode '#{mode}', must be one of #{MODES.join(", ")}.")
    @chain  = new Chain()
    @mode   = mode
    # Localhost servers: pass request to localhost
    @_localhosts = { "localhost": true, '127.0.0.1': true }
    # Pass through requests to these servers
    @_passThrough = { }
    # Dropp connections to these servers
    @_dropped = { }
    @catalog = new Catalog(this)
    @headers = MATCH_HEADERS

    # Automatically emit connection errors and such, also prevent process from failing.
    @on "error", (error, url)=>
      debug("Replay: #{error.message || error}")


  # Addes a proxy to the beginning of the processing chain, so it executes ahead of any existing proxy.
  #
  # Example
  #     replay.use replay.logger()
  use: (proxy)->
    @chain.prepend(proxy)

  # Alias allow to passThrough for backward compatibility
  allow: (hosts...)->
    @passThrough(hosts...)

  # Pass through all requests to these hosts
  passThrough: (hosts...)->
    @reset(hosts...)
    for host in hosts
      @_passThrough[host] = true

  # True to pass through requests to this host
  isPassThrough: (host)->
    domain = host.replace(/^[^.]+/, '*')
    return !!(@_passThrough[host] || @_passThrough[domain] || @_passThrough["*.#{host}"])

  # Do not allow network access to these hosts (drop connection)
  drop: (hosts...)->
    @reset(hosts...)
    for host in hosts
      @_dropped[host] = true

  # True if this host is on the dropped list
  isDropped: (host)->
    domain = host.replace(/^[^.]+/, '*')
    return !!(@_dropped[host] || @_dropped[domain] || @_dropped['*.#{host}'])

  # Treats this host as localhost: requests are routed directly to 127.0.0.1, no
  # replay.  Useful when you want to send requests to the test server using its
  # production host name.
  localhost: (hosts...)->
    @reset(hosts...)
    for host in hosts
      @_localhosts[host] = true

  # True if this host should be treated as localhost.
  isLocalhost: (host)->
    domain = host.replace(/^[^.]+/, '*')
    return !!(@_localhosts[host] || @_localhosts[domain] || @_localhosts["*.#{host}"])

  # Use this when you want to exclude host from dropped/pass-through/localhost
  reset: (hosts...)->
    for host in hosts
      delete @_localhosts[host]
      delete @_passThrough[host]
      delete @_dropped[host]

  @prototype.__defineGetter__ "fixtures", ->
    @catalog.getFixturesDir()

  @prototype.__defineSetter__ "fixtures", (dir)->
    # Clears loaded fixtures, and updates to new dir
    @catalog.setFixturesDir(dir)


replay = new Replay(process.env.REPLAY || "replay")


# The default processing chain (from first to last):
# - Pass through requests to localhost
# - Log request to console is `deubg` is true
# - Replay recorded responses
# - Pass through requests in bloody and cheat modes
passWhenBloodyOrCheat = (request)->
  return replay.isPassThrough(request.url.hostname) ||
         (replay.mode == "cheat" && !replay.isDropped(request.url.hostname))
passToLocalhost = (request)->
  return replay.isLocalhost(request.url.hostname) ||
         replay.mode == "bloody"

replay.use passThrough(passWhenBloodyOrCheat)
replay.use recorder(replay)
replay.use logger(replay)
replay.use passThrough(passToLocalhost)


module.exports = replay
