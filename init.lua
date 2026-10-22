-- moorings lives in ~/.hammerspoon/moorings, a link to the repo.
package.path = hs.configdir .. "/moorings/?.lua;" .. package.path

-- moorings holds a global reference so the menu bar item and timers are not collected.
moorings = require("anchors").start()
