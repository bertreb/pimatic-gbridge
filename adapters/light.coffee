module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'

  class LightAdapter extends events.EventEmitter

    constructor: (adapterConfig) ->

      @device = adapterConfig.pimaticDevice
      @topicPrefix = adapterConfig.mqttPrefix
      @topicUser = adapterConfig.mqttUser
      @gbridgeDeviceId = Number adapterConfig.gbridgeDeviceId
      @mqttConnector = adapterConfig.mqttConnector

      @twoFa = adapterConfig.twoFa
      @twoFaPin = adapterConfig.twoFaPin

      @device.on 'state', deviceStateHandler
      @device.on 'dimlevel', deviceDimlevelHandler
      @device.system = @

      @publishState()

    deviceStateHandler = (state) ->
      # device status chaged, updating device status in gBridge
      _mqttHeader = @system.getTopic() + '/onoff/set'
      env.logger.debug "Device state change, publish state: mqttHeader: " + _mqttHeader + ", state: " + state
      @system.mqttConnector.publish(_mqttHeader, String state)

    deviceDimlevelHandler = (dimlevel) ->
      # device status changed, updating device status in gBridge
      _mqttHeader = @system.getTopic() + '/brightness/set'
      env.logger.debug "Device state change, publish dimlevel: mqttHeader: " + _mqttHeader + ", dimlevel: " + dimlevel
      @system.mqttConnector.publish(_mqttHeader, String dimlevel)

    executeAction: (type, value) ->
      # device status changed, updating device status in gBridge
      env.logger.debug "received action, type: " + type + ", state: " + value
      switch type
        when 'onoff'
          env.logger.debug "Execute action for device " + @device.id + ", set state: " + value
          @device.changeStateTo(value > 0)
        when 'brightness'
          env.logger.debug "Execute action for device " + @device.id + ", set state: " + value
          @device.changeDimlevelTo(value)
        when 'scene'
          env.logger.debug "Scene not implemented for device " + @device.id + ", set state: " + value
        when 'requestsync'
          env.logger.debug "Requestsync -> publish state for device " + @device.id + ", set state: " + value
          @publishState()
        else
          env.logger.error "Unknown action '#{type}'"

    publishState: () =>
      _mqttHeader1 = @getTopic() + '/onoff/set'
      @device.getState().then((state) =>
        env.logger.debug "Publish state, mqttHeader: " + _mqttHeader1 + ", state: " + state
        @mqttConnector.publish(_mqttHeader1, String state)
      ).catch((err) =>
        env.logger.error "STATE:" + err.message
      )
      _mqttHeader2 = @getTopic() + '/brightness/set'
      @device.getDimlevel().then((dimlevel) =>
        env.logger.debug "Publish dimlevel, mqttHeader: " + _mqttHeader2 + ", dimlevel: " + dimlevel
        @mqttConnector.publish(_mqttHeader2, String dimlevel)
      ).catch((err) =>
        env.logger.error "DIMLEVEL: " + err.message
      )

    setGbridgeDeviceId: (deviceId) =>
      @gbridgeDeviceId = deviceId

    getTopic: () =>
      _topic = @topicPrefix + "/" + @topicUser + "/d" + @gbridgeDeviceId
      return _topic

    getType: () ->
      return "Light"

    getTraits: () ->
      traits = [
        {'type' : 'Brightness'},
        {'type' : 'OnOff'} #,
        #{'type' : 'Scene'}
      ]
      return traits

    getTwoFa: () =>
      _twoFa =
        used: false
      switch @twoFa
        when "ack"
          _twoFa["used"] = true
          _twoFa["method"] = "ack"
        when "pin"
          _twoFa["used"] = true
          _twoFa["method"] = "pin"
          _twoFa["pin"] = @twoFaPin
      return _twoFa

    destroy: ->
      @device.removeListener 'state', deviceHandler
      @device.removeListener 'dimlevel', deviceHandler
