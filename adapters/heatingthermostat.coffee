module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'
  childProcess = require("child_process")


  class HeatingThermostatAdapter extends events.EventEmitter

    constructor: (adapterConfig) ->

      @device = adapterConfig.pimaticDevice
      @subDevice = adapterConfig.pimaticSubDeviceId
      @temperatureDevice = adapterConfig.auxiliary
      @topicPrefix = adapterConfig.mqttPrefix
      @topicUser = adapterConfig.mqttUser
      @gbridgeDeviceId = Number adapterConfig.gbridgeDeviceId
      @mqttConnector = adapterConfig.mqttConnector

      @twoFa = adapterConfig.twoFa
      @twoFaPin = adapterConfig.twoFaPin

      @device.getTemperatureSetpoint()
      .then((temp)=>
        @setpoint = temp
      )


      @thermostat = on
      @mode = "heat"
      @device.changeModeTo(@mode)
      .then(() =>
        env.logger.debug "Thermostat mode changed to " + @mode
      )
      @ambient = 0
      @ambiantSensor = false
      if @temperatureDevice?
        if @temperatureDevice.hasAttribute('temperature')
          @temperatureDevice.getTemperature()
          .then((temp)=>
            @ambient = temp
            @temperatureDevice.on "temperature", ambientHandler
            @temperatureDevice.system = @
            @ambiantSensor = true
          )

      @humidity = 0
      @humiditySensor = false
      if @temperatureDevice?
        if @temperatureDevice.hasAttribute('humidity')
          @temperatureDevice.getHumidity()
          .then((humidity)=>
            @humidity = humidity
            @temperatureDevice.on "humidity", humidityHandler
            @temperatureDevice.system = @
            @humiditySensor = true
          )

      #modeItems = ["off", "heat", "cool", "on", "auto", "fan-only", "purifier", "eco", "dry"]
      #Default gBridge supported modes: ["off","heat","on","auto"]

      @device.on "mode", modeHandler
      @device.on "temperatureSetpoint", setpointHandler
      @device.system = @

      @publishState()


    modeHandler = (mode) ->
      # device status changed, NOT updating device status in gBridge
      #_mqttHeader1 = @system.getTopic() + '/tempset-mode/set'
      #@system.mode = mode
      env.logger.debug "Device state change, no publish!!!" # publish mode: mqttHeader: " + _mqttHeader1 + ", mode: " + mode
      #@system.mqttConnector.publish(_mqttHeader1, String mode)

    setpointHandler = (setpoint) ->
      # device status changed, updating device status in gBridge
      _mqttHeader2 = @system.getTopic() + '/tempset-setpoint/set'
      @system.setpoint = setpoint
      env.logger.debug "Device state change, publish setpoint: mqttHeader: " + _mqttHeader2 + ", setpoint: " + setpoint
      @system.mqttConnector.publish(_mqttHeader2, String setpoint)

    ambientHandler = (ambient) ->
      # device status changed, updating device status in gBridge
      _mqttHeader3 = @system.getTopic() + '/tempset-ambient/set'
      @system.ambient = ambient
      env.logger.debug "Device state change, publish ambient: mqttHeader: " + _mqttHeader3 + ", ambient: " + ambient
      @system.mqttConnector.publish(_mqttHeader3, String ambient)

    humidityHandler = (humidity) ->
      # device status changed, updating device status in gBridge
      _mqttHeader4 = @system.getTopic() + '/tempset-humidity/set'
      @system.humidity = humidity
      env.logger.debug "Device state change, publish humidity: mqttHeader: " + _mqttHeader4 + ", humidity: " + humidity
      @system.mqttConnector.publish(_mqttHeader4, String humidity)

    executeAction: (type, value) ->
      # device status changed, updating device status in gBridge
      env.logger.debug "received action, type: " + type + ", state: " + value
      switch type
        when 'tempset-mode'
          env.logger.debug "Execute action for device " + @device.id + ", set mode: " + value
          switch value
            when "heat"
              @thermostat = on
              @mode = "heat"
            when "eco"
              @thermostat = on
              @mode = "eco"
            when "on"
              @thermostat = on
              @mode = "heat"
            when "off"
              @thermostat = off
              @mode = "off"
          @device.changeModeTo(@mode)
          .then(() =>
            env.logger.debug "Thermostat mode changed to " + @mode
          )
          @_setThermostat(@thermostat, @mode)
        when 'tempset-setpoint'
          env.logger.debug "Execute action for device " + @device.id + ", set setpoint: " + value
          @device.changeTemperatureTo(Math.round((Number value) * 100) / 100)
        when 'requestsync'
          env.logger.debug "Requestsync -> publish state for device " + @device.id
          @publishState()
        else
          env.logger.error "Unknown action '#{type}'"

    publishState: () =>
      _mqttHeader2 = @getTopic() + '/tempset-mode/set'
      env.logger.debug "Publish mode, mqttHeader: " + _mqttHeader2 + ", mode: " + @mode
      @mqttConnector.publish(_mqttHeader2, String @mode)

      _mqttHeader1 = @getTopic() + '/tempset-setpoint/set'
      env.logger.debug "Publish setpoint, mqttHeader: " + _mqttHeader1 + ", setpoint: " + @setpoint
      @mqttConnector.publish(_mqttHeader1, String @setpoint)

      if @ambiantSensor
        _mqttHeader3 = @getTopic() + '/tempset-ambient/set'
        env.logger.debug "Publish ambient, mqttHeader: " + _mqttHeader3 + ", ambient: " + @ambient
        @mqttConnector.publish(_mqttHeader3, String @ambient)

      if @humiditySensor
        _mqttHeader4 = @getTopic() + '/tempset-humidity/set'
        env.logger.debug "Publish humidity, mqttHeader: " + _mqttHeader4 + ", humidity: " + @humidity
        @mqttConnector.publish(_mqttHeader4, String @humidity)


    _setThermostat: (action, mode) =>
      env.logger.debug "Switch Thermostat: " + action + ", with mode: " + mode

    setGbridgeDeviceId: (deviceId) =>
      @gbridgeDeviceId = deviceId

    getGbridgeDeviceId: () =>
      return @gbridgeDeviceId

    getTopic: () =>
      _topic = @topicPrefix + "/" + @topicUser + "/d" + @gbridgeDeviceId
      return _topic

    getType: () ->
      return "Thermostat"

    getTraits: () =>
      traits = [
        {'type' : 'TempSet.Setpoint'},
        {'type' : 'TempSet.Mode'},
        {'type' : 'TempSet.Ambient'}
      ]
      hum = {'type' : 'TempSet.Humidity'}
      if @temperatureDevice? 
        if @temperatureDevice.hasAttribute('humidity')
          hum = {'type' : ' TempSet.Humidity', 'humiditySupported' : true}
      traits.push hum
      return traits

    setTwofa: (_twofa) =>
      @twoFa = _twofa

    getTwoFa: () =>
      _twoFa = null
      switch @twoFa
        when "ack"
          _twoFa = "ack"
        #when "pin"
        #  _twoFa["used"] = true
        #  _twoFa["method"] = "pin"
        #  _twoFa["pin"] = String @twoFaPin
      return _twoFa

    destroy: ->
      @device.removeListener "mode", modeHandler
      @device.removeListener "temperatureSetpoint", setpointHandler
      if @ambientDevice?
        @temperatureDevice.removeListener "temperature", ambientHandler
      if @humidityDevice?
        @temperatureDevice.removeListener "humidity", humidityHandler

