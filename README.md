# Russian Driving Simulator (Roblox)

A realistic driving simulator for Roblox, written in Luau: five premium cars with
simulated engines, gearboxes, tyres and suspension, to be driven on a Russian
open-world map under ПДД РФ.

The game is built in six stages. **Stage 1 (vehicle physics and five cars) is
the current state of this repository.** See [docs/STAGE1.md](docs/STAGE1.md) for
the stage report, test results and the in-Studio checklist.

| Stage | Scope | Status |
| --- | --- | --- |
| 1 | Vehicle physics, five cars, lights, controls | Implemented, awaiting Studio playtest |
| 2 | Interiors, first/third-person cameras | Not started |
| 3 | Open-world map and road network | Not started |
| 4 | Russian traffic signs and road markings | Not started |
| 5 | Traffic lights and traffic rules | Not started |
| 6 | Optimisation, mobile, multiplayer testing | Not started |

## Getting it into Roblox Studio

Pick one:

1. **Open the built place.** Open `dist/RussianDrivingSimulator.rbxlx` in Roblox
   Studio and press Play. Nothing else is needed.
2. **Rojo.** Install the tools in `rokit.toml`, run `rojo serve`, and connect
   with the Rojo Studio plugin. `rojo build -o dist/RussianDrivingSimulator.rbxlx`
   regenerates the place file.
3. **By hand.** Create the instances below and paste each file's contents.
   A file named `X.luau` is a **ModuleScript** `X`; `Main.server.luau` is a
   **Script** `Main`; `Main.client.luau` is a **LocalScript** `Main`; a folder
   containing `init.luau` is a ModuleScript with the other files as children.
   Also set `Workspace.Gravity` to `35.035714`.

## Where everything lives in the Explorer

```
ReplicatedStorage
└─ DrivingSim                      (Folder)        src/shared
   ├─ Constants                    scale, tags, light constants
   ├─ Types                        config and physics types
   ├─ Remotes                      Action / Telemetry endpoints
   ├─ VehiclePhysics               raycast chassis: sim <-> Roblox physics
   ├─ Config
   │  ├─ Surfaces                  grip per road surface
   │  └─ Vehicles                  (ModuleScript) registry of the five cars
   │     ├─ LadogaPremier  AuroraSenat  SokolGT  TaigaGrand  NevaSport
   └─ Physics                      engine-independent simulation
      ├─ Geometry                  wheel positions, spring and damper rates
      ├─ Powertrain                engine torque curve, automatic gearbox
      ├─ TireModel                 slip-angle tyre forces, friction circle
      ├─ Steering                  speed-sensitive rack, Ackermann
      └─ VehicleSim                one simulation step for a whole car

ServerScriptService
└─ DrivingSim                      (Folder)        src/server
   ├─ Main                         (Script) world scale, track, spawns cars
   ├─ VehicleBuilder               builds a car model from its config
   ├─ VehicleSpawner               places cars in Workspace.Vehicles
   ├─ VehicleService               seats, ownership, validation, parked cars
   └─ TestTrack                    stage 1 proving ground

StarterPlayer
└─ StarterPlayerScripts
   └─ DrivingSim                   (Folder)        src/client
      ├─ Main                      (LocalScript)
      ├─ VehicleController         input, drives the local car
      ├─ VehicleLights             renders lights for every car
      ├─ WheelVisuals              wheel spin, steering, suspension travel
      └─ TelemetryHud              stage 1 readout

Workspace                          (created at runtime)
├─ TestTrack                       proving ground
└─ Vehicles                        the five cars
```

`CameraController`, `UIController`, `AudioController`, `RoadSignSystem`,
`TrafficLightController` and `TrafficRulesSystem` arrive with their stages.

## Controls

| Key | Action |
| --- | --- |
| F (hold, next to a car) | Get in |
| W / S | Accelerate / brake; hold S at standstill for reverse |
| A / D | Steer |
| Space | Handbrake |
| Q / E | Left / right turn signal (self-cancelling) |
| H | Hazard lights |
| L | Headlights: off, low beam, high beam |
| F | Leave the car |
| R | Put a stuck or overturned car back on its wheels |

A gamepad also works (R2/L2, left stick, A handbrake, D-pad signals and lights).
The V and C camera keys and touch controls belong to stages 2 and 6.

## How the physics works

Every car is one weighted chassis part with four suspension rays. Each physics
frame `VehiclePhysics` measures the wheel contacts, `VehicleSim` computes spring,
damper, anti-roll, engine, brake and tyre forces in SI units, and the result is
applied to the chassis as impulses. The driver's client simulates the car it
owns; the server simulates parked cars, owns all light state, rate-limits and
validates client messages, and corrects cars that exceed their speed envelope.

The world uses 1 stud = 0.28 m and real gravity, so km/h, metres and seconds on
screen are true to the simulation.

## Checks

```
lune run tests/run        # physics: acceleration, top speed, braking, stability
lune run tests/builder    # car models: dimensions, wheels, lights, seat
selene src tests && stylua --check src tests
rojo sourcemap -o sourcemap.json && luau-lsp analyze --sourcemap=sourcemap.json \
  --definitions=globalTypes.d.luau --no-strict-dm-types src
```

The tests load the shipped modules outside Roblox (see `tests/loader.luau`).
They cannot replace a playtest in Studio; the checklist is in the stage report.
