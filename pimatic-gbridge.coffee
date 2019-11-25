module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  types = env.require('decl-api').types
  rp = require 'request-promise'
  gbridgeConnector = require('./gbridge-connector')(env)
  switchAdapter = require('./adapters/switch')(env)
  lightAdapter = require('./adapters/light')(env)
  mqtt = require('mqtt')
  match = require('mqtt-wildcard')
  _ = require('lodash')


  class GbridgePlugin extends env.plugins.Plugin
    init: (app, @framework, @config) =>

      pluginConfigDef = require './pimatic-gbridge-config-schema'
      configProperties = pluginConfigDef.properties
      @gbridgePrefix = "gBridge"
      @userPrefix = (@config?.mqttUsername).split("-")[1] or ""# the second part of mqtt username with 'u'
      @debug = @config?.debug or false
      @mqttOptions =
          host: @config?.mqttServer or configProperties.mqttServer.default
          port: 1883
          username: @config?.mqttUsername or ""
          password: @config?.mqttPassword or ""
          clientId: 'pimatic_' + Math.random().toString(16).substr(2, 8)
          protocolVersion: @config?.protocolVersion or 4
          protocolId: @config?.mqttProtocol or configProperties.mqttProtocol.default
          keepalive: 180
          clean: true
          rejectUnauthorized: false
      if @config.protocol is "MQTTS"
        @mqttOptions.protocolId = "MQTTS"
        @mqttOptions.host = "mqtts://" + options.url
        @mqttOptions.port = 8883
        @mqttOptions["key"] = @config?.certPath or configProperties.certPath.default
        @mqttOptions["cert"] = @config?.keyPath or configProperties.keyPath.default
        @mqttOptions["ca"] = @config?.caPath or configProperties.caPath.default

      @gbridgeOptions =
        subscription: @config?.gbridgeSubscription or configProperties.gbridgeSubscription.default
        server: @config?.gbridgeServer or configProperties.gbridgeServer.default
        apiKey: @config?.gbridgeApiKey or ""

      @gbridgeSubscription = @config.gbridgeSubscription
      @mqttBaseTopic = @gbridgePrefix + "/" + @userPrefix + "/#"

      env.logger.info JSON.stringify(@mqttOptions)

      @mqttClient = null
      @Connection = new Promise( (resolve, reject) =>
        @mqttClient = new mqtt.connect(@mqttOptions)
        @mqttClient.on("connect", () =>
          resolve()
        )

        @mqttClient.on('error', reject)

        @mqttClient.on "connect", () =>
          env.logger.debug "Successfully connected to MQTT server"

        @mqttClient.on 'reconnect', () =>
          env.logger.debug "Reconnecting to MQTT server"

        @mqttClient.on 'offline', () =>
          env.logger.debug "MQTT server is offline"

        @mqttClient.on 'error', (error) ->
          env.logger.error "Mqtt server error #{error}"
          env.logger.debug error.stack

        @mqttClient.on 'close', (msg) ->
          env.logger.debug "Connection with MQTT server was closed " + msg

        )

      deviceConfigDef = require("./device-config-schema")
      @framework.deviceManager.registerDeviceClass('GbridgeDevice', {
        configDef: deviceConfigDef.GbridgeDevice,
        createCallback: (config, lastState) => new GbridgeDevice(config, lastState, @framework, @)
      })

  class GbridgeDevice extends env.devices.Device

    constructor: (@config, lastState, @framework, @plugin) ->
      @id = @config.id
      @name = @config.name

      @devMgr = @framework.deviceManager
      @gbridgeDevices = []
      @adapters = {}

      @inited = false

      @gbridgeConnector = new gbridgeConnector(@plugin.gbridgeOptions)
      @mqttConnector = @plugin.mqttClient

      checkMultipleDevices = []
      for _device in @config.devices
        do(_device) =>
          device = @framework.deviceManager.getDeviceById(_device.pimatic_device_id)
          if device instanceof env.devices.DimmerActuator
            #OK @configDevices.push _device
          else if device instanceof env.devices.SwitchActuator
            #OK @configDevices.push _device
          else if device instanceof env.devices.HeatingThermostat
            throw new Error "Device type HeatingThermostat not implemented"
          else if device instanceof env.devices.ShutterController
            throw new Error "Device type ShutterController not implemented"
          else
            throw new Error "Device type does not exist"
          if _.indexOf(checkMultipleDevices, String _device.pimatic_device_id) > -1
            throw new Error "#{device.id} is already used"
          else
            checkMultipleDevices.push String _device.pimatic_device_id

      if @plugin.gbridgeSubscription is "Free" and @config.devices.length > 4
        throw new Error "Your subscription allows max 4 devices"

      @framework.on 'after init', =>
        @mqttConnector.subscribe(@plugin.mqttBaseTopic, (err) =>
          if !(err)
            env.logger.debug "Mqtt subscribed to gBridge"
            if @debug then env.logger.info "Mqtt subscribed to gBridge"
            @emit "mqttConnected"
          else
            @emit "error", err
        )

      @gbridgeConnector.on 'gbridgeConnected', =>
        env.logger.debug "gbridge connected"
        if @debug then env.logger.info "gbridge connected"
        @framework.variableManager.waitForInit()
        .then () =>
          @addAdapters()
          .then () =>
            env.logger.debug "Adapters added"
            @gbridgeConnector.getDevices()
            .then (devices) =>
              env.logger.debug "gbridge devices received, devices: " + JSON.stringify(devices)
              @gbridgeDevices = devices
              @syncDevices()
              .then () =>
                @inited = true
                if @debug then env.logger.info "connectors active"
              .catch (err) =>
                env.logger.error "Error suncing devices: " + err
            .catch (err) =>
              env.logger.error "Error getting devices: " + err
          .catch (err) =>
            env.logger.error("Error adding adapters! ") # + err)

      @gbridgeConnector.on 'error', (err) =>
        env.logger.error "Error: " + err

      @mqttConnector.on 'message', (topic, message, packet) =>

        _info = (String topic).split('/') #Tomatch(topic, @baseTopic)?
        _gBridgePrefix = _info[0]
        _userPrefix = _info[1]
        _device_id = Number _info[2].substr(1)
        _trait = _info[3]
        _value = String message #JSON.parse(message)

        env.logger.debug "topic: " + topic + ", message: " + message + " received " + JSON.stringify(packet)
        if @debug then env.logger.info env.logger.info "topic: " + topic + ", message: " + message + " received " + JSON.stringify(packet)
        switch String message
          when "EXECUTE"
            # do nothing
            env.logger.debug "EXECUTE received: " + JSON.stringify(packet)
          when "SYNC"
            env.logger.debug "SYNC received: " + JSON.stringify(packet)
          when "QUERY"
            env.logger.debug "device_id: " + _device_id + ", message: " + message + ", " + JSON.stringify(packet)
            for _device in @config.devices
              _adapter = @getAdapter(_device.pimatic_device_id)
              if _adapter?
                _adapter.publishState()
          else
            adapter = @getAdapter(_device_id)
            if adapter?
              if topic.endsWith('/set')
                # do nothing yet
              else
                adapter.executeAction(_trait, _value)

      super()


    getAdapter: (deviceId) =>
      _adapter1 = _.find(@adapters, (d) => ((String d.gbridgeDeviceId)).match(String deviceId))
      if _adapter1?
        env.logger.debug "gBridgeDeviceID match found"
        return _adapter1
      _adapter2 = _.find(@adapters, (d) => ((String d.device.id)).match(String deviceId))
      if _adapter2?
        env.logger.debug "pimaticDeviceID match found"
        return _adapter2
      return undefined

    addAdapters: () =>
      return new Promise( (resolve,reject) =>
        for _value, key in @config.devices
          pimaticDevice = @devMgr.getDeviceById(_value.pimatic_device_id)
          unless pimaticDevice?
            reject()
          @config.devices[key].gbridge_device_id = 0 unless _value.pimatic_device_id?

          _adapterConfig =
            mqttConnector: @plugin.mqttClient
            pimaticDevice: pimaticDevice
            mqttPrefix: @plugin.gbridgePrefix
            mqttUser: @plugin.userPrefix
            gbridgeDeviceId: if _value.gbridge_device_id? then _value.gbridge_device_id else 0
            twoFa: @twoFa
            twoFaPin: @twoFaPin
          if pimaticDevice instanceof env.devices.DimmerActuator
            env.logger.debug "Add light adapter with ID: " + pimaticDevice.id
            @adapters[String pimaticDevice.id] = new lightAdapter(_adapterConfig)
          else if pimaticDevice instanceof env.devices.SwitchActuator
            env.logger.debug "Add switch adapter with ID: " + pimaticDevice.id
            @adapters[String pimaticDevice.id] = new switchAdapter(_adapterConfig)
          else if pimaticDevice instanceof env.devices.HeatingThermostat
            env.logger.debug "Device type HeatingThermostat not implemented"
          else if pimaticDevice instanceof env.devices.ShutterController
            env.logger.debug "Device type ShutterController not implemented"
          else
            env.logger.error "Device type does not exist"
        resolve()
      )

    syncDevices: () =>
      return new Promise( (resolve,reject) =>
        gbridgeAdditions = []
        gbridgeRemovals = []

        if @config.devices? and @gbridgeDevices?
          for _device in @config.devices
            if !@inArray(_device.name, @gbridgeDevices)
              gbridgeAdditions.push _device
          for _gbridgeDevice in @gbridgeDevices
            if !@inArray(_gbridgeDevice.name, @config.devices)
              gbridgeRemovals.push _gbridgeDevice

          env.logger.debug "gbridgeAdditions: " + JSON.stringify(gbridgeAdditions)
          env.logger.debug "gbridgeRemovals: " + JSON.stringify(gbridgeRemovals)
          for _device in gbridgeAdditions
            adapter = @getAdapter(_device.pimatic_device_id)
            unless adapter?
              env.logger.error "Adapter not found for pimatic device '#{_device.gbridge_device_id}'"
              return
            env.logger.debug "Device: '" + _device.name + "' not found in gBridge, adding"
            _deviceAdd =
              name: _device.name
              type: adapter.getType()
              traits: adapter.getTraits()
            _twofa = adapter.getTwoFa()
            if _twofa.used
              _deviceAdd["twafa"] = _twofa.twafa
              if _twofa.twoFa.twofaPin?
                _deviceAdd["twofapin"] = _twofa.twoFaPin
            @gbridgeConnector.addDevice(_deviceAdd)
            .then (device) =>
              env.logger.debug "config.device to be updated with gbridge.device_id: " + device.id
              for _value, key in @config.devices
                if _value.name is device.name
                  #update all 3 configs
                  @config.devices[key]["gbridge_device_id"] = device.id
                  @adapters[_value.pimatic_device_id]["gbridge_device_id"] = device.id
                  @getAdapter(_value.pimatic_device_id).gbridgeDeviceId = device.id
                  env.logger.debug "config.device updated with gbridge.device_id: " + device.id
            .catch (err) =>
              env.logger.error "Error: updating gbridge_device_id: " + err
              reject()

          for _deviceRemove in gbridgeRemovals
            env.logger.debug "GbridgeDevice: '" + _deviceRemove.name + "' not found in Config, removing from gBridge"
            @gbridgeConnector.removeDevice(_deviceRemove)
            .then () =>
              env.logger.debug "Device #{_device.name} removed from gBridge"
            .catch (err) =>
              env.logger.error "Error: device #{_device.name} not removed from gBridge, " + err
              reject()

          env.logger.debug "gBridge and Devices synced"
          @gbridgeConnector.requestSync()
        resolve()
      )

    inArray: (value, array) ->
      if value? and array?
        for _value in array
          if value == _value.name
            return true
      return false

    destroy: ->
      @mqttConnector.removeAllListeners()
      @gbridgeConnector.removeAllListeners()
      @.removeAllListeners()
      super()


  plugin = new GbridgePlugin
  return plugin
