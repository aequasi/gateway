# Gateway

This is the umbrella project containing Mee6's real-time Discord stuff. Events are broadcasted through redis's pubsub facility.

## Events

Each events are in the form

```json
{
  "t": "EVENT_TYPE",
  "d": "some data",
  "g": 159962941502783488,
  "s": [0, 256],
  "ts": 1507970959017
}
```

- `t` is the event type (events types are listed below)
- `d` is the data sent with the events (generally an object)
- `g` is a guild snowflake id (optional)
- `s` is a [shard_id, shard_count] info (optional)
- `ts` is the timestamp when the event has been sent

Every guild related events listed bellow do not have a `s` parameter. The way the gateway is made, guilds don't know which shard they belong to.

Events are broadcasted to channels in the form `gateway.event.{event_type}` where `event_type` is actually what we call t here.

Bellow is a list of all the events types.

### GUILD_JOIN
<table>
  <tr>
    <th colspan="3">Guild Join Structure</th>
  </tr>
  <tr>
    <td>Field</td>
    <td>Type</td>
    <td>Description</td>
  </tr>
  <tr>
    <td>id</td>
    <td>snowflake</td>
    <td>Guild's id</td>
  </tr>
  <tr>
    <td>name</td>
    <td>string</td>
    <td>Guild's name</td>
  </tr>
  <tr>
    <td>icon</td>
    <td>string</td>
    <td>Icon hash</td>
  </tr>
  <tr>
    <td>owner_id</td>
    <td>snowflake</td>
    <td>Owner's user id</td>
  </tr>
  <tr>
    <td>roles</td>
    <td>id_map</td>
    <td>Map of discord roles</td>
  </tr>
  <tr>
    <td>large</td>
    <td>bool</td>
    <td>Whether it's a large guild</td>
  </tr>
  <tr>
    <td>unavailable</td>
    <td>bool</td>
    <td>Whether the guild is unavailable</td>
  </tr>
  <tr>
    <td>channels</td>
    <td>id_map</td>
    <td>Map of discord channels</td>
  </tr>
</table>

### GUILD_UPDATE

Same as Guild Join structure

### GUILD_LEAVE

Same as Guild Leave structure

### GUILD_MEMBER_UPDATE

Contains a Discord Member

### GUILD_MEMBER_JOIN

Contains a Discord member

### GUILD_MEMBER_UPDATE

Contains a list of Discord member

### GUILD_MEMBER_LEAVE

Contains a Discord member

### MESSAGE_CREATE

<table>
  <tr>
    <th colspan="3">Guild Join Structure</th>
  </tr>
  <tr>
    <td>Field</td>
    <td>Type</td>
    <td>Description</td>
  </tr>
  <tr>
    <td>id</td>
    <td>snowflake</td>
    <td>Guild's id</td>
  </tr>
  <tr>
    <td>name</td>
    <td>string</td>
    <td>Guild's name</td>
  </tr>
  <tr>
    <td>icon</td>
    <td>string</td>
    <td>Icon hash</td>
  </tr>
  <tr>
    <td>owner_id</td>
    <td>snowflake</td>
    <td>Owner's user id</td>
  </tr>
  <tr>
    <td>roles</td>
    <td>id_map</td>
    <td>Map of discord roles</td>
  </tr>
  <tr>
    <td>large</td>
    <td>bool</td>
    <td>Whether it's a large guild</td>
  </tr>
  <tr>
    <td>unavailable</td>
    <td>bool</td>
    <td>Whether the guild is unavailable</td>
  </tr>
  <tr>
    <td>channels</td>
    <td>id_map</td>
    <td>Map of discord channels</td>
  </tr>
</table>

### COMMAND_EXECUTE

Same structure as Message Create with 2 addition fields:

- command_name `string`
- text `string`

For example if someone sends `!foo bar hello world` the command_name would be `!foo` and text would be `bar hello world` 

