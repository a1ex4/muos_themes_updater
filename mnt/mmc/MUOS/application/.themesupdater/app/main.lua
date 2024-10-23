local json = require("dkjson")
local https = require("https")

local theme_dir = "/run/muos/storage/theme/"
local active_theme_dir = "/run/muos/storage/theme/active/"
local archive_dir = "/mnt/mmc/ARCHIVE/"

local gh_token = nil

-- Resolution and layout 
local screenWidth, screenHeight = 640, 480
local menuHeight = 20
local yPosMain = 0
local buttonIcons = {}

-- Tables to store the themes
local allThemes = {}
local filteredThemes = {}  -- This will store the filtered themes
local sortedThemes = {}  -- This will store the filtered and sorted themes
local installedThemes = {}  -- This will store the locally installed themes
local previews = {}

local releaseData
-- Filter types and the current filter
local filters = {"All", "Installed", "Update avail."}
local currentFilterIndex = 1  -- Index to track the current filter

-- Sorting
local sortKeys = {"name", "updatedAgo", "downloads"}  -- The list of keys to sort by
local sortOrder = 1         -- Sort order: 1 for ascending, -1 for descending
local currentSortIndex = 1   -- Index to track the current sort key

-- Views
local views = {"List", "Details"}
local currentViewIndex = 2   -- Index to track the current view

-- Define a map of human-readable column names to theme keys
local sortKeysMap = {
    ["name"] = "Name",
    ["updatedAgo"] = "Updated",
    ["downloads"] = "Downloads"
}

-- Global variables for list / details view
local selectedTheme = 1
local numThemes = 1
local perPage = 1
local backgroundImage
local showThemeMenu = false
local selectedMenuItem = 1 -- Index of the currently selected menu item
local menuItems = {}

local request_headers = {
    ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36",
    ["Content-Type"] = "application/json",
    ["Accept"] = "application/vnd.github+json"
}

if gh_token ~= nil then
    request_headers["Authorization"] = "Bearer " .. gh_token
end

-- utils functions

function folder_exists(path)
    local handle = io.popen('ls -d "' .. path .. '"')
    local result = handle:read("*a")
    handle:close()
    return result:match(path) ~= nil
end

function file_exists(path)
    local handle = io.popen('ls "' .. path .. '"')
    local result = handle:read("*a")
    handle:close()
    print(result)
    return result:match(path) ~= nil
end

function scandir(directory)
    local i, t, popen = 0, {}, io.popen
    local pfile = popen('ls ' .. directory)
    -- local pfile = popen('dir "'..directory..'" /b')
    for filename in pfile:lines() do
        if filename:sub(-4) == ".zip" then
            i = i + 1
            t[i] = filename
        end
    end
    pfile:close()
    return t
end

function contains(l, el)
    for _, value in ipairs(l) do
        if value == el then
            return true
        end
    end
    return false
end

function imageFromUrl(themeName, url)
    if previews[themeName] == nil then
        print("Preview for " .. themeName .. " not available, need to download")
        url = string.gsub(url, " ", "%%20")
        print("imageFromUrl : " .. url)
        local code, body, headers = https.request(url, {
            headers = request_headers
        })
        if code ~= 200 then
            if code == 404 then
                previews[themeName] = "404"
            end
            print("return nil : " .. code)
            return nil
        else
            local rawImageData = body
            local img = love.graphics.newImage(
                love.filesystem.newFileData(rawImageData, "preview.png"))
            previews[themeName] = {img = img}

            -- local jsonData = json.decode(body)
            -- if jsonData.status == "404" then
            --     previews[themeName] = {b64 = "404"}
            -- else
            --     local img = love.graphics.newImage(
            --         love.image.newImageData(
            --         love.filesystem.newFileData(
            --             love.data.decode("string", "base64", jsonData.content), '', 'text')))
            --     previews[themeName] = {b64 = jsonData.content, img = img}
            -- end
        end
    end
    return previews[themeName]
end

function dateStringToEpoch(date_string)
    -- Parse the date string using socket's `gettime` function
    local pattern = "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)Z"
    local year, month, day, hour, min, sec = date_string:match(pattern)

    -- Convert to epoch using os.time
    epoch_time = os.time({
        year = year,
        month = month,
        day = day,
        hour = hour,
        min = min,
        sec = sec,
        isdst = false -- Z indicates UTC, no DST
    })
    return tonumber(epoch_time)
end

function epochToTimeAgo(epoch_time)
    -- Get current epoch time
    local current_time = os.time()

    -- Calculate the difference in seconds
    local diff = os.difftime(current_time, epoch_time)

    local minutes = math.floor(diff / 60)
    local hours = math.floor(minutes / 60)
    local days = math.floor(hours / 24)
    local weeks = math.floor(days / 7)
    local months = math.floor(days / 30)
    local years = math.floor(days / 365)

    if years > 0 then
        return (years == 1 and "a year ago" or years .. " years ago")
    elseif months > 0 then
        return (months == 1 and "a month ago" or months ..  " months ago")
    elseif weeks > 0 then
        return (weeks == 1 and "a week ago" or weeks .. " weeks ago")
    elseif days > 0 then
        return (days == 1 and "a day ago" or days .. " days ago")
    elseif hours > 0 then
        return (hours == 1 and "an hour ago" or hours .. " hours ago")
    elseif minutes > 0 then
        return (minutes == 1 and "a minute ago" or minutes .. " minutes ago")
    else
        return (seconds == 1 and "a second ago" or seconds .. " seconds ago")
    end
end

function love.load()
    love.window.setMode(screenWidth, screenHeight)
    love.graphics.setFont(love.graphics.newFont("assets/NotoSans-Light.ttf", 18))
    os.execute("rm -rf app/assets/glyph")
    if folder_exists(active_theme_dir .. "glyph/footer") then
        os.execute("cp -rp " .. theme_dir .. "/active/glyph/footer app/assets/glyph")
    end

    if file_exists("app/assets/glyph/a.png") then
        buttonIcons.a = love.graphics.newImage("assets/glyph/a.png")
    else
        buttonIcons.a = love.graphics.newImage("assets/T_S_A_Retro.png")
    end

    if file_exists("app/assets/glyph/b.png") then
        buttonIcons.b = love.graphics.newImage("assets/glyph/b.png")
    else
        buttonIcons.b = love.graphics.newImage("assets/T_S_B_Retro.png")
    end

    if file_exists("app/assets/glyph/x.png") then
        buttonIcons.x = love.graphics.newImage("assets/glyph/x.png")
    else
        buttonIcons.x = love.graphics.newImage("assets/T_S_X_Retro.png")
    end

    if file_exists("app/assets/glyph/y.png") then
        buttonIcons.y = love.graphics.newImage("assets/glyph/y.png")
    else
        buttonIcons.y = love.graphics.newImage("assets/T_S_Y_Retro.png")
    end

    if file_exists("app/assets/glyph/menu.png") then
        buttonIcons.start = love.graphics.newImage("assets/glyph/menu.png")
    else
        buttonIcons.start = love.graphics.newImage("assets/T_X_X.png")
    end

    -- Initial data fetch
    buildThemesData()
end

-- Function to fetch data using an HTTP GET request
function getReleaseData()
    local url = "https://api.github.com/repos/MustardOS/theme/releases"
    local response_code, body, headers = https.request(url, {
        headers = request_headers
    })
    if response_code == 200 then
        -- Return the concatenated response body as a string
        releaseData = json.decode(body)
    else
        print("HTTP request failed with code: " .. response_code)
    end
end

function parseThemesData(jsonData)
    local themes = {}
    local parsedThemes = {}

    -- Loop through each release and extract relevant data
    for _, release in ipairs(releaseData) do
        for _, asset in ipairs(release.assets) do
            -- Extract theme data from each asset
            local status = ""
            local filename = asset.name:gsub("%.zip", "")
            local themeName = filename:gsub("%.", " ")
            if themes[themeName] ~= nil then
                themes[themeName].downloads = themes[themeName].downloads + asset.download_count
            elseif filename ~= "@_Complete_Theme_Archive" then
                local releaseDate = asset.updated_at
                local updatedEpoch = dateStringToEpoch(releaseDate)
                local updatedAgo = epochToTimeAgo(updatedEpoch)
                local latestVersion = release.tag_name
                if installedThemes[themeName] ~= nil then
                    if contains(installedThemes[themeName], latestVersion) then
                        status = "Installed"
                    else
                        status = "Update avail."
                    end
                end
                local theme = {
                    name = themeName,
                    filename = filename,
                    releaseDate = releaseDate,
                    updatedEpoch = updatedEpoch,
                    updatedAgo = updatedAgo,
                    version = latestVersion,
                    status = status,
                    size = asset.size,
                    downloads = asset.download_count,
                    downloadUrl = asset.browser_download_url,
                    previewUrl = "https://api.github.com/repos/MustardOS/theme/contents/" .. themeName .. "/preview.png",
                    previewDirectUrl = "https://raw.githubusercontent.com/MustardOS/theme/main/" .. themeName .. "/preview.png"
                }

                -- Add to themes table
                themes[themeName] = theme
            end
        end
    end
    for _, theme in pairs(themes) do
        table.insert(parsedThemes, theme)
    end
    return parsedThemes
end

-- Fetch and build table data
function buildThemesData(refreshRelease)
    refreshRelease = refreshRelease or true
    -- get installed themes
    getInstalledThemes()
    -- download latest releases data
    if refreshRelease then
        getReleaseData()
    end
    if releaseData then
        allThemes = parseThemesData()
    end
end

function downloadTheme(performUpdate)
    local theme = filteredThemes[selectedTheme]
    print("Downloading " .. theme.name)
    local code, body, headers = https.request(theme.downloadUrl)
    print(code)
    dest_dir = theme_dir
    -- if theme.filename == " @_Complete_Theme_Archive" then
    --     dest_dir = archive_dir
    -- end
    local f = assert(io.open(dest_dir .. theme.filename .. "__v" .. theme.version .. ".zip", 'wb'))
    f:write(body)
    f:close()
    
    performUpdate = performUpdate or true
    if performUpdate then
        buildThemesData(false)
        showThemeMenu = false
    end
end

function removeTheme(performUpdate)
    local theme = filteredThemes[selectedTheme]
    print("Removing " .. theme.name)
    local allFiles = scandir(theme_dir)
    
    for i, file in ipairs(allFiles) do
        if file:sub(1, #theme.filename) == theme.filename and file:sub(-4) == ".zip" then
            print("File to remove: " .. file)
            os.execute("rm -f " .. theme_dir .. file)
        end
    end

    performUpdate = performUpdate or true
    if performUpdate then
        buildThemesData(false)
        showThemeMenu = false
    end
end

function updateTheme()
    removeTheme(false)
    downloadTheme(false)

    buildThemesData(false)
    showThemeMenu = false
end

function getInstalledThemes()
    installedThemes = {}
    local allFiles = scandir(theme_dir)
    for i, file in ipairs(allFiles) do
        local filename = file:gsub("%.zip", "")
        if string.find(filename, "__v") then
            local themeName, version = filename:match("(.*)__v(.*)")
            themeName = themeName:gsub("%.", " ")
            print("themeName: " .. themeName .. ", version: " .. version)
            if installedThemes[themeName] == nil then
                installedThemes[themeName] = {version}
            else
                table.insert(installedThemes[themeName], version)
            end
        else
            print("Unrecognized file: " .. file)
        end
    end
end

-- Function to apply the current filter
function applyFilter(filter)
    filteredThemes = {}  -- Clear existing filtered data
    -- "all" filter (no filtering, display everything)
    if filter == "All" then
        filteredThemes = allThemes
    -- "installed" filter (example: filter only rows that have 'installed' = true)
    elseif filter == "Installed" then
        for i, theme in ipairs(allThemes) do
            if theme.status == "Installed" then
                table.insert(filteredThemes, theme)
            end
        end
    -- "upgrade available" filter (example: filter only rows where 'upgrade' = true)
    elseif filter == "Update avail." then
        for i, theme in ipairs(allThemes) do 
            if theme.status == "Update avail." then
                table.insert(filteredThemes, theme)
            end
        end
    end
end

-- Sort the table by a specific key (like "name" or "date")
function sortThemes(key)
    local function padnum(d) local dec, n = string.match(d, "(%.?)0*(.+)")
        return #dec > 0 and ("%.12f"):format(d) or ("%s%03d%s"):format(dec, #n, n) end
    
    table.sort(filteredThemes, function(a,b)
        if sortOrder == 1 then
            first, last = a, b
        else
            first, last = b, a
        end

        if key == "updatedAgo" or key == "downloads" then
            -- num sort
            if first[key] == last[key] then
                return first["name"] < last["name"]
            else
                return first[key] < last[key]
            end
        else
            -- alphanum sort
            return string.lower(tostring(first[key])):gsub("%.?%d+",padnum)..("%3d"):format(#last[key])
                    < string.lower(tostring(last[key])):gsub("%.?%d+",padnum)..("%3d"):format(#first[key])
        end
    end)
    return filteredThemes
end

-- Toggle the sorting key and order
function cycleSort()
    -- Reverse the sort order (ascending <-> descending)
    sortOrder = -sortOrder
    if sortOrder > 0 then
        -- Cycle to the next sort key
        currentSortIndex = currentSortIndex + 1
        if currentSortIndex > #sortKeys then
            currentSortIndex = 1  -- Cycle back to the first key
            sortOrder = 1
        end
    end
    -- Apply filter and sort themes
    sortThemes(sortKeys[currentSortIndex])
    selectedTheme = 1
end

-- Cycle through the filters
function cycleFilter()
    -- Move to the next filter
    currentFilterIndex = currentFilterIndex + 1
    if currentFilterIndex > #filters then
        currentFilterIndex = 1  -- Cycle back to the first filter
    end
    -- Apply filter and sort themes
    applyFilter(filters[currentFilterIndex])
    selectedTheme = 1
end

-- Cycle through the views
function cycleView()
    -- Move to the next view
    currentViewIndex = currentViewIndex + 1
    if currentViewIndex > #views then
        currentViewIndex = 1  -- Cycle back to the first filter
    end
end

-- Handle Xbox controller input
function love.gamepadpressed(joystick, button)
    print("Button pressed: " .. button)
    if button == "dpdown" then
        if showThemeMenu then
            selectedMenuItem = math.min(selectedMenuItem + 1, #menuItems)
        else
            selectedTheme = math.min(selectedTheme + 1, numThemes)
        end
    elseif button == "dpup" then
        if showThemeMenu then
            selectedMenuItem = math.max(selectedMenuItem - 1, 1)
        else
            selectedTheme = math.max(selectedTheme -1, 1)
        end
    elseif button == "leftshoulder" then
        selectedTheme = math.max(selectedTheme -10, 1)
    elseif button == "rightshoulder" then
        selectedTheme = math.min(selectedTheme + 10, numThemes)
    elseif button == "x" then
        cycleSort()
    elseif button == "y" then
        cycleFilter()
    elseif button == "a" then
        if showThemeMenu then
            menuItems[selectedMenuItem].action()
        else
            showThemeMenu = true
            selectedMenuItem = 1
        end
    elseif button == "b" then
        if showThemeMenu then
            showThemeMenu = false
        else
            print("exit menu")
        end
    elseif button == "start" then
        cycleView()
    end
end

function love.keypressed(key)
    print("Key pressed: " .. key)
    if key == "down" then
        if showThemeMenu then
            selectedMenuItem = math.min(selectedMenuItem + 1, #menuItems)
        else
            selectedTheme = math.min(selectedTheme + 1, numThemes)
        end
    elseif key == "up" then
        if showThemeMenu then
            selectedMenuItem = math.max(selectedMenuItem - 1, 1)
        else
            selectedTheme = math.max(selectedTheme -1, 1)
        end
    elseif key == "x" then
        cycleSort()
    elseif key == "y" then
        cycleFilter()
    elseif key == "h" then
        cycleView()
    elseif key == "pagedown" then
        selectedTheme = math.min(math.floor(selectedTheme + perPage), numThemes)
    elseif key == "pageup" then
        selectedTheme = math.max(math.floor(selectedTheme - perPage), 1)
    elseif key == "t" then
        downloadTheme(filteredThemes[selectedTheme])
    elseif key == "return" then
        if showThemeMenu then
            menuItems[selectedMenuItem].action()
        else
            showThemeMenu = true
            selectedMenuItem = 1
        end
    elseif key == "escape" then
        if showThemeMenu then
            showThemeMenu = false
        else
            print("exit menu")
        end
    end
    print("selectedTheme: " .. selectedTheme)
end

-- Function to draw the menu bar
function drawMenuBar()
    local paddingX = 10
    local paddingY = screenHeight - menuHeight - 5
    local iconSize = menuHeight

    -- Get the current font height for alignment purposes
    local fontHeight = love.graphics.getFont():getHeight()

    -- Calculate scale factors for each button icon based on desired size
    local scale = iconSize / buttonIcons.x:getHeight()

    -- Calculate the vertical position to center the text
    local textOffset = (iconSize - fontHeight) / 2

    -- Draw X button with scaling and vertically centered text (Sort)
    love.graphics.draw(buttonIcons.x, paddingX, paddingY, 0, scale, scale)
    local currentSortKey = sortKeysMap[sortKeys[currentSortIndex]]
    local sortOrderText = sortOrder == 1 and "Asc." or "Desc."
    love.graphics.print("Sort: " .. currentSortKey .. " (" .. sortOrderText .. ")", paddingX + iconSize + 5, paddingY + textOffset)

    -- Draw Y button with scaling and vertically centered text (Filter)
    love.graphics.draw(buttonIcons.y, paddingX + 230, paddingY, 0, scale, scale)
    love.graphics.print("Filter: " .. filters[currentFilterIndex], paddingX + 230 + iconSize + 5, paddingY + textOffset)

    -- Draw menu button with scaling and vertically centered text
    local scaleStart = iconSize / buttonIcons.start:getHeight()
    love.graphics.draw(buttonIcons.start, paddingX + 430, paddingY, 0, scaleStart, scaleStart)
    love.graphics.print("View: " .. views[currentViewIndex], paddingX + 430 + buttonIcons.start:getWidth()*scaleStart + 5, paddingY + textOffset)
end

function drawBackground()
    -- Set the color for the transparent overlay (RGBA: 1, 1, 1, 0.5 = 50% transparent white)
    love.graphics.setColor(40/255, 42/255, 54/255, 1)
    -- Draw a rectangle over the whole screen as the transparent layer
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    -- Reset color to white (full opacity) for subsequent draws
    love.graphics.setColor(1, 1, 1, 1)
end

-- Function to draw the table dynamically
function drawTable()
    numThemes = #filteredThemes

    -- Set some colors for table elements
    local borderColor = {1, 1, 1, 1} -- Light gray for borders
    local headerBackgroundColor = {0.2, 0.2, 0.2, 0.8} -- Dark gray for the header background
    local headerTextColor = {1, 1, 1, 1} -- White for header text
    local rowTextColor = {1, 1, 1, 1} -- White for row text

    -- Calculate column widths
    local columnWidths = {100, 150, 100, 100} -- Adjust based on the number of columns
    local startX = 5
    local startY = yPosMain

    local fontHeight = love.graphics.getFont():getHeight()
    local rowHeight = fontHeight + 5
    local textOffset = (rowHeight - fontHeight) / 2

    -- Table column headers
    -- Draw the header row with borders
    love.graphics.setColor(borderColor)
    love.graphics.rectangle("line", 0, startY, screenWidth, rowHeight)

    love.graphics.print("Name", startX, startY)
    love.graphics.print("Updated", startX + 280, startY)
    love.graphics.print("Downloads", startX + 400, startY)
    love.graphics.print("Status", startX + 510, startY)

    startY = startY + rowHeight
    perPage = (screenHeight - rowHeight * 2) / rowHeight
    local scrollPadding = perPage / 2
    local scrollThreshold = math.floor(perPage - scrollPadding + 0.5)

    if numThemes > 0 then
        -- Draw each theme
        for i, theme in ipairs(filteredThemes) do
            local yPos = startY + (i - 1) * rowHeight
            local toDisplay = true
            
            scrollIndex = selectedTheme - scrollThreshold
            if scrollIndex >= 0 then
                yPos = startY + (i - 1 - scrollIndex) * rowHeight
            end

            -- handle scroll
            if selectedTheme > scrollThreshold then
                -- need to scroll down
                if (selectedTheme - scrollThreshold + 1 > i) or (i > perPage - scrollThreshold + selectedTheme) then
                    toDisplay = false
                end
            elseif (i > perPage) then
                toDisplay = false
            end

            if toDisplay then
                if i == selectedTheme then
                    love.graphics.setColor(213/255, 223/255, 229/255)
                    love.graphics.rectangle("fill", 0, yPos, screenWidth, rowHeight)
                    love.graphics.setColor(0, 0, 0)
                else
                    love.graphics.setColor(1, 1, 1)
                end
                love.graphics.print(theme.name, startX, yPos + textOffset)
                love.graphics.print(theme.updatedAgo, startX + 280, yPos + textOffset)
                love.graphics.print(tostring(theme.downloads), startX + 400, yPos + textOffset)
                love.graphics.print(tostring(theme.status), startX + 510, yPos + textOffset)
                
                love.graphics.setColor(1,1,1)
            end
        end
        -- previewImage = imageFromUrl(filteredThemes[selectedTheme].name, filteredThemes[selectedTheme].previewUrl).img
        -- if previewImage and previewImage ~= "404" then
        --     -- Draw the background image
        --     love.graphics.draw(previewImage, screenWidth - previewImage:getWidth(), screenHeight - previewImage:getHeight() - rowHeight)
        -- end
    end
end

function drawList()
    numThemes = #filteredThemes
    if numThemes > 0 then
        -- Set some colors for table elements
        local borderColor = {1, 1, 1, 1} -- Light gray for borders
        local headerBackgroundColor = {0.2, 0.2, 0.2, 0.8} -- Dark gray for the header background
        local headerTextColor = {1, 1, 1, 1} -- White for header text
        local rowTextColor = {1, 1, 1, 1} -- White for row text

        -- Calculate column widths
        local startX = 5
        local startY = yPosMain

        local fontHeight = love.graphics.getFont():getHeight()
        local rowHeight = fontHeight + 5
        local textOffset = (rowHeight - fontHeight) / 2

        perPage = (screenHeight - rowHeight) / rowHeight
        local scrollPadding = perPage / 2
        local scrollThreshold = math.floor(perPage - scrollPadding + 0.5)

        -- Draw each theme
        for i, theme in ipairs(filteredThemes) do
            local yPos = startY + (i - 1) * rowHeight
            local toDisplay = true

            scrollIndex = selectedTheme - scrollThreshold
            if scrollIndex >= 0 then
                yPos = startY + (i - 1 - scrollIndex) * rowHeight
            end
            
            -- handle scroll
            if selectedTheme > scrollThreshold then
                -- need to scroll down
                if (selectedTheme - scrollThreshold + 1 > i) or (i > perPage - scrollThreshold + selectedTheme) then
                    toDisplay = false
                end
            elseif (i > perPage) then
                toDisplay = false
            end

            if toDisplay then
                
                if i == selectedTheme then
                    love.graphics.setColor(213/255, 223/255, 229/255)
                    love.graphics.rectangle("fill", 0, yPos, 290, rowHeight)
                    love.graphics.setColor(0, 0, 0)

                else
                    love.graphics.setColor(1, 1, 1)
                end
                love.graphics.print(theme.name, startX, yPos + textOffset)
                love.graphics.setColor(1,1,1)
            end
        end

        imgFromUrl = imageFromUrl(filteredThemes[selectedTheme].name, filteredThemes[selectedTheme].previewDirectUrl)
        if imgFromUrl then
            previewImage = imgFromUrl.img
        end
        if previewImage and previewImage ~= "404" then
            -- Draw the background image
            love.graphics.draw(previewImage, screenWidth *2/3- previewImage:getWidth()/2 + 30, (screenHeight - yPosMain) /2 - previewImage:getHeight() + 80)
        end
        local themeStatus = filteredThemes[selectedTheme].status
        if themeStatus == "" then
            themeStatus = "Not installed"
        end
        love.graphics.print("Updated " .. filteredThemes[selectedTheme].updatedAgo .. ", " .. filteredThemes[selectedTheme].downloads .. " downloads", 315, (screenHeight - yPosMain) /2 + 90)
        love.graphics.print("Latest version: " .. filteredThemes[selectedTheme].version, 315, (screenHeight - yPosMain) /2 + 90 + fontHeight * 1)
        love.graphics.print("Status: " .. themeStatus, 315, (screenHeight - yPosMain) /2 + 90 + fontHeight * 2)
    end
end

-- Draw the menu function
function drawMenu()
    -- Set up colors
    local backgroundColor = {108/255, 117/255, 244/255, 1} -- Black with transparency
    local textColor = {0.8, 0.8, 0.8, 1} -- White for text
    local highlightColor = {1, 1, 1, 1} -- Light blue for highlighting

    -- Get screen dimensions
    local screenWidth, screenHeight = love.graphics.getDimensions()

    menuItems = {}
    local themeStatus = filteredThemes[selectedTheme].status
    if themeStatus == "Update avail." then
        table.insert(menuItems, {text = "Update theme", action = updateTheme})
    end
    if themeStatus == "Installed" or themeStatus == "Update avail." then
        -- table.insert(menuItems, {text = "Apply theme", action = applyTheme})
        table.insert(menuItems, {text = "Remove theme", action = removeTheme})
    end

    if themeStatus == "" then
        table.insert(menuItems, {text = "Install theme", action = downloadTheme})
    end

    -- Calculate menu dimensions
    local menuWidth = 200
    local menuHeight = #menuItems * 20 + 10 -- Height based on number of items
    local menuX = (screenWidth - menuWidth) / 2
    local menuY = (screenHeight - menuHeight) / 2

    -- Draw menu background
    love.graphics.setColor(backgroundColor)
    love.graphics.rectangle("fill", menuX, menuY, menuWidth, menuHeight)

    -- Draw menu items
    for i, item in ipairs(menuItems) do
        local itemY = menuY + (i - 1) * 20

        -- Highlight the selected item
        if i == selectedMenuItem then
            love.graphics.setColor(highlightColor)
        else
            love.graphics.setColor(textColor)
        end
        love.graphics.printf(item.text, menuX, itemY, menuWidth, "center")
    end
end

-- Main draw function
function love.draw()
    -- Apply filter and sort themes
    applyFilter(filters[currentFilterIndex])
    sortThemes(sortKeys[currentSortIndex])
    -- Draw
    drawBackground()
    yPosMain = 0

    drawMenuBar()
    currentView = views[currentViewIndex]
    if currentView == "Details" then
        drawTable()
    elseif currentView == "List" then
        drawList()
    end
    if showThemeMenu then
        drawMenu()
    end
end
