module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'


  class TemperatureAdapter extends events.EventEmitter

    constructor: (adapterConfig) ->

      @device = adapterConfig.pimaticDevice
      @subDevice = adapterConfig.pimaticSubDeviceId
      @temperatureAttribute = adapterConfig.auxiliary
      @humidityAttribute = adapterConfig.auxiliary2
      @topicPrefix = adapterConfig.mqttPrefix
      @topicUser = adapterConfig.mqttUser
      @gbridgeDeviceId = Number adapterConfig.gbridgeDeviceId
      @mqttConnector = adapterConfig.mqttConnector

      @twoFa = adapterConfig.twoFa
      @twoFaPin = adapterConfig.twoFaPin

      @mode ="heat"

      @temperature = 0
      @temperatureSensor = false
      @humidity = 0
      @humiditySensor = false
      if @device?
        if @device.hasAttribute(@temperatureAttribute)
          temp = @device.getLastAttributeValue(@temperatureAttribute)
          @temperature = temp
          @setpoint = temp
          @device.on @temperatureAttribute, temperatureHandler
          @device.system = @
          @temperatureSensor = true
        if @device.hasAttribute(@humidityAttribute)
          humidity = @device.getLastAttributeValue(@humidityAttribute)
          @humidity = humidity
          @device.on @humidityAttribute, humidityHandler
          @humiditySensor = true

      #modeItems = ["off", "heat", "cool", "on", "auto", "fan-only", "purifier", "eco", "dry"]
      #Default gBridge supported modes: ["off","heat","on","auto"]

      @device.system = @

      if @temperatureSensor or @humiditySensor 
        @publishState()

    temperatureHandler = (ambient) ->
      # device status changed, updating device status in gBridge
      _mqttHeader3 = @system.getTopic() + '/tempset-ambient/set'
      @system.temperature = ambient
      @system.setpoint = ambient
      env.logger.debug "Device state change, publish ambient: mqttHeader: " + _mqttHeader3 + ", ambient: " + ambient
      @system.mqttConnector.publish(_mqttHeader3, String ambient)
      _mqttHeader1 = @getTopic() + '/tempset-setpoint/set'
      env.logger.debug "Publish setpoint, mqttHeader: " + _mqttHeader1 + ", setpoint: " + ambient
      @system.mqttConnector.publish(_mqttHeader1, String ambient)

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
          env.logger.debug "No action for device " + @device.id + ", set mode: " + value
        when 'tempset-setpoint'
          env.logger.debug "No action for device " + @device.id + ", set setpoint: " + value
          #@device.changeTemperatureTo(Math.round((Number value) * 100) / 100)
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
        {'type' : 'TempSet.Mode', 'modesSupported' : ["off","heat","on","eco"]},
        {'type' : 'TempSet.Ambient'}
      ]
      hum = {'type' : 'TempSet.Humidity'}
      if humiditySensor?
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
      @device.removeListener @temperatureAttribute, temperatureHandler
      @device.removeListener @humidityAttribute, humidityHandler

