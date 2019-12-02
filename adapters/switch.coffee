module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'

  class SwitchAdapter extends events.EventEmitter

    constructor: (adapterConfig) ->

      @device = adapterConfig.pimaticDevice
      @topicPrefix = adapterConfig.mqttPrefix
      @topicUser = adapterConfig.mqttUser
      @gbridgeDeviceId = Number adapterConfig.gbridgeDeviceId
      @mqttConnector = adapterConfig.mqttConnector

      @twoFa = adapterConfig.twoFa
      @twoFaPin = adapterConfig.twoFaPin

      @device.on "state", deviceStateHandler
      @device.system = @

      @publishState()

    deviceStateHandler = (state) ->
      # device status changed, updating device status in gBridge
      _mqttHeader = @system.getTopic() + '/onoff/set'
      env.logger.debug "Device state change, publish state: mqttHeader: " + _mqttHeader + ", state: " + state
      @system.mqttConnector.publish(_mqttHeader, String state)

    executeAction: (type, value) ->
      # device status changed, updating device status in gBridge
      env.logger.debug "received action, type: " + type + ", state: " + value
      switch type
        when 'onoff'
          env.logger.debug "Execute action for device " + @device.id + ", set state: " + value
          @device.changeStateTo(Boolean value>0)
        when 'requestsync'
          env.logger.debug "Requestsync -> publish state for device " + @device.id + ", set state: " + value
          @publishState()
        else
          env.logger.error "Unknown action '#{type}'"

    publishState: () =>
      _mqttHeader = @getTopic() + '/onoff/set'
      @device.getState().then((state) =>
        env.logger.debug "Publish state, mqttHeader: " + _mqttHeader + ", state: " + state
        @mqttConnector.publish(_mqttHeader, String state)
      ).catch((err) =>
        env.logger.error "STATE:" + err.message
      )

    setGbridgeDeviceId: (deviceId) =>
      @gbridgeDeviceId = deviceId

    getTopic: () =>
      _topic = @topicPrefix + "/" + @topicUser + "/d" + @gbridgeDeviceId
      return _topic

    getType: () ->
      return "Switch"

    getTraits: () ->
      traits = [
        {'type' : 'OnOff'}
      ]
      return traits

    getTwoFa: () =>
      _twoFa =
        used: false
      switch @twoFa
        when "ack"
          _twoFa["used"] = true
          _twoFa["method"] = "ack"
        #when "pin"
        #  _twoFa["used"] = true
        #  _twoFa["method"] = "pin"
        #  _twoFa["pin"] = String @twoFaPin
      return _twoFa

    destroy: ->
      @device.removeListener "state", deviceStateHandler
