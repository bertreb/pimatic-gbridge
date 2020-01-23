pimatic-gbridge
===================
The gBridge plugin lets you connect a Pimatic home automation system with a Google assistant via gBridge.
When you add a supported Pimatic device to the gBridgeDevice devicelist, the device is automatically added in gBridge and Google Assistant.

gBridge is a MQTT broker that 'works with Google'. First you create a gBridge account, connect your google (assistant) account to gBridge and obtaining an API key. Then you can configure the plugin and add devices to be controlled via Google Assistant. Details for setup and configuration at https://about.gbridge.io.
The number of supported devices is depending on the gBridge plan you've got. The free plan allows 4 devices and the paid plan gives an unlimited number of devices.
Devices are not exposed automatically to gBridge and Google Assistant. You have to add them individually in the config.


Installation
------------
To enable the gBridge plugin add this to the plugins section via the GUI or add it in the config.json file.

```
...
{
  plugin: "Gbridge"

Options to configure in the plugin settings:
  gbridgeApiKey:        "The apikey to get an access_token"
  gbridgeSubscription:  "The type of subscription; Free (max 4 devices) Standard or (unlimited)"
  mqttServer:           "Hosted gBridge servername" (default mqtt.gbridge.io)
  mqttProtocol:         "The used protocol for hosted MQTT server. MQTT (default) or MQTTS"
  mqttUsername:         "The mqtt hosted server username"
  mqttPassword:         "The mqtt hosted server password"
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
After the plugin is installed a Gbridge device can be added.

Below the settings with the default values. In the devices your configure which Pimatic devices will be controlled by Google Assistant and what name they get. The name is visible in the Google Assistant and is the name you use in voice commands.
In this release the SwitchActuator, DimmerActuator, ButtonsDevice, ShutterController, Milight (RGBWZone and FullColorZone) and HeatingThermostat based Pimatic devices are supported.
When there's at least 1 device in the config, the dot will go present after a connection to gBridge and the mqtt server is made.

#### Milight
For the Milight devices automatic configuration is not implemented. You need to configure the milight device in gBridge (with the traits 'OnOff', 'Brightness' and 'colorsettingrgb') and after that configure(add) the milight device in config of the gBridge device in Pimatic. The name you used for the Milight device in gBridge must by exactly the same as the name in pimatic gBridge! When you want to change the name of a Milight device you have to reinstall it in gBridge (because automatic configuration isn't supported)

#### Thermostat
For the HeatingThermostat you can add a temperature/humidity sensor. Add in the auxiliary field the device ID of the temperature sensor. The sensor needs to have 'temperature' and 'humidity' named attributes. If the attribute names are different, you can put a variables devices 'in between' (which converts the attribute names to 'temperature' and 'humidity').
The heating device is only using the temperature setting of the device.
The following modes are supported: off, heat and eco.
Mode setting options via Pimatic Gui are not used. The mode attributes will be set by gBridge and can be accessed/used via the device-id.mode variable

```
{
  "id": "<gbridge-device-id>",
  "class": "GbridgeDevice",
    devices:  "list of devices connected to Google Assistant"
      name:                 "the gBridge device name, and command used in Google Assistant"
      pimatic_device_id:    "the ID of the pimatic device"
      pimatic_subdevice_id: "the ID of a pimatic subdevice, only needed for a button id"
      auxiliary:            "adapter specific field to add functionality to the bridge"
      twofa:                 "Two-step confirmation. Google Assistant will ask for confirmation"
                              ["none", "ack"] default: "none"
}
```

---------

The plugin is Node v10 compatible and in development. You could backup Pimatic before you are using this plugin!
