Core.init({
	get = function(settingKey)
		return plugin:GetSetting(settingKey)
	end,
	set = function(settingKey, value)
		plugin:SetSetting(settingKey, value)
	end,
})

local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, true, 380, 500, 340, 420)
local widget = plugin:CreateDockWidgetPluginGui("WorkasaveWidget", widgetInfo)
widget.Title = "Workasave"
widget.Name = "Workasave"

local userInterface = buildUI(widget, Core)

local TOOLBAR_ICON = "rbxassetid://108447167291430"

local toolbar = plugin:CreateToolbar("Workasave")
local toolbarButton = toolbar:CreateButton("Workasave", "Save and load your game environment", TOOLBAR_ICON, "Workasave")
toolbarButton.ClickableWhenViewportHidden = true

toolbarButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toolbarButton:SetActive(widget.Enabled)
	if widget.Enabled then
		userInterface.refresh()
	end
end)
toolbarButton:SetActive(widget.Enabled)

plugin.Unloading:Connect(function()
	userInterface.destroy()
end)
