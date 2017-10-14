# Events List

### Guild Join
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

### Guild Update

Same as Guild Join structure

### Guild Leave

Same as Guild Leave structure

### Guild Member Update

Contains a Discord Member

### Guild Member Join

Contains a Discord member

### Guild Members Update

Contains an id_map of Discord member

### Guild Member Leave

Contains a Discord member

### Message Create

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

### Command Execute

Same structure as Message Create with 2 addition fields:

- command_name `string`
- text `string`

For example if someone sends `!foo bar hello world` the command_name would be `!foo` and text would be `bar hello world` 

