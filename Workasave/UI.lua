local StudioSettings = settings().Studio
local DEFAULT_MODIFIER = Enum.StudioStyleGuideModifier.Default

local MODE_DESCRIPTIONS = {
	merge = "Adds what is missing and updates only what changed (scripts, values, properties). "
		.. "Anything extra in this place is kept.",
	replace = "Deletes the current contents of the ticked services and loads the save, "
		.. "so this place matches the save exactly.",
}

local function buildUI(rootGui, Core)
	local connections = {}
	local themedStyles = {}

	local function themeColor(guideName, modifier)
		local ok, color = pcall(function()
			return StudioSettings.Theme:GetColor(Enum.StudioStyleGuideColor[guideName], modifier or DEFAULT_MODIFIER)
		end)
		return ok and color or Color3.fromRGB(128, 128, 128)
	end

	local function addStyle(instance, restyleFunction)
		table.insert(themedStyles, { instance, restyleFunction })
		restyleFunction()
		return restyleFunction
	end

	local function restyleEverything()
		for i = #themedStyles, 1, -1 do
			local style = themedStyles[i]
			if style[1]:IsDescendantOf(rootGui) then
				style[2]()
			else
				table.remove(themedStyles, i)
			end
		end
	end
	table.insert(connections, StudioSettings.ThemeChanged:Connect(restyleEverything))

	local function connect(signal, handler)
		table.insert(connections, signal:Connect(handler))
	end

	local function createInstance(className, properties, parent)
		local instance = Instance.new(className)
		if instance:IsA("GuiObject") then
			instance.BorderSizePixel = 0
		end
		for propertyName, value in properties do
			instance[propertyName] = value
		end
		instance.Parent = parent
		return instance
	end

	local function addPadding(parent, pixels)
		createInstance("UIPadding", {
			PaddingLeft = UDim.new(0, pixels), PaddingRight = UDim.new(0, pixels),
			PaddingTop = UDim.new(0, pixels), PaddingBottom = UDim.new(0, pixels),
		}, parent)
	end

	local function createLabel(parent, text, properties, guideName)
		local label = createInstance("TextLabel", {
			BackgroundTransparency = 1,
			Text = text,
			Font = Enum.Font.SourceSans,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, parent)
		for propertyName, value in properties or {} do
			label[propertyName] = value
		end
		addStyle(label, function()
			label.TextColor3 = themeColor(guideName or "MainText")
		end)
		return label
	end

	local function createButton(parent, text, isPrimary)
		local button = createInstance("TextButton", {
			Text = text,
			Font = Enum.Font.SourceSansSemibold,
			TextSize = 14,
			AutoButtonColor = false,
			Size = UDim2.fromOffset(0, 28),
			AutomaticSize = Enum.AutomaticSize.X,
			BorderSizePixel = 1,
		}, parent)
		createInstance("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, button)
		createInstance("UICorner", { CornerRadius = UDim.new(0, 4) }, button)
		local isHovered, isDisabled = false, false
		local restyle = addStyle(button, function()
			local modifier = DEFAULT_MODIFIER
			if isDisabled then
				modifier = Enum.StudioStyleGuideModifier.Disabled
			elseif isHovered then
				modifier = Enum.StudioStyleGuideModifier.Hover
			end
			button.BackgroundColor3 = themeColor(isPrimary and "DialogMainButton" or "Button", modifier)
			button.TextColor3 = themeColor(isPrimary and "DialogMainButtonText" or "ButtonText", modifier)
			button.BorderColor3 = themeColor("ButtonBorder", modifier)
		end)
		connect(button.MouseEnter, function()
			isHovered = true
			restyle()
		end)
		connect(button.MouseLeave, function()
			isHovered = false
			restyle()
		end)
		return button, function(disabled)
			isDisabled = disabled
			button.Active = not disabled
			restyle()
		end
	end

	local function placeBar(bar, fromX, fromY, toX, toY)
		local deltaX, deltaY = toX - fromX, toY - fromY
		local thickness = bar.Size.Y.Offset
		bar.Size = UDim2.fromOffset(math.sqrt(deltaX * deltaX + deltaY * deltaY) + thickness * 0.6, thickness)
		bar.Position = UDim2.fromOffset((fromX + toX) / 2, (fromY + toY) / 2)
		bar.Rotation = math.deg(math.atan2(deltaY, deltaX))
	end

	local function createIcon(parent, width, height, thickness, guideName)
		local container = createInstance("Frame", {
			Size = UDim2.fromOffset(width, height), BackgroundTransparency = 1,
		}, parent)
		local function recolor()
			for _, child in container:GetChildren() do
				if child:GetAttribute("IconBar") then
					child.BackgroundColor3 = themeColor(guideName)
				end
			end
		end
		addStyle(container, recolor)
		return {
			instance = container,
			draw = function(lines)
				for _, child in container:GetChildren() do
					if child:GetAttribute("IconBar") then
						child:Destroy()
					end
				end
				for _, points in lines do
					for i = 1, #points - 1 do
						local bar = createInstance("Frame", {
							AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(0, thickness),
						}, container)
						bar:SetAttribute("IconBar", true)
						placeBar(bar, points[i][1], points[i][2], points[i + 1][1], points[i + 1][2])
					end
				end
				recolor()
			end,
		}
	end

	local CHEVRON_LINES = {
		right = { { { 4, 1 }, { 10, 7 }, { 4, 13 } } },
		left = { { { 10, 1 }, { 4, 7 }, { 10, 13 } } },
		down = { { { 1, 4 }, { 7, 10 }, { 13, 4 } } },
	}
	local TRAY_LINES = { { 5, 19 }, { 5, 27 }, { 27, 27 }, { 27, 19 } }
	local SAVE_ICON_LINES = { { { 16, 4 }, { 16, 19 } }, { { 9, 13 }, { 16, 20 }, { 23, 13 } }, TRAY_LINES }
	local LOAD_ICON_LINES = { { { 16, 20 }, { 16, 5 } }, { { 9, 12 }, { 16, 5 }, { 23, 12 } }, TRAY_LINES }
	local CHECK_LINES = { { { 4, 9.5 }, { 7.5, 13 }, { 14, 5.5 } } }

	local function createChevron(parent, direction, guideName)
		local icon = createIcon(parent, 14, 14, 2, guideName or "SubText")
		icon.draw(CHEVRON_LINES[direction])
		return {
			instance = icon.instance,
			setDirection = function(newDirection)
				icon.draw(CHEVRON_LINES[newDirection])
			end,
		}
	end

	local function createCheckbox(parent, initialValue, onChanged)
		local isChecked = initialValue
		local box = createInstance("TextButton", {
			Size = UDim2.fromOffset(18, 18),
			Text = "",
			AutoButtonColor = false,
			BorderSizePixel = 1,
		}, parent)
		createInstance("UICorner", { CornerRadius = UDim.new(0, 3) }, box)
		local checkIcon = createIcon(box, 18, 18, 2, "CheckedFieldIndicator")
		checkIcon.draw(CHECK_LINES)
		local restyle = addStyle(box, function()
			box.BackgroundColor3 = themeColor(isChecked and "CheckedFieldBackground" or "InputFieldBackground")
			box.BorderColor3 = themeColor(isChecked and "CheckedFieldBorder" or "InputFieldBorder")
			checkIcon.instance.Visible = isChecked
		end)
		connect(box.MouseButton1Click, function()
			isChecked = not isChecked
			restyle()
			if onChanged then
				onChanged(isChecked)
			end
		end)
		return {
			instance = box,
			get = function()
				return isChecked
			end,
			set = function(value)
				isChecked = value
				restyle()
			end,
		}
	end

	local function createScrollList(parent, properties)
		local list = createInstance("ScrollingFrame", {
			BackgroundTransparency = 1,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 8,
			ScrollingDirection = Enum.ScrollingDirection.Y,
		}, parent)
		for propertyName, value in properties do
			list[propertyName] = value
		end
		createInstance("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, list)
		addStyle(list, function()
			list.ScrollBarImageColor3 = themeColor("ScrollBar")
		end)
		return list
	end

	local function clearChildren(frame)
		for _, child in frame:GetChildren() do
			if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
				child:Destroy()
			end
		end
	end

	local function escapeRichText(text)
		return (text:gsub("[<>&]", { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;" }))
	end

	local function dimText(text)
		return ('<font transparency="0.5">%s</font>'):format(text)
	end

	local HEADER_HEIGHT = 36
	local STATUS_HEIGHT = 30

	local mainFrame = createInstance("Frame", { Size = UDim2.fromScale(1, 1) }, rootGui)
	addStyle(mainFrame, function()
		mainFrame.BackgroundColor3 = themeColor("MainBackground")
	end)

	local headerFrame = createInstance("Frame", { Size = UDim2.new(1, 0, 0, HEADER_HEIGHT) }, mainFrame)
	addStyle(headerFrame, function()
		headerFrame.BackgroundColor3 = themeColor("TabBar")
	end)
	local backButton = createInstance("TextButton", {
		Text = "Back",
		Font = Enum.Font.SourceSansSemibold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.fromOffset(70, HEADER_HEIGHT),
		Visible = false,
	}, headerFrame)
	createInstance("UIPadding", { PaddingLeft = UDim.new(0, 20) }, backButton)
	local backChevron = createChevron(backButton, "left", "LinkText")
	backChevron.instance.Position = UDim2.new(0, -18, 0.5, -7)
	addStyle(backButton, function()
		backButton.TextColor3 = themeColor("LinkText")
	end)
	local titleLabel = createLabel(headerFrame, "Workasave", {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.SourceSansBold,
		TextSize = 17,
	})

	local viewsFrame = createInstance("Frame", {
		Position = UDim2.fromOffset(0, HEADER_HEIGHT),
		Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + STATUS_HEIGHT)),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, mainFrame)

	local statusFrame = createInstance("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, STATUS_HEIGHT),
	}, mainFrame)
	addStyle(statusFrame, function()
		statusFrame.BackgroundColor3 = themeColor("TabBar")
	end)
	local statusLabel = createLabel(statusFrame, "Ready", {
		Position = UDim2.fromOffset(10, 2), Size = UDim2.new(1, -20, 0, 18), TextSize = 13,
	}, "SubText")
	local progressTrack = createInstance("Frame", {
		Position = UDim2.new(0, 10, 1, -7), Size = UDim2.new(1, -20, 0, 3),
	}, statusFrame)
	local progressFill = createInstance("Frame", { Size = UDim2.fromScale(0, 1) }, progressTrack)
	addStyle(progressTrack, function()
		progressTrack.BackgroundColor3 = themeColor("InputFieldBackground")
		progressFill.BackgroundColor3 = themeColor("DialogMainButton")
	end)

	local function setStatus(text, fraction)
		statusLabel.Text = text
		progressFill.Size = UDim2.fromScale(math.clamp(fraction or 0, 0, 1), 1)
	end

	local dialogOverlay = createInstance("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Visible = false,
		Active = true,
		ZIndex = 20,
	}, mainFrame)
	local dialogBox = createInstance("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -32, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 1,
		ZIndex = 21,
	}, dialogOverlay)
	createInstance("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, dialogBox)
	addPadding(dialogBox, 12)
	createInstance("UICorner", { CornerRadius = UDim.new(0, 6) }, dialogBox)
	addStyle(dialogBox, function()
		dialogBox.BackgroundColor3 = themeColor("MainBackground")
		dialogBox.BorderColor3 = themeColor("Border")
	end)
	local dialogTitle = createLabel(dialogBox, "", {
		Size = UDim2.new(1, 0, 0, 20), Font = Enum.Font.SourceSansBold, TextSize = 17, ZIndex = 22, LayoutOrder = 1,
	})
	local dialogBody = createLabel(dialogBox, "", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true, TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 22, LayoutOrder = 2,
	})
	local dialogChoices = createScrollList(dialogBox, {
		Size = UDim2.new(1, 0, 0, 0), ZIndex = 22, LayoutOrder = 3, Visible = false,
	})
	local dialogButtonRow = createInstance("Frame", {
		Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, ZIndex = 22, LayoutOrder = 4,
	}, dialogBox)
	createInstance("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, dialogButtonRow)

	local function showDialog(title, body, buttonDefinitions, choiceLabels)
		clearChildren(dialogButtonRow)
		clearChildren(dialogChoices)
		dialogTitle.Text = title
		dialogBody.Text = body
		dialogBody.Visible = body ~= ""
		local answered = Instance.new("BindableEvent")
		for number, definition in buttonDefinitions do
			local button = createButton(dialogButtonRow, definition.text, definition.primary)
			button.ZIndex = 23
			button.LayoutOrder = number
			button.MouseButton1Click:Once(function()
				answered:Fire(number, nil)
			end)
		end
		dialogChoices.Visible = choiceLabels ~= nil
		if choiceLabels then
			dialogChoices.Size = UDim2.new(1, 0, 0, math.min(#choiceLabels * 30, 210))
			for number, labelText in choiceLabels do
				local choiceButton = createButton(dialogChoices, labelText, false)
				choiceButton.AutomaticSize = Enum.AutomaticSize.None
				choiceButton.Size = UDim2.new(1, -8, 0, 28)
				choiceButton.TextXAlignment = Enum.TextXAlignment.Left
				choiceButton.ZIndex = 23
				choiceButton.LayoutOrder = number
				choiceButton.MouseButton1Click:Once(function()
					answered:Fire(0, number)
				end)
			end
		end
		dialogOverlay.Visible = true
		local buttonNumber, choiceNumber = answered.Event:Wait()
		dialogOverlay.Visible = false
		answered:Destroy()
		return buttonNumber, choiceNumber
	end

	local function showMessage(title, body)
		showDialog(title, body, { { text = "OK", primary = true } })
	end

	local isBusy = false
	local busyAwareSetters = {}

	local function setBusy(value)
		isBusy = value
		for _, setDisabled in busyAwareSetters do
			setDisabled(value)
		end
	end

	local function runWhileBusy(work)
		if isBusy then
			return
		end
		setBusy(true)
		task.spawn(function()
			local ok, errorMessage = pcall(work)
			setBusy(false)
			if not ok then
				setStatus("Failed", 0)
				warn("[Workasave] " .. tostring(errorMessage))
				showMessage("Something went wrong", tostring(errorMessage))
			end
		end)
	end

	local VIEW_TITLES = { home = "Workasave", save = "Save", loadList = "Load", loadDetail = "Load" }
	local BACK_TARGETS = { save = "home", loadList = "home", loadDetail = "loadList" }

	local views = {}
	for _, viewName in { "home", "save", "loadList", "loadDetail" } do
		views[viewName] = createInstance("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false,
		}, viewsFrame)
	end

	local currentView = "home"
	local refreshHome, refreshSave, refreshLoadList, refreshLoadDetail

	local function showView(viewName)
		currentView = viewName
		for name, frame in views do
			frame.Visible = name == viewName
		end
		backButton.Visible = viewName ~= "home"
		titleLabel.Text = VIEW_TITLES[viewName]
		if viewName == "home" then
			refreshHome()
		elseif viewName == "save" then
			refreshSave()
		elseif viewName == "loadList" then
			refreshLoadList()
		elseif viewName == "loadDetail" then
			refreshLoadDetail()
		end
	end

	connect(backButton.MouseButton1Click, function()
		if not isBusy then
			showView(BACK_TARGETS[currentView] or "home")
		end
	end)

	local homeView = views.home
	createInstance("UIListLayout", {
		Padding = UDim.new(0, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, homeView)
	createLabel(homeView, "Save your game environment and bring it to any place.", {
		Size = UDim2.new(1, -48, 0, 40), TextWrapped = true, TextTruncate = Enum.TextTruncate.None,
		TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1,
	}, "SubText")

	local function createMenuCard(text, layoutOrder, iconLines)
		local card = createInstance("TextButton", {
			Size = UDim2.new(1, -48, 0, 68), Text = "", AutoButtonColor = false,
			BorderSizePixel = 1, LayoutOrder = layoutOrder,
		}, homeView)
		createInstance("UICorner", { CornerRadius = UDim.new(0, 6) }, card)
		local cardIcon = createIcon(card, 32, 32, 2.5, "DialogMainButton")
		cardIcon.instance.Position = UDim2.new(0, 14, 0.5, -16)
		cardIcon.draw(iconLines)
		local isHovered = false
		local restyle = addStyle(card, function()
			card.BackgroundColor3 = themeColor("Button", isHovered and Enum.StudioStyleGuideModifier.Hover or DEFAULT_MODIFIER)
			card.BorderColor3 = themeColor("ButtonBorder")
		end)
		connect(card.MouseEnter, function()
			isHovered = true
			restyle()
		end)
		connect(card.MouseLeave, function()
			isHovered = false
			restyle()
		end)
		createLabel(card, text, {
			Position = UDim2.fromOffset(60, 10), Size = UDim2.new(1, -72, 0, 26),
			Font = Enum.Font.SourceSansBold, TextSize = 20,
		})
		local detailLabel = createLabel(card, "", {
			Position = UDim2.fromOffset(60, 38), Size = UDim2.new(1, -72, 0, 18),
		}, "SubText")
		return card, detailLabel
	end

	local saveCard, saveCardDetail = createMenuCard("Save", 2, SAVE_ICON_LINES)
	local loadCard, loadCardDetail = createMenuCard("Load", 3, LOAD_ICON_LINES)
	saveCardDetail.Text = "Store this place's services, scripts and settings"

	function refreshHome()
		local count = #Core.list()
		loadCardDetail.Text = count == 0 and "No saves yet" or (count .. (count == 1 and " save" or " saves") .. " available")
	end

	connect(saveCard.MouseButton1Click, function()
		showView("save")
	end)
	connect(loadCard.MouseButton1Click, function()
		showView("loadList")
	end)

	local saveView = views.save
	local saveTargetId = nil

	local targetButton = createButton(saveView, "New save")
	targetButton.Position = UDim2.fromOffset(8, 8)
	targetButton.Size = UDim2.new(1, -16, 0, 28)
	targetButton.AutomaticSize = Enum.AutomaticSize.None
	targetButton.TextXAlignment = Enum.TextXAlignment.Left
	targetButton:FindFirstChildOfClass("UIPadding").PaddingRight = UDim.new(0, 30)
	local targetChevron = createChevron(targetButton, "down", "ButtonText")
	targetChevron.instance.AnchorPoint = Vector2.new(1, 0.5)
	targetChevron.instance.Position = UDim2.new(1, 18, 0.5, 0)

	local nameBox = createInstance("TextBox", {
		Position = UDim2.fromOffset(8, 42),
		Size = UDim2.new(1, -16, 0, 28),
		Text = "",
		PlaceholderText = "Name this save",
		ClearTextOnFocus = false,
		Font = Enum.Font.SourceSans,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		BorderSizePixel = 1,
	}, saveView)
	createInstance("UIPadding", { PaddingLeft = UDim.new(0, 8) }, nameBox)
	createInstance("UICorner", { CornerRadius = UDim.new(0, 4) }, nameBox)
	addStyle(nameBox, function()
		nameBox.BackgroundColor3 = themeColor("InputFieldBackground")
		nameBox.BorderColor3 = themeColor("InputFieldBorder")
		nameBox.TextColor3 = themeColor("MainText")
		nameBox.PlaceholderColor3 = themeColor("DimmedText")
	end)

	local overwriteHint = createLabel(saveView, "", {
		Position = UDim2.fromOffset(10, 74), Size = UDim2.new(1, -20, 0, 30),
		TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextSize = 12,
		TextYAlignment = Enum.TextYAlignment.Top, Visible = false,
	}, "SubText")

	local selectionRow = createInstance("Frame", {
		Position = UDim2.fromOffset(8, 106), Size = UDim2.new(1, -16, 0, 26), BackgroundTransparency = 1,
	}, saveView)
	createInstance("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
	}, selectionRow)
	local selectAllButton = createButton(selectionRow, "All")
	local selectNoneButton = createButton(selectionRow, "None")
	local selectionCountLabel = createLabel(selectionRow, "", { Size = UDim2.fromOffset(110, 26), LayoutOrder = 10 }, "SubText")

	local serviceList = createScrollList(saveView, {
		Position = UDim2.fromOffset(8, 136),
		Size = UDim2.new(1, -16, 1, -136 - 48),
	})
	local saveButton, setSaveButtonDisabled = createButton(saveView, "Save", true)
	saveButton.AnchorPoint = Vector2.new(0, 1)
	saveButton.Position = UDim2.new(0, 8, 1, -8)
	saveButton.Size = UDim2.new(1, -16, 0, 34)
	saveButton.AutomaticSize = Enum.AutomaticSize.None
	table.insert(busyAwareSetters, setSaveButtonDisabled)

	local serviceCheckboxes = {}
	local expandedServices = {}
	local MAX_ITEMS_SHOWN = 100

	local function updateSelectionCount()
		local selected = 0
		for _, checkbox in serviceCheckboxes do
			if checkbox.get() then
				selected += 1
			end
		end
		selectionCountLabel.Text = selected .. " selected"
	end

	local function updateSaveTarget()
		local target = Core.find(saveTargetId)
		if saveTargetId and not target then
			saveTargetId = nil
		end
		targetButton.Text = target and ("Overwrite: " .. target.name) or "New save"
		saveButton.Text = target and "Overwrite save" or "Save"
		overwriteHint.Visible = target ~= nil
		overwriteHint.Text = "Ticked services replace their copy in this save. "
			.. "Services you don't tick stay in the save as they are."
		selectionRow.Position = UDim2.fromOffset(8, target and 106 or 78)
		serviceList.Position = UDim2.fromOffset(8, target and 136 or 108)
		serviceList.Size = UDim2.new(1, -16, 1, -(target and 136 or 108) - 48)
	end

	function refreshSave()
		local previousChoices = {}
		for serviceName, checkbox in serviceCheckboxes do
			previousChoices[serviceName] = checkbox.get()
		end
		serviceCheckboxes = {}
		clearChildren(serviceList)
		updateSaveTarget()

		for order, serviceInfo in Core.describe() do
			local rowFrame = createInstance("Frame", {
				Size = UDim2.new(1, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1, LayoutOrder = order,
			}, serviceList)
			createInstance("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, rowFrame)
			local headerRow = createInstance("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = 1 }, rowFrame)

			local startsChecked = previousChoices[serviceInfo.name]
			if startsChecked == nil then
				startsChecked = true
			end
			local checkbox = createCheckbox(headerRow, startsChecked, updateSelectionCount)
			checkbox.instance.Position = UDim2.new(0, 4, 0.5, -9)
			serviceCheckboxes[serviceInfo.name] = checkbox

			local hasItems = #serviceInfo.items > 0 or #serviceInfo.skipped > 0
			local arrowButton = createInstance("TextButton", {
				Position = UDim2.fromOffset(28, 0), Size = UDim2.fromOffset(20, 26),
				BackgroundTransparency = 1, Text = "", Active = hasItems,
			}, headerRow)
			local arrowChevron = createChevron(arrowButton, expandedServices[serviceInfo.name] and "down" or "right")
			arrowChevron.instance.Position = UDim2.new(0.5, -7, 0.5, -7)
			arrowChevron.instance.Visible = hasItems

			local summary = "properties only"
			if #serviceInfo.items > 0 then
				summary = #serviceInfo.items .. (#serviceInfo.items == 1 and " item" or " items")
			end
			createLabel(headerRow, serviceInfo.name .. "  " .. dimText(summary), {
				Position = UDim2.fromOffset(50, 0), Size = UDim2.new(1, -54, 1, 0), RichText = true,
			})

			local itemsFrame = nil
			local function rebuildItems()
				if itemsFrame then
					itemsFrame:Destroy()
					itemsFrame = nil
				end
				if not expandedServices[serviceInfo.name] then
					return
				end
				itemsFrame = createInstance("Frame", {
					Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1, LayoutOrder = 2,
				}, rowFrame)
				createInstance("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, itemsFrame)
				for number, item in serviceInfo.items do
					if number > MAX_ITEMS_SHOWN then
						createLabel(itemsFrame, ("... and %d more"):format(#serviceInfo.items - MAX_ITEMS_SHOWN), {
							Size = UDim2.new(1, 0, 0, 20), LayoutOrder = number,
						}, "DimmedText").Position = UDim2.fromOffset(52, 0)
						break
					end
					local itemLabel = createLabel(itemsFrame, escapeRichText(item.name) .. "  " .. dimText(item.class), {
						Size = UDim2.new(1, 0, 0, 20), LayoutOrder = number, RichText = true,
					})
					createInstance("UIPadding", { PaddingLeft = UDim.new(0, 52) }, itemLabel)
				end
				for number, containerName in serviceInfo.skipped do
					local skippedLabel = createLabel(itemsFrame, containerName .. "  (contains parts, not saved)", {
						Size = UDim2.new(1, 0, 0, 20), LayoutOrder = MAX_ITEMS_SHOWN + number,
					}, "WarningText")
					createInstance("UIPadding", { PaddingLeft = UDim.new(0, 52) }, skippedLabel)
				end
			end
			rebuildItems()
			if hasItems then
				connect(arrowButton.MouseButton1Click, function()
					expandedServices[serviceInfo.name] = not expandedServices[serviceInfo.name] or nil
					arrowChevron.setDirection(expandedServices[serviceInfo.name] and "down" or "right")
					rebuildItems()
				end)
			end
		end
		updateSelectionCount()
	end

	connect(selectAllButton.MouseButton1Click, function()
		for _, checkbox in serviceCheckboxes do
			checkbox.set(true)
		end
		updateSelectionCount()
	end)
	connect(selectNoneButton.MouseButton1Click, function()
		for _, checkbox in serviceCheckboxes do
			checkbox.set(false)
		end
		updateSelectionCount()
	end)

	connect(targetButton.MouseButton1Click, function()
		if isBusy then
			return
		end
		task.spawn(function()
			local entries, labels = {}, { "New save" }
			for _, entry in Core.list() do
				if not entry.auto then
					table.insert(entries, entry)
					table.insert(labels, ("%s   (%s)"):format(entry.name, os.date("%b %d, %H:%M", entry.created)))
				end
			end
			local _, choice = showDialog("Save to", "", { { text = "Cancel" } }, labels)
			if choice == nil then
				return
			end
			if choice == 1 then
				saveTargetId = nil
				nameBox.Text = ""
			else
				saveTargetId = entries[choice - 1].id
				nameBox.Text = entries[choice - 1].name
			end
			updateSaveTarget()
		end)
	end)

	local function appendWarnings(lines, warnings, limit)
		for number, warning in warnings do
			if number > limit then
				table.insert(lines, ("... and %d more"):format(#warnings - limit))
				break
			end
			table.insert(lines, "- " .. warning)
		end
	end

	connect(saveButton.MouseButton1Click, function()
		if isBusy then
			return
		end
		local chosenServices = {}
		for _, serviceName in Core.ServiceNames do
			local checkbox = serviceCheckboxes[serviceName]
			if checkbox and checkbox.get() then
				table.insert(chosenServices, serviceName)
			end
		end
		if #chosenServices == 0 then
			task.spawn(showMessage, "Nothing selected", "Tick at least one service to save.")
			return
		end
		local target = Core.find(saveTargetId)
		local saveName = nameBox.Text:match("^%s*(.-)%s*$")
		if saveName == "" then
			saveName = target and target.name or ("%s - %s"):format(game.Name, os.date("%b %d, %H:%M"))
		end
		task.spawn(function()
			if target then
				local choice = showDialog("Overwrite save?", ('"%s" will be updated with the %d ticked %s. Their old copy in this save is replaced.')
					:format(target.name, #chosenServices, #chosenServices == 1 and "service" or "services"),
					{ { text = "Cancel" }, { text = "Overwrite", primary = true } })
				if choice ~= 2 then
					return
				end
			end
			runWhileBusy(function()
				local entry, warnings = Core.save(saveName, chosenServices, setStatus, nil, target and target.id or nil)
				setStatus(('Saved "%s"'):format(entry.name), 1)
				saveTargetId = nil
				nameBox.Text = ""
				local lines = {
					('"%s" is saved.'):format(entry.name),
					("Size: %s (%s before compression)"):format(Core.formatBytes(entry.storedBytes), Core.formatBytes(entry.rawBytes)),
				}
				if #warnings > 0 then
					table.insert(lines, "")
					table.insert(lines, "Notes:")
					appendWarnings(lines, warnings, 8)
				end
				showMessage("Save complete", table.concat(lines, "\n"))
				refreshSave()
			end)
		end)
	end)

	local loadListView = views.loadList
	local selectedEntryId = nil

	local emptyLoadLabel = createLabel(loadListView, "No saves yet.\nGo back and choose Save to create one.", {
		Position = UDim2.fromOffset(12, 16), Size = UDim2.new(1, -24, 0, 50), TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top,
	}, "SubText")
	local saveCardList = createScrollList(loadListView, {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 1, -16),
	})

	function refreshLoadList()
		local entries = Core.list()
		clearChildren(saveCardList)
		emptyLoadLabel.Visible = #entries == 0
		saveCardList.Visible = #entries > 0
		for order, entry in entries do
			local card = createInstance("TextButton", {
				Size = UDim2.new(1, -4, 0, 56), Text = "", AutoButtonColor = false,
				BorderSizePixel = 1, LayoutOrder = order,
			}, saveCardList)
			createInstance("UICorner", { CornerRadius = UDim.new(0, 5) }, card)
			local isHovered = false
			local restyle = addStyle(card, function()
				card.BackgroundColor3 = themeColor("Button", isHovered and Enum.StudioStyleGuideModifier.Hover or DEFAULT_MODIFIER)
				card.BorderColor3 = themeColor("ButtonBorder")
			end)
			connect(card.MouseEnter, function()
				isHovered = true
				restyle()
			end)
			connect(card.MouseLeave, function()
				isHovered = false
				restyle()
			end)
			createLabel(card, (entry.auto and "[backup]  " or "") .. entry.name, {
				Position = UDim2.fromOffset(10, 5), Size = UDim2.new(1, -20, 0, 20),
				Font = Enum.Font.SourceSansSemibold, TextSize = 15,
			})
			local serviceCount = 0
			for _ in entry.services do
				serviceCount += 1
			end
			createLabel(card, ("%s  |  %d services  |  %s"):format(
				os.date("%b %d %Y, %H:%M", entry.created), serviceCount, Core.formatBytes(entry.storedBytes)), {
				Position = UDim2.fromOffset(10, 26), Size = UDim2.new(1, -20, 0, 14), TextSize = 13,
			}, "SubText")
			createLabel(card, "from " .. tostring(entry.placeName or "unknown place"), {
				Position = UDim2.fromOffset(10, 39), Size = UDim2.new(1, -20, 0, 14), TextSize = 12,
			}, "DimmedText")
			connect(card.MouseButton1Click, function()
				if not isBusy then
					selectedEntryId = entry.id
					showView("loadDetail")
				end
			end)
		end
	end

	local loadDetailView = views.loadDetail
	local loadMode = "replace"

	local detailTitleLabel = createLabel(loadDetailView, "", {
		Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 22),
		Font = Enum.Font.SourceSansBold, TextSize = 16,
	})
	local detailInfoLabel = createLabel(loadDetailView, "", {
		Position = UDim2.fromOffset(10, 30), Size = UDim2.new(1, -20, 0, 16), TextSize = 13,
	}, "SubText")

	local modeRow = createInstance("Frame", {
		Position = UDim2.fromOffset(8, 54), Size = UDim2.new(1, -16, 0, 28), BackgroundTransparency = 1,
	}, loadDetailView)
	createInstance("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
	}, modeRow)
	local replaceButton = createButton(modeRow, "Replace")
	local mergeButton = createButton(modeRow, "Merge")
	replaceButton.LayoutOrder = 1
	mergeButton.LayoutOrder = 2
	local modeDescriptionLabel = createLabel(loadDetailView, "", {
		Position = UDim2.fromOffset(10, 86), Size = UDim2.new(1, -20, 0, 48),
		TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextSize = 12,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, "SubText")

	local function updateModeButtons()
		mergeButton.Font = loadMode == "merge" and Enum.Font.SourceSansBold or Enum.Font.SourceSans
		replaceButton.Font = loadMode == "replace" and Enum.Font.SourceSansBold or Enum.Font.SourceSans
		mergeButton.BorderSizePixel = loadMode == "merge" and 2 or 1
		replaceButton.BorderSizePixel = loadMode == "replace" and 2 or 1
		modeDescriptionLabel.Text = MODE_DESCRIPTIONS[loadMode]
	end
	connect(mergeButton.MouseButton1Click, function()
		loadMode = "merge"
		updateModeButtons()
	end)
	connect(replaceButton.MouseButton1Click, function()
		loadMode = "replace"
		updateModeButtons()
	end)

	local loadServiceList = createScrollList(loadDetailView, {
		Position = UDim2.fromOffset(8, 138),
		Size = UDim2.new(1, -16, 1, -138 - 48),
	})
	local loadActionRow = createInstance("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -8),
		Size = UDim2.new(1, -16, 0, 34), BackgroundTransparency = 1,
	}, loadDetailView)
	createInstance("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
	}, loadActionRow)
	local loadButton, setLoadButtonDisabled = createButton(loadActionRow, "Load", true)
	loadButton.Size = UDim2.fromOffset(0, 34)
	local deleteButton, setDeleteButtonDisabled = createButton(loadActionRow, "Delete save")
	deleteButton.Size = UDim2.fromOffset(0, 34)
	deleteButton.LayoutOrder = 2
	table.insert(busyAwareSetters, setLoadButtonDisabled)
	table.insert(busyAwareSetters, setDeleteButtonDisabled)

	local loadCheckboxes = {}

	function refreshLoadDetail()
		local entry = Core.find(selectedEntryId)
		if not entry then
			showView("loadList")
			return
		end
		detailTitleLabel.Text = entry.name
		detailInfoLabel.Text = ("%s  |  from %s"):format(os.date("%b %d %Y, %H:%M", entry.created), tostring(entry.placeName or "unknown place"))
		updateModeButtons()
		clearChildren(loadServiceList)
		loadCheckboxes = {}
		for order, serviceName in Core.ServiceNames do
			local serviceInfo = entry.services[serviceName]
			if serviceInfo then
				local rowFrame = createInstance("Frame", {
					Size = UDim2.new(1, -4, 0, 24), BackgroundTransparency = 1, LayoutOrder = order,
				}, loadServiceList)
				local checkbox = createCheckbox(rowFrame, true)
				checkbox.instance.Position = UDim2.new(0, 4, 0.5, -9)
				loadCheckboxes[serviceName] = checkbox
				local summary = "properties only"
				if serviceInfo.itemCount and serviceInfo.itemCount > 0 then
					summary = serviceInfo.itemCount .. (serviceInfo.itemCount == 1 and " item" or " items")
				end
				createLabel(rowFrame, serviceName .. "  " .. dimText(summary), {
					Position = UDim2.fromOffset(30, 0), Size = UDim2.new(1, -34, 1, 0), RichText = true,
				})
			end
		end
	end

	connect(deleteButton.MouseButton1Click, function()
		if isBusy then
			return
		end
		local entry = Core.find(selectedEntryId)
		if not entry then
			return
		end
		task.spawn(function()
			local choice = showDialog("Delete save?", ('"%s" will be permanently removed from this computer.'):format(entry.name),
				{ { text = "Cancel" }, { text = "Delete", primary = true } })
			if choice == 2 then
				Core.delete(entry.id)
				selectedEntryId = nil
				setStatus("Deleted", 0)
				showView("loadList")
			end
		end)
	end)

	local function describeLoadResult(report)
		local lines = {}
		for _, serviceName in Core.ServiceNames do
			local stats = report.services[serviceName]
			if stats then
				if report.mode == "merge" then
					table.insert(lines, ("%s: %d updated, %d added, %d unchanged"):format(serviceName, stats.updated, stats.added, stats.unchanged))
				else
					table.insert(lines, ("%s: %d removed, %d added"):format(serviceName, stats.removed, stats.added))
				end
				if stats.properties > 0 then
					table.insert(lines, ("   %d properties changed"):format(stats.properties))
				end
				if #stats.failedProperties > 0 then
					table.insert(lines, "   could not set: " .. table.concat(stats.failedProperties, ", "))
				end
			end
		end
		if #report.warnings > 0 then
			table.insert(lines, "")
			appendWarnings(lines, report.warnings, 8)
		end
		table.insert(lines, "")
		table.insert(lines, "A backup was saved, and Ctrl+Z undoes this load.")
		return table.concat(lines, "\n")
	end

	connect(loadButton.MouseButton1Click, function()
		if isBusy then
			return
		end
		local entry = Core.find(selectedEntryId)
		if not entry then
			return
		end
		local chosenServices = {}
		for _, serviceName in Core.ServiceNames do
			local checkbox = loadCheckboxes[serviceName]
			if checkbox and checkbox.get() then
				table.insert(chosenServices, serviceName)
			end
		end
		if #chosenServices == 0 then
			task.spawn(showMessage, "Nothing selected", "Tick at least one service to load.")
			return
		end
		local mode = loadMode
		task.spawn(function()
			local question = mode == "merge" and "Merge into this place?" or "Replace current contents?"
			local body = ('%s "%s" into the CURRENT place:\n\n%s\n\nParts and models in Workspace are never touched. '
				.. "A backup is made first, and Ctrl+Z undoes the load."):format(
				mode == "merge" and "Merging" or "Replacing the contents of these services with", entry.name,
				table.concat(chosenServices, ", "))
			local choice = showDialog(question, body, {
				{ text = "Cancel" }, { text = mode == "merge" and "Merge" or "Replace", primary = true },
			})
			if choice ~= 2 then
				return
			end
			runWhileBusy(function()
				local report = Core.load(entry.id, chosenServices, mode, setStatus)
				setStatus(('Loaded "%s"'):format(entry.name), 1)
				showMessage("Load complete", describeLoadResult(report))
			end)
		end)
	end)

	showView("home")

	return {
		showView = showView,
		refresh = function()
			showView(currentView)
		end,
		destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			mainFrame:Destroy()
		end,
	}
end
