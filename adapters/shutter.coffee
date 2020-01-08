module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'

  class ShutterAdapter extends events.EventEmitter

    constructor: (adapterConfig) ->

      @device = adapterConfig.pimaticDevice
      @subDeviceId = adapterConfig.pimaticSubDeviceId
      @topicPrefix = adapterConfig.mqttPrefix
      @topicUser = adapterConfig.mqttUser
      @gbridgeDeviceId = Number adapterConfig.gbridgeDeviceId
      @mqttConnector = adapterConfig.mqttConnector

      @twoFa = adapterConfig.twoFa
      @twoFaPin = adapterConfig.twoFaPin

      @position = 0
      env.logger.debug "Closing the shutters to sync"
      @device.moveByPercentage(-100)

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
        when 'openclose'
          env.logger.debug "Execute action for device " + @device.id + ", set state: " + value
          #_position = @device._position
          if @position is value
            env.logger.debug "Shutter already in requested postion"
            return
          _move = value - @position
          env.logger.debug "Shutter moved from #{@position} to #{value}"
          @device.moveByPercentage(_move)
          @position = value
          #@device.changeStateTo(Boolean value>0) # moveToPosition??????
        when 'requestsync'
          env.logger.debug "Requestsync -> publish state for device " + @device.id + ", set state: " + value
          @publishState()
        else
          env.logger.error "Unknown action '#{type}'"

    publishState: () =>
      _mqttHeader = @getTopic() + '/openclose/set'
      #@getPosition().then((state) =>
      env.logger.debug "Publish position, mqttHeader: " + _mqttHeader + ", position: " + @position
      @mqttConnector.publish(_mqttHeader, String @position)
      #).catch((err) =>
      #  env.logger.error "STATE:" + err.message
      #)

    setGbridgeDeviceId: (deviceId) =>
      @gbridgeDeviceId = deviceId

    getGbridgeDeviceId: () =>
      return @gbridgeDeviceId

    getTopic: () =>
      _topic = @topicPrefix + "/" + @topicUser + "/d" + @gbridgeDeviceId
      return _topic

    getType: () ->
      return "Shutter"

    getTraits: () ->
      traits = [
        {'type' : 'OpenClose'}
      ]
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
      @device.removeListener "state", deviceStateHandler