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
      @configProperties = pluginConfigDef.properties
      @gbridgePrefix = "gBridge"
      @userPrefix = (@config?.mqttUsername).split("-")[1] or ""# the second part of mqtt username with 'u'
      @debug = @config?.debug or false
      @gbridgeOptions =
        subscription: @config?.gbridgeSubscription or @configProperties.gbridgeSubscription.default
        server: @config?.gbridgeServer or @configProperties.gbridgeServer.default
        apiKey: @config?.gbridgeApiKey or ""

      @gbridgeSubscription = @config.gbridgeSubscription
      @mqttBaseTopic = @gbridgePrefix + "/" + @userPrefix + "/#"

      env.logger.info JSON.stringify(@mqttOptions)

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

      @debug = @config?.debug or false

      @_gbridgeConnected = false
      @_mqttConnected = false

      @mqttOptions =
          host: @plugin.config?.mqttServer or @plugin.configProperties.mqttServer.default
          port: 1883
          username: @plugin.config?.mqttUsername or ""
          password: @plugin.config?.mqttPassword or ""
          clientId: 'pimatic_' + Math.random().toString(16).substr(2, 8)
          protocolVersion: @config?.mqttProtocolVersion or 4
          queueQoSZero: true
          keepalive: 180
          clean: true
          rejectUnauthorized: false
          reconnectPeriod: 15000
          debug: @plugin.config?.debug or false
      if @config.mqttProtocol == "MQTTS"
        #@mqttOptions.protocolId = "MQTTS"
        @mqttOptions.protocol = "mqtts"
        #@mqttOptions.host = "mqtts://" + @mqttOptions.host
        @mqttOptions.port = 8883
        #@mqttOptions["keyPath"] = @config?.certPath or @plugin.configProperties.certPath.default
        #@mqttOptions["certPath"] = @config?.keyPath or @plugin.configProperties.keyPath.default
        #@mqttOptions["ca"] = @config?.caPath or @plugin.configProperties.caPath.default
      else
        @mqttOptions.protocolId = @config?.mqttProtocol or @plugin.configProperties.mqttProtocol.default

      checkMultipleDevices = []
      for _device in @config.devices
        do(_device) =>
          device = @framework.deviceManager.getDeviceById(_device.pimatic_device_id)
          if device instanceof env.devices.DimmerActuator
            #device type implemented
          else if device instanceof env.devices.SwitchActuator
            #device type implemented
          else if device instanceof env.devices.HeatingThermostat
            throw new Error "Device type HeatingThermostat not implemented"
          else if device instanceof env.devices.ShutterController
            throw new Error "Device type ShutterController not implemented"
          else if not device?
            throw new Error "Device #{_device.pimatic_device_id} does not exist"
          else
            throw new Error "Device type does not exist"
          if _.indexOf(checkMultipleDevices, String _device.pimatic_device_id) > -1
            throw new Error "#{device.id} is already used"
          else
            checkMultipleDevices.push String _device.pimatic_device_id

      if @plugin.gbridgeSubscription is "Free" and @config.devices.length > 4
        throw new Error "Your subscription allows max 4 devices"

      @mqttConnector = new mqtt.connect(@mqttOptions)
      @mqttConnector.on "connect", () =>
        env.logger.debug "Successfully connected to MQTT server"
        @mqttConnector.subscribe(@plugin.mqttBaseTopic, (err,granted) =>
          if granted?
            env.logger.debug "Mqtt subscribed to gBridge"
            if @debug then env.logger.info "Mqtt subscribed to gBridge: " + JSON.stringify(granted)
            @_connectionStatus("mqttConnected")
          if err?
            env.logger.error "Mqtt subscribe error " + err
        )
        if @debug and @gbridgeConnected then env.logger.info "connectors active"

      @mqttConnector.on 'reconnect', () =>
        env.logger.debug "Reconnecting to MQTT server"

      @mqttConnector.on 'offline', () =>
        env.logger.debug "MQTT server is offline"
        @_connectionStatus("mqttDisconnected")

      @mqttConnector.on 'error', (error) =>
        env.logger.error "Mqtt server error #{error}"
        env.logger.debug error.stack
        @_connectionStatus("mqttDisconnected")

      @mqttConnector.on 'close', () =>
        env.logger.debug "Connection with MQTT server was closed "
        @_connectionStatus("mqttDisconnected")

      @gbridgeConnector = new gbridgeConnector(@plugin.gbridgeOptions)
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
              if @debug then env.logger.info "gbridge devices received, devices: " + JSON.stringify(devices)
              @gbridgeDevices = devices
              @syncDevices()
              .then () =>
                @_connectionStatus("gbridgeConnected")
              .catch (err) =>
                env.logger.error "Error syncing devices: " + err
            .catch (err) =>
              env.logger.error "Error getting devices: " + err
          .catch (err) =>
            env.logger.error("Error adding adapters! ") # + err)

      @gbridgeConnector.on 'error', (err) =>
        env.logger.error "Error: " + err
        @_connectionStatus("gbridgeDisconnected")

      @mqttConnector.on 'message', (topic, message, packet) =>

        _info = (String topic).split('/') #Tomatch(topic, @baseTopic)?
        _gBridgePrefix = _info[0]
        _userPrefix = _info[1]
        _device_id = Number _info[2].substr(1)
        _trait = _info[3]
        _value = String message #JSON.parse(message)

        env.logger.debug "topic: " + topic + ", message: " + message + " received " + JSON.stringify(packet)
        if @debug then env.logger.info "topic: " + topic + ", message: " + message + " received " + JSON.stringify(packet)
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
                env.logger.debug "/set received for gbridge device #{_device_id}, no action"
              else
                adapter.executeAction(_trait, _value)

      super()

    _connectionStatus: (connector) =>
      if connector == "gbridgeConnected" then @_gbridgeConnected = true
      if connector == "gbridgeDisconnected" then @_gbridgeConnected = false
      if connector == "mqttConnected" then @_mqttConnected = true
      if connector == "mqttDisconnected" then @_mqttConnected = false
      if @_gbridgeConnected and @_mqttConnected
        env.logger.info "Gbridge online"
      else
        env.logger.info "Gbridge offline"


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
            mqttConnector: @mqttConnector
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
          if @debug
            env.logger.info "gbridgeAdditions: " + JSON.stringify(gbridgeAdditions)
            env.logger.info "gbridgeRemovals: " + JSON.stringify(gbridgeRemovals)
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
                  #update all 2 configs
                  @config.devices[key]["gbridge_device_id"] = device.id
                  @adapters[_value.pimatic_device_id]["gbridge_device_id"] = device.id
                  env.logger.debug "config.device and @adapters updated with gbridge.device_id: " + device.id
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
      for adapter of @adapters
        delete adapters
      @mqttConnector.removeAllListeners()
      @gbridgeConnector.removeAllListeners()
      @.removeAllListeners()
      super()


  plugin = new GbridgePlugin
  return plugin
