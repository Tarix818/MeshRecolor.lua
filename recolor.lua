local shared = odh_shared_plugins

--// Services
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

--// Plugin section
local mesh_recolour_section = shared.AddSection("Mesh Recolourer")

mesh_recolour_section:AddLabel("Mesh Recolourer")
mesh_recolour_section:AddParagraph(
    "How to use",
    "Select one or more MeshParts/Parts, enter a colour, then press Apply Colour."
)

mesh_recolour_section:AddParagraph(
    "Colour formats",
    "BrickColor name, HEX (#RRGGBB), or RGB (R,G,B). Examples: Really red, #00FF00, 0,120,255"
)

--// Current colour text.
--// The TextBox is the main custom colour input.
local colourInput = ""

--// Preset colours
local presetColours = {
    "Really red",
    "Bright blue",
    "Bright green",
    "New Yeller",
    "Hot pink",
    "Royal purple",
    "Institutional white",
    "Black",
    "Dark stone grey",
    "Gold"
}

local colourDropdown = mesh_recolour_section:AddDropdown(
    "Preset Colour",
    presetColours,
    function(selected)
        if type(selected) == "string" then
            colourInput = selected
            shared.Notify("Selected colour: " .. selected, 2)
        end
    end
)

mesh_recolour_section:AddTextBox("Custom Colour", function(text)
    if type(text) ~= "string" then
        shared.Notify("Invalid colour input.", 2)
        return
    end

    colourInput = text

    if text == "" then
        shared.Notify("Colour input cleared.", 2)
    else
        shared.Notify("Custom colour set to: " .. text, 2)
    end
end)

--// Safely parse several useful colour formats.
local function parseColour(input)
    if type(input) ~= "string" then
        return nil
    end

    input = string.gsub(input, "^%s+", "")
    input = string.gsub(input, "%s+$", "")

    if input == "" then
        return nil
    end

    -- HEX: #RRGGBB or RRGGBB
    local hex = input

    if string.sub(hex, 1, 1) == "#" then
        hex = string.sub(hex, 2)
    end

    if string.match(hex, "^%x%x%x%x%x%x$") then
        local r = tonumber(string.sub(hex, 1, 2), 16)
        local g = tonumber(string.sub(hex, 3, 4), 16)
        local b = tonumber(string.sub(hex, 5, 6), 16)

        if r and g and b then
            return Color3.fromRGB(r, g, b)
        end
    end

    -- RGB: R,G,B
    local r, g, b = string.match(
        input,
        "^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$"
    )

    if r and g and b then
        r = tonumber(r)
        g = tonumber(g)
        b = tonumber(b)

        if r and g and b
            and r >= 0 and r <= 255
            and g >= 0 and g <= 255
            and b >= 0 and b <= 255 then

            return Color3.fromRGB(r, g, b)
        end

        return nil
    end

    -- RGB function format: rgb(R,G,B)
    local rr, gg, bb = string.match(
        string.lower(input),
        "^rgb%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*%)$"
    )

    if rr and gg and bb then
        rr = tonumber(rr)
        gg = tonumber(gg)
        bb = tonumber(bb)

        if rr and gg and bb
            and rr >= 0 and rr <= 255
            and gg >= 0 and gg <= 255
            and bb >= 0 and bb <= 255 then

            return Color3.fromRGB(rr, gg, bb)
        end

        return nil
    end

    -- BrickColor name or BrickColor number.
    local success, brickColour = pcall(function()
        local numericValue = tonumber(input)

        if numericValue then
            return BrickColor.new(numericValue)
        end

        return BrickColor.new(input)
    end)

    if success and brickColour then
        return brickColour.Color
    end

    return nil
end

--// Apply colour to one supported object.
local function recolourObject(object, colour)
    if not object or not object:IsA("BasePart") then
        return false, "Not a BasePart"
    end

    -- MeshParts using SurfaceAppearance need the SurfaceAppearance
    -- tint changed because SurfaceAppearance overrides the normal
    -- MeshPart appearance.
    if object:IsA("MeshPart") then
        local surfaceAppearance = object:FindFirstChildOfClass("SurfaceAppearance")

        if surfaceAppearance then
            local success, err = pcall(function()
                surfaceAppearance.Color = colour
            end)

            if success then
                return true, "SurfaceAppearance"
            end

            return false, err or "Could not change SurfaceAppearance.Color"
        end

        -- Normal MeshPart / legacy TextureID appearance.
        local success, err = pcall(function()
            object.Color = colour
        end)

        if success then
            return true, "MeshPart"
        end

        return false, err or "Could not change MeshPart.Color"
    end

    -- Normal Parts, including Parts containing SpecialMesh.
    -- BasePart.Color controls the visible part colour, so we do
    -- not modify the SpecialMesh itself or any unrelated children.
    local success, err = pcall(function()
        object.Color = colour
    end)

    if success then
        return true, "Part"
    end

    return false, err or "Could not change Part.Color"
end

--// Apply button
mesh_recolour_section:AddButton("Apply Colour", function()
    -- Validate colour first.
    local colour = parseColour(colourInput)

    if not colour then
        shared.Notify(
            "Invalid colour. Use a BrickColor name, #RRGGBB, or R,G,B.",
            4
        )
        return
    end

    -- Safely obtain the current Studio selection.
    local selection
    local selectionSuccess, selectionResult = pcall(function()
        return Selection:Get()
    end)

    if not selectionSuccess then
        shared.Notify("Could not read the current Studio selection.", 4)
        return
    end

    selection = selectionResult

    if type(selection) ~= "table" or #selection == 0 then
        shared.Notify("Select at least one MeshPart or Part first.", 3)
        return
    end

    local changedCount = 0
    local skippedCount = 0
    local failedCount = 0

    -- Only operate on objects directly selected by the user.
    -- We deliberately do not search descendants of Models so that
    -- unrelated objects are never changed accidentally.
    for _, object in ipairs(selection) do
        if object and object.Parent and object:IsA("BasePart") then
            local success = recolourObject(object, colour)

            if success then
                changedCount = changedCount + 1
            else
                failedCount = failedCount + 1
            end
        else
            skippedCount = skippedCount + 1
        end
    end

    -- Make the operation undoable in Studio.
    if changedCount > 0 then
        pcall(function()
            ChangeHistoryService:SetWaypoint("Mesh Recolourer - Apply Colour")
        end)
    end

    if changedCount == 0 then
        shared.Notify(
            "Nothing was recoloured. Select a MeshPart or Part.",
            4
        )
        return
    end

    local message = "Recoloured " .. changedCount .. " object(s)."

    if skippedCount > 0 then
        message = message .. " Skipped " .. skippedCount .. "."
    end

    if failedCount > 0 then
        message = message .. " Failed " .. failedCount .. "."
    end

    shared.Notify(message, 4)
end)

--// Helpful selection reminder
mesh_recolour_section:AddButton("Check Selection", function()
    local success, selection = pcall(function()
        return Selection:Get()
    end)

    if not success or type(selection) ~= "table" then
        shared.Notify("Could not read Studio selection.", 3)
        return
    end

    local supported = 0

    for _, object in ipairs(selection) do
        if object and object:IsA("BasePart") then
            supported = supported + 1
        end
    end

    if #selection == 0 then
        shared.Notify("Nothing is selected.", 3)
    elseif supported == 0 then
        shared.Notify("Selection contains no Parts or MeshParts.", 3)
    else
        shared.Notify(
            tostring(supported) .. " supported object(s) selected.",
            3
        )
    end
end)