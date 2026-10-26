-- CrezUI.lua
-- glass ui for roblox executors. draggable, tabbed, touch-friendly, animated.
-- local UI = loadstring(game:HttpGet(URL))()
-- local win = UI.new({ Title = "...", Subtitle = "...", Logo = "rbxassetid://..." })

local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

local CONFIG_DIR = "CrezUI"
local TOUCH = UIS.TouchEnabled and not UIS.KeyboardEnabled
local ROW_H = TOUCH and 40 or 32
local HEAD_H = TOUCH and 54 or 46
local TAB_H = TOUCH and 40 or 34
local HB = TOUCH and 32 or 28
local TOP_PAD = TOUCH and 46 or 10
local OPT_H = TOUCH and 34 or 28

local T_FAST = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local T_MED = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local T_SPRING = TweenInfo.new(0.36, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local T_PRESS = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- change these to restyle. pass overrides as opts.Theme
local DEFAULT = {
	Accent = Color3.fromRGB(150, 112, 255),
	Accent2 = Color3.fromRGB(78, 172, 255),
	Bg = Color3.fromRGB(14, 14, 22),
	GlassT = 0.22,
	Card = Color3.fromRGB(28, 28, 42),
	CardT = 0.4,
	Fill = Color3.fromRGB(40, 40, 60),
	FillT = 0.35,
	Hover = Color3.fromRGB(62, 62, 88),
	Off = Color3.fromRGB(64, 64, 86),
	Stroke = Color3.fromRGB(255, 255, 255),
	StrokeT = 0.8,
	Text = Color3.fromRGB(240, 240, 248),
	Dim = Color3.fromRGB(148, 148, 172),
	Radius = 16,
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
}
local C = {}

local function applyTheme(over)
	for k, v in pairs(DEFAULT) do C[k] = v end
	if type(over) == "table" then
		for k, v in pairs(over) do C[k] = v end
	end
end

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function corner(o, r)
	return make("UICorner", { CornerRadius = UDim.new(0, r or C.Radius) }, o)
end

local function stroke(o, t)
	return make("UIStroke", {
		Color = C.Stroke, Transparency = t or C.StrokeT, Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, o)
end

local function accentGrad(o, rot)
	return make("UIGradient", { Color = ColorSequence.new(C.Accent, C.Accent2), Rotation = rot or 0 }, o)
end

-- white-to-clear gradient on a frame gives the glass sheen
local function sheen(o, top)
	return make("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, top or 0.9),
			NumberSequenceKeypoint.new(0.45, 0.98),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 90,
	}, o)
end

local function tween(o, info, props)
	local t = TweenService:Create(o, info, props)
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

local function resolveKey(v, fallback)
	if typeof(v) == "EnumItem" and v.EnumType == Enum.KeyCode then return v end
	if type(v) == "string" then
		local ok, kc = pcall(function() return Enum.KeyCode[v] end)
		if ok and kc then return kc end
	end
	return fallback
end

local function isImage(v)
	if type(v) == "number" then return true end
	return type(v) == "string" and (v:sub(1, 4) == "rbxa" or v:sub(1, 4) == "http")
end

-- image asset or letter, centered in parent
local function icon(parent, v, size, fallback, color)
	if type(v) == "number" then v = "rbxassetid://" .. v end
	if isImage(v) then
		return make("ImageLabel", {
			Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1,
			Image = v, ImageColor3 = color or C.Text, ScaleType = Enum.ScaleType.Fit,
		}, parent)
	end
	return make("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Text = tostring(v or fallback or ""), TextColor3 = color or C.Text,
		Font = C.FontBold, TextSize = math.floor(size * 0.8),
	}, parent)
end

local function setGlyph(g, color)
	if not g then return end
	if g:IsA("ImageLabel") then
		tween(g, T_FAST, { ImageColor3 = color })
	else
		tween(g, T_FAST, { TextColor3 = color })
	end
end

local function rowLabel(parent, text, offX)
	return make("TextLabel", {
		Size = UDim2.new(1, offX or -60, 1, 0), BackgroundTransparency = 1, Text = tostring(text),
		TextColor3 = C.Text, Font = C.Font, TextSize = 13,
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

-- onTap fires only when the pointer barely moved, so dragging doesn't toggle
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
	if state == nil then state = not self._visible end
	if state == self._visible then return end
	self._visible = state
	for _, t in ipairs(self._anims) do t:Cancel() end
	self._anims = {}
	if self._blur then self._blur.Enabled = state end
	if state then
		self._main.Visible = true
		self._main.GroupTransparency = 1
		self._scale.Scale = 0.92
		table.insert(self._anims, tween(self._main, T_MED, { GroupTransparency = 0 }))
		table.insert(self._anims, tween(self._scale, T_SPRING, { Scale = 1 }))
	else
		table.insert(self._anims, tween(self._scale, T_FAST, { Scale = 0.92 }))
		local fade = tween(self._main, T_FAST, { GroupTransparency = 1 })
		table.insert(self._anims, fade)
		fade.Completed:Connect(function(ps)
			if ps == Enum.PlaybackState.Completed and not self._visible then
				self._main.Visible = false
			end
		end)
	end
end

function Window:SetTitle(text)
	self._titleLbl.Text = tostring(text)
end

function Window.new(opts)
	if type(opts) == "string" then opts = { Title = opts } end
	opts = opts or {}
	applyTheme(opts.Theme)

	local env = getgenv and getgenv() or _G
	if env.CrezUI_Window then pcall(env.CrezUI_Window.Destroy, env.CrezUI_Window) end

	local self = setmetatable({
		Flags = {}, _controls = {}, _defaults = {}, _conns = {}, _tabs = {},
		_active = nil, _anims = {}, _visible = true, _toastN = 0,
	}, Window)

	local parent = guiParent()
	for _, name in ipairs({ "CrezUI", "CrezUILauncher" }) do
		local old = parent:FindFirstChild(name)
		if old then old:Destroy() end
	end

	local vp = viewport()
	local w = math.floor(math.min(opts.Width or 520, vp.X - 16))
	local h = math.floor(math.min(opts.Height or 370, vp.Y - TOP_PAD - 16))
	self._compact = w < 420
	local sideW = self._compact and 52 or 128

	local gui = make("ScreenGui", {
		Name = "CrezUI", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
	}, parent)
	self.gui = gui
	env.CrezUI_Window = self

	-- blur is game-wide, off unless asked for
	if opts.Blur then
		self._blur = make("BlurEffect", { Name = "CrezUIBlur", Size = 12, Enabled = true }, Lighting)
	end

	local main = make("CanvasGroup", {
		Name = "Main", Size = UDim2.fromOffset(w, h),
		Position = UDim2.fromOffset(math.floor((vp.X - w) / 2), math.max(TOP_PAD, math.floor((vp.Y - h) / 2))),
		BackgroundColor3 = C.Bg, BackgroundTransparency = C.GlassT, BorderSizePixel = 0,
		ClipsDescendants = true, GroupTransparency = 0,
	}, gui)
	corner(main, C.Radius)
	stroke(main)
	local scale = make("UIScale", { Scale = 1 }, main)
	self._main, self._scale = main, scale

	local shine = make("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
	}, main)
	sheen(shine, 0.9)

	-- header
	local logoS = TOUCH and 34 or 30
	local textX = 12 + logoS + 10
	local head = make("Frame", { Size = UDim2.new(1, 0, 0, HEAD_H), BackgroundTransparency = 1 }, main)
	local logoBox = make("Frame", {
		Size = UDim2.fromOffset(logoS, logoS), Position = UDim2.fromOffset(12, (HEAD_H - logoS) / 2),
		BackgroundColor3 = C.Accent, BorderSizePixel = 0,
	}, head)
	corner(logoBox, 10)
	accentGrad(logoBox, 45)
	icon(logoBox, opts.Logo, 22, string.upper(string.sub(tostring(opts.Title or "C"), 1, 1)), Color3.new(1, 1, 1))

	local titleY = TOUCH and 9 or 7
	self._titleLbl = make("TextLabel", {
		Size = UDim2.new(1, -(textX + 90), 0, 20), Position = UDim2.fromOffset(textX, titleY),
		BackgroundTransparency = 1, Text = tostring(opts.Title or "CrezUI"), TextColor3 = C.Text,
		Font = C.FontBold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, head)
	make("TextLabel", {
		Size = UDim2.new(1, -(textX + 90), 0, 14), Position = UDim2.fromOffset(textX, titleY + 19),
		BackgroundTransparency = 1, Text = tostring(opts.Subtitle or ""), TextColor3 = C.Dim,
		Font = C.Font, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, head)

	local function headBtn(text, xOff)
		local b = make("TextButton", {
			Size = UDim2.fromOffset(HB, HB), Position = UDim2.new(1, xOff, 0.5, -HB / 2),
			BackgroundColor3 = C.Fill, BackgroundTransparency = C.FillT, BorderSizePixel = 0,
			AutoButtonColor = false, Text = text, TextColor3 = C.Dim, Font = C.FontBold, TextSize = 14,
		}, head)
		corner(b, 9)
		b.MouseEnter:Connect(function() tween(b, T_FAST, { TextColor3 = C.Text, BackgroundColor3 = C.Hover }) end)
		b.MouseLeave:Connect(function() tween(b, T_FAST, { TextColor3 = C.Dim, BackgroundColor3 = C.Fill }) end)
		return b
	end
	local minBtn = headBtn("-", -(HB * 2 + 16))
	local hideBtn = headBtn("X", -(HB + 10))

	make("Frame", {
		Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromOffset(0, HEAD_H),
		BackgroundColor3 = C.Stroke, BackgroundTransparency = 0.85, BorderSizePixel = 0,
	}, main)

	-- body
	local body = make("Frame", {
		Size = UDim2.new(1, 0, 1, -(HEAD_H + 1)), Position = UDim2.fromOffset(0, HEAD_H + 1),
		BackgroundTransparency = 1,
	}, main)
	local side = make("Frame", {
		Size = UDim2.new(0, sideW, 1, -16), Position = UDim2.fromOffset(8, 8), BackgroundTransparency = 1,
	}, body)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, side)
	local pages = make("Frame", {
		Size = UDim2.new(1, -(sideW + 26), 1, -16), Position = UDim2.fromOffset(sideW + 18, 8),
		BackgroundTransparency = 1,
	}, body)
	self._side, self._pages = side, pages

	local collapsed = false
	minBtn.MouseButton1Click:Connect(function()
		collapsed = not collapsed
		minBtn.Text = collapsed and "+" or "-"
		body.Visible = not collapsed
		tween(main, T_MED, { Size = UDim2.fromOffset(w, collapsed and HEAD_H or h) })
	end)
	hideBtn.MouseButton1Click:Connect(function() self:Toggle(false) end)
	self:_drag(head, main)

	-- toasts
	self._toasts = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.new(1, -24, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
	}, gui)
	make("UIListLayout", {
		Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, self._toasts)

	-- toggle key
	local key = resolveKey(opts.ToggleKey, Enum.KeyCode.Insert)
	self:_bind(UIS.InputBegan, function(i, gp)
		if not gp and i.KeyCode == key then self:Toggle() end
	end)

	-- floating launcher, mainly for phones (no Insert key there)
	local ls = TOUCH and 52 or 44
	local lgui = make("ScreenGui", {
		Name = "CrezUILauncher", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1000,
	}, parent)
	self.launcherGui = lgui
	local pill = make("Frame", {
		Size = UDim2.fromOffset(ls, ls), Position = UDim2.new(1, -(ls + 12), 0.5, -ls / 2),
		BackgroundColor3 = C.Bg, BackgroundTransparency = C.GlassT, BorderSizePixel = 0,
	}, lgui)
	corner(pill, ls / 2)
	stroke(pill, 0.5)
	local pillScale = make("UIScale", { Scale = 1 }, pill)
	icon(pill, opts.Launcher or opts.Logo, ls * 0.5, string.upper(string.sub(tostring(opts.Title or "C"), 1, 1)), C.Text)
	local hitBtn = make("TextButton", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
	}, pill)
	hitBtn.MouseButton1Down:Connect(function() tween(pillScale, T_PRESS, { Scale = 0.9 }) end)
	hitBtn.MouseButton1Up:Connect(function() tween(pillScale, T_SPRING, { Scale = 1 }) end)
	self:_drag(hitBtn, pill, function() self:Toggle() end)

	local cam = workspace.CurrentCamera
	if cam then
		self:_bind(cam:GetPropertyChangedSignal("ViewportSize"), function()
			self:_place(main, main.AbsolutePosition.X, main.AbsolutePosition.Y)
		end)
	end

	-- intro
	main.GroupTransparency = 1
	scale.Scale = 0.92
	tween(main, T_MED, { GroupTransparency = 0 })
	tween(scale, T_SPRING, { Scale = 1 })

	return self
end

function Window:AddTab(name, iconValue)
	local btn = make("TextButton", {
		Size = UDim2.new(1, 0, 0, TAB_H), BackgroundColor3 = C.Accent, BackgroundTransparency = 1,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = #self._tabs + 1,
	}, self._side)
	corner(btn, 11)

	local bar = make("Frame", {
		Size = UDim2.fromOffset(3, 16), Position = UDim2.fromOffset(4, (TAB_H - 16) / 2),
		BackgroundColor3 = C.Accent, BorderSizePixel = 0, Visible = false,
	}, btn)
	corner(bar, 2)

	local ico = make("Frame", { Size = UDim2.fromOffset(TAB_H, TAB_H), BackgroundTransparency = 1 }, btn)
	local glyph = icon(ico, iconValue, 16, string.upper(string.sub(tostring(name), 1, 1)), C.Dim)
	local lbl = make("TextLabel", {
		Size = UDim2.new(1, -(TAB_H + 4), 1, 0), Position = UDim2.fromOffset(TAB_H, 0),
		BackgroundTransparency = 1, Text = tostring(name), TextColor3 = C.Dim, Font = C.Font, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = not self._compact,
	}, btn)

	local wrap = make("CanvasGroup", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
		Visible = false, GroupTransparency = 0,
	}, self._pages)
	local page = make("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = TOUCH and 3 or 2, ScrollBarImageColor3 = C.Accent,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, wrap)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, page)
	make("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, page)

	local tab = setmetatable({
		win = self, wrap = wrap, page = page, btn = btn, lbl = lbl, glyph = glyph, bar = bar, sections = 0,
	}, Tab)
	table.insert(self._tabs, tab)

	btn.MouseButton1Click:Connect(function() self:Select(tab) end)
	btn.MouseEnter:Connect(function()
		if self._active ~= tab then tween(btn, T_FAST, { BackgroundTransparency = 0.9 }) end
	end)
	btn.MouseLeave:Connect(function()
		if self._active ~= tab then tween(btn, T_FAST, { BackgroundTransparency = 1 }) end
	end)

	if not self._active then self:Select(tab) end
	return tab
end

function Window:Select(tab)
	if self._active == tab then return end
	local prev = self._active
	self._active = tab
	for _, t in ipairs(self._tabs) do
		local on = t == tab
		t.bar.Visible = on
		tween(t.btn, T_FAST, { BackgroundTransparency = on and 0.8 or 1 })
		setGlyph(t.glyph, on and C.Text or C.Dim)
		tween(t.lbl, T_FAST, { TextColor3 = on and C.Text or C.Dim })
	end
	if prev then prev.wrap.Visible = false end
	tab.wrap.Visible = true
	tab.wrap.GroupTransparency = 1
	tween(tab.wrap, T_MED, { GroupTransparency = 0 })
end

function Tab:AddSection(title)
	self.sections = self.sections + 1
	local card = make("Frame", {
		Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.Card, BackgroundTransparency = C.CardT, BorderSizePixel = 0,
		LayoutOrder = self.sections,
	}, self.page)
	corner(card, C.Radius - 4)
	stroke(card, 0.82)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, card)

	local head = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, AutoButtonColor = false,
		Text = "", LayoutOrder = 1,
	}, card)
	make("TextLabel", {
		Size = UDim2.new(1, -44, 1, 0), Position = UDim2.fromOffset(14, 0), BackgroundTransparency = 1,
		Text = string.upper(tostring(title)), TextColor3 = C.Dim, Font = C.FontBold, TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, head)
	local chev = make("TextLabel", {
		Size = UDim2.fromOffset(20, 34), Position = UDim2.new(1, -32, 0, 0), BackgroundTransparency = 1,
		Text = "v", TextColor3 = C.Dim, Font = C.FontBold, TextSize = 12,
	}, head)

	-- content height is driven by the layout so collapse can tween it
	local content = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, ClipsDescendants = true, LayoutOrder = 2,
	}, card)
	local list = make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, content)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
	}, content)

	local open = true
	local function fit()
		if open then content.Size = UDim2.new(1, 0, 0, list.AbsoluteContentSize.Y + 10) end
	end
	list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
	task.defer(fit)

	head.MouseButton1Click:Connect(function()
		open = not open
		local target = open and (list.AbsoluteContentSize.Y + 10) or 0
		tween(content, T_MED, { Size = UDim2.new(1, 0, 0, target) })
		tween(chev, T_MED, { Rotation = open and 0 or -90 })
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
	local pressing = false
	local row = self:_row(ROW_H)
	rowLabel(row, o.Name, -66)

	local TW, TH = 44, 26
	local track = make("TextButton", {
		Size = UDim2.fromOffset(TW, TH), Position = UDim2.new(1, -TW, 0.5, -TH / 2),
		BackgroundColor3 = C.Off, BorderSizePixel = 0, AutoButtonColor = false, Text = "",
	}, row)
	corner(track, TH / 2)
	local knob = make("Frame", {
		Size = UDim2.fromOffset(20, 20), Position = UDim2.fromOffset(3, 3),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
	}, track)
	corner(knob, 10)

	-- knob stretches while pressed, springs to its side on release
	local function place(instant)
		local kw = pressing and 26 or 20
		local x = state and (TW - 3 - kw) or 3
		local color = state and C.Accent or C.Off
		if instant then
			knob.Size = UDim2.fromOffset(kw, 20)
			knob.Position = UDim2.fromOffset(x, 3)
			track.BackgroundColor3 = color
		else
			tween(knob, T_SPRING, { Size = UDim2.fromOffset(kw, 20), Position = UDim2.fromOffset(x, 3) })
			tween(track, T_FAST, { BackgroundColor3 = color })
		end
	end

	local function set(v, silent)
		state = v == true
		win.Flags[key] = state
		place(silent)
		if not silent then fire(o.Callback, state) end
	end

	track.MouseEnter:Connect(function()
		if not state then tween(track, T_FAST, { BackgroundColor3 = C.Hover }) end
	end)
	track.MouseLeave:Connect(function()
		pressing = false
		if not state then tween(track, T_FAST, { BackgroundColor3 = C.Off }) end
		place(false)
	end)
	track.MouseButton1Down:Connect(function() pressing = true; place(false) end)
	track.MouseButton1Up:Connect(function() pressing = false; place(false) end)
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
	local sliding = false
	local row = self:_row(TOUCH and 54 or 48)

	make("TextLabel", {
		Size = UDim2.new(1, -74, 0, 18), BackgroundTransparency = 1, Text = tostring(o.Name),
		TextColor3 = C.Text, Font = C.Font, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	local readout = make("TextLabel", {
		Size = UDim2.new(0, 74, 0, 18), Position = UDim2.new(1, -74, 0, 0), BackgroundTransparency = 1,
		TextColor3 = C.Accent, Font = C.FontBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right,
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
	accentGrad(fill)
	local knob = make("Frame", {
		Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0, ZIndex = 2,
	}, track)
	corner(knob, 7)
	local hit = make("TextButton", {
		Size = UDim2.new(1, 0, 0, TOUCH and 30 or 24), Position = UDim2.fromOffset(0, 22),
		BackgroundTransparency = 1, AutoButtonColor = false, Text = "",
	}, row)

	local function render(instant)
		local rel = (value - min) / math.max(max - min, 1e-9)
		if instant then
			fill.Size = UDim2.fromScale(rel, 1)
			knob.Position = UDim2.fromScale(rel, 0.5)
		else
			tween(fill, T_MED, { Size = UDim2.fromScale(rel, 1) })
			tween(knob, T_MED, { Position = UDim2.fromScale(rel, 0.5) })
		end
		readout.Text = tostring(value) .. suffix
	end

	local function set(v, silent, instant)
		local n = math.floor((tonumber(v) or min) / step + 0.5) * step
		value = tonumber(string.format("%.6g", math.clamp(n, min, max)))
		win.Flags[key] = value
		render(instant or silent)
		if not silent then fire(o.Callback, value) end
	end

	local function apply(x)
		local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		set(min + rel * (max - min), false, true)
	end

	hit.MouseButton1Down:Connect(function(i)
		sliding = true
		tween(knob, T_FAST, { Size = UDim2.fromOffset(18, 18) })
	end)
	hit.InputBegan:Connect(function(i)
		if isTap(i) then apply(i.Position.X) end
	end)
	win:_bind(UIS.InputChanged, function(i)
		if sliding and isDrag(i) then apply(i.Position.X) end
	end)
	win:_bind(UIS.InputEnded, function(i)
		if isTap(i) and sliding then
			sliding = false
			tween(knob, T_SPRING, { Size = UDim2.fromOffset(14, 14) })
		end
	end)

	local ctrl = { Set = function(v) set(v) end, Get = function() return value end }
	win:_register(key, ctrl, default)
	set(default, true, true)
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
	local opened = false

	local row = self:_row(ROW_H)
	local head = make("TextButton", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.Fill, BackgroundTransparency = C.FillT,
		BorderSizePixel = 0, AutoButtonColor = false, Text = "",
	}, row)
	corner(head, 9)
	local headLbl = make("TextLabel", {
		Size = UDim2.new(1, -40, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1,
		Text = "", TextColor3 = C.Text, Font = C.Font, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, head)
	local chev = make("TextLabel", {
		Size = UDim2.fromOffset(20, ROW_H), Position = UDim2.new(1, -28, 0, 0), BackgroundTransparency = 1,
		Text = "v", TextColor3 = C.Dim, Font = C.FontBold, TextSize = 12,
	}, head)

	self.order = self.order + 1
	local n = #options
	local fullH = n * OPT_H + math.max(n - 1, 0) * 2 + 8
	local list = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = C.Bg, BackgroundTransparency = C.GlassT,
		BorderSizePixel = 0, ClipsDescendants = true, Visible = false, LayoutOrder = self.order,
	}, self.box)
	corner(list, 9)
	stroke(list, 0.6)
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

	local function isOn(opt)
		if multi then return picked[opt] == true end
		return current == opt
	end

	local function refresh()
		for opt, b in pairs(buttons) do
			local on = isOn(opt)
			tween(b, T_FAST, {
				BackgroundTransparency = on and 0.8 or 1,
				TextColor3 = on and C.Accent or C.Text,
			})
		end
	end

	local function setOpen(v)
		opened = v
		if v then
			list.Visible = true
			tween(list, T_MED, { Size = UDim2.new(1, 0, 0, fullH) })
		else
			local t = tween(list, T_FAST, { Size = UDim2.new(1, 0, 0, 0) })
			t.Completed:Connect(function()
				if not opened then list.Visible = false end
			end)
		end
		tween(chev, T_MED, { Rotation = v and 180 or 0 })
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
			Size = UDim2.new(1, 0, 0, OPT_H), BackgroundColor3 = C.Accent, BackgroundTransparency = 1,
			BorderSizePixel = 0, AutoButtonColor = false, Text = tostring(opt),
			TextColor3 = C.Text, Font = C.Font, TextSize = 13,
		}, list)
		corner(b, 7)
		buttons[opt] = b
		b.MouseButton1Click:Connect(function()
			if multi then
				picked[opt] = (not picked[opt]) or nil
				set(values())
			else
				setOpen(false)
				set(opt)
			end
		end)
	end

	head.MouseButton1Click:Connect(function() setOpen(not opened) end)

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
	local kw = TOUCH and 108 or 96
	local kh = TOUCH and 30 or 24

	local row = self:_row(ROW_H)
	rowLabel(row, o.Name, -(kw + 8))
	local btn = make("TextButton", {
		Size = UDim2.fromOffset(kw, kh), Position = UDim2.new(1, -kw, 0.5, -kh / 2),
		BackgroundColor3 = C.Fill, BackgroundTransparency = C.FillT, BorderSizePixel = 0,
		AutoButtonColor = false, Text = "",
	}, row)
	corner(btn, 8)
	local btnLbl = make("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "",
		TextColor3 = C.Text, Font = C.Font, TextSize = 12,
	}, btn)

	local function render()
		if listening then
			btnLbl.Text = "press a key"
			btnLbl.TextColor3 = C.Accent
		else
			btnLbl.Text = current and current.Name or "none"
			btnLbl.TextColor3 = C.Text
		end
	end

	local function set(v, silent)
		current = resolveKey(v, nil)
		listening = false
		win.Flags[key] = current and current.Name or nil
		render()
		if not silent then fire(o.Callback, current) end
	end

	btn.MouseButton1Click:Connect(function()
		listening = true
		render()
	end)

	-- Escape or Backspace clears while listening
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
	local row = self:_row(TOUCH and 60 or 54)

	make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Text = tostring(o.Name),
		TextColor3 = C.Text, Font = C.Font, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	local box = make("TextBox", {
		Size = UDim2.new(1, 0, 0, TOUCH and 32 or 28), Position = UDim2.fromOffset(0, 22),
		BackgroundColor3 = C.Fill, BackgroundTransparency = C.FillT, BorderSizePixel = 0, Text = "",
		PlaceholderText = o.Placeholder or "", PlaceholderColor3 = C.Dim,
		TextColor3 = C.Text, Font = C.Font, TextSize = 13, ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	corner(box, 9)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, box)
	local focusStroke = stroke(box, 0.7)

	box.Focused:Connect(function() tween(focusStroke, T_FAST, { Color = C.Accent, Transparency = 0.2 }) end)

	local function set(v, silent)
		local s = v == nil and "" or tostring(v)
		box.Text = s
		last = s
		win.Flags[key] = s
		if not silent then fire(o.Callback, s) end
	end

	box.FocusLost:Connect(function()
		tween(focusStroke, T_FAST, { Color = C.Stroke, Transparency = 0.7 })
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
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = primary and Color3.new(1, 1, 1) or C.Fill,
		BackgroundTransparency = primary and 0 or C.FillT,
		BorderSizePixel = 0, AutoButtonColor = false, Text = tostring(o.Name),
		TextColor3 = C.Text, Font = C.FontBold, TextSize = 13,
	}, row)
	corner(b, 9)
	if primary then accentGrad(b) end
	local sc = make("UIScale", { Scale = 1 }, b)

	b.MouseEnter:Connect(function()
		if not primary then tween(b, T_FAST, { BackgroundColor3 = C.Hover }) end
	end)
	b.MouseLeave:Connect(function()
		if not primary then tween(b, T_FAST, { BackgroundColor3 = C.Fill }) end
	end)
	b.MouseButton1Down:Connect(function() tween(sc, T_PRESS, { Scale = 0.95 }) end)
	b.MouseButton1Up:Connect(function() tween(sc, T_SPRING, { Scale = 1 }) end)
	b.MouseButton1Click:Connect(function() fire(o.Callback) end)
	return b
end

function Section:AddLabel(text)
	local row = self:_row(18)
	local l = make("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = tostring(text or ""),
		TextColor3 = C.Dim, Font = C.Font, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)
	return { Set = function(t) l.Text = tostring(t) end }
end

function Window:Notify(text, seconds)
	self._toastN = self._toastN + 1
	local msg = tostring(text)
	local tw = math.min(viewport().X - 32, #msg * 7 + 36)
	local cg = make("CanvasGroup", {
		Size = UDim2.fromOffset(tw, TOUCH and 36 or 30), BackgroundColor3 = C.Bg,
		BackgroundTransparency = C.GlassT, BorderSizePixel = 0, GroupTransparency = 1,
		LayoutOrder = self._toastN,
	}, self._toasts)
	corner(cg, 10)
	stroke(cg, 0.6)
	make("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = msg,
		TextColor3 = C.Text, Font = C.Font, TextSize = 13,
	}, cg)
	tween(cg, T_MED, { GroupTransparency = 0 })
	task.delay(seconds or 2.5, function()
		if not cg.Parent then return end
		local t = tween(cg, T_MED, { GroupTransparency = 1 })
		t.Completed:Connect(function() cg:Destroy() end)
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
	local tab = self:AddTab("Config")
	local sec = tab:AddSection("Profile")

	local row = sec:_row(ROW_H)
	local box = make("TextBox", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.Fill, BackgroundTransparency = C.FillT,
		BorderSizePixel = 0, Text = "default", PlaceholderText = "profile name",
		PlaceholderColor3 = C.Dim, TextColor3 = C.Text, Font = C.Font, TextSize = 13,
		ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	corner(box, 9)
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
	for _, t in ipairs(self._anims) do t:Cancel() end
	self._anims = {}
	if self._blur then self._blur:Destroy() end
	if self.gui then self.gui:Destroy() end
	if self.launcherGui then self.launcherGui:Destroy() end
	local env = getgenv and getgenv() or _G
	if env.CrezUI_Window == self then env.CrezUI_Window = nil end
end

return Window
