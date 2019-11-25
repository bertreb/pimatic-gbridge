pimatic-gbridge
===================
The Gbridge plugin lets you connect a Pimatic home automation system with a Google assistant via Gbridge. Gbridge is a MQTT broker that 'works with Google'. After creating an gBrige account and obtaining an API key you can configure the plugin and add devices to be controlled via Google Assistant.
The number of devices id dependent on the gBridge plan you've got. The free plan allows 4 devices the paid plan gives an unlimited number of devices.


Installation
------------
To enable the Gbridge plugin add this to the plugins section via the GUI or add it in the config.json file.

```
...
{
  plugin: "Gbridge"

Options to configure in the plugin settings:
  gbridgeApiKey:        "The apikey to get an access_token"
  gbridgeSubscription:  "The type of subscription; Free (max 4 devices) Standard (unlimited number of devices)"
  mqttServer:           "Hosted gBridge servername" (default mqtt.gbridge.io)
  mqttProtocol:         "The used protocol for hosted MQTT server. MQTT (default) or MQTTS"
  mqttUsername:         "The mqtt hosted server username"
  mqttPassword:         "The mqtt hosted server password"
  mqttBaseTopic:        "gBridge/u{user_id}/" not changable in free plan
  certPath:             "Path to the certificate in PEM format for the MQTTS/TLS connection"
  keyPath:              "Path to the key in PEM format,  for the MQTTS/TLS connection"
  caPath:               "Path to the trusted CA list"
  gbridgeServer:        "The gBridge api server address" default: "https://gbridge.kappelt.net/api/v2"
  gbridgeUser:          "The gbridge username"
  gbridgePassword:      "The gbridge password"
  debug:                "Debug mode. Writes debug messages to the pimatic log."
}
...
```

Gbridge device
-----------------
When the plugin is installed (including restart) a Gbridge device can be added.


Below the settings with the default values. In the devices your confure which Pimatic devices will be controlled by Google Assistant and what name they get. The name is visible in the Google Assistant and is the name you use in voice commands.

```
{
  "id": "<gbridge-device-id>",
  "class": "GbridgeDevice",
        devices:  "list of devices connected to Google Assistant"
          name:              "the gBridge device name, and command used in GoogleAssistant"
          pimatic_device_id: "the pimatic device ID"
          gbridge_device_id: "The gbrigde device ID. Is automatically added"
          twofa:             "Two-step confirmation or PIN-Code verification"
                              ["none", "ack", "pin"] default: "none"
          twofaPin:           "PIN code for two step authorization. The PIN code is a 4 to 8 digit number"
}
```

---------

The plugin is Node v10 compatible and in development. You could backup Pimatic before you are using this plugin!
