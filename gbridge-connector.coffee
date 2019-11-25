module.exports = (env) ->

  rp = require 'request-promise'
  Promise = env.require 'bluebird'
  events = require 'events'


  class GbridgeConnector extends events.EventEmitter

    constructor: (options) ->
      @gbridgeApiUrl = options.server
      @apikey = options.apiKey
      @accessToken = null
      @start()

    start: () =>
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
        options =
          uri: @gbridgeApiUrl + "/device"
          method: 'GET'
          auth:
            bearer: @accessToken
          json: true
        rp(options)
        .then (devices) =>
          env.logger.debug devices.length + " gbridge devices received"
          resolve(devices)
        .catch (err) =>
          env.logger.info "=====> " + err
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
          env.logger.info "Gbridge_device_id received: " + JSON.stringify(device)
          return resolve(device)
        ).catch((err) =>
          return reject(err)     
        )
      )

    removeDevice: (device) =>
      return new Promise( (resolve,reject) =>
        options =
          uri: @gbridgeApiUrl + '/device/' + device.device_id
          method: 'DELETE'
          auth:
            bearer: @accessToken
          json: true
        rp(options).then(() =>
          return resolve(device)
        ).catch((err) =>
          return reject(err)
        )
      )

    requestSync: () =>
      options =
        uri: @gbridgeApiUrl + '/requestsync'
        method: 'GET'
        auth:
          bearer: @accessToken
        json: true
      rp(options).then(() =>
        @emit 'requestSynced'
      ).catch((err) =>
        @emit 'gbridgeError', "requestSync: " + @_statusCode err.statusCode
      )
