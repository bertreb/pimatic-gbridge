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
            gbridge_device_id:
              descpription: "The gBrigde device ID. Is automatically added"
              type: "number"
              required: true
              default: 0
            twofa:
              description: "Two-step confirmation. Google Assistant will ask for confirmation"
              enum: ["none", "ack"]
  }
}
