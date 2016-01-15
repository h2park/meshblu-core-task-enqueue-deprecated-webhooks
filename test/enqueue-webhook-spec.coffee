_ = require 'lodash'
uuid = require 'uuid'
redis = require 'fakeredis'
mongojs = require 'mongojs'
Datastore = require 'meshblu-core-datastore'
JobManager = require 'meshblu-core-job-manager'
EnqueueWebhooks = require '../'

describe 'EnqueueWebhooks', ->
  beforeEach (done) ->
    @datastore = new Datastore
      database: mongojs 'enqueue-webhook-test'
      collection: 'devices'

    @datastore.remove => done()

  beforeEach ->
    @redisKey = uuid.v1()
    pepper = 'im-a-pepper'
    @jobManager = new JobManager
      client: _.bindAll redis.createClient @redisKey
      timeoutSeconds: 1

    @tokenManager = generateAndStoreTokenInCache: sinon.stub().yields null, 'abc123'

    @cache = _.bindAll redis.createClient @redisKey

    @uuidAliasResolver = resolve: (uuid, callback) => callback(null, uuid)
    options = {
      @datastore
      @uuidAliasResolver
      @jobManager
      pepper
      @client
      @tokenManager
    }

    @sut = new EnqueueWebhooks options

  describe '->do', ->
    context 'messageType: broadcast', ->
      context 'when given a device', ->
        beforeEach (done) ->
          record =
            uuid: 'someone-uuid'
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
              messageType: 'broadcast'
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
            expect(@request.metadata.auth).to.deep.equal uuid: 'someone-uuid', token: 'abc123'
            expect(@request.metadata.jobType).to.equal 'DeliverWebhook'
            expect(@request.metadata.toUuid).to.equal 'emitter-uuid'
            expect(@request.metadata.messageType).to.equal 'broadcast'
            expect(@request.metadata.fromUuid).to.equal 'someone-uuid'
            expect(@request.rawData).to.equal '{"devices":"*"}'
            expect(@request.metadata.options).to.deep.equal
              url: 'http://requestb.in/18gkt511'
              method: 'POST'
              type: 'webhook'

    context 'messageType: sent', ->
      context 'when given a device', ->
        beforeEach (done) ->
          record =
            uuid: 'someone-uuid'
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
              messageType: 'sent'
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
            expect(@request.metadata.auth).to.deep.equal uuid: 'someone-uuid', token: 'abc123'
            expect(@request.metadata.jobType).to.equal 'DeliverWebhook'
            expect(@request.metadata.toUuid).to.equal 'emitter-uuid'
            expect(@request.metadata.messageType).to.equal 'sent'
            expect(@request.metadata.fromUuid).to.equal 'someone-uuid'
            expect(@request.rawData).to.equal '{"devices":"*"}'
            expect(@request.metadata.options).to.deep.equal
              url: 'http://requestb.in/18gkt511'
              method: 'POST'
              type: 'webhook'

      context 'when given a device with two webhooks of the same type', ->
        beforeEach (done) ->
          record =
            uuid: 'someone-uuid'
            meshblu:
              messageHooks: [
                type: 'webhook'
                url: 'http://requestb.in/18gkt511',
                method: 'POST'
              ,
                type: 'webhook'
                url: 'http://example.com',
                method: 'GET'
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
              messageType: 'sent'
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
            expect(@request.metadata.auth).to.deep.equal uuid: 'someone-uuid', token: 'abc123'
            expect(@request.metadata.jobType).to.equal 'DeliverWebhook'
            expect(@request.metadata.toUuid).to.equal 'emitter-uuid'
            expect(@request.metadata.messageType).to.equal 'sent'
            expect(@request.metadata.fromUuid).to.equal 'someone-uuid'
            expect(@request.rawData).to.equal '{"devices":"*"}'
            expect(@request.metadata.options).to.deep.equal
              url: 'http://requestb.in/18gkt511'
              method: 'POST'
              type: 'webhook'

          describe 'the second job', ->
            beforeEach (done) ->
              @jobManager.getRequest ['request'], (error, @request) =>
                done error

            it 'should create another job', ->
              expect(@request.metadata.auth).to.deep.equal uuid: 'someone-uuid', token: 'abc123'
              expect(@request.metadata.jobType).to.equal 'DeliverWebhook'
              expect(@request.metadata.toUuid).to.equal 'emitter-uuid'
              expect(@request.metadata.messageType).to.equal 'sent'
              expect(@request.metadata.fromUuid).to.equal 'someone-uuid'
              expect(@request.rawData).to.equal '{"devices":"*"}'
              expect(@request.metadata.options).to.deep.equal
                url: 'http://example.com'
                method: 'GET'
                type: 'webhook'

    context 'messageType: received', ->
      beforeEach (done) ->
        record =
          uuid: 'emitter-uuid'
          meshblu:
            forwarders:
              received: [
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
          rawData: '{"devices":["emitter-uuid"]}'

        @sut.do request, (error, @response) => done error

      it 'should return a 204', ->
        expectedResponse =
          metadata:
            responseId: 'its-electric'
            code: 204
            status: 'No Content'

        expect(@response).to.deep.equal expectedResponse
