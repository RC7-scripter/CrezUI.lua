-- CrezUI.lua
-- roblox executor ui: draggable, tabbed, touch-friendly.
-- loadstring(game:HttpGet(URL))() -> UI.new({ Title = "..." })

local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local CONFIG_DIR = "CrezUI"
local TOUCH = UIS.TouchEnabled and not UIS.KeyboardEnabled
local ROW_H = TOUCH and 38 or 30
local HEAD_H = TOUCH and 48 or 40
local TAB_H = TOUCH and 38 or 32
local TOP_PAD = TOUCH and 44 or 8

local C = {
	Bg = Color3.fromRGB(13, 13, 18),
	Panel = Color3.fromRGB(20, 20, 27),
	Card = Color3.fromRGB(25, 25, 34),
	Field = Color3.fromRGB(34, 34, 45),
	Hover = Color3.fromRGB(44, 44, 58),
	Line = Color3.fromRGB(52, 52, 68),
	Text = Color3.fromRGB(238, 238, 246),
	Dim = Color3.fromRGB(138, 138, 158),
	A1 = Color3.fromRGB(146, 104, 255),
	A2 = Color3.fromRGB(70, 168, 255),
	Off = Color3.fromRGB(58, 58, 74),
}

local TW = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TW_SLOW = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local FONT = Enum.Font.GothamMedium
local FONT_B = Enum.Font.GothamBold

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function corner(o, r)
	make("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o)
end

local function stroke(o, transparency)
	make("UIStroke", {
		Color = C.Line, Transparency = transparency or 0, Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, o)
end

local function grad(o, rot)
	return make("UIGradient", { Color = ColorSequence.new(C.A1, C.A2), Rotation = rot or 0 }, o)
end

local function tween(o, info, props)
	local t = TweenService:Create(o, info or TW, props)
	t:Play()
	return t
end

local function safeCall(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then warn("[CrezUI] " .. tostring(err)) end
end

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
	local vp = cam and cam.ViewportSize
	if vp and vp.X > 0 then return vp end
	return Vector2.new(1280, 720)
end

local function isTap(i)
	return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end

local function isDrag(i)
	return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch
end

local function rowLabel(parent, text, offX)
	return make("TextLabel", {
		Size = UDim2.new(1, offX or -60, 1, 0), BackgroundTransparency = 1, Text = tostring(text),
		TextColor3 = C.Text, Font = FONT, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent)
end

local Window, Tab, Section = {}, {}, {}
Window.__index = Window
Tab.__index = Tab
Section.__index = Section

function Window:_bind(sig, fn)
	local c = sig:Connect(fn)
	table.insert(self._conns, c)
	return c
end

function Window:_claim(name)
	local base = tostring(name or "Control")
	local key, n = base, 1
	while self._controls[key] do
		n = n + 1
		key = base .. " #" .. n
	end
	if key ~= base then warn("[CrezUI] duplicate flag '" .. base .. "' renamed to '" .. key .. "'") end
	return key
end

function Window:_register(key, ctrl, default)
	self._controls[key] = ctrl
	self._defaults[key] = default
end

function Window:_place(frame, x, y)
	local vp = viewport()
	local s = frame.AbsoluteSize
	x = math.clamp(x, 6, math.max(6, vp.X - s.X - 6))
	y = math.clamp(y, TOP_PAD, math.max(TOP_PAD, vp.Y - s.Y - 6))
	frame.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
end

-- onTap fires only if the pointer barely moved, so launcher drags don't toggle
function Window:_drag(handle, frame, onTap)
	local active, moved, from, origin = false, 0, nil, nil
	self:_bind(handle.InputBegan, function(i)
		if not isTap(i) then return end
		active, moved = true, 0
		from, origin = i.Position, frame.AbsolutePosition
	end)
	self:_bind(UIS.InputChanged, function(i)
		if not active or not isDrag(i) then return end
		local d = i.Position - from
		moved = math.max(moved, d.Magnitude)
		self:_place(frame, origin.X + d.X, origin.Y + d.Y)
	end)
	self:_bind(UIS.InputEnded, function(i)
		if not active or not isTap(i) then return end
		active = false
		if moved < 8 and onTap then onTap() end
	end)
end

function Window:Toggle(state)
	if state == nil then state = not self.main.Visible end
	self.main.Visible = state
end

function Window.new(opts)
	if type(opts) == "string" then opts = { Title = opts } end
	opts = opts or {}

	local env = getgenv and getgenv() or _G
	if env.CrezUI_Window then pcall(env.CrezUI_Window.Destroy, env.CrezUI_Window) end

	local self = setmetatable({
		Flags = {}, _controls = {}, _defaults = {}, _conns = {}, _tabs = {}, _active = nil,
	}, Window)

	local parent = guiParent()
	for _, name in ipairs({ "CrezUI", "CrezUILauncher" }) do
		local old = parent:FindFirstChild(name)
		if old then old:Destroy() end
	end

	local vp = viewport()
	local w = math.floor(math.min(opts.Width or 520, vp.X - 16))
	local h = math.floor(math.min(opts.Height or 360, vp.Y - TOP_PAD - 16))
	self._compact = w < 420
	local sideW = self._compact and 50 or 124

	local gui = make("ScreenGui", {
		Name = "CrezUI", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
	}, parent)
	self.gui = gui
	env.CrezUI_Window = self

	local main = make("Frame", {
		Name = "Main", Size = UDim2.fromOffset(w, h),
		Position = UDim2.fromOffset(math.floor((vp.X - w) / 2), math.max(TOP_PAD, math.floor((vp.Y - h) / 2))),
		BackgroundColor3 = C.Bg, BorderSizePixel = 0, ClipsDescendants = true,
	}, gui)
	corner(main, 14)
	stroke(main, 0.2)
	self.main = main

	-- header
	local head = make("Frame", {
		Size = UDim2.new(1, 0, 0, HEAD_H), BackgroundColor3 = C.Panel, BorderSizePixel = 0,
	}, main)
	corner(head, 14)
	make("Frame", {
		Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -14),
		BackgroundColor3 = C.Panel, BorderSizePixel = 0,
	}, head)

	local logo = make("Frame", {
		Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(12, (HEAD_H - 24) / 2),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
	}, head)
	corner(logo, 7)
	grad(logo, 45)
	make("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Text = string.upper(string.sub(tostring(opts.Title or "C"), 1, 1)),
		TextColor3 = Color3.new(1, 1, 1), Font = FONT_B, TextSize = 13,
	}, logo)

	make("TextLabel", {
		Size = UDim2.new(1, -110, 1, 0), Position = UDim2.fromOffset(44, 0), BackgroundTransparency = 1,
		Text = tostring(opts.Title or "CrezUI"), TextColor3 = C.Text, Font = FONT_B, TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, head)

	local function headBtn(text, xOff)
		local b = make("TextButton", {
			Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, xOff, 0.5, -14),
			BackgroundColor3 = C.Field, BorderSizePixel = 0, AutoButtonColor = false,
			Text = text, TextColor3 = C.Dim, Font = FONT_B, TextSize = 14,
		}, head)
		corner(b, 8)
		b.MouseEnter:Connect(function() tween(b, TW, { TextColor3 = C.Text, BackgroundColor3 = C.Hover }) end)
		b.MouseLeave:Connect(function() tween(b, TW, { TextColor3 = C.Dim, BackgroundColor3 = C.Field }) end)
		return b
	end
	local minBtn = headBtn("-", -68)
	local hideBtn = headBtn("X", -34)

	-- body
	local body = make("Frame", {
		Size = UDim2.new(1, 0, 1, -HEAD_H), Position = UDim2.fromOffset(0, HEAD_H), BackgroundTransparency = 1,
	}, main)
	local side = make("Frame", {
		Size = UDim2.new(0, sideW, 1, -16), Position = UDim2.fromOffset(8, 8), BackgroundTransparency = 1,
	}, body)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, side)
	local pages = make("Frame", {
		Size = UDim2.new(1, -(sideW + 24), 1, -16), Position = UDim2.fromOffset(sideW + 16, 8),
		BackgroundTransparency = 1,
	}, body)
	self._side, self._pages = side, pages

	local collapsed = false
	minBtn.MouseButton1Click:Connect(function()
		collapsed = not collapsed
		minBtn.Text = collapsed and "+" or "-"
		body.Visible = not collapsed
		tween(main, TW_SLOW, { Size = UDim2.fromOffset(w, collapsed and HEAD_H or h) })
	end)
	hideBtn.MouseButton1Click:Connect(function() self:Toggle(false) end)
	self:_drag(head, main)

	-- toasts
	self._toasts = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(0, 360, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
	}, gui)
	make("UIListLayout", {
		Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, self._toasts)

	-- insert key hides or shows the window
	self:_bind(UIS.InputBegan, function(i, gp)
		if not gp and i.KeyCode == Enum.KeyCode.Insert then self:Toggle() end
	end)

	-- floating launcher, works everywhere, mainly for phones
	local s = TOUCH and 52 or 44
	local lgui = make("ScreenGui", {
		Name = "CrezUILauncher", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1000,
	}, parent)
	self.launcherGui = lgui
	local pill = make("TextButton", {
		Size = UDim2.fromOffset(s, s), Position = UDim2.new(1, -(s + 12), 0.5, -s / 2),
		BackgroundColor3 = C.Panel, BorderSizePixel = 0, AutoButtonColor = false,
		Text = "C", TextColor3 = C.Text, Font = FONT_B, TextSize = 18,
	}, lgui)
	corner(pill, s / 2)
	make("UIStroke", { Color = C.A1, Thickness = 1.5, Transparency = 0.2 }, pill)
	self:_drag(pill, pill, function() self:Toggle() end)

	local cam = workspace.CurrentCamera
	if cam then
		self:_bind(cam:GetPropertyChangedSignal("ViewportSize"), function()
			self:_place(main, main.AbsolutePosition.X, main.AbsolutePosition.Y)
		end)
	end

	return self
end

function Window:AddTab(name, icon)
	local btn = make("TextButton", {
		Size = UDim2.new(1, 0, 0, TAB_H), BackgroundColor3 = C.Field, BackgroundTransparency = 1,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = #self._tabs + 1,
	}, self._side)
	corner(btn, 9)

	local bar = make("Frame", {
		Size = UDim2.fromOffset(3, 16), Position = UDim2.fromOffset(0, TAB_H / 2 - 8),
		BackgroundColor3 = C.A1, BorderSizePixel = 0, Visible = false,
	}, btn)
	corner(bar, 2)

	local ic = make("TextLabel", {
		Size = self._compact and UDim2.fromScale(1, 1) or UDim2.fromOffset(TAB_H, TAB_H),
		BackgroundTransparency = 1, Text = icon or string.upper(string.sub(tostring(name), 1, 1)),
		TextColor3 = C.Dim, Font = FONT_B, TextSize = 14,
	}, btn)
	local lbl = make("TextLabel", {
		Size = UDim2.new(1, -(TAB_H + 4), 1, 0), Position = UDim2.fromOffset(TAB_H + 4, 0),
		BackgroundTransparency = 1, Text = tostring(name), TextColor3 = C.Dim, Font = FONT, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = not self._compact,
	}, btn)

	local page = make("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
		ScrollBarThickness = TOUCH and 3 or 2, ScrollBarImageColor3 = C.A1,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, self._pages)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, page)
	make("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, page)

	local tab = setmetatable({ win = self, page = page, btn = btn, lbl = lbl, ic = ic, bar = bar, sections = 0 }, Tab)
	table.insert(self._tabs, tab)

	btn.MouseButton1Click:Connect(function() self:Select(tab) end)
	btn.MouseEnter:Connect(function()
		if self._active ~= tab then tween(btn, TW, { BackgroundTransparency = 0.6 }) end
	end)
	btn.MouseLeave:Connect(function()
		if self._active ~= tab then tween(btn, TW, { BackgroundTransparency = 1 }) end
	end)

	if not self._active then self:Select(tab) end
	return tab
end

function Window:Select(tab)
	self._active = tab
	for _, t in ipairs(self._tabs) do
		local on = t == tab
		t.page.Visible = on
		t.bar.Visible = on
		tween(t.btn, TW, { BackgroundTransparency = on and 0 or 1 })
		tween(t.ic, TW, { TextColor3 = on and C.Text or C.Dim })
		tween(t.lbl, TW, { TextColor3 = on and C.Text or C.Dim })
	end
end

function Tab:AddSection(title)
	self.sections = self.sections + 1
	local card = make("Frame", {
		Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.Card, BorderSizePixel = 0, LayoutOrder = self.sections,
	}, self.page)
	corner(card, 12)
	stroke(card, 0.45)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, card)

	local head = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, AutoButtonColor = false,
		Text = "", LayoutOrder = 1,
	}, card)
	make("TextLabel", {
		Size = UDim2.new(1, -40, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1,
		Text = string.upper(tostring(title)), TextColor3 = C.Dim, Font = FONT_B, TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, head)
	local chev = make("TextLabel", {
		Size = UDim2.fromOffset(20, 34), Position = UDim2.new(1, -30, 0, 0), BackgroundTransparency = 1,
		Text = "v", TextColor3 = C.Dim, Font = FONT_B, TextSize = 12,
	}, head)

	local content = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, LayoutOrder = 2,
	}, card)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, content)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
	}, content)

	local open = true
	head.MouseButton1Click:Connect(function()
		open = not open
		content.Visible = open
		tween(chev, TW, { Rotation = open and 0 or -90 })
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
	local state = false
	local row = self:_row(ROW_H)
	rowLabel(row, o.Name, -60)

	local track = make("TextButton", {
		Size = UDim2.fromOffset(42, 24), Position = UDim2.new(1, -42, 0.5, -12),
		BackgroundColor3 = C.Off, BorderSizePixel = 0, AutoButtonColor = false, Text = "",
	}, row)
	corner(track, 12)
	local knob = make("Frame", {
		Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(3, 3),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
	}, track)
	corner(knob, 9)

	local function render(instant)
		local color = state and C.A1 or C.Off
		local pos = state and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3)
		if instant then
			track.BackgroundColor3 = color
			knob.Position = pos
		else
			tween(track, TW, { BackgroundColor3 = color })
			tween(knob, TW, { Position = pos })
		end
	end

	local function set(v, silent)
		state = v == true
		win.Flags[key] = state
		render(silent)
		if not silent then fire(o.Callback, state) end
	end

	track.MouseEnter:Connect(function()
		if not state then tween(track, TW, { BackgroundColor3 = C.Hover }) end
	end)
	track.MouseLeave:Connect(function()
		if not state then tween(track, TW, { BackgroundColor3 = C.Off }) end
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
	local step = o.Increment or 1
	local suffix = o.Suffix or ""
	local default = o.Default or min
	local value = min
	local row = self:_row(TOUCH and 52 or 46)

	make("TextLabel", {
		Size = UDim2.new(1, -70, 0, 18), BackgroundTransparency = 1, Text = tostring(o.Name),
		TextColor3 = C.Text, Font = FONT, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	local readout = make("TextLabel", {
		Size = UDim2.new(0, 70, 0, 18), Position = UDim2.new(1, -70, 0, 0), BackgroundTransparency = 1,
		TextColor3 = C.A1, Font = FONT_B, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right,
	}, row)

	local track = make("Frame", {
		Size = UDim2.new(1, 0, 0, 6), Position = UDim2.fromOffset(0, 30),
		BackgroundColor3 = C.Off, BorderSizePixel = 0,
	}, row)
	corner(track, 3)
	local fill = make("Frame", {
		Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
	}, track)
	corner(fill, 3)
	grad(fill)
	local ks = TOUCH and 16 or 14
	local knob = make("Frame", {
		Size = UDim2.fromOffset(ks, ks), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0, ZIndex = 2,
	}, track)
	corner(knob, ks / 2)

	local hit = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 22),
		BackgroundTransparency = 1, AutoButtonColor = false, Text = "",
	}, row)

	local function set(v, silent)
		local n = math.floor((tonumber(v) or min) / step + 0.5) * step
		n = math.clamp(n, min, max)
		value = tonumber(string.format("%.6g", n))
		local rel = (value - min) / math.max(max - min, 1e-9)
		fill.Size = UDim2.fromScale(rel, 1)
		knob.Position = UDim2.fromScale(rel, 0.5)
		readout.Text = tostring(value) .. suffix
		win.Flags[key] = value
		if not silent then fire(o.Callback, value) end
	end

	local sliding = false
	local function apply(x)
		local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		set(min + rel * (max - min))
	end
	hit.InputBegan:Connect(function(i)
		if isTap(i) then
			sliding = true
			apply(i.Position.X)
		end
	end)
	win:_bind(UIS.InputChanged, function(i)
		if sliding and isDrag(i) then apply(i.Position.X) end
	end)
	win:_bind(UIS.InputEnded, function(i)
		if isTap(i) then sliding = false end
	end)

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
	local current = nil
	local picked = {}
	local buttons = {}
	local OPT_H = TOUCH and 32 or 26

	local row = self:_row(ROW_H)
	local head = make("TextButton", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.Field, BorderSizePixel = 0,
		AutoButtonColor = false, Text = "",
	}, row)
	corner(head, 8)
	local headLbl = make("TextLabel", {
		Size = UDim2.new(1, -36, 1, 0), Position = UDim2.fromOffset(10, 0), BackgroundTransparency = 1,
		Text = "", TextColor3 = C.Text, Font = FONT, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, head)
	local chev = make("TextLabel", {
		Size = UDim2.fromOffset(20, ROW_H), Position = UDim2.new(1, -26, 0, 0), BackgroundTransparency = 1,
		Text = "v", TextColor3 = C.Dim, Font = FONT_B, TextSize = 12,
	}, head)

	self.order = self.order + 1
	local list = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.Bg,
		BorderSizePixel = 0, Visible = false, LayoutOrder = self.order,
	}, self.box)
	corner(list, 8)
	stroke(list, 0.3)
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
	}, list)

	local function values()
		if not multi then return current end
		local out = {}
		for _, opt in ipairs(options) do
			if picked[opt] then table.insert(out, opt) end
		end
		return out
	end

	local function summary(v)
		if not multi then return v ~= nil and tostring(v) or "none" end
		return #v > 0 and table.concat(v, ", ") or "none"
	end

	local function refresh()
		for opt, b in pairs(buttons) do
			local on = (multi and picked[opt] == true) or (not multi and current == opt)
			tween(b, TW, {
				BackgroundTransparency = on and 0 or 1,
				TextColor3 = on and C.A1 or C.Text,
			})
		end
	end

	local function set(v, silent)
		if multi then
			picked = {}
			if type(v) == "table" then
				for _, x in ipairs(v) do picked[x] = true end
			end
		else
			current = v
		end
		local out = values()
		headLbl.Text = o.Name .. ":  " .. summary(out)
		refresh()
		win.Flags[key] = out
		if not silent then fire(o.Callback, out) end
	end

	for _, opt in ipairs(options) do
		local b = make("TextButton", {
			Size = UDim2.new(1, 0, 0, OPT_H), BackgroundColor3 = C.Field, BackgroundTransparency = 1,
			BorderSizePixel = 0, AutoButtonColor = false, Text = tostring(opt),
			TextColor3 = C.Text, Font = FONT, TextSize = 13,
		}, list)
		corner(b, 6)
		buttons[opt] = b
		b.MouseButton1Click:Connect(function()
			if multi then
				picked[opt] = (not picked[opt]) or nil
				set(values())
			else
				list.Visible = false
				tween(chev, TW, { Rotation = 0 })
				set(opt)
			end
		end)
	end

	head.MouseButton1Click:Connect(function()
		list.Visible = not list.Visible
		tween(chev, TW, { Rotation = list.Visible and 180 or 0 })
	end)

	local ctrl = { Set = function(v) set(v) end, Get = function() return values() end }
	win:_register(key, ctrl, default)
	set(default, true)
	return ctrl
end

function Section:AddKeybind(o)
	local win = self.win
	local key = win:_claim(o.Flag or o.Name)
	local default = o.Default
	local current, listening = nil, false
	local kw = TOUCH and 104 or 92
	local kh = TOUCH and 28 or 22

	local row = self:_row(ROW_H)
	rowLabel(row, o.Name, -(kw + 8))

	local btn = make("TextButton", {
		Size = UDim2.fromOffset(kw, kh), Position = UDim2.new(1, -kw, 0.5, -kh / 2),
		BackgroundColor3 = C.Field, BorderSizePixel = 0, AutoButtonColor = false, Text = "",
	}, row)
	corner(btn, 7)
	local btnLbl = make("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "",
		TextColor3 = C.Text, Font = FONT, TextSize = 12,
	}, btn)

	local function render()
		if listening then
			btnLbl.Text = "press a key"
			btnLbl.TextColor3 = C.A1
		else
			btnLbl.Text = current and current.Name or "none"
			btnLbl.TextColor3 = C.Text
		end
	end

	local function set(v, silent)
		if type(v) == "string" then
			local ok, kc = pcall(function() return Enum.KeyCode[v] end)
			v = ok and kc or nil
		end
		if typeof(v) ~= "EnumItem" then v = nil end
		current, listening = v, false
		win.Flags[key] = current and current.Name or nil
		render()
		if not silent then fire(o.Callback, current) end
	end

	btn.MouseButton1Click:Connect(function()
		listening = true
		render()
	end)

	win:_bind(UIS.InputBegan, function(i, gp)
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
	end)

	local ctrl = { Set = function(v) set(v) end, Get = function() return current end }
	win:_register(key, ctrl, default)
	set(default, true)
	return ctrl
end

function Section:AddInput(o)
	local win = self.win
	local key = win:_claim(o.Flag or o.Name)
	local default = o.Default ~= nil and tostring(o.Default) or ""
	local last = default
	local row = self:_row(TOUCH and 58 or 52)

	make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Text = tostring(o.Name),
		TextColor3 = C.Text, Font = FONT, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	local box = make("TextBox", {
		Size = UDim2.new(1, 0, 0, TOUCH and 30 or 26), Position = UDim2.fromOffset(0, 22),
		BackgroundColor3 = C.Field, BorderSizePixel = 0, Text = "",
		PlaceholderText = o.Placeholder or "", PlaceholderColor3 = C.Dim,
		TextColor3 = C.Text, Font = FONT, TextSize = 13, ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	corner(box, 8)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, box)

	local function set(v, silent)
		local s = v == nil and "" or tostring(v)
		box.Text = s
		last = s
		win.Flags[key] = s
		if not silent then fire(o.Callback, s) end
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
	local row = self:_row(ROW_H)
	local primary = o.Primary == true
	local b = make("TextButton", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = primary and Color3.new(1, 1, 1) or C.Field,
		BorderSizePixel = 0, AutoButtonColor = false, Text = tostring(o.Name),
		TextColor3 = C.Text, Font = FONT_B, TextSize = 13,
	}, row)
	corner(b, 8)
	if primary then grad(b) end

	b.MouseEnter:Connect(function()
		tween(b, TW, primary and { BackgroundTransparency = 0.12 } or { BackgroundColor3 = C.Hover })
	end)
	b.MouseLeave:Connect(function()
		tween(b, TW, primary and { BackgroundTransparency = 0 } or { BackgroundColor3 = C.Field })
	end)
	b.MouseButton1Click:Connect(function() fire(o.Callback) end)
	return b
end

function Section:AddLabel(text)
	local row = self:_row(18)
	local l = make("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = tostring(text or ""),
		TextColor3 = C.Dim, Font = FONT, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)
	return { Set = function(t) l.Text = tostring(t) end }
end

function Window:Notify(text, seconds)
	self._toastN = (self._toastN or 0) + 1
	local t = make("TextLabel", {
		Size = UDim2.fromOffset(0, TOUCH and 34 or 28), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Panel, BorderSizePixel = 0, Text = tostring(text),
		TextColor3 = C.Text, Font = FONT, TextSize = 13, LayoutOrder = self._toastN,
	}, self._toasts)
	corner(t, 9)
	make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, t)
	task.delay(seconds or 2.5, function()
		if not t.Parent then return end
		local tw = tween(t, TW_SLOW, { BackgroundTransparency = 1, TextTransparency = 1 })
		tw.Completed:Connect(function() t:Destroy() end)
	end)
end

function Window:Save(path)
	if not writefile then
		warn("[CrezUI] writefile not available")
		return false
	end
	if makefolder and isfolder and not isfolder(CONFIG_DIR) then pcall(makefolder, CONFIG_DIR) end
	local ok, err = pcall(writefile, path, HttpService:JSONEncode(self.Flags))
	if not ok then warn("[CrezUI] save failed: " .. tostring(err)) end
	return ok
end

-- only keys present in the file are touched, and each control's callback fires
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

-- puts every control back to its build-time default; callbacks fire
function Window:Reset()
	for key, c in pairs(self._controls) do
		safeCall(c.Set, self._defaults[key])
	end
end

function Window:AddConfigTab()
	local tab = self:AddTab("Config", "+")
	local sec = tab:AddSection("Profile")

	local row = sec:_row(ROW_H)
	local box = make("TextBox", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.Field, BorderSizePixel = 0,
		Text = "default", PlaceholderText = "profile name", PlaceholderColor3 = C.Dim,
		TextColor3 = C.Text, Font = FONT, TextSize = 13, ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	corner(box, 8)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10) }, box)

	local status = sec:AddLabel("ready")

	local function path()
		local n = box.Text:gsub("[^%w_%-]", "")
		if n == "" then n = "default" end
		return CONFIG_DIR .. "/" .. n .. ".json"
	end

	sec:AddButton({
		Name = "Save", Primary = true,
		Callback = function()
			status.Set(self:Save(path()) and ("saved " .. path()) or "save failed")
		end,
	})
	sec:AddButton({
		Name = "Load",
		Callback = function()
			status.Set(self:Load(path()) and ("loaded " .. path()) or "load failed")
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
