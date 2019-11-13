pimatic-gbridge
===================
The Gbridge plugin lets you connect a Pimatic home automation system with a Google assistant via Gbridge. Gbridge is an MQTT brokers that 'works with Google'. After creating an gBrige account and obtaining an API key you can configure the plugin and add devices to be controlled via Google Assistant.
The number of devices id dependent on the gBrige plan you've got. The free plan allows 4 devices the paid plan gives an unlimited number of devices.

Installation
------------
To enable the Gbridge plugin add this to the plugins section via the GUI or add it in the config.json file.

```
...
{
  "plugin": "Gbridge"
}
...
```

Stats device
-----------------
When the plugin is installed (including restart) a Stats device can be added. Below the settings with the default values.

```
{
  "id": "<stats-device-id>",
  "class": "GbridgeDevice",
}
```

---------

The plugin is Node v10 compatible and in development. You could backup Pimatic before you are using this plugin!
