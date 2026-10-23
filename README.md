# force_quests

Quick jobs from one NPC. Talk to Philip at the airport and pick a job from his menu: deliver a trailer to Paleto Bay with a truck, load four boxes into a van in Vinewood Hills, wreck an old car with a bulldozer, or clean nine spots in the subway. Come back to Philip and he pays you.

Free. Works on ESX Legacy, QBCore and QBox.

## Features

- Four quests out of the box (trailer delivery, boxes, scrapping, cleaning), each with its own vehicles, stops and reward
- Philip's menu with ox_lib, prompts with ox_target, qb-target or [E] with the ox_lib text UI
- Quest vehicles are spawned by the server, with keys (qbx_vehiclekeys, qb-vehiclekeys) and full fuel (ox_fuel)
- Server-side checks: quest ids and stop indexes from the config, stop order, distance, the right vehicle, the trailer at the drop, the wreck's damage, timed pickups and cleaning, travel time between places, one quest per player, one player per quest
- The reward is a random amount between a minimum and a maximum, paid once by the server as cash or bank money
- Cooldown per quest after being paid, cancel at Philip, a maximum duration, and cleanup when the player leaves or the resource restarts
- Build your own quests from deliver, return, carry, scrap and task stops
- English and Swedish locales

## Requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- OneSync
- ESX Legacy, QBCore or QBox (other frameworks through `server/custom/frameworks/custom.lua`)
- Optional: ox_target or qb-target

No database and no items are used.

## Installation

1. Put the folder in your resources as `force_quests`.
2. Add `ensure force_quests` to `server.cfg` below `ensure ox_lib`. The order relative to your framework and target resource doesn't matter.
3. Edit `config.lua`: rewards, payout account, cooldowns and the quests.

## Documentation

https://docs.forcedevelopments.com/free-resources/force_quests/introduction
