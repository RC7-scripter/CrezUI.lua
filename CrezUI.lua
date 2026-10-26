-- language: Luau, file: CrezUI.lua, target: Roblox executor, draggable tabbed toggle UI
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local TI = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local THEME = {
	Main = Color3.fromRGB(18, 18, 22),
	Head = Color3.fromRGB(26, 26, 32),
	Row = Color3.fromRGB(30, 30, 38),
	RowHover = Color3.fromRGB(40, 40, 50),
	Accent = Color3.fromRGB(120, 90, 255),
	Off = Color3.fromRGB(55, 55, 65),
	Text = Color3.fromRGB(235, 235, 240),
	Dim = Color3.fromRGB(140, 140, 155),
	Radius = 8,
}
local CONFIG_DIR = "CrezUI"

local function safeCall(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, ...)
	if not ok then warn("[CrezUI] " .. tostring(err)) end
end

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function round(o, r)
	make("UICorner", { CornerRadius = UDim.new(0, r or THEME.Radius) }, o)
end

local function guiParent()
	local ok, hui = pcall(function() return gethui and gethui() end)
	if ok and typeof(hui) == "Instance" then return hui end
	return CoreGui
end

local function isPress(i)
	return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end

local function isMove(i)
	return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch
end

local function row(sec, h)
	sec.order = sec.order + 1
	return make("Frame", { Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1, LayoutOrder = sec.order }, sec.box)
end

local Window = {}
Window.__index = Window
local Tab = {}
Tab.__index = Tab
local Section = {}
Section.__index = Section

function Window:_bind(c)
	table.insert(self.conns, c)
	return c
end

function Window:_drag(handle, target)
	local dragging, startInput, startPos = false, nil, nil
	self:_bind(handle.InputBegan:Connect(function(i)
		if isPress(i) then
			dragging = true
			startInput = i.Position
			startPos = target.Position
		end
	end))
	self:_bind(UIS.InputChanged:Connect(function(i)
		if dragging and isMove(i) then
			local d = i.Position - startInput
			target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
	self:_bind(UIS.InputEnded:Connect(function(i)
		if isPress(i) then dragging = false end
	end))
end

function Window.new(title)
	local env = getgenv and getgenv() or _G
	if env.CrezUI_Window then pcall(function() env.CrezUI_Window:Destroy() end) end

	local self = setmetatable({}, Window)
	self.Flags = {}
	self.controls = {}
	self.conns = {}
	self.tabs = {}
	self.width = 440
	self.height = 340

	local parent = guiParent()
	local old = parent:FindFirstChild("CrezUI")
	if old then old:Destroy() end
	local gui = make("ScreenGui", {
		Name = "CrezUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
	}, parent)
	self.gui = gui
	env.CrezUI_Window = self

	local main = make("Frame", {
		Size = UDim2.fromOffset(self.width, self.height),
		Position = UDim2.new(0.5, -self.width / 2, 0.5, -self.height / 2),
		BackgroundColor3 = THEME.Main, BorderSizePixel = 0, ClipsDescendants = true,
	}, gui)
	round(main)
	self.main = main

	local head = make("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = THEME.Head, BorderSizePixel = 0 }, main)
	round(head)
	make("Frame", { Size = UDim2.new(1, 0, 0, 10), Position = UDim2.new(0, 0, 1, -10), BackgroundColor3 = THEME.Head, BorderSizePixel = 0 }, head)
	make("TextLabel", {
		Size = UDim2.new(1, -80, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1,
		Text = title or "CrezUI", TextColor3 = THEME.Text, Font = Enum.Font.GothamBold, TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, head)

	local collapseBtn = make("TextButton", {
		Size = UDim2.fromOffset(28, 24), Position = UDim2.new(1, -36, 0.5, -12), BackgroundColor3 = THEME.Row,
		BorderSizePixel = 0, Text = "-", TextColor3 = THEME.Text, Font = Enum.Font.GothamBold, TextSize = 16,
		AutoButtonColor = false,
	}, head)
	round(collapseBtn, 6)

	local body = make("Frame", {
		Size = UDim2.new(1, 0, 1, -36), Position = UDim2.fromOffset(0, 36), BackgroundTransparency = 1,
	}, main)
	local tabBar = make("Frame", {
		Size = UDim2.new(0, 110, 1, -12), Position = UDim2.fromOffset(6, 6), BackgroundTransparency = 1,
	}, body)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, tabBar)
	local pages = make("Frame", {
		Size = UDim2.new(1, -128, 1, -12), Position = UDim2.fromOffset(122, 6), BackgroundTransparency = 1,
	}, body)
	self.tabBar, self.pages = tabBar, pages

	local collapsed = false
	collapseBtn.MouseButton1Click:Connect(function()
		collapsed = not collapsed
		body.Visible = not collapsed
		collapseBtn.Text = collapsed and "+" or "-"
		main.Size = UDim2.fromOffset(self.width, collapsed and 36 or self.height)
	end)

	self:_drag(head, main)
	self:_bind(UIS.InputBegan:Connect(function(i, gp)
		if not gp and i.KeyCode == Enum.KeyCode.Insert then gui.Enabled = not gui.Enabled end
	end))

	return self
end

function Window:AddTab(name)
	local btn = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = THEME.Row, BorderSizePixel = 0,
		Text = name, TextColor3 = THEME.Dim, Font = Enum.Font.GothamMedium, TextSize = 13,
		AutoButtonColor = false, LayoutOrder = #self.tabs + 1,
	}, self.tabBar)
	round(btn, 6)
	local page = make("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
		ScrollBarThickness = 3, ScrollBarImageColor3 = THEME.Accent,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(0, 0, 0, 0),
	}, self.pages)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, page)

	local tab = setmetatable({ win = self, page = page, btn = btn, sections = 0 }, Tab)
	table.insert(self.tabs, tab)
	btn.MouseButton1Click:Connect(function() self:Select(tab) end)
	if #self.tabs == 1 then self:Select(tab) end
	return tab
end

function Window:Select(tab)
	for _, t in ipairs(self.tabs) do
		local on = t == tab
		t.page.Visible = on
		t.btn.BackgroundColor3 = on and THEME.Accent or THEME.Row
		t.btn.TextColor3 = on and THEME.Text or THEME.Dim
	end
end

function Tab:AddSection(title)
	self.sections = self.sections + 1
	local box = make("Frame", {
		Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = THEME.Row, BorderSizePixel = 0, LayoutOrder = self.sections,
	}, self.page)
	round(box)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
	}, box)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, box)
	make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, LayoutOrder = 0,
		Text = string.upper(title), TextColor3 = THEME.Accent, Font = Enum.Font.GothamBold, TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, box)
	return setmetatable({ win = self.win, box = box, order = 0 }, Section)
end

function Section:AddToggle(o)
	local win = self.win
	local flag = o.Flag or o.Name
	local state = false
	local r = row(self, 24)
	make("TextLabel", {
		Size = UDim2.new(1, -46, 1, 0), BackgroundTransparency = 1, Text = o.Name,
		TextColor3 = THEME.Text, Font = Enum.Font.Gotham, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
	}, r)
	local track = make("TextButton", {
		Size = UDim2.fromOffset(36, 18), Position = UDim2.new(1, -36, 0.5, -9),
		BackgroundColor3 = THEME.Off, BorderSizePixel = 0, Text = "", AutoButtonColor = false,
	}, r)
	round(track, 9)
	local knob = make("Frame", {
		Size = UDim2.fromOffset(14, 14), Position = UDim2.fromOffset(2, 2),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
	}, track)
	round(knob, 7)

	local function set(v, silent)
		state = v == true
		win.Flags[flag] = state
		TweenService:Create(track, TI, { BackgroundColor3 = state and THEME.Accent or THEME.Off }):Play()
		TweenService:Create(knob, TI, {
			Position = state and UDim2.fromOffset(20, 2) or UDim2.fromOffset(2, 2),
		}):Play()
		if not silent then task.spawn(safeCall, o.Callback, state) end
	end

	track.MouseButton1Click:Connect(function() set(not state) end)
	win.controls[flag] = { Set = function(v) set(v) end, Get = function() return state end }
	set(o.Default == true, o.Default ~= true)
	return win.controls[flag]
end

function Section:AddSlider(o)
	local win = self.win
	local flag = o.Flag or o.Name
	local min, max, inc = o.Min or 0, o.Max or 100, o.Increment or 1
	local value = min
	local r = row(self, 38)
	local lbl = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Text = "",
		TextColor3 = THEME.Text, Font = Enum.Font.Gotham, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
	}, r)
	local bar = make("Frame", {
		Size = UDim2.new(1, 0, 0, 6), Position = UDim2.fromOffset(0, 26),
		BackgroundColor3 = THEME.Off, BorderSizePixel = 0,
	}, r)
	round(bar, 3)
	local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = THEME.Accent, BorderSizePixel = 0 }, bar)
	round(fill, 3)
	local hit = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 18),
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
	}, r)

	local function set(v, silent)
		value = math.clamp(math.floor(v / inc + 0.5) * inc, min, max)
		fill.Size = UDim2.fromScale((value - min) / (max - min), 1)
		lbl.Text = o.Name .. ": " .. tostring(value)
		win.Flags[flag] = value
		if not silent then task.spawn(safeCall, o.Callback, value) end
	end

	local sliding = false
	local function apply(x)
		local rel = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
		set(min + rel * (max - min))
	end
	hit.InputBegan:Connect(function(i)
		if isPress(i) then
			sliding = true
			apply(i.Position.X)
		end
	end)
	win:_bind(UIS.InputChanged:Connect(function(i)
		if sliding and isMove(i) then apply(i.Position.X) end
	end))
	win:_bind(UIS.InputEnded:Connect(function(i)
		if isPress(i) then sliding = false end
	end))

	win.controls[flag] = { Set = function(v) set(v) end, Get = function() return value end }
	set(o.Default or min, false)
	return win.controls[flag]
end

function Section:AddDropdown(o)
	local win = self.win
	local flag = o.Flag or o.Name
	local multi = o.Multi == true
	local options = o.Options or {}
	local chosen = {}
	local current = nil
	local buttons = {}

	local r = row(self, 26)
	local head = make("TextButton", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = THEME.Off, BorderSizePixel = 0,
		Text = "", AutoButtonColor = false,
	}, r)
	round(head, 6)
	local headText = make("TextLabel", {
		Size = UDim2.new(1, -10, 1, 0), Position = UDim2.fromOffset(8, 0), BackgroundTransparency = 1,
		TextColor3 = THEME.Text, Font = Enum.Font.Gotham, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "",
	}, head)

	self.order = self.order + 1
	local list = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = THEME.Head,
		BorderSizePixel = 0, Visible = false, LayoutOrder = self.order,
	}, self.box)
	round(list, 6)
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
	}, list)

	local function selectedList()
		local t = {}
		for _, opt in ipairs(options) do
			if chosen[opt] then table.insert(t, opt) end
		end
		return t
	end

	local function paint()
		for opt, b in pairs(buttons) do
			local on = (multi and chosen[opt] == true) or (not multi and current == opt)
			b.TextColor3 = on and THEME.Accent or THEME.Dim
		end
	end

	local function commit(silent)
		local value
		if multi then
			value = selectedList()
			local names = table.concat(value, ", ")
			headText.Text = o.Name .. ": " .. (names ~= "" and names or "none")
		else
			value = current
			headText.Text = o.Name .. ": " .. tostring(current or "none")
		end
		win.Flags[flag] = value
		paint()
		if not silent then task.spawn(safeCall, o.Callback, value) end
	end

	for _, opt in ipairs(options) do
		local b = make("TextButton", {
			Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = THEME.Row, BorderSizePixel = 0,
			Text = tostring(opt), TextColor3 = THEME.Dim, Font = Enum.Font.Gotham, TextSize = 12,
			AutoButtonColor = false,
		}, list)
		round(b, 5)
		buttons[opt] = b
		b.MouseButton1Click:Connect(function()
			if multi then
				chosen[opt] = not chosen[opt] or nil
			else
				current = opt
				list.Visible = false
			end
			commit()
		end)
	end

	head.MouseButton1Click:Connect(function()
		list.Visible = not list.Visible
	end)

	local function set(v, silent)
		if multi then
			chosen = {}
			if type(v) == "table" then
				for _, x in ipairs(v) do chosen[x] = true end
			end
		else
			current = v
		end
		commit(silent)
	end

	win.controls[flag] = {
		Set = function(v) set(v) end,
		Get = function() return multi and selectedList() or current end,
	}
	set(o.Default, true)
	return win.controls[flag]
end

function Section:AddButton(o)
	local r = row(self, 26)
	local b = make("TextButton", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = THEME.Off, BorderSizePixel = 0,
		Text = o.Name, TextColor3 = THEME.Text, Font = Enum.Font.GothamMedium, TextSize = 13, AutoButtonColor = false,
	}, r)
	round(b, 6)
	b.MouseEnter:Connect(function() TweenService:Create(b, TI, { BackgroundColor3 = THEME.RowHover }):Play() end)
	b.MouseLeave:Connect(function() TweenService:Create(b, TI, { BackgroundColor3 = THEME.Off }):Play() end)
	b.MouseButton1Click:Connect(function() safeCall(o.Callback) end)
	return b
end

function Window:Save(path)
	if not writefile then warn("[CrezUI] writefile missing") return false end
	if makefolder and isfolder and not isfolder(CONFIG_DIR) then pcall(makefolder, CONFIG_DIR) end
	local ok, err = pcall(writefile, path, HttpService:JSONEncode(self.Flags))
	if not ok then warn("[CrezUI] save failed: " .. tostring(err)) end
	return ok
end

function Window:Load(path)
	if not (readfile and isfile) or not isfile(path) then warn("[CrezUI] no config " .. path) return false end
	local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
	if not ok or type(data) ~= "table" then warn("[CrezUI] bad config") return false end
	for flag, v in pairs(data) do
		local c = self.controls[flag]
		if c then c.Set(v) end
	end
	return true
end

function Window:AddConfigTab()
	local tab = self:AddTab("Config")
	local sec = tab:AddSection("Config Files")
	local nameRow = row(sec, 26)
	local box = make("TextBox", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = THEME.Off, BorderSizePixel = 0,
		Text = "default", PlaceholderText = "config name", PlaceholderColor3 = THEME.Dim,
		TextColor3 = THEME.Text, Font = Enum.Font.Gotham, TextSize = 13, ClearTextOnFocus = false,
	}, nameRow)
	round(box, 6)
	local status = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Text = "",
		TextColor3 = THEME.Dim, Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
	}, sec.box)
	sec.order = sec.order + 1
	status.LayoutOrder = sec.order

	local function path()
		local n = box.Text ~= "" and box.Text or "default"
		return CONFIG_DIR .. "/" .. n .. ".json"
	end
	sec:AddButton({
		Name = "Save",
		Callback = function()
			status.Text = self:Save(path()) and ("saved " .. path()) or "save failed"
		end,
	})
	sec:AddButton({
		Name = "Load",
		Callback = function()
			status.Text = self:Load(path()) and ("loaded " .. path()) or "load failed"
		end,
	})
	return tab
end

function Window:Destroy()
	for _, c in ipairs(self.conns) do c:Disconnect() end
	self.conns = {}
	if self.gui then self.gui:Destroy() end
end

return Window
