module.exports = {
  title: "Gbridge"
  type: "object"
  properties:
    gbridgeApiKey:
      description: "The apikey to get an access_token"
      required: true
      type: "string"
      default: ""
    gbridgeServer:
      description: "The gBridge api server address"
      type: "string"
      default: "https://gbridge.kappelt.net/api/v2"
      required: true
    gbridgeSubscription:
      description: "The type of subscription; Free (max 4 devices) Standard (unlimited number of devices)"
      required: true
      type: "string"
      enum: ["Free","Standard"]
      default: "Free"
    mqttServer:
      description: "Hosted servername"
      type: "string"
      required: true
      default: "mqtt.gbridge.io"
    mqttProtocol:
      description: "The used protocol for hosted MQTT server. MQTT (default) or MQTTS (with cert,key and ca)"
      type: "string"
      required: true
      enum:["MQTT", "MQTTS"]
      default: "MQTT"
    mqttProtocolVersion:
      description: "The used protocolVersion of MQTT"
      type: "integer"
      required: true
      default: 4
    mqttUsername:
      description: "The mqtt hosted server username"
      type: "string"
      required: true
    mqttPassword:
      description: "The mqtt hosted server password"
      type: "string"
      required: true
    certPath:
      description: "Path to the certificate of the client in PEM format, required for the TLS connection"
      type: "string"
      default: "/etc/ssl/certs/"
      required: false
    keyPath:
      description: "Path to the key of the client in PEM format, required for the TLS connection"
      type: "string"
      default: "/etc/ssl/certs/"
      required: false
    caPath:
      description: "Path to the trusted CA list"
      type: "string"
      default: "/etc/ssl/certs/"
      required: false
    debug:
      description: "Debug mode. Writes debug messages to the pimatic log, if set to true."
      type: "boolean"
      default: false
}
