--[[
* Chains displays current skillchains for the active target.
* It is based on the skillchains addon by Ivaar for Ashita v3.
*
* Several functions are leveraged from LuAshitacast by Thorny
* ParseActionPacket function is leveraged from timers by The Mystic
*
* Chains is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* Chains is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with Ashita.  If not, see <https://www.gnu.org/licenses/>.
--]]

addon.name     = 'chains';
addon.author   = 'Sippius - Original Ashita-v3 skillchains by Ivaar';
addon.version  = '0.8';
addon.desc     = 'Display current skillchain options.';

require('common');
local ffi = require('ffi');
local chat = require('chat');
local imgui = require('imgui');
local d3d8 = require('d3d8');
local settings = require('settings');

local skills = require('skills');

--=============================================================================
-- Addon Variables
--=============================================================================
local default_settings = T{
    position_x = 100,
    position_y = 100,
    font_scale = 1.0,
    opacity = T{
        background = 0.8,
        border = 0.5,
        text = 1.0,
    },
    show_burst_names = true,
    bg_style = 'solid',                  -- 'solid' or 'menu' (FFXI style)
    bg_color = { 0.06, 0.06, 0.06 },     -- solid background color
    menu_top = { 0.10, 0.08, 0.17 },     -- FFXI menu gradient, top
    menu_bottom = { 0.125, 0.125, 0.30 },-- FFXI menu gradient, bottom
    scanlines = 0.6,                     -- FFXI menu scanline strength
    border_color = { 0.6, 0.6, 0.7 },
    outline = T{
        enabled = false,
        thickness = 1,
        color = { 0.0, 0.0, 0.0 },
        opacity = 1.0,
    },
    list_outline = T{                    -- outline for the chain list text
        enabled = false,
        thickness = 1,
        color = { 0.0, 0.0, 0.0 },
        opacity = 1.0,
    },
    icon_scale = 1.0,
    line_scale = 1.0,                    -- text size of the skillchain list lines
    line_spacing = 0.0,                  -- extra pixels between list lines
    ws_color = { 1.0, 1.0, 1.0 },        -- weapon skill name color
    countdown = T{
        scale = 3.0,
        opacity = 0.5,
        color = { 0.3, 1.0, 0.3 },
        wait_color = { 1.0, 0.0, 0.0 },
    },
    display = T{
        color = true,
        pet = true,
        spell = true,
        weapon = true,
    },
};

local chains = T{
    settings = settings.load(default_settings),
    visible = false,
    move = nil,

    debug = false,
    forceAeonic = 0, -- set from 0 to 3
    forceImmanence = false, -- boolean
    forceAffinity = false, -- boolean
};

-- ensure newer settings exist when loading an older settings file
local function ValidateSettings()
    local s = chains.settings;
    if type(s.opacity) ~= 'table' then s.opacity = T{}; end
    for k,v in pairs(default_settings.opacity) do
        if type(s.opacity[k]) ~= 'number' then s.opacity[k] = v; end
    end
    if s.show_burst_names == nil then s.show_burst_names = default_settings.show_burst_names; end
    if type(s.icon_scale) ~= 'number' then s.icon_scale = default_settings.icon_scale; end
    if type(s.line_scale) ~= 'number' then s.line_scale = default_settings.line_scale; end
    if type(s.line_spacing) ~= 'number' then s.line_spacing = default_settings.line_spacing; end
    if type(s.ws_color) ~= 'table' or #s.ws_color < 3 then
        s.ws_color = { default_settings.ws_color[1], default_settings.ws_color[2], default_settings.ws_color[3] };
    end
    local function ensureColor(t, k, d)
        if type(t[k]) ~= 'table' or #t[k] < 3 then t[k] = { d[1], d[2], d[3] }; end
    end
    if s.bg_style ~= 'solid' and s.bg_style ~= 'menu' then s.bg_style = default_settings.bg_style; end
    ensureColor(s, 'bg_color',     default_settings.bg_color);
    ensureColor(s, 'menu_top',     default_settings.menu_top);
    ensureColor(s, 'menu_bottom',  default_settings.menu_bottom);
    ensureColor(s, 'border_color', default_settings.border_color);
    if type(s.scanlines) ~= 'number' then s.scanlines = default_settings.scanlines; end
    if type(s.outline) ~= 'table' then s.outline = T{}; end
    if type(s.outline.enabled) ~= 'boolean' then s.outline.enabled = default_settings.outline.enabled; end
    if type(s.outline.thickness) ~= 'number' then s.outline.thickness = default_settings.outline.thickness; end
    if type(s.outline.opacity) ~= 'number' then s.outline.opacity = default_settings.outline.opacity; end
    ensureColor(s.outline, 'color', default_settings.outline.color);
    if type(s.list_outline) ~= 'table' then
        -- migrate: start from the previous shared outline settings
        s.list_outline = T{
            enabled = s.outline.enabled, thickness = s.outline.thickness, opacity = s.outline.opacity,
            color = { s.outline.color[1], s.outline.color[2], s.outline.color[3] },
        };
    end
    if type(s.list_outline.enabled) ~= 'boolean' then s.list_outline.enabled = default_settings.list_outline.enabled; end
    if type(s.list_outline.thickness) ~= 'number' then s.list_outline.thickness = default_settings.list_outline.thickness; end
    if type(s.list_outline.opacity) ~= 'number' then s.list_outline.opacity = default_settings.list_outline.opacity; end
    ensureColor(s.list_outline, 'color', default_settings.list_outline.color);
    if type(s.countdown) ~= 'table' then s.countdown = T{}; end
    for k,v in pairs(default_settings.countdown) do
        if type(v) == 'table' then
            if type(s.countdown[k]) ~= 'table' or #s.countdown[k] < 3 then
                s.countdown[k] = { v[1], v[2], v[3] };
            end
        elseif type(s.countdown[k]) ~= 'number' then
            s.countdown[k] = v;
        end
    end
end
ValidateSettings();

-- config window state (imgui widgets need table-wrapped values)
chains.config = { open = { false } };

local function SyncConfig()
    local s, c = chains.settings, chains.config;
    c.background = { s.opacity.background };
    c.border     = { s.opacity.border };
    c.text       = { s.opacity.text };
    c.scale      = { s.font_scale };
    c.names      = { s.show_burst_names };
    c.icon_scale = { s.icon_scale };
    c.line_scale   = { s.line_scale };
    c.line_spacing = { s.line_spacing };
    c.ws_color     = { s.ws_color[1], s.ws_color[2], s.ws_color[3] };
    c.bg_color     = { s.bg_color[1], s.bg_color[2], s.bg_color[3] };
    c.menu_top     = { s.menu_top[1], s.menu_top[2], s.menu_top[3] };
    c.menu_bottom  = { s.menu_bottom[1], s.menu_bottom[2], s.menu_bottom[3] };
    c.border_color = { s.border_color[1], s.border_color[2], s.border_color[3] };
    c.scanlines    = { s.scanlines };
    c.lo_enabled   = { s.list_outline.enabled };
    c.lo_thickness = { s.list_outline.thickness };
    c.lo_opacity   = { s.list_outline.opacity };
    c.lo_color     = { s.list_outline.color[1], s.list_outline.color[2], s.list_outline.color[3] };
    c.ol_enabled   = { s.outline.enabled };
    c.ol_thickness = { s.outline.thickness };
    c.ol_opacity   = { s.outline.opacity };
    c.ol_color     = { s.outline.color[1], s.outline.color[2], s.outline.color[3] };
    c.cd_scale   = { s.countdown.scale };
    c.cd_opacity = { s.countdown.opacity };
    c.cd_color   = { s.countdown.color[1], s.countdown.color[2], s.countdown.color[3] };
    c.cd_wait    = { s.countdown.wait_color[1], s.countdown.wait_color[2], s.countdown.wait_color[3] };
end
SyncConfig();

-- store player ID
-- * capture on init
local playerID;

-- store list of valid player/pet skills
-- * capture bluskill on 0x44 packet or first GetSkillchains call
-- * capture wepskill on 0xAC packet or first GetSkillchains call
-- * capture petskill on 0xAC packet or first GetSkillchains call
-- * capture schskill on load
local actionTable = T{
    schskill = skills.immanence,
};

-- store per player buff information
-- * player/buff added through action packet
-- * buff deleted through action packet when used or through presentevent on timeout
-- * player deleted through present event when no buff active
local playerTable = T{
};

-- store per target information on properties and duration
-- * target added through action packet
-- * target deleted through present event on timeout
local targetTable = T{
};

-- static information on skillchains
local chainInfo = T{
    Radiance = T{level = 4, burst = T{'Fire','Wind','Lightning','Light'}},
    Umbra    = T{level = 4, burst = T{'Earth','Ice','Water','Dark'}},
    Light    = T{level = 3, burst = T{'Fire','Wind','Lightning','Light'},
        aeonic = T{level = 4, skillchain = 'Radiance'},
        Light  = T{level = 4, skillchain = 'Light'},
    },
    Darkness = T{level = 3, burst = T{'Earth','Ice','Water','Dark'},
        aeonic   = T{level = 4, skillchain = 'Umbra'},
        Darkness = T{level = 4, skillchain = 'Darkness'},
    },
    Gravitation = T{level = 2, burst = T{'Earth','Dark'},
        Distortion    = T{level = 3, skillchain = 'Darkness'},
        Fragmentation = T{level = 2, skillchain = 'Fragmentation'},
    },
    Fragmentation = T{level = 2, burst = T{'Wind','Lightning'},
        Fusion     = T{level = 3, skillchain = 'Light'},
        Distortion = T{level = 2, skillchain = 'Distortion'},
    },
    Distortion = T{level = 2, burst = T{'Ice','Water'},
        Gravitation = T{level = 3, skillchain = 'Darkness'},
        Fusion      = T{level = 2, skillchain = 'Fusion'},
    },
    Fusion = T{level = 2, burst = T{'Fire','Light'},
        Fragmentation = T{level = 3, skillchain = 'Light'},
        Gravitation   = T{level = 2, skillchain = 'Gravitation'},
    },
    Compression = T{level = 1, burst = T{'Darkness'},
        Transfixion = T{level = 1, skillchain = 'Transfixion'},
        Detonation  = T{level = 1, skillchain = 'Detonation'},
    },
    Liquefaction = T{level = 1, burst = T{'Fire'},
        Impaction = T{level = 2, skillchain = 'Fusion'},
        Scission  = T{level = 1, skillchain = 'Scission'},
    },
    Induration = T{level = 1, burst = T{'Ice'},
        Reverberation = T{level = 2, skillchain = 'Fragmentation'},
        Compression   = T{level = 1, skillchain = 'Compression'},
        Impaction     = T{level = 1, skillchain = 'Impaction'},
    },
    Reverberation = T{level = 1, burst = T{'Water'},
        Induration = T{level = 1, skillchain = 'Induration'},
        Impaction  = T{level = 1, skillchain = 'Impaction'},
    },
    Transfixion = T{level = 1, burst = T{'Light'},
        Scission      = T{level = 2, skillchain = 'Distortion'},
        Reverberation = T{level = 1, skillchain = 'Reverberation'},
        Compression   = T{level = 1, skillchain = 'Compression'},
    },
    Scission = T{level = 1, burst = T{'Earth'},
        Liquefaction  = T{level = 1, skillchain = 'Liquefaction'},
        Reverberation = T{level = 1, skillchain = 'Reverberation'},
        Detonation    = T{level = 1, skillchain = 'Detonation'},
    },
    Detonation = T{level = 1, burst = T{'Wind'},
        Compression = T{level = 2, skillchain = 'Gravitation'},
        Scission    = T{level = 1, skillchain = 'Scission'},
    },
    Impaction = T{level = 1, burst = T{'Lightning'},
        Liquefaction = T{level = 1, skillchain = 'Liquefaction'},
        Detonation   = T{level = 1, skillchain = 'Detonation'},
    },
};

-- IMGUI RGB color format {red, green, blue, alpha}
local colors = {};           -- Color codes by Sammeh
colors.Light =         { 1.0, 1.0, 1.0, 1.0 }; --'0xFFFFFFFF';
colors.Dark =          { 0.0, 0.0, 0.8, 1.0 }; --'0x0000CCFF';
colors.Ice =           { 0.0, 1.0, 1.0, 1.0 }; --'0x00FFFFFF';
colors.Water =         { 0.0, 1.0, 1.0, 1.0 }; --'0x00FFFFFF';
colors.Earth =         { 0.6, 0.5, 0.0, 1.0 }; --'0x997600FF';
colors.Wind =          { 0.4, 1.0, 0.4, 1.0 }; --'0x66FF66FF';
colors.Fire =          { 1.0, 0.0, 0.0, 1.0 }; --'0xFF0000FF';
colors.Lightning =     { 1.0, 0.0, 1.0, 1.0 }; --'0xFF00FFFF';
colors.Gravitation =   { 0.4, 0.2, 0.0, 1.0 }; --'0x663300FF';
colors.Fragmentation = { 1.0, 0.6, 1.0, 1.0 }; --'0xFA9CF7FF';
colors.Fusion =        { 1.0, 0.4, 0.4, 1.0 }; --'0xFF6666FF';
colors.Distortion =    { 0.2, 0.6, 1.0, 1.0 }; --'0x3399FFFF';
colors.Darkness =      colors.Dark;
colors.Umbra =         colors.Dark;
colors.Compression =   colors.Dark;
colors.Radiance =      colors.Light;
colors.Transfixion =   colors.Light;
colors.Induration =    colors.Ice;
colors.Reverberation = colors.Water;
colors.Scission =      colors.Earth;
colors.Detonation =    colors.Wind;
colors.Liquefaction =  colors.Fire;
colors.Impaction =     colors.Lightning;

local statusID = {
    AL  = 163, -- Azure Lore
    CA  = 164, -- Chain Affinity
    AM1 = 270, -- Aftermath: Lv.1
    AM2 = 271, -- Aftermath: Lv.2
    AM3 = 272, -- Aftermath: Lv.3
    IM  = 470  -- Immanence
};

local MessageTypes = T{
    2,   -- '<caster> casts <spell>. <target> takes <amount> damage'
  --100, -- 'The <player> uses ..' -- Causes Super Jump to match as Spinning Axe if enabled
    110, -- '<user> uses <ability>. <target> takes <amount> damage.'
  --161, -- Additional effect: <number> HP drained from <target>.
  --162, -- Additional effect: <number> MP drained from <target>.
    185, -- 'player uses, target takes 10 damage. DEFAULT'
    187, -- '<user> uses <skill>. <amount> HP drained from <target>'
    317, -- 'The <player> uses .. <target> takes .. points of damage.'
  --529, -- '<user> uses <ability>. <target> is chainbound.',
    802  -- 'The <user> uses <skill>. <number> HP drained from <target>.'
}

local PetMessageTypes = T{
    110, -- '<user> uses <ability>. <target> takes <amount> damage.'
    317  -- 'The <player> uses .. <target> takes .. points of damage.'
};

local ChainBuffTypes = T{
    [statusID.AL] = { duration = 30 }, -- 40 with relic hands
    [statusID.CA] = { duration = 30 },
    [statusID.IM] = { duration = 60 }
};

local EquipSlotNames = T{
    [1] = 'Main',
    --[2] = 'Sub',
    [3] = 'Range',
    --[4] = 'Ammo',
    --[5] = 'Head',
    --[6] = 'Body',
    --[7] = 'Hands',
    --[8] = 'Legs',
    --[9] = 'Feet',
    --[10] = 'Neck',
    --[11] = 'Waist',
    --[12] = 'Ear1',
    --[13] = 'Ear2',
    --[14] = 'Ring1',
    --[15] = 'Ring2',
    --[16] = 'Back'
};

local SkillPropNames = T{
    [1] = 'Light',
    [2] = 'Darkness',
    [3] = 'Gravitation',
    [4] = 'Fragmentation',
    [5] = 'Distortion',
    [6] = 'Fusion',
    [7] = 'Compression',
    [8] = 'Liquefaction',
    [9] = 'Induration',
    [10] = 'Reverberation',
    [11] = 'Transfixion',
    [12] = 'Scission',
    [13] = 'Detonation',
    [14] = 'Impaction',
    [15] = 'Radiance',
    [16] = 'Umbra'
};

--=============================================================================
-- Registers a callback for the settings to monitor for character switches.
--=============================================================================
settings.register('settings', 'settings_update', function (s)
    if (s ~= nil) then
        chains.settings = s;
        ValidateSettings();
        SyncConfig();
    end

    settings.save();
end);

--=============================================================================
-- Return color formatt table
---@param t string Skillchain property
---@return table
--=============================================================================
-- based on code from skillchains by Ivaar
--=============================================================================
local function GetPropertyColor(t)
    local c = { 1.0, 1.0, 1.0, 1.0 };
    if chains.settings.display.color and colors[t] then
        c = colors[t];
    end
    -- apply text opacity
    return { c[1], c[2], c[3], c[4] * chains.settings.opacity.text };
end

--=============================================================================
-- Element icons (icons/<name>.png) used for the magic burst display
--=============================================================================
local iconFiles = {
    Fire      = 'Fire',
    Ice       = 'Ice',
    Wind      = 'Wind',
    Earth     = 'Earth',
    Lightning = 'Lightning',
    Water     = 'Water',
    Light     = 'Light',
    Dark      = 'Dark',
    Darkness  = 'Dark',
};

local iconCache = {};


---@param element string Burst element name
---@return userdata|nil texture
local function GetElementIcon(element)
    local file = iconFiles[element];
    if not file then return nil; end
    if iconCache[file] == nil then
        iconCache[file] = false; -- mark as attempted so a failed load is not retried every frame
        local texPtr = ffi.new('IDirect3DTexture8*[1]');
        local path = ('%sicons\\%s.png'):fmt(addon.path, file);
        local hr = ffi.C.D3DXCreateTextureFromFileA(d3d8.get_device(), path, texPtr);
        if hr == ffi.C.S_OK then
            iconCache[file] = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', texPtr[0]));
        end
    end
    return iconCache[file] or nil;
end

---Return text width in pixels (handles both return styles of CalcTextSize)
local function TextWidth(text)
    local a = imgui.CalcTextSize(text);
    if type(a) == 'table' then return a[1] or a.x or 0; end
    return a or 0;
end


--=============================================================================
-- Text with optional outline. The outline is drawn as copies of the text
-- offset in 8 directions, then the real text is drawn on top (so layout and
-- SameLine behave as normal).
--=============================================================================
local OUTLINE_OFFSETS = {
    { -1, -1 }, { 0, -1 }, { 1, -1 },
    { -1,  0 },            { 1,  0 },
    { -1,  1 }, { 0,  1 }, { 1,  1 },
};

---@param text string
---@param color table {r,g,b,a}
---@param ol table|nil Outline settings (defaults to the countdown outline)
local function DrawText(text, color, ol)
    ol = ol or chains.settings.outline;
    if ol.enabled and ol.opacity > 0 then
        local x, y = imgui.GetCursorPosX(), imgui.GetCursorPosY();
        local t = ol.thickness;
        local oc = { ol.color[1], ol.color[2], ol.color[3], ol.opacity * (color[4] or 1.0) };
        for _,o in ipairs(OUTLINE_OFFSETS) do
            imgui.SetCursorPos({ x + o[1] * t, y + o[2] * t });
            imgui.TextColored(oc, text);
        end
        imgui.SetCursorPos({ x, y });
    end
    imgui.TextColored(color, text);
end

--=============================================================================
-- Outline option widgets shared by the chain list and countdown sections.
---@param id string Unique suffix for widget ids
---@param ol table Settings table {enabled, thickness, color, opacity}
---@param w table Widget values {enabled, thickness, color, opacity}
---@return boolean changed
--=============================================================================
local function OutlineControls(id, ol, w)
    local changed = false;
    if imgui.Checkbox('Outline##' .. id, w.enabled) then
        ol.enabled = w.enabled[1]; changed = true;
    end
    if ol.enabled then
        if imgui.SliderFloat('Outline thickness##' .. id, w.thickness, 1.0, 3.0, '%.0f px') then
            ol.thickness = math.floor(w.thickness[1] + 0.5); changed = true;
        end
        if imgui.ColorEdit3('Outline color##' .. id, w.color) then
            ol.color = { w.color[1], w.color[2], w.color[3] }; changed = true;
        end
        if imgui.SliderFloat('Outline opacity##' .. id, w.opacity, 0.0, 1.0, '%.2f') then
            ol.opacity = w.opacity[1]; changed = true;
        end
    end
    return changed;
end

--=============================================================================
-- FFXI style menu background: dark purple/navy vertical gradient with
-- horizontal scanlines and a thin inner frame, drawn with the window draw list.
-- Returns false if the draw list calls are not supported.
--=============================================================================
local function PackColor(r, g, b, a)
    local function c8(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5); end
    return c8(a) * 16777216 + c8(b) * 65536 + c8(g) * 256 + c8(r);
end

local function DrawMenuBackground()
    local s = chains.settings;
    local alpha = s.opacity.background;
    local ok = pcall(function()
        local dl = imgui.GetWindowDrawList();
        local px, py = imgui.GetWindowPos();
        local w, h = imgui.GetWindowWidth(), imgui.GetWindowHeight();
        local top, bot = s.menu_top, s.menu_bottom;
        local dark = 1.0 - 0.30 * s.scanlines;   -- darkness of the alternate scanline rows

        local y = 0;
        while y < h do
            local t = y / math.max(1, h);
            local f = ((math.floor(y / 2)) % 2 == 0) and 1.0 or dark;
            local r = (top[1] + (bot[1] - top[1]) * t) * f;
            local g = (top[2] + (bot[2] - top[2]) * t) * f;
            local b = (top[3] + (bot[3] - top[3]) * t) * f;
            dl:AddRectFilled({ px, py + y }, { px + w, py + math.min(y + 2, h) }, PackColor(r, g, b, alpha), 0.0, 0);
            y = y + 2;
        end

        -- inner frame (darker shade of the border color)
        local bc, ba = s.border_color, s.opacity.border;
        local col = PackColor(bc[1] * 0.55, bc[2] * 0.55, bc[3] * 0.55, ba);
        dl:AddRectFilled({ px + 1, py + 1 }, { px + w - 1, py + 2 }, col, 0.0, 0);
        dl:AddRectFilled({ px + 1, py + h - 2 }, { px + w - 1, py + h - 1 }, col, 0.0, 0);
        dl:AddRectFilled({ px + 1, py + 1 }, { px + 2, py + h - 1 }, col, 0.0, 0);
        dl:AddRectFilled({ px + w - 2, py + 1 }, { px + w - 1, py + h - 1 }, col, 0.0, 0);
    end);
    if not ok then
        chains.menuFailed = true;
        print('chains: FFXI menu background is not supported here, using solid background.');
    end
end

--=============================================================================
-- Draw the large watermark countdown centered in the window, with the magic
-- burst element icons to its right (same height as the number).
-- Drawn first so the rest of the content sits on top of it.
---@param text string Number to display
---@param color table Color {r,g,b,a}
---@param bursts table|nil List of burst element names
--=============================================================================
local function DrawCountdown(text, color, bursts)
    local fs = chains.settings.font_scale;
    local cd = chains.settings.countdown;
    local cx, cy = imgui.GetCursorPosX(), imgui.GetCursorPosY();

    imgui.SetWindowFontScale(fs * cd.scale);
    local tw, th = TextWidth(text), imgui.GetTextLineHeight();
    local winW, winH = imgui.GetWindowWidth(), imgui.GetWindowHeight();

    -- gather icons that loaded successfully
    local icons = {};
    for _,v in ipairs(bursts or {}) do
        local icon = GetElementIcon(v);
        if icon then table.insert(icons, icon); end
    end

    local iconH = th * chains.settings.icon_scale;
    local gap = 6 * fs;
    local groupW = tw;
    if #icons > 0 then
        groupW = groupW + gap + #icons * iconH + (#icons - 1) * gap;
    end

    local x = math.max(0, (winW - groupW) / 2);
    imgui.SetCursorPos({ x, math.max(0, (winH - th) / 2) });
    DrawText(text, color);

    x = x + tw + gap;
    for _,icon in ipairs(icons) do
        imgui.SetCursorPos({ x, math.max(0, (winH - iconH) / 2) });
        imgui.Image(tonumber(ffi.cast('uint32_t', icon)), { iconH, iconH },
            { 0, 0 }, { 1, 1 }, { 1.0, 1.0, 1.0, cd.opacity }, { 0, 0, 0, 0 });
        x = x + iconH + gap;
    end

    imgui.SetWindowFontScale(fs);
    imgui.SetCursorPos({ cx, cy });
end

--=============================================================================
-- Return count of requested buff. Return zero if buff is not active.
---@param matchBuff string Name of buff to check
---@return integer count 
--=============================================================================
-- based on code from LuAshitacast by Thorny
--=============================================================================
local GetBuffCount = function(matchBuff)
    local count = 0;
    local buffs = AshitaCore:GetMemoryManager():GetPlayer():GetBuffs();
    if (type(matchBuff) == 'string') then
        local matchText = string.lower(matchBuff);
        for _, buff in pairs(buffs) do
            local buffString = AshitaCore:GetResourceManager():GetString("buffs.names", buff);
			if (buffString ~= nil) and (string.lower(buffString) == matchText) then
                count = count + 1;
            end
        end
    elseif (type(matchBuff) == 'number') then
        for _, buff in pairs(buffs) do
            if (buff == matchBuff) then
                count = count + 1;
            end
        end
    end
    return count;
end

--=============================================================================
-- Return equipment data
---@return table equipTable Current equipment information
--=============================================================================
-- based on code from LuAshitacast by Thorny
--=============================================================================
-- Combined gData.GetEquipment and gEquip.GetCurrentEquip
--=============================================================================
local GetEquipment = function()
    local inventoryManager = AshitaCore:GetMemoryManager():GetInventory();
    local equipTable = {};

    for k, v in pairs(EquipSlotNames) do
        local equippedItem = inventoryManager:GetEquippedItem(k - 1);
        local index = bit.band(equippedItem.Index, 0x00FF);
        local eqEntry = {};
        if (index == 0) then
            eqEntry.Container = 0;
            eqEntry.Item = nil;
        else
            eqEntry.Container = bit.band(equippedItem.Index, 0xFF00) / 256;
            eqEntry.Item = inventoryManager:GetContainerItem(eqEntry.Container, index);
            if (eqEntry.Item.Id == 0) or (eqEntry.Item.Count == 0) then
                eqEntry.Item = nil;
            end
        end
        if (type(eqEntry) == 'table') and (eqEntry.Item ~= nil) then
            local resource = AshitaCore:GetResourceManager():GetItemById(eqEntry.Item.Id);
            if (resource ~= nil) then
                local singleTable = {};
                singleTable.Container = eqEntry.Container;
                singleTable.Item = eqEntry.Item;
                singleTable.Name = resource.Name[1];
                singleTable.Resource = resource;
                equipTable[v] = singleTable;
            end
        end
    end

    return equipTable;
end

--=============================================================================
-- Return player data
---@return table playerTable Current player information
--=============================================================================
-- based on code from LuAshitacast by Thorny
--=============================================================================
local GetPlayer = function()
    local playerTable = {};
    local pParty = AshitaCore:GetMemoryManager():GetParty();
    local pPlayer = AshitaCore:GetMemoryManager():GetPlayer();

    local mainJob = pPlayer:GetMainJob();
    playerTable.MainJob = AshitaCore:GetResourceManager():GetString("jobs.names_abbr", mainJob);
    playerTable.MainJobLevel = pPlayer:GetJobLevel(mainJob);
    playerTable.MainJobSync = pPlayer:GetMainJobLevel();
    playerTable.Name = pParty:GetMemberName(0);

    local subJob = pPlayer:GetSubJob();
    playerTable.SubJob = AshitaCore:GetResourceManager():GetString("jobs.names_abbr", subJob);
    playerTable.SubJobLevel = pPlayer:GetJobLevel(subJob);
    playerTable.SubJobSync = pPlayer:GetSubJobLevel();
    playerTable.TP = pParty:GetMemberTP(0);

    return playerTable;
end

--=============================================================================
-- Return table with current weaponskill data
---@return table skillTable Currently available weapon skills
--=============================================================================
local GetWeaponskills = function()
    local skillTable = T{};
    local pPlayer = AshitaCore:GetMemoryManager():GetPlayer();

    for k,v in pairs(skills[3]) do
        if v and pPlayer:HasWeaponSkill(k) then
            skillTable:append(v);
        end
    end

    return skillTable;
end

--=============================================================================
-- Return table with current pet skill data
---@return table skillTable Currently available pet skills
--=============================================================================
local function GetPetskills()
    local skillTable = T{};
    local pPlayer = AshitaCore:GetMemoryManager():GetPlayer();

    for k,v in pairs(skills.playerPet) do
        if v and pPlayer:HasAbility(k+512) then
            skillTable:append(v);
        end
    end

    return skillTable;
  end

--=============================================================================
-- Define blu offset data for use by GetBluskills()
--=============================================================================
  local blu = {
    offset = ffi.cast('uint32_t*', ashita.memory.find('FFXiMain.dll', 0, 'C1E1032BC8B0018D????????????B9????????F3A55F5E5B', 10, 0))
};

--=============================================================================
-- Returns the table of current set BLU spells.
---@return table skillTable The current set BLU spells.
--=============================================================================
-- based on code from blusets by Atom0s
--=============================================================================
function GetBluskills()
    local skillTable = T{};

    local ptr = ashita.memory.read_uint32(AshitaCore:GetPointerManager():Get('inventory'));
    if (ptr == 0) then
        return T{ };
    end
    ptr = ashita.memory.read_uint32(ptr);
    if (ptr == 0) then
        return T{ };
    end
    --local spellTable = T(ashita.memory.read_array((ptr + blu.offset[0]) + (blu.is_blu_main() and 0x04 or 0xA0), 0x14));
    local spellTable = T(ashita.memory.read_array((ptr + blu.offset[0]) + 0x04, 0x14));

    for _,v in pairs(spellTable) do
        if skills[4][v+512] then
            skillTable:append(skills[4][v+512]);
        end
    end

    return skillTable;
end

--=============================================================================
---Return current aftermath level
---@return integer
--=============================================================================
local GetAftermathLevel = function()
    return GetBuffCount(statusID.AM1) + 2*GetBuffCount(statusID.AM2) + 3*GetBuffCount(statusID.AM3) + chains.forceAeonic;
end

--=============================================================================
---Return action property table with aeonic property added
---@param action table Action information
---@param actor integer Actor ID
---@return table propertyTable Updated property table
--=============================================================================
local GetAeonicProperty = function(action, actor)
    local propertyTable = table.copy(action.skillchain);

    if action.aeonic and (action.weapon or chains.forceAeonic > 0) and actor == playerID and GetAftermathLevel()>0 then
        local main = GetEquipment().Main;
        local range = GetEquipment().Range;
        local validMain = action.weapon == (main and main.Name) or chains.forceAeonic > 0;
        local validRange = action.weapon == (range and range.Name);
        if validMain or validRange then
            table.insert(propertyTable,1,action.aeonic);
        end
    end

    return propertyTable;
end

--=============================================================================
-- Return formatted table of valid skillchain options
---@param target number ServerID of target
---@return table chainTable Current skillchain options
--=============================================================================
local GetSkillchains = function(target)
    local actions = T{};
    local chainTable = T{};
    local levelTable = T{{},{},{},{}};

    local mainJob = GetPlayer().MainJob;
    local enableSCH = mainJob == 'SCH' and ((playerTable[playerID] and playerTable[playerID][statusID.IM]) or
                                            chains.forceImmanence);
    local enableBLU = mainJob == 'BLU' and ((playerTable[playerID] and playerTable[playerID][statusID.AL]) or
                                            (playerTable[playerID] and playerTable[playerID][statusID.CA]) or
                                            chains.forceAffinity);

    -- Create weaponskill table if it does not already exist
    -- Will update through incoming 0xAC packets
    if not actionTable.wepskill then
        actionTable.wepskill = GetWeaponskills();
    end

    -- Create petskill table if it does not already exist
    -- Will update through incoming 0xAC packets
    if T{ 'BST', 'SMN' }:contains(mainJob) and not actionTable.petskill then
            actionTable.petskill = GetPetskills();
    end

    -- Create bluskill table if it does not already exist
    -- Will update through incoming 0x44 packets
    if mainJob == 'BLU' and not actionTable.bluskill then
        actionTable.bluskill = GetBluskills();
    end

    -- Initialize actions with weaponskills
    if chains.settings.display.weapon then
        actions = actions:extend(actionTable.wepskill);
    end

    -- Add skill tables based on job and active buffs
    if chains.settings.display.pet and mainJob:any('BST','SMN') and actionTable.petskill then
        actions = actions:extend(actionTable.petskill);
    elseif chains.settings.display.spell and enableBLU and actionTable.bluskill then
        actions = actions:extend(actionTable.bluskill);
    elseif chains.settings.display.spell and enableSCH and actionTable.schskill then
        actions = actions:extend(actionTable.schskill);
    end

    -- Search for valid skillchains and store into a table per skillchain level
    -- iterate over current abilities
    for _,action in pairs(actions) do

        -- insert aeonic property
        local actionProperty = GetAeonicProperty(action,playerID);

        -- iterate over 1st property (target property)
        for _,prop1 in pairs(target.property) do
            local match = nil;

            -- iterate over 2nd property (action property) and exit after first match
            for _,prop2 in pairs(actionProperty) do
                match = chainInfo[prop1][prop2];
                if match then break end
            end

            -- store first match and exit
            if match then
                -- check for ultimate skillchain
                local checkAeonic = chainInfo[prop1].level == 3 and (target.step + GetAftermathLevel()) >= 4;
                if checkAeonic and chainInfo[prop1]['aeonic'] then
                    match = chainInfo[prop1]['aeonic'];
                end

                -- add skillchain information to table
                local skillchain = {
                    outText = ('%-17s>> Lv.%d'):fmt(action.en, match.level),
                    outName = ('%-17s'):fmt(action.en),
                    outLevel = ('>> Lv.%d'):fmt(match.level),
                    outProp = match.skillchain,
                }
                table.insert(levelTable[match.level],skillchain);
                break;
            end;
        end
    end

    -- Sort results to a single table based on skillchain level
    for x=4,1,-1 do
        for _,v in pairs(levelTable[x]) do
            table.insert(chainTable,v);
        end
    end

    return chainTable;
end

--=============================================================================
-- Reset stored skillchain lists for each active target
-- This would trigger on weapon, ability and pet changes
--=============================================================================
local function ResetSkillchains()
    for _,v in pairs(targetTable) do
        v.skillchains = nil;
    end
end

--=============================================================================
-- Return true if another player belongs to the player's alliance.
---@param id number ServerId
---@return boolean
--=============================================================================
local function isPlayerInAlliance(id)
    local pParty = AshitaCore:GetMemoryManager():GetParty();

    for i = 0, 17 do
        if pParty:GetMemberIsActive(i) == 1 and pParty:GetMemberServerId(i) == id then
            return true
        end
    end

    return false
end

--=============================================================================
-- Return true if a pet belongs to the player's alliance.
---@param id number ServerId
---@return boolean
--=============================================================================
local function isPetInAlliance(id)
    local pParty = AshitaCore:GetMemoryManager():GetParty();
    local pEntity = AshitaCore:GetMemoryManager():GetEntity();

    for i = 0, 17 do
        if pParty:GetMemberIsActive(i) == 1 then
            local playerIndex = pParty:GetMemberTargetIndex(i);
            local petIndex = pEntity:GetPetTargetIndex(playerIndex);
            if pEntity:GetServerId(petIndex) == id then
                return true;
            end
        end
    end

    return false
end

--=============================================================================
-- Print formatted error information
--=============================================================================
-- Copied from tHotBar by Thorny as part of ParseActionPacket
--=============================================================================
local function Error(text)
    local color = ('\30%c'):format(68);
    local highlighted = color .. string.gsub(text, '$H', '\30\01\30\02');
    highlighted = string.gsub(highlighted, '$R', '\30\01' .. color);
    print(chat.header(addon.name) .. highlighted .. '\30\01');
end

--=============================================================================
-- Return action packet data in a table format
---@param e table Incoming packet table
---@return table pendingActionPacket Parsed action packet table
--=============================================================================
-- Based on code from tHotBar by Thorny
-- https://github.com/Windower/Lua/blob/dev/addons/libs/packets/data.lua
-- https://github.com/Windower/Lua/blob/dev/addons/libs/packets/fields.lua
--=============================================================================
function ParseActionPacket(e)
    local bitData;
    local bitOffset;
    local maxLength = e.size * 8;

    local function UnpackBits(length)
        if ((bitOffset + length) > maxLength) then
            maxLength = 0; --Using this as a flag since any malformed fields mean the data is trash anyway.
            return 0;
        end
        local value = ashita.bits.unpack_be(bitData, 0, bitOffset, length);
        bitOffset = bitOffset + length;
        return value;
    end

    local pendingActionPacket = T{};
    bitData = e.data_raw;
    bitOffset = 40;

    pendingActionPacket.UserId = UnpackBits(32);
    local targetCount = UnpackBits(6);
    bitOffset = bitOffset + 4; --Unknown 4 bits
    pendingActionPacket.Type = UnpackBits(4);
    pendingActionPacket.Id = UnpackBits(32); --{unknown[15:0], param[15:0]}
    bitOffset = bitOffset + 32; --Unknown 32 bits --{recast[31:0]}?

    pendingActionPacket.Targets = T{};
    for i = 1,targetCount do
        local target = T{};
        target.Id = UnpackBits(32);
        local actionCount = UnpackBits(4);
        target.Actions = T{};
        for j = 1,actionCount do
            local action = {};
            action.Reaction = UnpackBits(5);
            action.Animation = UnpackBits(12);
            action.SpecialEffect = UnpackBits(7);
            action.Knockback = UnpackBits(3);
            action.Param = UnpackBits(17);
            action.Message = UnpackBits(10);
            action.Flags = UnpackBits(31);

            local hasAdditionalEffect = (UnpackBits(1) == 1);
            if hasAdditionalEffect then
                local additionalEffect = {};
                additionalEffect.Damage = UnpackBits(10); --{effect[3:0],animation[5:0]}
                additionalEffect.Param = UnpackBits(17);
                additionalEffect.Message = UnpackBits(10);
                action.AdditionalEffect = additionalEffect;
            end

            local hasSpikesEffect = (UnpackBits(1) == 1);
            if hasSpikesEffect then
                local spikesEffect = {};
                spikesEffect.Damage = UnpackBits(10); --{effect[3:0],animation[5:0]}
                spikesEffect.Param = UnpackBits(14);
                spikesEffect.Message = UnpackBits(10);
                action.SpikesEffect = spikesEffect;
            end

            target.Actions:append(action);
        end
        pendingActionPacket.Targets:append(target);
    end

    if (maxLength == 0) then
        Error(string.format('Malformed action packet detected.  Type:$H%u$R User:$H%u$R Targets:$H%u$R', pendingActionPacket.Type, pendingActionPacket.UserId, #pendingActionPacket.Targets));
        pendingActionPacket.Targets = T{}; --Blank targets so that it doesn't register bad info later.
    end

    return pendingActionPacket;

end

--=============================================================================
-- event: load
-- desc: Event called when the addon is being loaded.
--=============================================================================
ashita.events.register('load', 'load_cb', function ()
    playerID = AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0);
end);

--=============================================================================
-- event: unload
-- desc: Event called when the addon is being unloaded.
--=============================================================================
ashita.events.register('unload', 'unload_cb', function ()
    settings.save();
end);

--=============================================================================
-- event: packet_in
-- desc: Event called when the addon is processing incoming packets.
--=============================================================================
ashita.events.register('packet_in', 'packet_in_cb', function (e)
    --[[ Valid Arguments
        e.id                 - (ReadOnly) The id of the packet.
        e.size               - (ReadOnly) The size of the packet.
        e.data               - (ReadOnly) The data of the packet.
        e.data_raw           - The raw data pointer of the packet. (Use with FFI.)
        e.data_modified      - The modified data.
        e.data_modified_raw  - The modified raw data. (Use with FFI.)
        e.chunk_size         - The size of the full packet chunk that contained the packet.
        e.chunk_data         - The data of the full packet chunk that contained the packet.
        e.chunk_data_raw     - The raw data pointer of the full packet chunk that contained the packet. (Use with FFI.)
        e.injected           - (ReadOnly) Flag that states if the packet was injected by Ashita or an addon/plugin.
        e.blocked            - Flag that states if the packet has been, or should be, blocked.
    --]]

    -- Action
    --[[ actionPacket.Type
        [1] = 'Melee attack',
        [2] = 'Ranged attack finish',
        [3] = 'Weapon Skill finish',
        [4] = 'Casting finish',
        [5] = 'Item finish',
        [6] = 'Job Ability',
        [7] = 'Weapon Skill start',
        [8] = 'Casting start',
        [9] = 'Item start',
        [11] = 'NPC TP finish',
        [12] = 'Ranged attack start',
        [13] = 'Avatar TP finish',
        [14] = 'Job Ability DNC',
        [15] = 'Job Ability RUN',
    --]]
    if e.id == 0x28 then

        -- Save a little bit of processing for packets that won't relate to SC..
        local type = ashita.bits.unpack_be(e.data_raw, 82, 4); -- byte: 0xA, bit: 0x2
        if not T{ 3, 4, 6, 11, 13, 14 }:contains(type) then
            return;
        end

        local actionPacket = ParseActionPacket(e);

        -- Only the primary target and action are parsed assuming that is all that apply
        local actor = actionPacket.UserId;
        local target = actionPacket.Targets[1];

        -- exit if target is nil due to corrupted packet
        if not target then
            return;
        end

        local targetAction = target.Actions[1];

        -- Overload packet type for pet actions (?)
        -- Prevents Weapon Bash from matching as an actionSkill
        local category = PetMessageTypes:contains(targetAction.Message) and 13 or actionPacket.Type;

        -- capture valid action skill and added effect property if there is a match
        local actionSkill = skills[category] and skills[category][bit.band(actionPacket.Id,0xFFFF)];
        local effectProperty = targetAction.AdditionalEffect and SkillPropNames[bit.band(targetAction.AdditionalEffect.Damage,0x3F)];

        --debug ===============================================================
        if chains.debug and T{ 3, 6, 13, 14 }:contains(actionPacket.Type) then
            local out = ('Type: %s -> %s, Id: %s'):fmt(actionPacket.Type, category, actionPacket.Id);
            if actionSkill then
                out = out .. (' Skill: %s'):fmt(actionSkill.en);
            end
            print(chat.header('0x28'):append(chat.error(out)));
            if targetAction then
                out = ('Action Message: %s'):fmt(targetAction.Message);
                if targetAction.AdditionalEffect then
                    out = out .. (' Effect: %s'):fmt(targetAction.AdditionalEffect.Damage);
                end
                if effectProperty then
                    out = out .. (' Property: %s'):fmt(effectProperty);
                end
            end
            print(chat.header('0x28'):append(chat.error(out)));
        end
        --=====================================================================

        -- exit if actor is not in alliance
        if not (isPlayerInAlliance(actor) or isPetInAlliance(actor)) then
            return;
        end

        -- Check for valid action skill with valid added effect propery - after first setp
        if actionSkill and effectProperty then
            local step = (targetTable[target.Id] and targetTable[target.Id].step or 1) + 1
            local delay = actionSkill and actionSkill.delay or 3
            local level = chainInfo[effectProperty].level

            -- Check for Lv.3 -> Lv.3 and bump to Lv.4 for closure
            if level == 3 and targetTable[target.Id] and targetTable[target.Id].property[1] == effectProperty then
                level = 4;
            end
            local closed = level == 4;

            targetTable[target.Id] = {
                en=actionSkill.en,
                property={effectProperty},
                ts=os.time(),
                dur=8-step+delay,
                wait=delay,
                step=step,
                closed=closed,
            };

        -- Check for valid actor skill with valid message - generic first step (excluding chainbound)
        -- Include spells when SCH Immanence or BLU Azure Lore / Chain Affinity is active
        -- Immanence and Chain Affinity buff status cleared on use
        elseif actionSkill and MessageTypes:contains(targetAction.Message) and (actionPacket.Type ~= 4 or (playerTable[actor])) then
            local delay = actionSkill and actionSkill.delay or 3
            targetTable[target.Id] = {
                en=actionSkill.en,
                property=GetAeonicProperty(actionSkill,actor),
                ts=os.time(),
                dur=7+delay,
                wait=delay,
                step=1,
            };

        -- Check for valid actor skill with chainbound message - chainbound first step
        -- Could be combined with previous first setp check
        elseif actionSkill and (targetAction.Message == 529) then
            targetTable[target.Id] = {
                en=actionSkill.en,
                property=actionSkill.skillchain,
                ts=os.time(),
                dur=9,
                wait=2,
                step=1,
                bound=targetAction.Param,
            };
        end

        -- Clear out used spell abilities
        if actionSkill and actionPacket.Type == 4 and playerTable[actor] then
            local buffID = playerTable[actor][statusID.CA] and statusID.CA or playerTable[actor][statusID.IM] and statusID.IM;
            if buffID then
                playerTable[actor][buffID] = nil;
            end
        end

        -- Capture buff information for each player
        if actionPacket.Type == 6 and ChainBuffTypes:containskey(targetAction.Param) then
            playerTable[actor] = playerTable[actor] or {};
            playerTable[actor][targetAction.Param] = os.time() + ChainBuffTypes[targetAction.Param].duration;
        end

    -- Action Message - Clear buff when getting '206 - ${target}'s ${status} effect wears off'.
    --  only works to clear local player
    elseif e.id == 0x29 and struct.unpack('H', e.data, 0x18+1) == 206 and struct.unpack('I', e.data, 8+1) == playerID then
        local effect = struct.unpack('H', e.data, 0xC+1)
        if playerTable[playerID] and playerTable[playerID][effect] then
            playerTable[playerID][effect] = nil;
        end

    -- Character Abilities (Weaponskills and BST/SMN PetSkills)
    elseif e.id == 0x0AC then --and e.data:sub(5) ~= actionTable.lastAC then
        actionTable.wepskill = T{};
        actionTable.petskill = T{};

        -- Packet contains one bit per ability to indicate if the ability is available
        -- * Byte in packet = floor(abilityID / 8) + 1
        -- * Bit in byte = abilityID % 8
        -- Logic does the following:
        -- * extract byte
        -- * shift bits right to move relavent bit to bit[0]
        -- * mask upper bits and compare to 1 (or >0)
        -- * alt equation: bit.band(bit.rshift(data:byte(math.floor(k/8)+1),(k%8)),0x01) == 1

        -- Weaponskills
        local data = e.data:sub(5);
        for k,v in pairs(skills[3]) do
            if math.floor((data:byte(math.floor(k/8)+1)%2^(k%8+1))/2^(k%8)) == 1 then
                table.insert(actionTable.wepskill, v);
            end
        end

        -- BST/SMN PetSkills - fix: skip if not BST or SMN?
        data = e.data:sub(69);
        for k,v in pairs(skills.playerPet) do
            if math.floor((data:byte(math.floor(k/8)+1)%2^(k%8+1))/2^(k%8)) == 1 then
                table.insert(actionTable.petskill, v);
            end
        end

        -- Reset skillchains on all active targets
        ResetSkillchains();

        --actionTable.lastAC = e.data:sub(5); --dedupe?

    -- BLU spells - e.data:byte(5) == 0x10 indicates BLU, e.data:byte(6) == 0 indicates main job
    elseif e.id == 0x44 and e.data:byte(5) == 0x10 and e.data:byte(6) == 0 then -- and e.data:sub(9, 18) ~= actionTable.last44 then
        actionTable.bluskill = T{};

        --Iterate through bytes 8+1 through 27+1 - corresponds to the 20 BLU spell slots
        for x = 8+1, 27+1 do
            local match = skills[4][e.data:byte(x)+512]
            if match then
                table.insert(actionTable.bluskill, match);
            end
        end

        --actionTable.last44 = e.data:sub(9, 18); --dedupe?
    end

end);

--=============================================================================
-- event: d3d_present
-- desc: Event called when the Direct3D device is presenting a scene.
--=============================================================================
ashita.events.register('d3d_present', 'present_cb', function ()

    -- Capture current time for comparison
    local now = os.time();

    -- Remove stale playerTable entries
    for pk,pv in pairs(playerTable) do
        for bk,bv in pairs(playerTable[pk]) do
            if now > bv then
                playerTable[pk][bk] = nil;
            end
        end
        if table.length(pv) == 0 then
            playerTable[pk] = nil;
        end
    end

    -- Remove stale targetTable entries
    for k,v in pairs(targetTable) do
        if v.ts and now-v.ts > v.dur then
            targetTable[k] = nil;
        end
    end

    -- UI
    local targetId = AshitaCore:GetMemoryManager():GetTarget():GetServerId(0);
    local render = targetId ~= nil and targetTable[targetId] and targetTable[targetId].dur-(now-targetTable[targetId].ts) > 0;

    local configOpen = chains.config.open[1];

    if render or chains.visible or chains.position or configOpen then

        local op = chains.settings.opacity;

        local flags = bit.bor(
            ImGuiWindowFlags_NoDecoration,
            ImGuiWindowFlags_AlwaysAutoResize,
            ImGuiWindowFlags_NoSavedSettings,
            ImGuiWindowFlags_NoFocusOnAppearing,
            ImGuiWindowFlags_NoNav)

        local useMenu = chains.settings.bg_style == 'menu' and not chains.menuFailed;
        imgui.SetNextWindowBgAlpha(useMenu and 0.0 or op.background)
        imgui.SetNextWindowSize({ 350 * chains.settings.font_scale * math.max(1.0, chains.settings.line_scale), -1 }, ImGuiCond_Always)

        -- keep a minimum height so the large countdown number always fits
        local minHeight = imgui.GetFontSize() * chains.settings.font_scale * chains.settings.countdown.scale + 16;
        imgui.SetNextWindowSizeConstraints({ -1, minHeight }, { FLT_MAX, FLT_MAX })

        if chains.position then
            imgui.SetNextWindowPos({ chains.position.x, chains.position.y }, ImGuiCond_Always, { 0, 0 });
        else
            imgui.SetNextWindowPos({ chains.settings.position_x, chains.settings.position_y }, ImGuiCond_Appearing, { 0, 0 });
        end

        -- border and default text opacity
        imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 1.0);
        local bc, bg = chains.settings.border_color, chains.settings.bg_color;
        imgui.PushStyleColor(ImGuiCol_WindowBg, { bg[1], bg[2], bg[3], useMenu and 0.0 or op.background });
        imgui.PushStyleColor(ImGuiCol_Border, { bc[1], bc[2], bc[3], op.border });
        imgui.PushStyleColor(ImGuiCol_Text, { 1.0, 1.0, 1.0, op.text });
        imgui.PushStyleColor(ImGuiCol_Separator, { bc[1], bc[2], bc[3], op.border });

        if (imgui.Begin('chains', true, flags)) then

            if useMenu then
                DrawMenuBackground();
            end

            if render then
                imgui.SetWindowFontScale(chains.settings.font_scale)

                local target = targetTable[targetId];
                local timediff = now-target.ts;
                local timer = target.dur-timediff;
                local cd = chains.settings.countdown;
                local fs = chains.settings.font_scale;

                -- Watermark countdown (red while waiting) with burst icons to its right on step 2+
                local waiting = (not target.closed) and timediff < target.wait;
                local c = waiting and cd.wait_color or cd.color;
                local bursts = target.step > 1 and target.property[1] and chainInfo[target.property[1]]
                               and chainInfo[target.property[1]].burst or nil;
                DrawCountdown(('%d'):fmt(waiting and (target.wait-timediff) or timer),
                              { c[1], c[2], c[3], cd.opacity }, bursts);

                -- Available skillchains
                if not target.closed then
                    local skillchains = GetSkillchains(target);
                    local wc = chains.settings.ws_color;
                    local wsColor = { wc[1], wc[2], wc[3], op.text };
                    local spacing = imgui.GetStyle().ItemSpacing;

                    imgui.SetWindowFontScale(fs * chains.settings.line_scale);
                    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { spacing.x, math.max(0, spacing.y + chains.settings.line_spacing) });
                    for _,v in pairs(skillchains) do
                        DrawText(v.outName, wsColor, chains.settings.list_outline);
                        imgui.SameLine(0,0);
                        DrawText(v.outLevel, { 1.0, 1.0, 1.0, op.text }, chains.settings.list_outline);
                        imgui.SameLine();
                        DrawText(v.outProp, GetPropertyColor(v.outProp), chains.settings.list_outline);
                    end
                    imgui.PopStyleVar(1);
                    imgui.SetWindowFontScale(fs);
                end
            elseif chains.visible or configOpen then
                imgui.SetWindowFontScale(chains.settings.font_scale)
                if configOpen then
                    local pc = chains.settings.countdown.color;
                    DrawCountdown('7', { pc[1], pc[2], pc[3], chains.settings.countdown.opacity }, { 'Earth', 'Dark' });
                end
                imgui.Text('');
                imgui.Text('                 --- Chains ---                 ');
                if configOpen and not chains.visible then
                    imgui.Text('        Preview - adjust options in Config       ');
                else
                    imgui.Text('         Click and drag to move display         ');
                end
                imgui.Text('');
            end

            if chains.position then
                chains.position = nil;
            end

            -- store current window position
            chains.settings.position_x, chains.settings.position_y = imgui.GetWindowPos();
        end
        imgui.End();
        imgui.PopStyleColor(4);
        imgui.PopStyleVar(1);
    end

    -- Config window
    if configOpen then
        imgui.SetNextWindowSize({ 320, 0 }, ImGuiCond_FirstUseEver);
        if imgui.Begin('Chains Config', chains.config.open, ImGuiWindowFlags_AlwaysAutoResize) then
            local cfg = chains.config;
            local changed = false;

            imgui.Text('Opacity');
            imgui.Separator();
            if imgui.SliderFloat('Background', cfg.background, 0.0, 1.0, '%.2f') then
                chains.settings.opacity.background = cfg.background[1]; changed = true;
            end
            if imgui.SliderFloat('Border', cfg.border, 0.0, 1.0, '%.2f') then
                chains.settings.opacity.border = cfg.border[1]; changed = true;
            end
            if imgui.SliderFloat('Text', cfg.text, 0.1, 1.0, '%.2f') then
                chains.settings.opacity.text = cfg.text[1]; changed = true;
            end

            imgui.Spacing();
            imgui.Text('Background');
            imgui.Separator();
            if imgui.RadioButton('Solid', chains.settings.bg_style == 'solid') then
                chains.settings.bg_style = 'solid'; changed = true;
            end
            imgui.SameLine();
            if imgui.RadioButton('FFXI menu', chains.settings.bg_style == 'menu') then
                chains.settings.bg_style = 'menu'; chains.menuFailed = nil; changed = true;
            end
            if chains.settings.bg_style == 'menu' then
                if imgui.ColorEdit3('Menu top##bg', cfg.menu_top) then
                    chains.settings.menu_top = { cfg.menu_top[1], cfg.menu_top[2], cfg.menu_top[3] }; changed = true;
                end
                if imgui.ColorEdit3('Menu bottom##bg', cfg.menu_bottom) then
                    chains.settings.menu_bottom = { cfg.menu_bottom[1], cfg.menu_bottom[2], cfg.menu_bottom[3] }; changed = true;
                end
                if imgui.SliderFloat('Scanlines##bg', cfg.scanlines, 0.0, 1.0, '%.2f') then
                    chains.settings.scanlines = cfg.scanlines[1]; changed = true;
                end
            else
                if imgui.ColorEdit3('Color##bg', cfg.bg_color) then
                    chains.settings.bg_color = { cfg.bg_color[1], cfg.bg_color[2], cfg.bg_color[3] }; changed = true;
                end
            end
            if imgui.ColorEdit3('Border color##bg', cfg.border_color) then
                chains.settings.border_color = { cfg.border_color[1], cfg.border_color[2], cfg.border_color[3] }; changed = true;
            end

            imgui.Spacing();
            imgui.Text('Countdown number');
            imgui.Separator();
            if imgui.SliderFloat('Size##cd', cfg.cd_scale, 1.0, 6.0, '%.1f') then
                chains.settings.countdown.scale = cfg.cd_scale[1]; changed = true;
            end
            if imgui.ColorEdit3('Color##cd', cfg.cd_color) then
                chains.settings.countdown.color = { cfg.cd_color[1], cfg.cd_color[2], cfg.cd_color[3] }; changed = true;
            end
            if imgui.ColorEdit3('Wait color##cd', cfg.cd_wait) then
                chains.settings.countdown.wait_color = { cfg.cd_wait[1], cfg.cd_wait[2], cfg.cd_wait[3] }; changed = true;
            end
            if imgui.SliderFloat('Opacity##cd', cfg.cd_opacity, 0.05, 1.0, '%.2f') then
                chains.settings.countdown.opacity = cfg.cd_opacity[1]; changed = true;
            end
            if OutlineControls('cd', chains.settings.outline,
                { enabled = cfg.ol_enabled, thickness = cfg.ol_thickness, color = cfg.ol_color, opacity = cfg.ol_opacity }) then
                changed = true;
            end

            imgui.Spacing();
            imgui.Text('Burst icons');
            imgui.Separator();
            if imgui.SliderFloat('Icon size (x countdown)', cfg.icon_scale, 0.3, 2.0, '%.2f') then
                chains.settings.icon_scale = cfg.icon_scale[1]; changed = true;
            end

            imgui.Spacing();
            imgui.Text('Chain list');
            imgui.Separator();
            if imgui.ColorEdit3('Weapon skill name##ws', cfg.ws_color) then
                chains.settings.ws_color = { cfg.ws_color[1], cfg.ws_color[2], cfg.ws_color[3] }; changed = true;
            end
            if imgui.SliderFloat('Text size##ln', cfg.line_scale, 0.5, 2.5, '%.2f') then
                chains.settings.line_scale = cfg.line_scale[1]; changed = true;
            end
            if imgui.SliderFloat('Line spacing##ln', cfg.line_spacing, 0.0, 20.0, '%.0f px') then
                chains.settings.line_spacing = cfg.line_spacing[1]; changed = true;
            end
            if OutlineControls('ls', chains.settings.list_outline,
                { enabled = cfg.lo_enabled, thickness = cfg.lo_thickness, color = cfg.lo_color, opacity = cfg.lo_opacity }) then
                changed = true;
            end

            imgui.Spacing();
            imgui.Text('Display');
            imgui.Separator();
            if imgui.SliderFloat('Font scale', cfg.scale, 0.5, 2.0, '%.2f') then
                chains.settings.font_scale = cfg.scale[1]; changed = true;
            end

            imgui.Spacing();
            if imgui.Button('Reset all') then
                local d = default_settings;
                for k,v in pairs(d.opacity) do chains.settings.opacity[k] = v; end
                chains.settings.icon_scale = d.icon_scale;
                chains.settings.line_scale = d.line_scale;
                chains.settings.line_spacing = d.line_spacing;
                chains.settings.ws_color = { d.ws_color[1], d.ws_color[2], d.ws_color[3] };
                chains.settings.show_burst_names = d.show_burst_names;
                chains.settings.bg_style = d.bg_style;
                chains.settings.bg_color = { d.bg_color[1], d.bg_color[2], d.bg_color[3] };
                chains.settings.menu_top = { d.menu_top[1], d.menu_top[2], d.menu_top[3] };
                chains.settings.menu_bottom = { d.menu_bottom[1], d.menu_bottom[2], d.menu_bottom[3] };
                chains.settings.border_color = { d.border_color[1], d.border_color[2], d.border_color[3] };
                chains.settings.scanlines = d.scanlines;
                chains.settings.list_outline = T{
                    enabled = d.list_outline.enabled, thickness = d.list_outline.thickness, opacity = d.list_outline.opacity,
                    color = { d.list_outline.color[1], d.list_outline.color[2], d.list_outline.color[3] },
                };
                chains.settings.outline = T{
                    enabled = d.outline.enabled, thickness = d.outline.thickness, opacity = d.outline.opacity,
                    color = { d.outline.color[1], d.outline.color[2], d.outline.color[3] },
                };
                chains.settings.countdown = T{
                    scale = d.countdown.scale, opacity = d.countdown.opacity,
                    color = { d.countdown.color[1], d.countdown.color[2], d.countdown.color[3] },
                    wait_color = { d.countdown.wait_color[1], d.countdown.wait_color[2], d.countdown.wait_color[3] },
                };
                SyncConfig();
                changed = true;
            end
            imgui.SameLine();
            if imgui.Button('Close') then
                cfg.open[1] = false;
            end

            if changed then
                settings.save();
            end
        end
        imgui.End();
    end

end);

--=============================================================================
-- event: command
-- desc: Event called when the addon is processing a command.
--=============================================================================
ashita.events.register('command', 'command_cb', function (e)
    --[[ Valid Arguments
        e.mode       - (ReadOnly) The mode of the command.
        e.command    - (ReadOnly) The raw command string.
        e.injected   - (ReadOnly) Flag that states if the command was injected by Ashita or an addon/plugin.
        e.blocked    - Flag that states if the command has been, or should be, blocked.
    --]]

    -- Parse the command arguments..
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/chains')) then
        return;
    end

    -- Block all related commands..
    e.blocked = true;

    --========================================================================
    -- Debug
    --========================================================================
    if (#args == 2) and (args[2] == 'debug') then
        chains.debug = not chains.debug;
        print(chat.header(addon.name):append(chat.message('%s: %s'):fmt(args[2], chains.debug and 'on' or 'off')));
    end

    --========================================================================
    -- Settings
    --========================================================================
    if (#args == 2) and chains.settings.display:containskey(args[2]) then
        chains.settings.display[args[2]] = not chains.settings.display[args[2]];
        local outText = '%sskill: %s'
        if args[2] == 'color' then
            outText = '%s: %s'
        end
        print(chat.header(addon.name):append(chat.message(outText):fmt(args[2], chains.settings.display[args[2]] and 'on' or 'off')));
    end

    --========================================================================
    -- Window management
    --========================================================================
    if (#args == 2) and (args[2] == 'config') then
        chains.config.open[1] = not chains.config.open[1];
    end

    if (#args == 2) and (args[2] == 'visible') then 
        chains.visible = not chains.visible;
    end

    if (#args == 3) and (args[2] == 'scale') then
        chains.settings.font_scale = args[3]:number();
        print(chat.header(addon.name):append(chat.message('Font scale set to %s'):fmt(chains.settings.font_scale)));
    end

    if (#args == 4) and (args[2] == 'move') then
        chains.position = {
            x = args[3]:number(),
            y = args[4]:number(),
        };
        print(chat.header(addon.name):append(chat.message('Window position set to x: %s, y: %s'):fmt(chains.position.x, chains.position.y)));
    end

end);