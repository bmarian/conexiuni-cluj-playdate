-- Entry point. Noble Engine owns the update loop, scene lifecycle and input
-- routing (see AGENTS.md "App Architecture"); lib/nav.lua adds the back stack
-- on top of it, and lib/theme.lua owns every visual decision.

import "libraries/noble/Noble"

import "lib/text"
import "lib/icons"
import "lib/theme"
import "lib/nav"
import "lib/api"
import "lib/store"

import "scenes/SyncScene"
import "scenes/MainMenuScene"
import "scenes/ListScene"
import "scenes/RouteScene"
import "scenes/TimetableScene"
import "scenes/StopScene"

Noble.Text.setFont(Theme.FONT_BODY)

-- Nothing to browse until the first sync has happened.
if Store.load() then
	Nav.start(MainMenuScene)
else
	Nav.start(SyncScene)
end
