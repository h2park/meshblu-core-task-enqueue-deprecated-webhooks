_ = require 'lodash'
async = require 'async'
UUID = require 'uuid'
TokenManager = require 'meshblu-core-manager-token'
DeviceManager = require 'meshblu-core-manager-device'
http = require 'http'

class EnqueueWebhooks
  constructor: (options={},dependencies={}) ->
    {@datastore,@jobManager, uuidAliasResolver,cache,pepper,@tokenManager} = options
    @deviceManager = new DeviceManager {@datastore, uuidAliasResolver}
    @tokenManager ?= new TokenManager {cache, uuidAliasResolver, pepper}

  _doCallback: (request, code, callback) =>
    response =
      metadata:
        responseId: request.metadata.responseId
        code: code
        status: http.STATUS_CODES[code]
    callback null, response

  do: (request, callback) =>
    {auth, toUuid, fromUuid, messageType} = request.metadata
    message = JSON.parse request.rawData

    @_send {auth, fromUuid, toUuid, messageType, message}, (error) =>
      return callback error if error?
      return @_doCallback request, 204, callback

  _createJob: ({auth, uuid, toUuid, fromUuid, messageType, message, options}, callback) =>
    job =
      metadata: {
        auth
        uuid
        toUuid
        fromUuid
        messageType
        message
        options
        responseId: UUID.v4()
        jobType: 'DeliverWebhook'
      }
      data: message
    @jobManager.createRequest 'request', job, callback

  _send: ({auth, toUuid, fromUuid, messageType, message}, callback) =>
    return callback null unless _.contains ['sent', 'broadcast'], messageType

    lookupUuid = toUuid

    @deviceManager.findOne {uuid:lookupUuid}, (error, device) =>
      return callback error if error?

      forwarders = device?.meshblu?.messageHooks
      return callback null unless forwarders?

      async.eachSeries forwarders, (options, next) =>
        @tokenManager.generateAndStoreTokenInCache lookupUuid, (error, token) =>
          auth =
            uuid: lookupUuid
            token: token

          @_createJob {auth, uuid: lookupUuid, toUuid, fromUuid, messageType, message, options}, next
      , callback

module.exports = EnqueueWebhooks
