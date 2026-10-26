-- language: Luau, file: CrezUI.lua, target: Roblox executor, modern draggable tabbed UI
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local CONFIG_DIR = "CrezUI"
local HEAD_H = 42

local THEME = {
	Bg = Color3.fromRGB(12, 12, 16),
	Panel = Color3.fromRGB(20, 20, 26),
	Raised = Color3.fromRGB(28, 28, 36),
	Hover = Color3.fromRGB(38, 38, 48),
	Stroke = Color3.fromRGB(46, 46, 60),
	Accent = Color3.fromRGB(124, 92, 255),
	Off = Color3.fromRGB(52, 52, 64),
	Text = Color3.fromRGB(236, 236, 244),
	Dim = Color3.fromRGB(132, 132, 150),
}
local FAST = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLOW = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local FONT = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function corner(o, r)
	return make("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o)
end

local function stroke(o, color, transparency)
	return make("UIStroke", {
		Color = color or THEME.Stroke,
		Transparency = transparency or 0,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, o)
end

local function tween(o, info, props)
	local t = TweenService:Create(o, info, props)
	t:Play()
	return t
end

local function safeCall(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, ...)
	if not ok then warn("[CrezUI] " .. tostring(err)) end
end

-- every callback goes through here: never blocks the UI, never throws
local function fire(cb, ...)
	if type(cb) == "function" then task.spawn(safeCall, cb, ...) end
end

local function guiParent()
	local ok, hui = pcall(function() return gethui and gethui() end)
	if ok and typeof(hui) == "Instance" then return hui end
	return CoreGui
end

local function viewport()
	local cam = workspace.CurrentCamera
	if cam and cam.ViewportSize.X > 0 then return cam.ViewportSize end
	return Vector2.new(1280, 720)
end

local function isPress(i)
	return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end

local function isMove(i)
	return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch
end

local function label(parent, text, wOff)
	return make("TextLabel", {
		Size = UDim2.new(1, wOff or -60, 1, 0), BackgroundTransparency = 1, Text = text,
		TextColor3 = THEME.Text, Font = FONT, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent)
end

local function iconButton(parent, text, pos)
	local b = make("TextButton", {
		Size = UDim2.fromOffset(28, 26), Position = pos, BackgroundColor3 = THEME.Raised,
		BorderSizePixel = 0, AutoButtonColor = false, Text = text,
		TextColor3 = THEME.Dim, Font = FONT_BOLD, TextSize = 15,
	}, parent)
	corner(b, 7)
	b.MouseEnter:Connect(function() tween(b, FAST, { TextColor3 = THEME.Text }) end)
	b.MouseLeave:Connect(function() tween(b, FAST, { TextColor3 = THEME.Dim }) end)
	return b
end

local Window = {}
Window.__index = Window
local Tab = {}
Tab.__index = Tab
local Section = {}
Section.__index = Section

function Window:_bind(c)
	table.insert(self._conns, c)
	return c
end

-- unique flag key; duplicate names get " #2", " #3" and a warning
function Window:_claim(name)
	local base = tostring(name or "Control")
	local key = base
	if self._controls[key] then
		local n = 1
		repeat
			n = n + 1
			key = base .. " #" .. n
		until not self._controls[key]
		warn("[CrezUI] duplicate flag '" .. base .. "', using '" .. key .. "'")
	end
	return key
end

function Window:_register(key, ctrl, default)
	self._controls[key] = ctrl
	self._defaults[key] = default
end

function Window:_place(x, y)
	local vp = viewport()
	local w, h = self.main.AbsoluteSize.X, self.main.AbsoluteSize.Y
	x = math.clamp(x, 0, math.max(0, vp.X - w))
	y = math.clamp(y, 0, math.max(0, vp.Y - h))
	self.main.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
end

function Window:_drag(handle, target)
	local dragging, startMouse, startPos = false, nil, nil
	self:_bind(handle.InputBegan:Connect(function(i)
		if isPress(i) then
			dragging = true
			startMouse = i.Position
			startPos = target.AbsolutePosition
		end
	end))
	self:_bind(UIS.InputChanged:Connect(function(i)
		if dragging and isMove(i) then
			local d = i.Position - startMouse
			self:_place(startPos.X + d.X, startPos.Y + d.Y)
		end
	end))
	self:_bind(UIS.InputEnded:Connect(function(i)
		if isPress(i) then dragging = false end
	end))
end

function Window:Toggle()
	self.gui.Enabled = not self.gui.Enabled
end

function Window.new(opts)
	if type(opts) == "string" then opts = { Title = opts } end
	opts = opts or {}
	local env = getgenv and getgenv() or _G
	if env.CrezUI_Window then pcall(function() env.CrezUI_Window:Destroy() end) end

	local self = setmetatable({}, Window)
	self.Flags = {}
	self._controls = {}
	self._defaults = {}
	self._conns = {}
	self._tabs = {}
	self._active = nil
	self._collapsed = false

	local parent = guiParent()
	for _, name in ipairs({ "CrezUI", "CrezUILauncher" }) do
		local old = parent:FindFirstChild(name)
		if old then old:Destroy() end
	end

	local vp = viewport()
	local width = math.floor(math.min(opts.Width or 540, vp.X - 16))
	local height = math.floor(math.min(opts.Height or 380, vp.Y - 80))
	local compact = width < 440
	local sideW = compact and 96 or 120

	local gui = make("ScreenGui", {
		Name = "CrezUI", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
	}, parent)
	self.gui = gui
	env.CrezUI_Window = self

	local main = make("Frame", {
		Name = "Main", Size = UDim2.fromOffset(width, height),
		Position = UDim2.fromOffset(math.floor((vp.X - width) / 2), math.floor((vp.Y - height) / 2)),
		BackgroundColor3 = THEME.Bg, BorderSizePixel = 0, ClipsDescendants = true,
	}, gui)
	corner(main, 12)
	stroke(main)
	self.main = main

	-- header
	local head = make("Frame", {
		Size = UDim2.new(1, 0, 0, HEAD_H), BackgroundColor3 = THEME.Panel, BorderSizePixel = 0,
	}, main)
	local dot = make("Frame", {
		Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(14, (HEAD_H - 8) / 2),
		BackgroundColor3 = THEME.Accent, BorderSizePixel = 0,
	}, head)
	corner(dot, 4)
	make("TextLabel", {
		Size = UDim2.new(1, -110, 1, 0), Position = UDim2.fromOffset(30, 0), BackgroundTransparency = 1,
		Text = opts.Title or "CrezUI", TextColor3 = THEME.Text, Font = FONT_BOLD, TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, head)
	local minBtn = iconButton(head, "-", UDim2.new(1, -66, 0.5, -13))
	local closeBtn = iconButton(head, "X", UDim2.new(1, -34, 0.5, -13))
	make("Frame", {
		Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 0, HEAD_H),
		BackgroundColor3 = THEME.Stroke, BorderSizePixel = 0,
	}, main)

	-- body
	local body = make("Frame", {
		Size = UDim2.new(1, 0, 1, -(HEAD_H + 1)), Position = UDim2.fromOffset(0, HEAD_H + 1),
		BackgroundTransparency = 1,
	}, main)
	local sidebar = make("Frame", {
		Size = UDim2.new(0, sideW, 1, -16), Position = UDim2.fromOffset(8, 8), BackgroundTransparency = 1,
	}, body)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, sidebar)
	local pages = make("Frame", {
		Size = UDim2.new(1, -(sideW + 24), 1, -16), Position = UDim2.fromOffset(sideW + 16, 8),
		BackgroundTransparency = 1,
	}, body)
	self._sidebar, self._pages = sidebar, pages

	minBtn.MouseButton1Click:Connect(function()
		self._collapsed = not self._collapsed
		minBtn.Text = self._collapsed and "+" or "-"
		body.Visible = not self._collapsed
		tween(main, SLOW, {
			Size = self._collapsed and UDim2.fromOffset(width, HEAD_H) or UDim2.fromOffset(width, height),
		})
	end)
	closeBtn.MouseButton1Click:Connect(function() self:Destroy() end)

	self:_drag(head, main)
	local cam = workspace.CurrentCamera
	if cam then
		self:_bind(cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			self:_place(main.AbsolutePosition.X, main.AbsolutePosition.Y)
		end))
	end

	-- Insert toggles the window everywhere
	self:_bind(UIS.InputBegan:Connect(function(i, gp)
		if not gp and i.KeyCode == Enum.KeyCode.Insert then self:Toggle() end
	end))

	-- floating launcher for touch devices (no Insert key on phones)
	local lgui = make("ScreenGui", {
		Name = "CrezUILauncher", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1000,
		Enabled = UIS.TouchEnabled,
	}, parent)
	self.launcherGui = lgui
	local launcher = make("TextButton", {
		Size = UDim2.fromOffset(42, 42), Position = UDim2.new(1, -58, 1, -110),
		BackgroundColor3 = THEME.Panel, BorderSizePixel = 0, AutoButtonColor = false,
		Text = "C", TextColor3 = THEME.Accent, Font = FONT_BOLD, TextSize = 17,
	}, lgui)
	corner(launcher, 21)
	stroke(launcher, THEME.Accent, 0.4)
	launcher.MouseButton1Click:Connect(function() self:Toggle() end)

	return self
end

function Window:AddTab(name)
	local btn = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = THEME.Raised, BackgroundTransparency = 1,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = #self._tabs + 1,
	}, self._sidebar)
	corner(btn, 7)
	local ind = make("Frame", {
		Size = UDim2.fromOffset(3, 14), Position = UDim2.fromOffset(4, 8),
		BackgroundColor3 = THEME.Accent, BorderSizePixel = 0, Visible = false,
	}, btn)
	corner(ind, 2)
	local lbl = make("TextLabel", {
		Size = UDim2.new(1, -18, 1, 0), Position = UDim2.fromOffset(14, 0), BackgroundTransparency = 1,
		Text = tostring(name), TextColor3 = THEME.Dim, Font = FONT, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, btn)
	local page = make("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
		ScrollBarThickness = 2, ScrollBarImageColor3 = THEME.Accent,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, self._pages)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, page)
	make("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 4) }, page)

	local tab = setmetatable({ win = self, page = page, btn = btn, lbl = lbl, ind = ind, sections = 0 }, Tab)
	table.insert(self._tabs, tab)
	btn.MouseButton1Click:Connect(function() self:Select(tab) end)
	btn.MouseEnter:Connect(function()
		if self._active ~= tab then tween(btn, FAST, { BackgroundTransparency = 0.5 }) end
	end)
	btn.MouseLeave:Connect(function()
		if self._active ~= tab then tween(btn, FAST, { BackgroundTransparency = 1 }) end
	end)
	if not self._active then self:Select(tab) end
	return tab
end

function Window:Select(tab)
	self._active = tab
	for _, t in ipairs(self._tabs) do
		local on = t == tab
		t.page.Visible = on
		t.ind.Visible = on
		tween(t.btn, FAST, { BackgroundTransparency = on and 0 or 1 })
		tween(t.lbl, FAST, { TextColor3 = on and THEME.Text or THEME.Dim })
	end
end

function Tab:AddSection(title)
	self.sections = self.sections + 1
	local card = make("Frame", {
		Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = THEME.Panel, BorderSizePixel = 0, LayoutOrder = self.sections,
	}, self.page)
	corner(card, 10)
	stroke(card)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, card)

	local header = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, BorderSizePixel = 0,
		AutoButtonColor = false, Text = "", LayoutOrder = 1,
	}, card)
	make("TextLabel", {
		Size = UDim2.new(1, -40, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1,
		Text = string.upper(tostring(title)), TextColor3 = THEME.Accent, Font = FONT_BOLD, TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, header)
	local arrow = make("TextLabel", {
		Size = UDim2.fromOffset(20, 30), Position = UDim2.new(1, -28, 0, 0), BackgroundTransparency = 1,
		Text = "-", TextColor3 = THEME.Dim, Font = FONT_BOLD, TextSize = 14,
	}, header)

	local content = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, LayoutOrder = 2,
	}, card)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, content)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
	}, content)

	local open = true
	header.MouseButton1Click:Connect(function()
		open = not open
		content.Visible = open
		arrow.Text = open and "-" or "+"
	end)

	return setmetatable({ win = self.win, box = content, order = 0 }, Section)
end

function Section:_row(h)
	self.order = self.order + 1
	return make("Frame", {
		Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1, LayoutOrder = self.order,
	}, self.box)
end

function Section:AddToggle(o)
	local win = self.win
	local key = win:_claim(o.Flag or o.Name)
	local default = o.Default == true
	local state = default
	local r = self:_row(30)
	label(r, o.Name, -56)

	local track = make("TextButton", {
		Size = UDim2.fromOffset(40, 22), Position = UDim2.new(1, -40, 0.5, -11),
		BackgroundColor3 = THEME.Off, BorderSizePixel = 0, AutoButtonColor = false, Text = "",
	}, r)
	corner(track, 11)
	local knob = make("Frame", {
		Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(3, 3),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
	}, track)
	corner(knob, 8)

	local function render(instant)
		local color = state and THEME.Accent or THEME.Off
		local pos = state and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3)
		if instant then
			track.BackgroundColor3 = color
			knob.Position = pos
		else
			tween(track, FAST, { BackgroundColor3 = color })
			tween(knob, FAST, { Position = pos })
		end
	end

	local function set(v, silent)
		state = v == true
		win.Flags[key] = state
		render(silent)
		if not silent then fire(o.Callback, state) end
	end

	track.MouseEnter:Connect(function()
		if not state then tween(track, FAST, { BackgroundColor3 = THEME.Hover }) end
	end)
	track.MouseLeave:Connect(function()
		if not state then tween(track, FAST, { BackgroundColor3 = THEME.Off }) end
	end)
	track.MouseButton1Click:Connect(function() set(not state) end)

	local ctrl = { Set = function(v) set(v) end, Get = function() return state end }
	win:_register(key, ctrl, default)
	set(default, true)
	return ctrl
end

function Section:AddSlider(o)
	local win = self.win
	local key = win:_claim(o.Flag or o.Name)
	local min, max = o.Min or 0, o.Max or 100
	local inc = o.Increment or 1
	local suffix = o.Suffix or ""
	local default = o.Default or min
	local value = min
	local r = self:_row(44)

	make("TextLabel", {
		Size = UDim2.new(1, -70, 0, 18), BackgroundTransparency = 1, Text = o.Name,
		TextColor3 = THEME.Text, Font = FONT, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
	}, r)
	local valueLbl = make("TextLabel", {
		Size = UDim2.new(0, 70, 0, 18), Position = UDim2.new(1, -70, 0, 0), BackgroundTransparency = 1,
		Text = "", TextColor3 = THEME.Accent, Font = FONT_BOLD, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, r)
	local bar = make("Frame", {
		Size = UDim2.new(1, 0, 0, 6), Position = UDim2.fromOffset(0, 28),
		BackgroundColor3 = THEME.Off, BorderSizePixel = 0,
	}, r)
	corner(bar, 3)
	local fill = make("Frame", {
		Size = UDim2.fromScale(0, 1), BackgroundColor3 = THEME.Accent, BorderSizePixel = 0,
	}, bar)
	corner(fill, 3)
	local knob = make("Frame", {
		Size = UDim2.fromOffset(12, 12), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0, ZIndex = 2,
	}, bar)
	corner(knob, 6)
	local hit = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 20),
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
	}, r)

	local function set(v, silent)
		value = math.clamp(math.floor((tonumber(v) or min) / inc + 0.5) * inc, min, max)
		local rel = (value - min) / math.max(max - min, 1e-9)
		fill.Size = UDim2.fromScale(rel, 1)
		knob.Position = UDim2.fromScale(rel, 0.5)
		valueLbl.Text = tostring(value) .. suffix
		win.Flags[key] = value
		if not silent then fire(o.Callback, value) end
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

	local ctrl = { Set = function(v) set(v) end, Get = function() return value end }
	win:_register(key, ctrl, default)
	set(default, true)
	return ctrl
end

function Section:AddDropdown(o)
	local win = self.win
	local key = win:_claim(o.Flag or o.Name)
	local multi = o.Multi == true
	local options = o.Options or {}
	local default = o.Default
	local selected = {}
	local current = nil
	local buttons = {}

	local r = self:_row(30)
	local head = make("TextButton", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = THEME.Raised, BorderSizePixel = 0,
		AutoButtonColor = false, Text = "",
	}, r)
	corner(head, 7)
	local headLbl = make("TextLabel", {
		Size = UDim2.new(1, -34, 1, 0), Position = UDim2.fromOffset(10, 0), BackgroundTransparency = 1,
		Text = "", TextColor3 = THEME.Text, Font = FONT, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, head)
	make("TextLabel", {
		Size = UDim2.fromOffset(20, 30), Position = UDim2.new(1, -24, 0, 0), BackgroundTransparency = 1,
		Text = "v", TextColor3 = THEME.Dim, Font = FONT_BOLD, TextSize = 12,
	}, head)

	self.order = self.order + 1
	local list = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = THEME.Bg,
		BorderSizePixel = 0, Visible = false, LayoutOrder = self.order,
	}, self.box)
	corner(list, 7)
	stroke(list)
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
	}, list)

	local function value()
		if multi then
			local out = {}
			for _, opt in ipairs(options) do
				if selected[opt] then table.insert(out, opt) end
			end
			return out
		end
		return current
	end

	local function text()
		if multi then
			local v = value()
			return #v > 0 and table.concat(v, ", ") or "none"
		end
		return current ~= nil and tostring(current) or "none"
	end

	local function refresh()
		for opt, b in pairs(buttons) do
			local on = (multi and selected[opt] == true) or (not multi and current == opt)
			b.TextColor3 = on and THEME.Accent or THEME.Text
			b.BackgroundTransparency = on and 0 or 1
		end
	end

	local function set(v, silent)
		if multi then
			selected = {}
			if type(v) == "table" then
				for _, x in ipairs(v) do selected[x] = true end
			end
		else
			current = v
		end
		headLbl.Text = o.Name .. ": " .. text()
		refresh()
		win.Flags[key] = value()
		if not silent then fire(o.Callback, value()) end
	end

	for _, opt in ipairs(options) do
		local b = make("TextButton", {
			Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = THEME.Raised, BackgroundTransparency = 1,
			BorderSizePixel = 0, AutoButtonColor = false, Text = tostring(opt),
			TextColor3 = THEME.Text, Font = FONT, TextSize = 12,
		}, list)
		corner(b, 5)
		buttons[opt] = b
		b.MouseButton1Click:Connect(function()
			if multi then
				selected[opt] = (not selected[opt]) or nil
				set(value())
			else
				list.Visible = false
				set(opt)
			end
		end)
	end

	head.MouseButton1Click:Connect(function()
		list.Visible = not list.Visible
	end)

	local ctrl = { Set = function(v) set(v) end, Get = function() return value() end }
	win:_register(key, ctrl, default)
	set(default, true)
	return ctrl
end

function Section:AddKeybind(o)
	local win = self.win
	local key = win:_claim(o.Flag or o.Name)
	local default = o.Default
	local current = nil
	local listening = false
	local r = self:_row(30)
	label(r, o.Name, -110)

	local btn = make("TextButton", {
		Size = UDim2.fromOffset(96, 22), Position = UDim2.new(1, -96, 0.5, -11),
		BackgroundColor3 = THEME.Off, BorderSizePixel = 0, AutoButtonColor = false, Text = "",
	}, r)
	corner(btn, 6)
	local btnLbl = make("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "",
		TextColor3 = THEME.Text, Font = FONT, TextSize = 12,
	}, btn)

	local function render()
		if listening then
			btnLbl.Text = "..."
			btnLbl.TextColor3 = THEME.Accent
		else
			btnLbl.Text = current and current.Name or "none"
			btnLbl.TextColor3 = THEME.Text
		end
	end

	local function set(v, silent)
		if type(v) == "string" then v = Enum.KeyCode[v] end
		if typeof(v) ~= "EnumItem" then v = nil end
		current = v
		win.Flags[key] = current and current.Name or nil
		listening = false
		render()
		if not silent then fire(o.Callback, current) end
	end

	btn.MouseButton1Click:Connect(function()
		listening = true
		render()
	end)

	-- Escape or Backspace clears the bind while listening
	win:_bind(UIS.InputBegan:Connect(function(i, gp)
		if listening and i.UserInputType == Enum.UserInputType.Keyboard then
			if i.KeyCode == Enum.KeyCode.Escape or i.KeyCode == Enum.KeyCode.Backspace then
				set(nil)
			else
				set(i.KeyCode)
			end
			return
		end
		if gp or listening or not current then return end
		if i.UserInputType == Enum.UserInputType.Keyboard and i.KeyCode == current then
			fire(o.OnPress)
		end
	end))

	local ctrl = { Set = function(v) set(v) end, Get = function() return current end }
	win:_register(key, ctrl, default)
	set(default, true)
	return ctrl
end

function Section:AddInput(o)
	local win = self.win
	local key = win:_claim(o.Flag or o.Name)
	local default = o.Default or ""
	local last = default
	local r = self:_row(52)
	label(r, o.Name, 0)

	local box = make("TextBox", {
		Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 22),
		BackgroundColor3 = THEME.Off, BorderSizePixel = 0, Text = "",
		PlaceholderText = o.Placeholder or "", PlaceholderColor3 = THEME.Dim,
		TextColor3 = THEME.Text, Font = FONT, TextSize = 13, ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, r)
	corner(box, 7)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8) }, box)

	local function set(v, silent)
		v = v == nil and "" or tostring(v)
		box.Text = v
		last = v
		win.Flags[key] = v
		if not silent then fire(o.Callback, v) end
	end

	box.FocusLost:Connect(function()
		if box.Text ~= last then set(box.Text) end
	end)

	local ctrl = { Set = function(v) set(v) end, Get = function() return last end }
	win:_register(key, ctrl, default)
	set(default, true)
	return ctrl
end

function Section:AddButton(o)
	local r = self:_row(30)
	local b = make("TextButton", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = THEME.Raised, BorderSizePixel = 0,
		AutoButtonColor = false, Text = o.Name, TextColor3 = THEME.Text, Font = FONT, TextSize = 13,
	}, r)
	corner(b, 7)
	b.MouseEnter:Connect(function() tween(b, FAST, { BackgroundColor3 = THEME.Hover }) end)
	b.MouseLeave:Connect(function() tween(b, FAST, { BackgroundColor3 = THEME.Raised }) end)
	b.MouseButton1Down:Connect(function() tween(b, FAST, { BackgroundColor3 = THEME.Accent }) end)
	b.MouseButton1Up:Connect(function() tween(b, FAST, { BackgroundColor3 = THEME.Hover }) end)
	b.MouseButton1Click:Connect(function() fire(o.Callback) end)
	return b
end

function Section:AddLabel(text)
	local r = self:_row(18)
	local l = make("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = tostring(text or ""),
		TextColor3 = THEME.Dim, Font = FONT, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, r)
	return { Set = function(t) l.Text = tostring(t) end }
end

function Window:Save(path)
	if not writefile then warn("[CrezUI] writefile missing") return false end
	if makefolder and isfolder and not isfolder(CONFIG_DIR) then pcall(makefolder, CONFIG_DIR) end
	local ok, err = pcall(function()
		writefile(path, HttpService:JSONEncode(self.Flags))
	end)
	if not ok then warn("[CrezUI] save failed: " .. tostring(err)) end
	return ok
end

-- only keys present in the file are touched; each Set fires its callback
function Window:Load(path)
	if not (readfile and isfile) or not isfile(path) then
		warn("[CrezUI] no config " .. tostring(path))
		return false
	end
	local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
	if not ok or type(data) ~= "table" then
		warn("[CrezUI] bad config " .. tostring(path))
		return false
	end
	for key, v in pairs(data) do
		local c = self._controls[key]
		if c then safeCall(c.Set, v) end
	end
	return true
end

-- sets every registered control back to its build-time default and fires callbacks
function Window:Reset()
	for key, c in pairs(self._controls) do
		safeCall(c.Set, self._defaults[key])
	end
end

function Window:AddConfigTab()
	local tab = self:AddTab("Config")
	local sec = tab:AddSection("Profile")

	local r = sec:_row(30)
	local box = make("TextBox", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = THEME.Off, BorderSizePixel = 0,
		Text = "default", PlaceholderText = "config name", PlaceholderColor3 = THEME.Dim,
		TextColor3 = THEME.Text, Font = FONT, TextSize = 13, ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, r)
	corner(box, 7)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8) }, box)

	local status = sec:AddLabel("ready")
	local function path()
		local n = box.Text ~= "" and box.Text or "default"
		return CONFIG_DIR .. "/" .. n .. ".json"
	end

	sec:AddButton({
		Name = "Save",
		Callback = function()
			local ok = self:Save(path())
			status.Set(ok and ("saved " .. path()) or "save failed")
		end,
	})
	sec:AddButton({
		Name = "Load",
		Callback = function()
			local ok = self:Load(path())
			status.Set(ok and ("loaded " .. path()) or "load failed")
		end,
	})
	sec:AddButton({
		Name = "Reset to defaults",
		Callback = function()
			self:Reset()
			status.Set("reset")
		end,
	})
	return tab
end

function Window:Destroy()
	for _, c in ipairs(self._conns) do c:Disconnect() end
	self._conns = {}
	if self.gui then self.gui:Destroy() end
	if self.launcherGui then self.launcherGui:Destroy() end
	local env = getgenv and getgenv() or _G
	if env.CrezUI_Window == self then env.CrezUI_Window = nil end
end

return Window
