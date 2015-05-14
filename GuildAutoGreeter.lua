require "Window"
require "ICCommLib"

local GuildAutoGreeter = {}
local GuildAutoGreeterInst

local strInstructions = "Use {player} in a message to insert the player name.\n" ..
                        "To have a random message chosen, place multiple messages on separate lines."

local strAddonVersion = "1.3"

local defaultSettings =
{
  enabled = true,
  salutation = true,
  welcome = true,
  greetingThreshold = 3
}

function string:split(inSplitPattern, outResults )
   if not outResults then
      outResults = { }
   end
   local theStart = 1
   local theSplitStart, theSplitEnd = string.find( self, inSplitPattern, theStart )
   while theSplitStart do
      table.insert( outResults, string.sub( self, theStart, theSplitStart-1 ) )
      theStart = theSplitEnd + 1
      theSplitStart, theSplitEnd = string.find( self, inSplitPattern, theStart )
   end
   table.insert( outResults, string.sub( self, theStart ) )
   return outResults
end

function shallowcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

local function CPrint(string)
  ChatSystemLib.PostOnChannel(ChatSystemLib.ChatChannel_Command, string, "")
end

function GuildAutoGreeter:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

  self.strJoinedMessage = "Welcome {player}"
  self.strSalutationMessage = "Hello {player}"
  self.state = false
  self.config = defaultSettings
  self.playersGreeted = {}
  self.playersGreetedSelf = {}
  self.tQueuedData = {}
  self.strGuildChannelName = ""
  self.addon = {}

    return o
end

function GuildAutoGreeter:Init()
  local bHasConfigureFunction = false
  local strConfigureButtonText = ""
  local tDependencies = {
    -- "UnitOrPackageName",
  }
  self.addon = Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end

function GuildAutoGreeter:OnLoad()
  self.xmlDoc = XmlDoc.CreateFromFile("GuildAutoGreeter.xml")
  self.xmlDoc:RegisterCallback("OnDocLoaded", self)
end

function GuildAutoGreeter:OnDocLoaded()
  if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
      self.wndMain = Apollo.LoadForm(self.xmlDoc, "GuildAutoGreeterForm", nil, self)
    if self.wndMain == nil then
      Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
      return
    end
      self.wndMain:Show(false, true)
    self.wndMain:FindChild("Description"):SetText(strInstructions)
  end
  -- Register handlers for events, slash commands and timer, etc.
  -- e.g. Apollo.RegisterEventHandler("KeyDown", "OnKeyDown", self)
  Apollo.RegisterSlashCommand("guildautogreeter", "OnSlashCommand", self)
  Apollo.RegisterSlashCommand("autogreet", "OnSlashCommand", self)

  Apollo.RegisterEventHandler("InterfaceMenuListHasLoaded", "OnInterfaceMenuListHasLoaded", self)
  Apollo.RegisterEventHandler("Generic_ToggleGuildAutoGreeter", "OnGuildGreetOptions", self)
  Apollo.RegisterEventHandler("ChatMessage", "OnChatMessage", self)

  Apollo.RegisterTimerHandler("GreetTimer", "OnGreetTimerUpdate", self)
  Apollo.CreateTimer("GreetTimer", 4, true)
end

function GuildAutoGreeter:OnGreeterMessage(channel, tMsg)
  if type(tMsg.player) ~= "string" then
    return
  end

  -- Count greeting from another player and update the count for the greeted player
  self:IncrPlayerGreeting(tMsg.player)
end

function GuildAutoGreeter:OnGreetTimerUpdate(strVar, nValue)
  if #self.tQueuedData > 0 then
    local tMessage = self.tQueuedData[1]
    table.remove(self.tQueuedData, 1)
    local t = {
      player = tMessage.player
    }

    ChatSystemLib.Command("/g " .. tMessage.msg)
    if (tMessage.type == "salutation") then
      if self.commChannel ~= nil then
        self.commChannel:SendMessage(t)
      end
    end
  else
    Apollo.StopTimer("GreetTimer")
  end
end

function GuildAutoGreeter:IncrPlayerGreeting(strPlayer)
  if 	self.playersGreeted[strPlayer] == nil then
    self.playersGreeted[strPlayer] = 1
  else
    self.playersGreeted[strPlayer] = self.playersGreeted[strPlayer] + 1
  end
end

function GuildAutoGreeter:OnChatMessage(channelCurrent, tMessage)
  --tMessage has bAutoResponse, bGM, bSelf, strSender, strRealmName, nPresenceState, arMessageSegments, unitSource, bShowChatBubble, bCrossFaction, nReportId
  -- arMessageSegments is an array of tables.  Each table representsa part of the message + the formatting for that segment.
  -- This allows us to signal font (alien text for example) changes mid stream.
  -- local example = arMessageSegments[1]
  -- example.strText is the text

  -- If the addon is enabled

  if self.config.enabled == true then
    if FriendshipLib.GetPersonalStatus() ~= FriendshipLib.AccountPresenceState_Away	 then
      if channelCurrent:GetType() == 15 then --guild
        text = tMessage.arMessageSegments[1].strText
        splitText = text:split(" ")
        playerName = splitText[1]

        -- Guild Join Message
        if self.config.welcome == true then
          if splitText[3] == "joined" then
            if self.strJoinedMessage ~= "" and self.strJoinedMessage ~= nil then
              local tSplitMessages = string.split(self.strJoinedMessage, "\n")
              local count = #tSplitMessages
              local idx = math.random(count)
              local t = {
                msg = string.gsub(tSplitMessages[idx], "{player}", playerName),
                type = "welcome",
                player = playerName
              }
              table.insert(self.tQueuedData, t)
              Apollo.StartTimer("GreetTimer")
            end
          end
        end

        -- Guild Online Message
        if self.config.salutation == true then
          if splitText[4] == "online." then
            if self.strSalutationMessage ~= "" and self.strSalutationMessage ~= nil then
              -- Only Greet if other people's greetings haven't crossed the threshold
              if self.playersGreeted[playerName] == nil or self.playersGreeted[playerName] < self.config.greetingThreshold then
                -- Only Greet if you haven't greeted once.
                if self.playersGreetedSelf[player] == nil then
                  local tSplitMessages = string.split(self.strSalutationMessage, "\n")
                  local count = #tSplitMessages
                  local idx = math.random(count)
                  local t = {
                    msg = string.gsub(string.sub(tSplitMessages[idx],1,100), "{player}", playerName),
                    type = "salutation",
                    player = playerName
                  }
                  self.playersGreetedSelf[playerName] = true
                  table.insert(self.tQueuedData, t)
                  Apollo.StartTimer("GreetTimer")
                end
              end
            end
          end
        end
      end
    end
  end
end

function GuildAutoGreeter:OnInterfaceMenuListHasLoaded()
  Event_FireGenericEvent("InterfaceMenuList_NewAddOn", "GuildAutoGreeter", {"Generic_ToggleGuildAutoGreeter", "", "CRB_Basekit:kitIcon_Holo_Social"})

  self.playerUnit = GameLib.GetPlayerUnit()
  self.strPlayerGuild = self.playerUnit:GetGuildName()
  if self.strPlayerGuild ~= nil then
    self.strGuildChannelName = "AutoGreeter"
    self.commChannel = ICCommLib.JoinChannel(self.strGuildChannelName, ICCommLib.CodeEnumICCommChannelType.Guild, GuildLib.GetGuilds()[1])
    self.commChannel:SetReceivedMessageFunction("OnGreeterMessage", self)
    --self.commChannel:SetSendMessageResultFunction("OnGreeterMessage", self)
    --self.commChannel:SetJoinResultFunction("OnChannelJoin", self)
  else
    self.strGuildChannelName = ""
    self.commChannel = nil
  end
end

function GuildAutoGreeter:OnOK()
  wndGreeting = self.wndMain:FindChild("Greeting")
  wndSalutation = self.wndMain:FindChild("Salutation")
  self.strJoinedMessage = wndGreeting:GetText()
  self.strSalutationMessage = wndSalutation:GetText()
  self.state = false
  self.wndMain:Close()
end

function GuildAutoGreeter:OnCancel()
  self.state = false
  self.wndMain:Close()
end

function GuildAutoGreeter:OnSave(eLevel)
  if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character then
    return
    end

  local tSavedData = {
    addonConfigVersion = strAddonVersion,
    salutation = self.strSalutationMessage,
    welcome = self.strJoinedMessage,
    config = self.config
  }
  return tSavedData
end

function GuildAutoGreeter:OnRestore(eLevel, tSavedData)
  if eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character then
    return
  end
  if tSavedData.addonConfigVersion  == strAddonVersion then
    self.strJoinedMessage = tSavedData.welcome
    self.strSalutationMessage = tSavedData.salutation
    if tSavedData.config then
      self.config = shallowcopy(tSavedData.config)
    end
  end
end

function GuildAutoGreeter:OnSlashCommand(sCmd, sInput)
  local s = string.lower(sInput)
  if s == nil or s == "" or s == "help" then
    CPrint("GuildAutoGreeter")
    CPrint("Usage:  /autogreet <command>")
    CPrint("============================")
    CPrint("   options   Shows the addon options.")
    CPrint("   enable    Enables the addon (default)")
    CPrint("   disable   Disables the addon")
    CPrint("   clear     Clears the greeting cache")
    CPrint("   reset      Restore default settings")
  elseif s == "options" then
    self:OnGuildGreetOptions()
  elseif s == "enable" then
    self.config.enabled = true
    self:ApplySettings()
  elseif s == "disable" then
    self.config.enabled = false
    self:ApplySettings()
  elseif s == "clear" then
    self.config = shallowcopy(defaultSettings)
    self:ApplySettings()
  elseif s == "reset" then
    self.config = shallowcopy(defaultSettings)
    self:ApplySettings()
  end
end

function GuildAutoGreeter:ApplySettings()
  local wndGreeting = self.wndMain:FindChild("Greeting")
  local wndSalutation = self.wndMain:FindChild("Salutation")
  local wndEnbaledButton = self.wndMain:FindChild("EnabledButton")
  local wndWelcomeButton = self.wndMain:FindChild("WelcomeButton")
  local wndSalutationButton = self.wndMain:FindChild("SalutationButton")
  local wndSliderFrame = self.wndMain:FindChild("Threshold"):FindChild("ThresholdSliderFrame")
  local wndSlider = wndSliderFrame:FindChild("ThresholdSlider")
  local wndEditBox = wndSliderFrame:FindChild("ThresholdEditBox")

  wndGreeting:SetText(self.strJoinedMessage)
  wndSalutation:SetText(self.strSalutationMessage)
  wndEnbaledButton:SetCheck(self.config.enabled)
  wndWelcomeButton:SetCheck(self.config.welcome)
  wndSalutationButton:SetCheck(self.config.salutation)
  wndEditBox:SetText(tostring(self.config.greetingThreshold))
  wndSlider:SetValue(tonumber(self.config.greetingThreshold))
end

function GuildAutoGreeter:OnGuildGreetOptions()
  if self.state == false then
    self.state = true
    self:ApplySettings()
    self.wndMain:Show(self.state)
  else
    self.state = false
    self.wndMain:Show(self.state)
  end
end

---------------------------------------------------------------------------------------------------
-- GuildAutoGreeterForm Functions
---------------------------------------------------------------------------------------------------
function GuildAutoGreeter:OnClose( wndHandler, wndControl )
  self.state = false
end

function GuildAutoGreeter:OnEnableChecked( wndHandler, wndControl, eMouseButton )
  self.config.enabled = true
end

function GuildAutoGreeter:OnEnableUnchecked( wndHandler, wndControl, eMouseButton )
  self.config.enabled = false
end

function GuildAutoGreeter:OnWelcomeChecked( wndHandler, wndControl, eMouseButton )
  self.config.welcome = true
end

function GuildAutoGreeter:OnWelcomeUnchecked( wndHandler, wndControl, eMouseButton )
  self.config.welcome = false
end

function GuildAutoGreeter:OnSalutationChecked( wndHandler, wndControl, eMouseButton )
  self.config.salutation = true
end

function GuildAutoGreeter:OnSalutationUnchecked( wndHandler, wndControl, eMouseButton )
  self.config.salutation = false
end

function GuildAutoGreeter:OnOptionsSliderChanged(wndHandler, wndControl, fValue, fOldValue)
  local wndEditBox = wndControl:GetParent():FindChild("ThresholdEditBox")

  if wndEditBox then
    wndEditBox:SetText(tostring(math.floor(fValue)))
  end
  self.config.greetingThreshold = math.floor(fValue)
end


local GuildAutoGreeterInst = GuildAutoGreeter:new()
GuildAutoGreeterInst:Init()