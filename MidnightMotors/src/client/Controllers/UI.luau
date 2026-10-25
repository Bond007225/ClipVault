--!strict
-- Tiny UI helpers shared by the HUD and garage screens.

local UI = {}

UI.Colors = {
	Bg = Color3.fromRGB(14, 14, 20),
	Panel = Color3.fromRGB(24, 24, 34),
	Accent = Color3.fromRGB(0, 190, 255),
	Pink = Color3.fromRGB(255, 60, 200),
	Text = Color3.fromRGB(240, 240, 245),
	Dim = Color3.fromRGB(150, 150, 165),
	Good = Color3.fromRGB(60, 230, 120),
	Warn = Color3.fromRGB(255, 190, 40),
	Bad = Color3.fromRGB(255, 60, 60),
}

function UI.corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
end

function UI.frame(parent: Instance, size: UDim2, pos: UDim2, color: Color3?, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = color or UI.Colors.Panel
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

function UI.label(parent: Instance, text: string, size: UDim2, pos: UDim2, textSize: number?, color: Color3?, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color or UI.Colors.Text
	l.Font = font or Enum.Font.GothamBold
	l.TextSize = textSize or 16
	l.TextWrapped = true
	l.Parent = parent
	return l
end

function UI.button(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3?, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = color or UI.Colors.Accent
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = UI.Colors.Text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.AutoButtonColor = true
	b.TextWrapped = true
	b.Parent = parent
	UI.corner(b, 6)
	b.Activated:Connect(onClick)
	return b
end

function UI.bar(parent: Instance, size: UDim2, pos: UDim2, color: Color3): (Frame, Frame)
	local back = UI.frame(parent, size, pos, Color3.fromRGB(40, 40, 50))
	UI.corner(back, 4)
	local fill = UI.frame(back, UDim2.fromScale(0, 1), UDim2.new(), color)
	UI.corner(fill, 4)
	return back, fill
end

function UI.money(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return "$" .. out
end

return UI
