module.exports = {
  title: "pimatic-gbridge device config schemas"
  GbridgeDevice: {
    title: "Gbridge config options"
    type: "object"
    extensions: ["xLink", "xAttributeOptions"]
    properties:
      devices:
        description: "list of devices connected to Google Assistant"
        format: "table"
        type: "array"
        default: []
        items:
          type: "object"
          properties:
            name:
              descpription: "the gBridge device name, and command used in GoogleAssistant"
              type: "string"
              required: true
            pimatic_device_id:
              descpription: "the pimatic device ID"
              type: "string"
              required: true
            pimatic_subdevice_id:
              description: " the ID of the subdevice like a button name"
              type: "string"
              required: false
            auxiliary:
              description: "adapter specific field to add functionality to the bridge"
              type: "string"
              required: false
            auxiliary2:
              description: "adapter specific field to add 2nd functionality to the bridge"
              type: "string"
              required: false
            twofa:
              description: "Two-step confirmation. Google Assistant will ask for confirmation"
              enum: ["none", "ack"]
  }
}
