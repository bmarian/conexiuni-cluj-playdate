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
import "scenes/TripScene"
import "scenes/StopScene"

Noble.Text.setFont(Theme.FONT_BODY)

-- Nothing to browse until the first sync.
if Store.load() then
	Nav.start(MainMenuScene)
else
	Nav.start(SyncScene)
end
