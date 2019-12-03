module.exports = (env) ->

  rp = require 'request-promise'
  Promise = env.require 'bluebird'
  events = require 'events'
  _ = require 'lodash'


  class GbridgeConnector extends events.EventEmitter

    constructor: (options) ->
      @gbridgeApiUrl = options.server
      @apikey = options.apiKey
      @accessToken = null
      options =
        uri: @gbridgeApiUrl + "/auth/token"
        method: 'POST'
        body:
          apikey: @apikey
        json: true
      rp(options)
      .then (res) =>
        @accessToken = res.access_token
        @emit 'gbridgeConnected'
      .catch (err) =>
        @emit 'error', "Not possible to connect to gBridge: " + err

    getDevices: () =>
      return new Promise( (resolve,reject) =>
        @devices = []
        options =
          uri: @gbridgeApiUrl + "/device"
          method: 'GET'
          auth:
            bearer: @accessToken
          json: true
        rp(options)
        .then (_devices) =>
          @count = _.size(_devices)
          if @count is 0 then resolve(@devices)
          for _device in _devices
            options2 = 
              uri: @gbridgeApiUrl + "/device/" + _device.device_id
              method: 'GET'
              auth:
                bearer: @accessToken
              json: true
            rp(options2)
            .then (device) =>
              @devices.push device
              @count -= 1
              if @count is 0
                resolve(@devices)
            .catch (err) =>
              env.logger.error err
              reject()
        .catch (err) =>
          env.logger.error err
          reject(err)
      )

    _statusCode: (statusCode) =>
      _return =
        switch statusCode
          when 400
           "Malformed JSON in request or Data validation error"
          when 401
           "Authorization token is either missing, invalid, expired or has insufficient privileges"
          when 404
           "Device not found"
          when 405
           "Methode not allowed"
          when 500
           "Internal error"
          else
            statusCode

    addDevice: (device) =>
      return new Promise( (resolve,reject) =>
        options =
          uri: @gbridgeApiUrl + '/device'
          method: 'POST'
          body: device
          auth:
            bearer: @accessToken
          json: true
        rp(options).then((device) =>
          resolve(device)
        ).catch((err) =>
          reject(err)
        )
      )

    updateDevice: (device, device_id) =>
      return new Promise( (resolve,reject) =>
        if not device_id?
          ebv.logger.error "device_id undefined"
          reject()
        options =
          uri: @gbridgeApiUrl + '/device/' + device_id
          method: 'PATCH'
          body: device
          auth:
            bearer: @accessToken
          json: true
        rp(options).then((device) =>
          resolve(device)
        ).catch((err) =>
          reject(err)
        )
      )

    removeDevice: (device_id) =>
      return new Promise( (resolve,reject) =>
        options =
          uri: @gbridgeApiUrl + '/device/' + device_id
          method: 'DELETE'
          auth:
            bearer: @accessToken
          json: true
        rp(options).then(() =>
          resolve()
        ).catch((err) =>
          reject(err)
        )
      )

    requestSync: () =>
      return new Promise( (resolve,reject) =>
        options =
          uri: @gbridgeApiUrl + '/requestsync'
          method: 'GET'
          auth:
            bearer: @accessToken
          json: true
        rp(options).then(() =>
          resolve()
        ).catch((err) =>
          reject(err)
        )
      )
