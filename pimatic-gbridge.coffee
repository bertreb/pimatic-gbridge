module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  types = env.require('decl-api').types
  rp = require 'request-promise'
  gbridgeConnector = require('./gbridge-connector')(env)
  switchAdapter = require('./adapters/switch')(env)
  lightAdapter = require('./adapters/light')(env)
  mqtt = require('mqtt')
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

      deviceConfigDef = require("./device-config-schema")
      @framework.deviceManager.registerDeviceClass('GbridgeDevice', {
        configDef: deviceConfigDef.GbridgeDevice,
        createCallback: (config, lastState) => new GbridgeDevice(config, lastState, @framework, @)
      })

  class GbridgeDevice extends env.devices.PresenceSensor

    constructor: (@config, lastState, @framework, @plugin) ->
      #@config = config
      @id = @config.id
      @name = @config.name
      #@config.devices = config.devices

      @devMgr = @framework.deviceManager
      @gbridgeDevices = []
      @adapters = {}
      @debug = @plugin.config?.debug or false

      @_gbridgeConnected = false
      @_mqttConnected = false
      @emit 'presence', false

      @mqttOptions =
          host: @plugin.config?.mqttServer or @plugin.configProperties.mqttServer.default
          port: 1883
          username: @plugin.config?.mqttUsername or ""
          password: @plugin.config?.mqttPassword or ""
          clientId: 'pimatic_' + Math.random().toString(16).substr(2, 8)
          protocolVersion: @plugin.config?.mqttProtocolVersion or 4
          queueQoSZero: true
          keepalive: 180
          clean: true
          rejectUnauthorized: false
          reconnectPeriod: 15000
          debug: @plugin.config?.debug or false
      if @plugin.config.mqttProtocol == "MQTTS"
        #@mqttOptions["protocolId"] = "MQTTS"
        @mqttOptions["protocol"] = "mqtts"
        @mqttOptions.port = 8883
        @mqttOptions["keyPath"] = @plugin.config?.certPath or @plugin.configProperties.certPath.default
        @mqttOptions["certPath"] = @plugin.config?.keyPath or @plugin.configProperties.keyPath.default
        @mqttOptions["ca"] = @plugin.config?.caPath or @plugin.configProperties.caPath.default
      else
        @mqttOptions["protocolId"] = @config?.mqttProtocol or @plugin.configProperties.mqttProtocol.default

      checkMultipleDevices = []
      @framework.variableManager.waitForInit()
      .then () =>
        for _device in @config.devices
          do(_device) =>
            try
              device = @framework.deviceManager.getDeviceById(_device.pimatic_device_id)
              if device instanceof env.devices.DimmerActuator
                #device type implemented
              else if device instanceof env.devices.SwitchActuator
                #device type implemented
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
            catch err
              throw new Error "Device #{_device.pimatic_device_id} does not exist"
      .catch (err) =>
        env.logger.error "Something is wrong: " + err

      if @plugin.gbridgeSubscription is "Free" and @config.devices.length > 4
        throw new Error "Your subscription allows max 4 devices"

      @mqttConnector = new mqtt.connect(@mqttOptions)
      @mqttConnector.on "connect", () =>
        env.logger.debug "Successfully connected to MQTT server"
        @mqttConnector.subscribe(@plugin.mqttBaseTopic, (err,granted) =>
          if granted?
            env.logger.debug "Mqtt subscribed to gBridge"
            @_connectionStatus("mqttConnected")
          if err?
            env.logger.debug err
        )

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
        @framework.variableManager.waitForInit()
        .then () =>
          @gbridgeConnector.getDevices()
          .then (devices) =>
            @gbridgeDevices = devices
            env.logger.debug "gbridge devices received, devices: " + JSON.stringify(devices)
            @addAdapters()
            .then () =>
              env.logger.debug "Adapters added"
              @syncDevices()
              .then () =>
                if @config.devices.length is 0
                  @mqttConnector.end()
                else
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
        switch String message
          when "EXECUTE"
            # do nothing
            env.logger.debug "EXECUTE received: " + JSON.stringify(packet)
          when "SYNC"
            env.logger.debug "SYNC received: " + JSON.stringify(packet)
          when "QUERY"
            env.logger.debug "device_id: " + _device_id + ", message: " + message + ", " + JSON.stringify(packet)
            for _device in @config.devices
              _adapter = @adapters[_device.pimatic_device_id]
              if _adapter?
                _adapter.publishState()
          else
            for adapter in @adapters
              if String adapter.gBridgeDeviceId == String _device_id
                if topic.endsWith('/set')
                  env.logger.debug "/set received for gbridge device #{_device_id}, no action"
                else
                  adapter.executeAction(_trait, _value)

      @framework.on "deviceRemoved", (device) =>
        if _.find(@config.devices, (d) => d.pimatic_device_id == device.id)
          throw new Error "Please remove device also in gBridge"
          env.logger.info "please remove device also in gBridge!"
          # delete device in gBridge
          # delete adapter
          # delete device-item this device

      super()

    _connectionStatus: (connector) =>
      if connector == "gbridgeConnected" then @_gbridgeConnected = true
      if connector == "gbridgeDisconnected" then @_gbridgeConnected = false
      if connector == "mqttConnected" then @_mqttConnected = true
      if connector == "mqttDisconnected" then @_mqttConnected = false
      if @_gbridgeConnected and @_mqttConnected
        env.logger.info "Gbridge online"
        @emit 'presence', true
      else
        env.logger.info "Gbridge offline"
        @emit 'presence', false

    _addAdapter: (pimatic_divice_id, newAdapter) =>
      @adapters[pimatic_divice_id] = newAdapter

    _getAdapter: (device_id) =>
      adapter = @adapters[device_id]
      if adapter?
        return adapter
      else
        for adapter2 of @adapters
          if String adapter2.gbridgeDeviceId == String device_id
            return adapter2
        env.logger.error "Adapter for device id: '#{device_id}' not found"
        return undefined

    getGbridgeDeviceId: (pimatic_device_name) =>
      for gbridgeDevice in @gbridgeDevices
        if gbridgeDevice.name == pimatic_device_name
          return gbridgeDevice.id

    addAdapters: () =>
      return new Promise( (resolve,reject) =>
        for _value, key in @config.devices
          pimaticDevice = @devMgr.getDeviceById(_value.pimatic_device_id)
          unless pimaticDevice?
            reject()

          _adapterConfig =
            mqttConnector: @mqttConnector
            pimaticDevice: pimaticDevice
            mqttPrefix: @plugin.gbridgePrefix
            mqttUser: @plugin.userPrefix
            gbridgeDeviceId: @getGbridgeDeviceId(_value.name)
            twoFa: _value.twofa
            #twoFaPin: if _value.twofaPin? then _value.twofaPin else undefined
          if pimaticDevice instanceof env.devices.DimmerActuator
            env.logger.debug "Add light adapter with ID: " + pimaticDevice.id
            @adapters[_value.pimatic_device_id] = new lightAdapter(_adapterConfig)
          else if pimaticDevice instanceof env.devices.SwitchActuator
            env.logger.debug "Add switch adapter with ID: " + pimaticDevice.id
            @adapters[_value.pimatic_device_id] = new switchAdapter(_adapterConfig)
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
        gbridgeUpdates = []
        gbridgeRemovals = []

        if @config.devices? and @gbridgeDevices?
          for _device in @config.devices
            if !_.find(@gbridgeDevices, (d) =>
              d.name == _device.name)
              gbridgeAdditions.push _device
            # check if the twofa changed and an update is needed
            else
              for _gbridgeDevice in @gbridgeDevices
                gbridgeTwofa = if _gbridgeDevice.twofa? then _gbridgeDevice.twofa else "none"
                deviceTwofa = if _device.twofa? then _device.twofa else "none"
                if (_gbridgeDevice.name is _device.name) and (gbridgeTwofa isnt deviceTwofa)
                  gbridgeUpdates.push _device
          for _gbridgeDevice in @gbridgeDevices
            if  !_.find(@config.devices, (d) =>
              d.name == _gbridgeDevice.name)
              gbridgeRemovals.push _gbridgeDevice

          env.logger.debug "gbridgeAdditions: " + JSON.stringify(gbridgeAdditions)
          env.logger.debug "gbridgeUpdates: " + JSON.stringify(gbridgeUpdates)
          env.logger.debug "gbridgeRemovals: " + JSON.stringify(gbridgeRemovals)

          for _device in gbridgeAdditions
            adapter = @_getAdapter(_device.pimatic_device_id)
            unless adapter?
              env.logger.error "Adapter not found for pimatic device '#{_device.pimatic_device_id}'"
              reject()
            env.logger.debug "Device: '" + _device.name + "' not found in gBridge, adding"
            _deviceAdd =
              name: _device.name
              type: adapter.getType()
              traits: adapter.getTraits()
              twofa: adapter.getTwoFa()
            @gbridgeConnector.addDevice(_deviceAdd)
            .then (device) =>
              for _value, key in @config.devices
                if _value.name is device.name
                  #@config.devices[key]["gbridge_device_id"] = device.id
                  @adapters[_value.pimatic_device_id].setGbridgeDeviceId(device.id)
                  env.logger.debug "Device '#{_device.name}' updated with gbridgeId '#{device.id}'"
            .catch (err) =>
              env.logger.error "Error: updating gbridge_device_id: " + JSON.stringify(err,null,2)
              reject()

          for _device in gbridgeUpdates
            adapter = @adapters[_device.pimatic_device_id]
            unless adapter?
              env.logger.error "Adapter not found for pimatic device '#{_device.gbridge_device_id}'"
              reject()
            adapter.setTwofa(_device.twofa)
            _deviceUpdate =
              name: _device.name
              type: adapter.getType()
              traits: adapter.getTraits()
              twofa: adapter.getTwoFa()
            env.logger.debug "Updating device: '" + _device.name + "' with " + JSON.stringify(_deviceUpdate) + " and gbridgeID " + @getGbridgeDeviceId(_device.name)
            @gbridgeConnector.updateDevice(_deviceUpdate, @getGbridgeDeviceId(_device.name))
            .then (device) =>
              env.logger.debug "config.device updated with gbridge.device_id: " + device.id
              env.logger.debug "Device updated"
            .catch (err) =>
              env.logger.error "Device not updated: " + JSON.stringify(err,null,2)
              reject()


          for _deviceRemove in gbridgeRemovals
            env.logger.debug "GbridgeDevice: '" + _deviceRemove.name + "' not found in Config, removing from gBridge"
            @gbridgeConnector.removeDevice(_deviceRemove.id)
            .then () =>
              env.logger.debug "Device #{_deviceRemove.name} removed from gBridge"
            .catch (err) =>
              env.logger.error "Error: device #{_deviceRemove.name} not removed from gBridge, " + err
              reject()

          env.logger.debug "gBridge and Devices synced"
          @gbridgeConnector.requestSync()

        resolve()
      )

    inArray: (value, array) ->
      if value? and array?
        for _value in array
          if value.localeCompare(_value.name)
            return true
      return false

    destroy: ->
      for adapter of @adapters
        delete adapters
      if @mqttConnector?
        @mqttConnector.removeAllListeners()
        @mqttConnector.end()
        @gbridgeConnector.removeAllListeners()
        @.removeAllListeners()
      super()


  plugin = new GbridgePlugin
  return plugin
