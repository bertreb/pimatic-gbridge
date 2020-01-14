module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'

  class LightColorAdapter extends events.EventEmitter

    constructor: (adapterConfig) ->

      @device = adapterConfig.pimaticDevice
      @subDeviceId = adapterConfig.pimaticSubDeviceId
      @topicPrefix = adapterConfig.mqttPrefix
      @topicUser = adapterConfig.mqttUser
      @gbridgeDeviceId = Number adapterConfig.gbridgeDeviceId
      @mqttConnector = adapterConfig.mqttConnector

      @twoFa = adapterConfig.twoFa
      @twoFaPin = adapterConfig.twoFaPin

      @device.on 'state', deviceStateHandler
      @device.on 'dimlevel', deviceDimlevelHandler
      @device.on 'hue', deviceHueHandler #(0-254 color, 255 is white)
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

    deviceHueHandler = (hue) ->
      # device status changed, updating device status in gBridge
      _mqttHeader = @system.getTopic() + '/colorsettingrgb/set'
      env.logger.debug "Device state change, publish rgblevel: mqttHeader: " + _mqttHeader + ", rgblevel: " + hue
      @system.mqttConnector.publish(_mqttHeader, String hue)

    executeAction: (type, value) ->
      # device status changed, updating device status in gBridge
      env.logger.debug "received action, type: " + type + ", state: " + value
      switch type
        when 'onoff'
          env.logger.debug "Execute action 'onoff' for device " + @device.id + ", set state: " + value
          @device.changeStateTo(value > 0)
        when 'brightness'
          env.logger.debug "Execute action 'brightness' for device " + @device.id + ", set brightness: " + value
          @device.changeDimlevelTo(value)
        when 'colorsettingrgb'
          env.logger.debug "Execute action 'colorsetting' for device " + @device.id + ", set colorsettingrgb: " + value
          
          @device.setColor(value)
        when 'scene'
          env.logger.debug "Scene not implemented for device " + @device.id
        when 'requestsync'
          env.logger.debug "Requestsync -> publish state for device " + @device.id
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
      _mqttHeader3 = @getTopic() + '/colorsettingrgb/set'
      @device.getHue().then((hue) =>
        #Hue to RGB ????
        env.logger.debug "Publish colorsetting, mqttHeader: " + _mqttHeader3 + ", rgblevel: " + hue
        @mqttConnector.publish(_mqttHeader3, String hue)
      ).catch((err) =>
        env.logger.error "HUELEVEL: " + err.message
      )

    setGbridgeDeviceId: (deviceId) =>
      @gbridgeDeviceId = deviceId

    getGbridgeDeviceId: () =>
      return @gbridgeDeviceId

    getTopic: () =>
      _topic = @topicPrefix + "/" + @topicUser + "/d" + @gbridgeDeviceId
      return _topic

    getType: () ->
      return "Light"

    getTraits: () ->
      traits = [
        {'type' : 'OnOff'},
        {'type' : 'Brightness'},
        {'type' : 'ColorSettingRGB'}
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
        #  _twoFa["pin"] = @twoFaPin
      return _twoFa

    destroy: ->
      @device.removeListener 'state', deviceStateHandler
      @device.removeListener 'dimlevel', deviceDimlevelHandler
      @device.removeListener 'hue', deviceHueHandler
