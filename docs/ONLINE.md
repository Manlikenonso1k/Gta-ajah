# Online play

Friends can play in the same city. Everyone who joins starts outside
**HOPE MEDICAL POINT**. You see each other walk, run and jump, and you see the cars
your friends drive. Each phone runs its own traffic and pedestrians, so those can
look different on each phone.

## Ways to play

The start screen has four choices:

| Choice | When to use it | Needs |
|---|---|---|
| **Play solo** | On your own, the same as before | Nothing |
| **Play online** | Friends anywhere with internet | The cloud server below, set up once |
| **Host on this phone** | Everyone on the same Wi-Fi | Nothing |
| **Join host** | Join a phone that is hosting on the same Wi-Fi | The address shown at the top of the host's screen, for example `192.168.1.5` |

In a game, open the phone menu and tap **Leave online game** to go back to the start
screen. Your name and the addresses you typed are remembered.

## Set up the cloud server (once, free)

The server is the small Node.js relay in `server/`. It only passes messages
between players and doesn't run the game. `render.yaml` sets it up on
[Render](https://render.com)'s free plan, and you can do all of this from a phone
browser:

1. Sign up at render.com with your GitHub account. Give Render access to this
   repository (it works with a private repository).
2. In the Render dashboard choose **New → Blueprint**, pick this repository and
   the branch that has `render.yaml`, then **Apply**.
3. When the deploy finishes, copy the service address, for example
   `https://garden-city-relay.onrender.com`. Opening it in a browser shows
   `Garden City Stories relay: 0 player(s) online`.
4. In the game, on **Play online**, type the address with `wss://` in front of it
   instead of `https://`: `wss://garden-city-relay.onrender.com`. The game remembers it.

To build the address into the app so friends don't have to type it, put it in
`net_config.json`:

```json
{
  "server_url": "wss://garden-city-relay.onrender.com"
}
```

Then export the APK again.

**Free plan note:** Render puts a free server to sleep after about 15 minutes with
no players. The first player to connect wakes it, which can take up to a minute.
The game waits up to 75 seconds and shows a message while it waits.

To run the relay on your own computer: `cd server && npm install && npm start`
(port 8910, or set `PORT`). Join it with `ws://<computer's address>:8910`.

## How it works

- `scripts/net.gd` (autoload `Net`) handles the connection. Every player sends small
  JSON messages over a WebSocket. The relay gives each player an id, adds it to
  their messages and forwards them to everyone else. With **Host on this phone**,
  the hosting phone runs the same relay itself on port 8910 and plays as id 1.
- `scripts/net_sync.gd` runs in the game world. About 12 times a second it sends the
  player's position, animation and, when driving, the car's position and speed. It
  shows each other player as `scripts/remote_player.gd`, which is the player model
  with their name above it.
- **Cars:** every phone builds the same city with the same parked cars, so a car a
  friend drives is moved by their messages: it is frozen on your phone, follows
  them, and you can't get into it. If a friend drives a traffic car that exists
  only on their phone, a copy of that model stands in for it. Their car can knock
  you down. Online, the solo save of where cars were left isn't used.
- **Not shared yet:** traffic, pedestrians and ragdolls. A friend who is knocked
  down disappears on your phone until they get up.
- **Test:** `godot --headless --path . --script tests/net_test.gd`. Add
  `-- --relay ws://127.0.0.1:8910` while `server/server.js` is running to test the
  cloud relay as well.
