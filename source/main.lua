import "libraries/noble/Noble"

import "lib/text"
import "lib/icons"
import "lib/theme"
import "lib/nav"
import "lib/api"
import "lib/bundle"
import "lib/store"

import "scenes/CityScene"
import "scenes/SyncScene"
import "scenes/MainMenuScene"
import "scenes/ListScene"
import "scenes/RouteScene"
import "scenes/TimetableScene"
import "scenes/TripScene"
import "scenes/StopScene"

Noble.Text.setFont(Theme.FONT_BODY)

-- A city first, then nothing to browse until its first sync.
if not Store.loadCity() then
	Nav.start(CityScene)
elseif Store.load() then
	Nav.start(MainMenuScene)
else
	Nav.start(SyncScene)
end
