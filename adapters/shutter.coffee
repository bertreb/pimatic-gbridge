module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'
  childProcess = require("child_process")


  class ShutterAdapter extends events.EventEmitter

    constructor: (adapterConfig) ->

      @device = adapterConfig.pimaticDevice
      @subDeviceId = adapterConfig.pimaticSubDeviceId
      @topicPrefix = adapterConfig.mqttPrefix
      @topicUser = adapterConfig.mqttUser
      @gbridgeDeviceId = Number adapterConfig.gbridgeDeviceId
      @mqttConnector = adapterConfig.mqttConnector
      @positionCommand = adapterConfig.auxiliary

      @twoFa = adapterConfig.twoFa
      @twoFaPin = adapterConfig.twoFaPin

      @position = 0

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
          if @positionCommand?
            value=Math.max(0,value)
            value = Math.min(100,value)
            command = @positionCommand + " #{value}"
            childProcess.exec(command, (err, stdout, stderr) =>
              if (err)
                #some err occurred
                env.logger.error "Error in Shutter adapter aux command " + err
                return
              else
                # the *entire* stdout and stderr (buffered)
                env.logger.debug "stdout: #{stdout}"
                env.logger.debug "stderr: #{stderr}"
                @position = Number stdout
            )
          env.logger.debug "Shutter moved from #{@position} to #{value}"
        when 'requestsync'
          env.logger.debug "Requestsync -> publish state for device " + @device.id + ", set state: " + value
          @publishState()
        else
          env.logger.error "Unknown action '#{type}'"

    publishState: () =>
      _mqttHeader = @getTopic() + '/openclose/set'
      env.logger.debug "Publish position, mqttHeader: " + _mqttHeader + ", position: " + @position
      @mqttConnector.publish(_mqttHeader, String @position)

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
