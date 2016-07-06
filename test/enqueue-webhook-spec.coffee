_ = require 'lodash'
uuid = require 'uuid'
redis = require 'fakeredis'
mongojs = require 'mongojs'
Datastore = require 'meshblu-core-datastore'
JobManager = require 'meshblu-core-job-manager'
EnqueueWebhooks = require '../'

describe 'EnqueueWebhooks', ->
  beforeEach (done) ->
    database = mongojs 'enqueue-webhook-test', ['devices']
    @datastore = new Datastore
      database: database
      collection: 'devices'

    database.devices.remove done

  beforeEach ->
    @redisKey = uuid.v1()
    pepper = 'im-a-pepper'
    @jobManager = new JobManager
      client: _.bindAll redis.createClient @redisKey
      timeoutSeconds: 1
      jobLogSampleRate: 1

    @cache = _.bindAll redis.createClient @redisKey

    @uuidAliasResolver = resolve: (uuid, callback) => callback(null, uuid)
    options = {
      @datastore
      @uuidAliasResolver
      @jobManager
      pepper
      @client
    }

    @sut = new EnqueueWebhooks options

  describe '->do', ->
    context 'messageType: received', ->
      context 'when given a device', ->
        beforeEach (done) ->
          record =
            uuid: 'emitter-uuid'
            meshblu:
              messageHooks: [
                  type: 'webhook'
                  url: 'http://requestb.in/18gkt511',
                  method: 'POST'
                ]

          @datastore.insert record, done

        beforeEach (done) ->
          request =
            metadata:
              auth:
                uuid: 'whoever-uuid'
                token: 'some-token'
              responseId: 'its-electric'
              toUuid: 'emitter-uuid'
              fromUuid: 'someone-uuid'
              messageType: 'received'
            rawData: '{"devices":"*"}'

          @sut.do request, (error, @response) => done error

        it 'should return a 204', ->
          expectedResponse =
            metadata:
              responseId: 'its-electric'
              code: 204
              status: 'No Content'

          expect(@response).to.deep.equal expectedResponse

        describe 'the first job', ->
          beforeEach (done) ->
            @jobManager.getRequest ['request'], (error, @request) =>
              done error

          it 'should create a job', ->
            expect(@request.metadata.auth).to.deep.equal uuid: 'emitter-uuid', token: 'some-token'
            expect(@request.metadata.jobType).to.equal 'DeliverWebhook'
            expect(@request.metadata.toUuid).to.equal 'emitter-uuid'
            expect(@request.metadata.messageType).to.equal 'received'
            expect(@request.metadata.fromUuid).to.equal 'someone-uuid'
            expect(@request.rawData).to.equal '{"devices":"*"}'
            expect(@request.metadata.options).to.deep.equal
              url: 'http://requestb.in/18gkt511'
              method: 'POST'
              type: 'webhook'
