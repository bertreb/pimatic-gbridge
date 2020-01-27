module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'


  class ContacttAdapter extends events.EventEmitter

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

      @contact = 0

      @device.getContact()
      .then((contact)=>
        if contact then @contact = 0 else @contact = 100
        @device.on "contact", contactHandler
        @device.system = @

        @publishState()
      )


    contactHandler = (contact) ->
      # device status changed, NOT updating device status in gBridge
      _mqttHeader = @system.getTopic() + '/openclose/set'
      if contact then @system.contact = 0 else @system.contact = 100

      env.logger.debug "Device state change, publish contact: mqttHeader: " + _mqttHeader + ", contact: " + @system.contact
      @system.mqttConnector.publish(_mqttHeader, String @system.contact)

    executeAction: (type, value) ->
      # device status changed, updating device status in gBridge
      env.logger.debug "received action, type: " + type + ", state: " + value
      switch type
        when 'openclose'
          env.logger.debug "No action action for device " + @device.id + ", set mode: " + value
          #@publishState()
        when 'requestsync'
          env.logger.debug "Requestsync -> publish state for device " + @device.id
          @publishState()
        else
          env.logger.error "Unknown action '#{type}'"

    publishState: () =>
      _mqttHeader = @getTopic() + '/openclose/set'
      env.logger.debug "Publish mode, mqttHeader: " + _mqttHeader + ", mode: " + @contact
      @mqttConnector.publish(_mqttHeader, String @contact)


    _setThermostat: (action, mode) =>
      env.logger.debug "Contact: " + action + ", with state: " + mode

    setGbridgeDeviceId: (deviceId) =>
      @gbridgeDeviceId = deviceId

    getGbridgeDeviceId: () =>
      return @gbridgeDeviceId

    getTopic: () =>
      _topic = @topicPrefix + "/" + @topicUser + "/d" + @gbridgeDeviceId
      return _topic

    getType: () ->
      return "Door"

    getTraits: () =>
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
      @device.removeListener "contact", contactHandler

