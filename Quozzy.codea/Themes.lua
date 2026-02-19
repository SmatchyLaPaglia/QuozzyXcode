-- spring/summer/autumn/winter palettes 
local SeasonPalettes = {
    Spring = {
        bg    = color(198, 227, 198),
        gridBg        = color(220, 245, 230, 255),
        tileFill  = color(235, 255, 245, 255),
        tileStroke= color(120, 190, 150, 255),
        tileText  = color(40, 100, 70, 255),
        selectLineAlsoWeirdlyTileHighlight= color(140, 200, 160, 255),
        uiAccent  = color(140, 200, 160, 255),
        uiAccent2 = color(220, 168, 160),
        invalid   = color(220, 80, 80, 255),
        valid     = color(70, 150, 90, 255),
        panelBG   = color(226, 234, 228, 230),
        panelDim  = color(0, 0, 0, 90),
    },
    
    Summer = {
        -- overall background: warm, light, a little “sun-bleached”
        bg     = color(252, 237, 212, 255),   -- warmer + brighter golden
        gridBg = color(255, 252, 243, 255),
        -- tiles: bright warm-white with a *teal* stroke so it doesn’t feel wintry navy
        tileFill  = color(255, 253, 246, 255),   -- bright warm-white (sunlit)
        tileStroke= color(0, 160, 150, 255),     -- turquoise / pool-water edge
        
        -- text: deep sea-green; still very readable on light tiles
        tileText  = color(20, 85, 80, 255),
        
        -- selection / highlight: sunflower-orange; distinct from Spring’s mint and Autumn’s amber
        selectLineAlsoWeirdlyTileHighlight = color(255, 190, 80, 255),
        
        -- UI accents: tropical teal + coral
        uiAccent  = color(0, 175, 160, 255),     -- teal button / highlight
        uiAccent2 = color(255, 125, 110, 255),   -- coral secondary accent
        
        -- status colors (keep roughly in family with other seasons)
        invalid   = color(230, 70, 70, 255),     -- warm red
        valid     = color(70, 155, 95, 255),     -- grassy green
        
        -- panel: slightly warm white; same dim overlay as others
        panelBG   = color(247, 247, 246, 235),
        panelDim  = color(0, 0, 0, 90),
    },
    
    Autumn = {
        bg     = color(217, 193, 160),   -- more muted brown-orange
        gridBg = color(250, 235, 220, 255),
        tileFill  = color(255, 245, 225, 255),
        tileStroke= color(170, 110, 60, 255),
        tileText  = color(80, 45, 20, 255),
        selectLineAlsoWeirdlyTileHighlight= color(210, 120, 60, 255),
        uiAccent  = color(210, 140, 70, 255),
        uiAccent2 = color(180, 80, 90, 255),
        invalid   = color(200, 60, 60, 255),
        valid     = color(80, 130, 60, 255),
        panelBG   = color(255, 250, 240, 235),
        panelDim  = color(0, 0, 0, 100),
    },
    
    Winter = {
        bg        = color(215, 229, 244, 255),   -- slightly deeper ice-blue
        gridBg    = color(238, 246, 255, 255),   -- lighter, closer to white-blue
        tileFill  = color(245, 250, 255, 255),
        tileStroke= color(110, 140, 180, 255),
        tileText  = color(30, 50, 90, 255),
        selectLineAlsoWeirdlyTileHighlight= color(104, 202, 210),
        uiAccent  = color(104, 202, 210),
        uiAccent2 = color(200, 170, 230, 255),
        invalid   = color(210, 70, 70, 255),
        valid     = color(70, 150, 110, 255),
        panelBG   = color(243, 244, 245, 235),
        panelDim  = color(0, 0, 0, 110),
    },
}

Color = {}  -- will be populated from the active season

seasons     = { "Spring", "Summer", "Autumn", "Winter" } -- you can append more later
seasonIndex = 1
SEASON_KEY  = "SeasonIndex"

function buildEffectivePaletteForSeason(idx)
    local name = seasons[idx]
    local base = SeasonPalettes[name]
    local result = {}
    
    for k, v in pairs(base) do
        result[k] = color(v.r, v.g, v.b, v.a)
    end
    
    -- same darkening logic you already use
    if result.tileFill then
        local tf = result.tileFill
        local f  = 0.7
        result.tileFill = color(tf.r * f, tf.g * f, tf.b * f, tf.a)
    end
    if result.tileStroke then
        local ts = result.tileStroke
        local f  = 0.8
        result.tileStroke = color(ts.r * f, ts.g * f, ts.b * f, ts.a)
    end
    
    result.tileLetter = color(245, 250, 255, 255)
    result.tileLetterHighlight = color(255, 255, 180, 255)
    
    return result
end

function applySeasonPalette()
    local palette = buildEffectivePaletteForSeason(seasonIndex)
    for k, v in pairs(palette) do
        Color[k] = v
    end
    
    -- rebuild rounded overlay sprites for this season
    rebuildOverlayPanelsForSeason()
end

function applyStartingSeason()
    local idx = readProjectData(SEASON_KEY)
    if type(idx) == "number" then
        idx = math.floor(idx)
        if idx < 1 or idx > #seasons then
            idx = 1
        end
        seasonIndex = idx
    end
    applySeasonPalette()
end