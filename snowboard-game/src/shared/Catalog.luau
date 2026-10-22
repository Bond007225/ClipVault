--!strict
-- Every cosmetic and snowboard the shop sells. Items with Price = 0 are owned by
-- everyone from the start. `Style` picks the procedural builder in Cosmetics.

export type Slot = "Hat" | "Glasses" | "Scarf" | "Jacket" | "Shirt" | "Gloves" | "Pants" | "Boots" | "Board"

export type BoardStats = {
	Speed: number,
	Turn: number,
	Pop: number,
}

export type Item = {
	Id: string,
	Name: string,
	Slot: Slot,
	Price: number,
	Style: string,
	Color: Color3,
	Accent: Color3,
	Material: Enum.Material?,
	Stats: BoardStats?,
}

local Catalog = {}

Catalog.Slots = { "Hat", "Glasses", "Scarf", "Jacket", "Shirt", "Gloves", "Pants", "Boots", "Board" } :: { Slot }

Catalog.SlotLabels = {
	Hat = "Hats",
	Glasses = "Glasses",
	Scarf = "Scarves",
	Jacket = "Jackets",
	Shirt = "Long Sleeves",
	Gloves = "Gloves",
	Pants = "Pants",
	Boots = "Boots",
	Board = "Snowboards",
} :: { [string]: string }

local rgb = Color3.fromRGB

local items: { Item } = {
	-- Hats
	{ Id = "hat_beanie_red", Name = "Classic Beanie", Slot = "Hat", Price = 0, Style = "Beanie", Color = rgb(196, 40, 40), Accent = rgb(240, 240, 240) },
	{ Id = "hat_pom_blue", Name = "Pom-Pom Beanie", Slot = "Hat", Price = 150, Style = "PomBeanie", Color = rgb(40, 90, 200), Accent = rgb(255, 255, 255) },
	{ Id = "hat_pom_pink", Name = "Bubblegum Pom", Slot = "Hat", Price = 200, Style = "PomBeanie", Color = rgb(255, 120, 190), Accent = rgb(255, 230, 250) },
	{ Id = "hat_trapper", Name = "Trapper Hat", Slot = "Hat", Price = 300, Style = "Trapper", Color = rgb(110, 70, 40), Accent = rgb(235, 225, 210) },
	{ Id = "hat_cap", Name = "Park Cap", Slot = "Hat", Price = 120, Style = "Cap", Color = rgb(30, 30, 30), Accent = rgb(255, 200, 0) },
	{ Id = "hat_helmet", Name = "Pro Helmet", Slot = "Hat", Price = 450, Style = "Helmet", Color = rgb(245, 245, 245), Accent = rgb(220, 30, 30), Material = Enum.Material.SmoothPlastic },
	{ Id = "hat_helmet_gold", Name = "Gold Medal Helmet", Slot = "Hat", Price = 2500, Style = "Helmet", Color = rgb(230, 180, 40), Accent = rgb(255, 255, 255), Material = Enum.Material.Foil },

	-- Glasses
	{ Id = "gl_shades", Name = "Aviator Shades", Slot = "Glasses", Price = 100, Style = "Shades", Color = rgb(20, 20, 20), Accent = rgb(200, 170, 60) },
	{ Id = "gl_round", Name = "Round Specs", Slot = "Glasses", Price = 80, Style = "Round", Color = rgb(150, 220, 255), Accent = rgb(60, 40, 30) },
	{ Id = "gl_goggles", Name = "Mirror Goggles", Slot = "Glasses", Price = 250, Style = "Goggles", Color = rgb(80, 160, 255), Accent = rgb(25, 25, 25) },
	{ Id = "gl_goggles_fire", Name = "Fire Goggles", Slot = "Glasses", Price = 450, Style = "Goggles", Color = rgb(255, 110, 20), Accent = rgb(255, 255, 255) },
	{ Id = "gl_goggles_rainbow", Name = "Rainbow Goggles", Slot = "Glasses", Price = 900, Style = "Goggles", Color = rgb(190, 80, 255), Accent = rgb(60, 255, 180), Material = Enum.Material.Neon },

	-- Scarves
	{ Id = "sc_wool", Name = "Wool Scarf", Slot = "Scarf", Price = 60, Style = "Wool", Color = rgb(200, 30, 50), Accent = rgb(200, 30, 50) },
	{ Id = "sc_striped", Name = "Candy Stripe Scarf", Slot = "Scarf", Price = 140, Style = "Striped", Color = rgb(230, 40, 40), Accent = rgb(255, 255, 255) },
	{ Id = "sc_long", Name = "Long Flowing Scarf", Slot = "Scarf", Price = 260, Style = "Long", Color = rgb(40, 140, 90), Accent = rgb(250, 220, 90) },
	{ Id = "sc_gaiter", Name = "Neck Gaiter", Slot = "Scarf", Price = 200, Style = "Gaiter", Color = rgb(40, 40, 50), Accent = rgb(0, 200, 255) },

	-- Jackets
	{ Id = "jk_puffer_blue", Name = "Puffer Jacket", Slot = "Jacket", Price = 0, Style = "Puffer", Color = rgb(40, 110, 210), Accent = rgb(20, 50, 110) },
	{ Id = "jk_puffer_orange", Name = "Safety Puffer", Slot = "Jacket", Price = 300, Style = "Puffer", Color = rgb(255, 120, 20), Accent = rgb(40, 40, 40) },
	{ Id = "jk_shell_green", Name = "Backcountry Shell", Slot = "Jacket", Price = 450, Style = "Shell", Color = rgb(60, 130, 70), Accent = rgb(230, 230, 230) },
	{ Id = "jk_shell_purple", Name = "Night Shell", Slot = "Jacket", Price = 500, Style = "Shell", Color = rgb(70, 40, 120), Accent = rgb(255, 210, 60) },
	{ Id = "jk_neon", Name = "Neon Pro Jacket", Slot = "Jacket", Price = 1200, Style = "Neon", Color = rgb(25, 25, 30), Accent = rgb(0, 255, 160) },
	{ Id = "jk_team", Name = "Olympic Team Jacket", Slot = "Jacket", Price = 3000, Style = "Shell", Color = rgb(255, 255, 255), Accent = rgb(200, 20, 40) },

	-- Long sleeve shirts
	{ Id = "sh_thermal", Name = "Thermal Long Sleeve", Slot = "Shirt", Price = 0, Style = "Plain", Color = rgb(150, 150, 155), Accent = rgb(150, 150, 155) },
	{ Id = "sh_flannel", Name = "Red Flannel", Slot = "Shirt", Price = 120, Style = "Flannel", Color = rgb(170, 30, 35), Accent = rgb(30, 30, 30) },
	{ Id = "sh_fleece", Name = "Cozy Fleece", Slot = "Shirt", Price = 180, Style = "Plain", Color = rgb(240, 230, 210), Accent = rgb(240, 230, 210), Material = Enum.Material.Fabric },
	{ Id = "sh_raglan", Name = "Raglan Tee", Slot = "Shirt", Price = 150, Style = "Raglan", Color = rgb(245, 245, 245), Accent = rgb(30, 60, 140) },

	-- Gloves
	{ Id = "gv_mittens", Name = "Wool Mittens", Slot = "Gloves", Price = 0, Style = "Mitten", Color = rgb(60, 60, 70), Accent = rgb(60, 60, 70) },
	{ Id = "gv_pro", Name = "Pro Gloves", Slot = "Gloves", Price = 150, Style = "Glove", Color = rgb(20, 20, 20), Accent = rgb(220, 30, 30) },
	{ Id = "gv_neon", Name = "Neon Gloves", Slot = "Gloves", Price = 400, Style = "Glove", Color = rgb(0, 255, 140), Accent = rgb(0, 0, 0), Material = Enum.Material.Neon },
	{ Id = "gv_yellow", Name = "Work Mitts", Slot = "Gloves", Price = 90, Style = "Mitten", Color = rgb(240, 200, 40), Accent = rgb(240, 200, 40) },

	-- Pants
	{ Id = "pt_snow_black", Name = "Snow Pants", Slot = "Pants", Price = 0, Style = "Plain", Color = rgb(35, 35, 40), Accent = rgb(35, 35, 40) },
	{ Id = "pt_cargo", Name = "Cargo Pants", Slot = "Pants", Price = 200, Style = "Cargo", Color = rgb(120, 110, 70), Accent = rgb(90, 80, 50) },
	{ Id = "pt_bibs_red", Name = "Red Bibs", Slot = "Pants", Price = 350, Style = "Bib", Color = rgb(190, 30, 30), Accent = rgb(30, 30, 30) },
	{ Id = "pt_bibs_white", Name = "Whiteout Bibs", Slot = "Pants", Price = 600, Style = "Bib", Color = rgb(240, 240, 245), Accent = rgb(80, 160, 255) },

	-- Boots
	{ Id = "bt_basic", Name = "Basic Boots", Slot = "Boots", Price = 0, Style = "Plain", Color = rgb(70, 50, 35), Accent = rgb(70, 50, 35) },
	{ Id = "bt_pro", Name = "Pro Boots", Slot = "Boots", Price = 250, Style = "Pro", Color = rgb(25, 25, 25), Accent = rgb(255, 80, 0) },
	{ Id = "bt_moon", Name = "Moon Boots", Slot = "Boots", Price = 500, Style = "Moon", Color = rgb(240, 240, 255), Accent = rgb(170, 170, 200) },

	-- Snowboards
	{ Id = "bd_rookie", Name = "Rookie Board", Slot = "Board", Price = 0, Style = "Board", Color = rgb(60, 140, 230), Accent = rgb(255, 255, 255), Stats = { Speed = 1, Turn = 1, Pop = 1 } },
	{ Id = "bd_carver", Name = "Carver", Slot = "Board", Price = 600, Style = "Board", Color = rgb(30, 30, 35), Accent = rgb(255, 60, 60), Stats = { Speed = 1.08, Turn = 0.95, Pop = 1 } },
	{ Id = "bd_parkrat", Name = "Park Rat", Slot = "Board", Price = 800, Style = "Board", Color = rgb(120, 220, 60), Accent = rgb(255, 0, 200), Stats = { Speed = 0.95, Turn = 1.15, Pop = 1.12 } },
	{ Id = "bd_racer", Name = "Alpine Racer", Slot = "Board", Price = 1500, Style = "Board", Color = rgb(250, 200, 20), Accent = rgb(20, 20, 20), Stats = { Speed = 1.15, Turn = 0.9, Pop = 1 } },
	{ Id = "bd_aurora", Name = "Aurora", Slot = "Board", Price = 3000, Style = "GlowBoard", Color = rgb(20, 20, 60), Accent = rgb(0, 255, 200), Stats = { Speed = 1.1, Turn = 1.08, Pop = 1.1 } },
	{ Id = "bd_gold", Name = "Olympic Gold", Slot = "Board", Price = 6000, Style = "GlowBoard", Color = rgb(230, 180, 40), Accent = rgb(255, 255, 255), Material = Enum.Material.Foil, Stats = { Speed = 1.14, Turn = 1.12, Pop = 1.15 } },
}

Catalog.Items = items

local byId: { [string]: Item } = {}
for _, item in items do
	assert(byId[item.Id] == nil, "Duplicate catalog id " .. item.Id)
	byId[item.Id] = item
end

-- What a brand-new player wears.
Catalog.DefaultEquipped = {
	Jacket = "jk_puffer_blue",
	Shirt = "sh_thermal",
	Gloves = "gv_mittens",
	Pants = "pt_snow_black",
	Boots = "bt_basic",
	Board = "bd_rookie",
	Hat = "hat_beanie_red",
} :: { [string]: string }

Catalog.DefaultBoard = "bd_rookie"

function Catalog.get(id: string): Item?
	return byId[id]
end

function Catalog.isSlot(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	for _, s in Catalog.Slots do
		if s == value then
			return true
		end
	end
	return false
end

function Catalog.boardStats(id: string?): BoardStats
	local item = if id then byId[id] else nil
	if item and item.Stats then
		return item.Stats
	end
	return { Speed = 1, Turn = 1, Pop = 1 }
end

return Catalog
