# Design Notes (transcribed from Figma sticky notes)

The source PNGs live in `_unused/design-notes/`. This file preserves their
content so those images can be deleted safely.

## Audio spec per screen

| Screen | Background music | Sound triggers |
|---|---|---|
| Welcome | game theme | tap JOIN KITCHEN, tap CREATE KITCHEN |
| Enter chef name A | game theme | tap TEXT FIELD, tap BACK, tap NEXT |
| Enter chef name B | game theme | tap ENTER, tap BACK |
| Number of players | game theme | tap NUMBER OF PLAYERS, tap BACK, tap PROCESS |
| Active kitchens | game theme | tap A KITCHEN, tap BACK, tap JOIN |
| Waiting room | lobby music | tap BACK, A PLAYER JOINS, tap START |
| Head chef appointment | drumroll | tap BACK, A PLAYER JOINS, tap START (different sound from the NEXT buttons) |
| Recipe | game theme | tap BACK, tap START |
| Countdown | — | countdown |

## Utensil display settings

**Unfocussed utensils**
- 130pt height
- soft drop shadow
- −20° rotation

**Focussed utensils**
- 280pt height
- harder drop shadow
- −20° rotation

## Storage placeholders

> Ingredients to be added to storage: dark ones are placeholders for when an
> ingredient is being used.

> Utensils to be added to storage: dark ones are placeholders for when a utensil
> is being used.

This is why every sprite in `Sprites/ingredients/` and `Sprites/utensils/` has a
matching `-in-use` variant.

## What's included in the kitchen

- 6 stations
- timer
- storage room
- rack
- garbage bin
- menu button (head chef only)

**Inside a station:** an ⓘ button for the tutorial.

## Copy

- Recipe screen: add the flamingo; write the command, something like
  *"make 1 strawberry shortcake within the given time limit."*
- "when someone leaves the kitchen" — state needs a screen/handler.
