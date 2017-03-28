_             = require 'lodash'
async         = require 'async'
UUID          = require 'uuid'
DeviceManager = require 'meshblu-core-manager-device'
http          = require 'http'

class EnqueueWebhooks
  constructor: (options={},dependencies={}) ->
    {@datastore,@jobManager,uuidAliasResolver} = options
    @deviceManager = new DeviceManager {@datastore, uuidAliasResolver}

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
    return callback null unless _.contains ['received', 'broadcast'], messageType

    lookupUuid = toUuid
    projection =
      uuid: true
      'meshblu.messageHooks': true

    @deviceManager.findOne {uuid:lookupUuid, projection}, (error, device) =>
      return callback error if error?

      forwarders = @getUniqueMessageHooks { device }
      return callback null unless forwarders?

      async.eachLimit forwarders, 100, (options, next) =>
        auth = _.cloneDeep auth
        auth.uuid = lookupUuid
        @_createJob {auth, uuid: lookupUuid, toUuid, fromUuid, messageType, message, options}, next
      , callback

  getUniqueMessageHooks: ({ device }) =>
    forwarders = _.get device, "meshblu.messageHooks"
    return null if _.isEmpty forwarders
    return null unless _.isArray forwarders
    uniqueForwarders = []
    _.each forwarders, (forwarder) =>
      alreadyExists = _.some uniqueForwarders, (existing) =>
        return _.isEqual forwarder, existing
      uniqueForwarders.push forwarder unless alreadyExists
    return uniqueForwarders

module.exports = EnqueueWebhooks
