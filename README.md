pimatic-gbridge
===================
# The gBridge service ended the 15th of March 2020. 

## This plugin can still work if you would use a self hosted gbridge service.
---
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
In this release the SwitchActuator, DimmerActuator, ButtonsDevice, ShutterController, Milight (RGBWZone and FullColorZone), HeatingThermostat, Contact and Temperature/Humidity sensor based Pimatic devices are supported.
When there's at least 1 device in the config, the dot will go present after a connection to gBridge and the mqtt server is made.



#### Shutter
For the Shutter device the auxiliary field is used to control a shutter via a shell script. The position of the shutter (the value) is added at the end of the script (with a space) before executing the script. A return value is used as actual shutter position.

More info on Shutter voice commands on [gBridge](https://doc.gbridge.io/traits/openclose.html)

#### Milight
For the Milight devices automatic configuration is not implemented. You need to configure the milight device in gBridge (with the traits 'OnOff', 'Brightness' and 'colorsettingrgb') and after that configure(add) the milight device in config of the gBridge device in Pimatic. The name you used for the Milight device in gBridge must by exactly the same as the name in pimatic gBridge! When you want to change the name of a Milight device you have to reinstall it in gBridge (because automatic configuration isn't supported)

More info Brigtness voice commands on [gBridge](https://doc.gbridge.io/traits/brightness.html)

#### Contact
You can add a Pimatic contact device to gBridge.
You give the contact a name that is usable with Google Assistant. The contact device id is put into the pimatic_device_id field. The rest of the fields is not used.
You can ask Google Assistant what de status of the contact-name is, or if a contact-name is opened or closed.

More info on contact voice commands on [gBridge](https://doc.gbridge.io/traits/openclose.html)

#### Thermostat
For the HeatingThermostat you CAN add a temperature/humidity sensor. In the auxiliary field, add the device-id of the temperature/humidity sensor. The sensor needs to have 'temperature' and 'humidity' named attributes. If the attribute names are different, you can put a variables devices 'in between' (which converts the attribute names to 'temperature' and 'humidity').
The heating device is only using the temperature setting of the device.
The following modes are supported: off, heat and eco.

More info on Thermostat voice commands on [gBridge](https://doc.gbridge.io/traits/temperaturesetting.html)

#### Temperature
The temperature/humidity sensor is not supported directly by gBridge and Google Assistant. This temperature/humidity sensor via implemented via a DummyThermostat.
The configuration is as follows:
- pimatic_device_id: the Temp/Hum device-id of the Pimatic Sensor
- auxiliary: the attribute name of the temperature attribute of the Pimatic sensor
- auxiliary2: if available the attribute name of the humidity attribute of the Pimatic sensor

In the Google Assistant (or Home app) you hear/see a thermostat device with the same ambiant(room) and setpoint temperature. This value is the temperature value of your Pimatic sensor.

Device configuration
-----------------

```
{
  "id": "<gbridge-device-id>",
  "class": "GbridgeDevice",
    devices:  "list of devices connected to Google Assistant"
      name:                 "the gBridge device name, and command used in Google Assistant"
      pimatic_device_id:    "the ID of the pimatic device"
      pimatic_subdevice_id: "the ID of a pimatic subdevice, only needed for a button id"
      auxiliary:            "adapter specific field to add functionality to the bridge"
      auxiliary2:            "2nd adapter specific field to add functionality to the bridge"
      twofa:                 "Two-step confirmation. Google Assistant will ask for confirmation"
                              ["none", "ack"] default: "none"
}
```

#### Deleting a gBridge device
Before you delete a gBridge device, please remove first all devices in the config and save the config. After that you can delete the gBridge device.
If you deleted the gBridge device before deleting the used devices, you must delete the devices in the gBridge management portal.

-----------------

The plugin is Node v10 compatible and in development. You could backup Pimatic before you are using this plugin!
