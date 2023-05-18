print("BFE: Loading loadsavemenu_shared.lua from Better FrontEnd (UI) v1.0");

include( "SupportFunctions" );
include( "Colors") ;

----------------------------------------------------------------        
-- Shared code for the LoadGameMenu and the SaveGameMenu
----------------------------------------------------------------        

-- The menu type that is using the shared code.
LOAD_GAME = 1;
SAVE_GAME = 2;
PAUSE_INCREMENT = .18;

-- Global Constants
g_FileEntryInstanceManager	= InstanceManager:new("FileEntry", "InstanceRoot", Controls.FileListEntryStack );
g_DescriptionTextManager	= InstanceManager:new("DescriptionText", "Root", Controls.GameInfoStack );
g_DescriptionHeaderManager	= InstanceManager:new("DetailsHeader", "Root", Controls.GameInfoStack );
g_DescriptionItemManager	= InstanceManager:new("DetailsItem", "Root", Controls.GameInfoStack );

local m_GameModeDetailsIM	:table = InstanceManager:new("GameModeDetails", "Root", Controls.GameInfoStack );
local m_GameModeNameIM		:table = InstanceManager:new("GameModeName", "Root");

-- Global Variables
g_ShowCloudSaves = false;
g_ShowAutoSaves = false;
g_ShowOfficialOnly = false; -- 230518 #8
g_ShowTuner = 1; -- 230518 #8 '1' is All
g_MenuType = 0;
g_iSelectedFileEntry = -1;

g_CloudSaves = {};

g_FileList = {};
g_FileEntryInstanceList = {};
g_GameType = SaveTypes.SINGLE_PLAYER;
g_FileType = SaveFileTypes.GAME_STATE;

g_CurrentGameMetaData = nil

g_FilenameIsValid = false;

g_DontUpdateFileName = false;

g_SearchQuery = nil; -- 230411 search pattern

----------------------------------------------------------------        
-- debug routine - prints a table, and tables inside recursively (up to 3 levels)
----------------------------------------------------------------        
function dshowtable(tTable:table, iLevel:number)
	local level:number = 0;
	if iLevel ~= nil then level = iLevel; end
	for k,v in pairs(tTable) do
		if level == 0 then     print(                                   k, type(v), tostring(v));
		elseif level == 1 then print(                           ":...", k, type(v), tostring(v));
		else                   print(string.rep(":  ",level-1), ":...", k, type(v), tostring(v)); end
		if type(v) == "table" and level < 3 then dshowtable(v, level+1); end
	end
end

----------------------------------------------------------------        
-- File Name Handling
----------------------------------------------------------------

----------------------------------------------------------------
function ValidateFileName(text)

	if text == nil then
		return false;
	end

	local isAllWhiteSpace = true;
	for i = 1, #text, 1 do
		if (string.byte(text, i) ~= 32) then
			isAllWhiteSpace = false;
			break;
		end
	end
	
	if (isAllWhiteSpace) then
		return false;
	end

	-- don't allow % character
	for i = 1, #text, 1 do
		if string.byte(text, i) == 37 then
			return false;
		end
	end

	local invalidCharArray = { '\"', '<', '>', '|', '\b', '\0', '\t', '\n', '/', '\\', '*', '?', ':' };

	for i, ch in ipairs(invalidCharArray) do
		if (string.find(text, ch) ~= nil) then
			return false;
		end
	end

	-- don't allow control characters
	for i = 1, #text, 1 do
		if (string.byte(text, i) < 32) then
			return false;
		end
	end

	return true;
end

----------------------------------------------------------------        
-- File sort pulldown and related
----------------------------------------------------------------        
g_CurrentSort = nil;	-- The current sorting technique.

----------------------------------------------------------------        
function AlphabeticalSort( a, b )    
    return Locale.Compare(a.DisplayName, b.DisplayName) == -1;
end

----------------------------------------------------------------        
function ReverseAlphabeticalSort( a, b ) 
    return Locale.Compare(b.DisplayName, a.DisplayName) == -1;
end

----------------------------------------------------------------        
function SortByName(a, b)
	if(g_ShowAutoSaves) then
		return ReverseAlphabeticalSort(a,b);
	else
		return AlphabeticalSort(a,b);
	end 
end

----------------------------------------------------------------        
function SortByLastModified(a, b)
	if(a.LastModified == nil) then
        return false;
    elseif(b.LastModified == nil) then
        return true;
    elseif ( a.LastModified == b.LastModified ) then
		return SortByName(a,b);
	else
		return ( a.LastModified > b.LastModified );
	end
end

---------------------------------------------------------------------------
-- Sort By Pulldown setup
-- Must exist below callback function names
---------------------------------------------------------------------------
local m_sortOptions = {
	{"LOC_SORTBY_LASTMODIFIED", SortByLastModified, 1},
	{"LOC_SORTBY_NAME",			SortByName, 2},
};


---------------------------------------------------------------------------
function RefreshSortPulldown()
	if g_GameType == SaveTypes.WORLDBUILDER_MAP then
		sortStyle = Options.GetUserOption("Interface", "WorldBuilderMapBrowseSortDefault");
	else
		sortStyle = Options.GetUserOption("Interface", "SaveGameBrowseSortDefault");
	end

	-- Make sure it is valid
	if sortStyle ~= 1 and sortStyle ~= 2 then
		sortStyle = 1;
	end

	Controls.SortByPullDown:GetButton():LocalizeAndSetText(m_sortOptions[sortStyle][1]);
	g_CurrentSort = m_sortOptions[sortStyle][2];
end

---------------------------------------------------------------------------
function SetupSortPulldown()
	local sortByPulldown = Controls.SortByPullDown;
	sortByPulldown:ClearEntries();
	for i, v in ipairs(m_sortOptions) do
		local controlTable = {};
		sortByPulldown:BuildEntry( "InstanceOne", controlTable );
		controlTable.Button:LocalizeAndSetText(v[1]);
	
		controlTable.Button:RegisterCallback(Mouse.eLClick, function()
			sortByPulldown:GetButton():LocalizeAndSetText( v[1] );
			g_CurrentSort = v[2];
			-- Store the default
			if g_GameType == SaveTypes.WORLDBUILDER_MAP then
				Options.SetUserOption("Interface", "WorldBuilderMapBrowseSortDefault", v[3]);
			else
				Options.SetUserOption("Interface", "SaveGameBrowseSortDefault", v[3]);
			end

	        Options.SaveOptions();

			RebuildFileList();
		end);
	
	end
	sortByPulldown:CalculateInternals();

	RefreshSortPulldown();
end



---------------------------------------------------------------------------
-- Tuner Pulldown setup
-- Must exist below callback function names
---------------------------------------------------------------------------
local m_TunerOptions = {
	{"{LOC_LOADSAVE_TUNER_ACTIVE_TITLE} {LOC_OPTIONS_ALL_AUTOSAVES}", 1},
	{"{LOC_LOADSAVE_TUNER_ACTIVE_TITLE} {LOC_YES}", 2},
	{"{LOC_LOADSAVE_TUNER_ACTIVE_TITLE} {LOC_NO}",  3},
};


---------------------------------------------------------------------------
function RefreshTunerPulldown()
	--[[
	if g_GameType == SaveTypes.WORLDBUILDER_MAP then
		sortStyle = Options.GetUserOption("Interface", "WorldBuilderMapBrowseSortDefault");
	else
		sortStyle = Options.GetUserOption("Interface", "SaveGameBrowseSortDefault");
	end

	-- Make sure it is valid
	if sortStyle ~= 1 and sortStyle ~= 2 then
		sortStyle = 1;
	end
	--]]
	Controls.TunerPullDown:GetButton():LocalizeAndSetText(m_TunerOptions[g_ShowTuner][1]);
end

---------------------------------------------------------------------------
function SetupTunerPulldown()
	local tunerPulldown = Controls.TunerPullDown;
	tunerPulldown:ClearEntries();
	for i, v in ipairs(m_TunerOptions) do
		local controlTable = {};
		tunerPulldown:BuildEntry( "InstanceOne", controlTable );
		controlTable.Button:LocalizeAndSetText(v[1]);
	
		controlTable.Button:RegisterCallback(Mouse.eLClick, function()
			tunerPulldown:GetButton():LocalizeAndSetText( v[1] );
			g_ShowTuner = v[2];
			--[[
			-- Store the default
			if g_GameType == SaveTypes.WORLDBUILDER_MAP then
				Options.SetUserOption("Interface", "WorldBuilderMapBrowseSortDefault", v[3]);
			else
				Options.SetUserOption("Interface", "SaveGameBrowseSortDefault", v[3]);
			end
	        Options.SaveOptions();--]]
			RebuildFileList();
		end);
	
	end
	tunerPulldown:CalculateInternals();

	RefreshTunerPulldown();
end



----------------------------------------------------------------        
-- Directory Browse
----------------------------------------------------------------        

g_CurrentDirectoryPath = "";
g_CurrentDirectorySegments = {};

---------------------------------------------------------------------------
function ChangeDirectoryLevelTo(toLevel)

	g_CurrentDirectoryPath = UI.TruncatePathLevels(SaveLocations.LOCAL_STORAGE, g_CurrentDirectoryPath, toLevel);
	g_CurrentDirectorySegments = UI.GetPathLevels(SaveLocations.LOCAL_STORAGE, g_CurrentDirectoryPath);

	ContextPtr:RequestRefresh();
end

---------------------------------------------------------------------------
function ChangeDirectoryTo(newDirectory)

	if newDirectory ~= nil then
		g_CurrentDirectoryPath = newDirectory;
		g_CurrentDirectorySegments = UI.GetPathLevels(SaveLocations.LOCAL_STORAGE, g_CurrentDirectoryPath);

		ContextPtr:RequestRefresh();
	end
end

---------------------------------------------------------------------------
function ChangeVolumeTo(newVolume)

	if newVolume ~= nil then
		g_CurrentDirectoryPath = newVolume;
		g_CurrentDirectorySegments = UI.GetPathLevels(SaveLocations.LOCAL_STORAGE, g_CurrentDirectoryPath);

		ContextPtr:RequestRefresh();
	end
end

---------------------------------------------------------------------------
function InitializeDirectoryBrowsing()
	g_CurrentDirectoryPath = "";
	g_CurrentDirectorySegments = {};

	-- both load and save call this function on init, so clear this here
	g_DontUpdateFileName = false;
end

---------------------------------------------------------------------------
function SetupDirectoryBrowsePulldown()
	local directoryPullDown = Controls.DirectoryPullDown;
	if directoryPullDown ~= nil then
		directoryPullDown:ClearEntries();

		if g_ShowCloudSaves or ((g_GameType ~= SaveTypes.WORLDBUILDER_MAP) and (g_GameType ~= SaveTypes.TILED_MAP)) then
			-- Only have directory browsing for WorldBuilder Maps or Tiled map import
			directoryPullDown:SetHide(true);
		else
			directoryPullDown:SetHide(false);

			if g_CurrentDirectoryPath == nil or g_CurrentDirectoryPath == "" then
				g_CurrentDirectoryPath = UI.GetSaveLocationPath(SaveLocations.LOCAL_STORAGE, g_GameType, SaveLocationOptions.NO_OPTIONS, true);		-- Get the save location path, if applicable.  Note, passing true at the end is requesting the previously used directory.
				g_CurrentDirectorySegments = UI.GetPathLevels(SaveLocations.LOCAL_STORAGE, g_CurrentDirectoryPath);
			end
		
			local usingVolumeName = nil;

			if g_CurrentDirectorySegments ~= nil then
				local iEntryCount = #g_CurrentDirectorySegments;
				if iEntryCount > 0 then
					-- We are going to go back to front, so the last directory is at the top of the pulldown.
					for i = iEntryCount, 1, -1 do 
						local v = g_CurrentDirectorySegments[i];
						local controlTable = {};
						directoryPullDown:BuildEntry( "InstanceOne", controlTable );
						local displayName;
						if v.DisplayName ~= nil and v.DisplayName ~= "" then
							displayName = v.DisplayName;
						else
							displayName = v.SegmentName;
						end

						controlTable.Button:LocalizeAndSetText(displayName);
						controlTable.Button:RegisterCallback(Mouse.eLClick, function()
							ChangeDirectoryLevelTo(i);
							end);

						-- Set the top level button to the first one.
						if i == iEntryCount then
							directoryPullDown:GetButton():LocalizeAndSetText(displayName);
						end

						if i == 1 then
							usingVolumeName = v.SegmentName;
						end
					end
				end
			end

			-- Put the volume list after that

			if g_VolumeList == nil then
				g_VolumeList = UI.GetVolumes(SaveLocations.LOCAL_STORAGE);
			end

			if g_VolumeList ~= nil then
				local iEntryCount = #g_VolumeList;
				if iEntryCount > 0 then
					for i = 1, iEntryCount, 1 do 
						local v = g_VolumeList[i];
						if usingVolumeName == nil or usingVolumeName ~= v.VolumeName then
							local controlTable = {};
							directoryPullDown:BuildEntry( "InstanceOne", controlTable );
							local displayName;
							if v.DisplayName ~= nil and v.DisplayName ~= "" then
								controlTable.Button:LocalizeAndSetText(v.DisplayName);
							else
								controlTable.Button:SetText(v.VolumeName);		-- Assume the volume name doesn't need translation.
							end

							local volumeName = v.VolumeName
							controlTable.Button:RegisterCallback(Mouse.eLClick, function()
								ChangeVolumeTo(volumeName);
							end);
						end
					end
				end				
			end
		end
		directoryPullDown:CalculateInternals();
	end
end

----------------------------------------------------------------        
-- File List creation
----------------------------------------------------------------        

function UpdateGameType()
	-- Updates the gameType from the game configuration. 
	if(GameConfiguration.IsWorldBuilderEditor()) then
        if (MapConfiguration.GetScript() == "WBImport.lua") and (g_MenuType == LOAD_GAME) then
            g_GameType = SaveTypes.TILED_MAP;
        else
            g_GameType = SaveTypes.WORLDBUILDER_MAP;
        end
	else
		g_GameType = Network.GetGameConfigurationSaveType();
	end
	
	-- Setup the type of file we are working with, full game state or configuration
	g_FileType = SaveFileTypes.GAME_STATE;

	local params = ContextPtr:GetPopupParameters();
	if params ~= nil then
		local fileType = params:GetValue("FileType");
		if fileType ~= nil then
			-- Make sure it is one of the values we know how to deal with.
			if fileType == SaveFileTypes.GAME_STATE or fileType == SaveFileTypes.GAME_CONFIGURATION then
				g_FileType = fileType;
			end
		end
	end

	-- Set some strings that change whether this is a Game State or Configuration operation
	if (g_GameType == SaveTypes.WORLDBUILDER_MAP or g_GameType == SaveTypes.TILED_MAP) and g_FileType == SaveFileTypes.GAME_STATE then
		Controls.NoGames:LocalizeAndSetText( "{LOC_NO_SAVED_MAPS:upper}" );
	else
		if g_FileType == SaveFileTypes.GAME_CONFIGURATION then
			Controls.NoGames:LocalizeAndSetText( "{LOC_NO_SAVED_CONFIGS:upper}" );
		else
			Controls.NoGames:LocalizeAndSetText( "{LOC_NO_SAVED_GAMES:upper}" );				
		end
	end

	-- Update Title text
	if g_GameType == SaveTypes.WORLDBUILDER_MAP and g_FileType == SaveFileTypes.GAME_STATE then
		if g_MenuType == SAVE_GAME then
			Controls.WindowHeader:LocalizeAndSetText( "{LOC_SAVE_MAP_BUTTON:upper}" );
		else
			Controls.WindowHeader:LocalizeAndSetText( "{LOC_LOAD_MAP:upper}" );
		end
    elseif g_GameType == SaveTypes.TILED_MAP then
            Controls.WindowHeader:LocalizeAndSetText( "{LOC_LOAD_TILED:upper}" );
	elseif g_FileType == SaveFileTypes.GAME_CONFIGURATION then
		if g_MenuType == SAVE_GAME then
			Controls.WindowHeader:LocalizeAndSetText( "{LOC_SAVE_CONFIG:upper}" );
		else
			Controls.WindowHeader:LocalizeAndSetText( "{LOC_LOAD_CONFIG:upper}" );
		end
	else
		if g_MenuType == SAVE_GAME then
			Controls.WindowHeader:LocalizeAndSetText( "{LOC_SAVE_GAME:upper}" );
		else
			Controls.WindowHeader:LocalizeAndSetText( "{LOC_LOAD_GAME:upper}" );
		end
	end


end

----------------------------------------------------------------        
----------------------------------------------------------------
function GetDisplayName(entry:table)

	if entry.IsDirectory == nil or entry.IsDirectory == false then
		if entry.DisplayName ~= nil and #entry.DisplayName > 0 then
			return entry.DisplayName;
		else
			if entry.Location == SaveLocations.LOCAL_STORAGE then
				return Path.GetFileNameWithoutExtension(entry.Name);
			else
				return entry.Name;
			end
		end
	else
		return entry.Name;
	end
end

----------------------------------------------------------------
-- 230515 #5 Build a file tooltip
function GetFileToolTip(entry:table)
	if entry.IsDirectory then return "This is a directory"; end
	local tt: table = {};
	table.insert(tt, "Civilization: "..Locale.LookupBundle(entry.HostCivilizationName));
	table.insert(tt, "Leader: "..Locale.LookupBundle(entry.HostLeaderName));
	table.insert(tt, "Turn: "..tostring(entry.CurrentTurn));
	table.insert(tt, "Era: "..Locale.LookupBundle(entry.HostEraName));
	if entry.MapScriptName then table.insert(tt, "Map: "..Locale.LookupBundle(entry.MapScriptName));
	else                        table.insert(tt, "Map: (unknown)"); end
	table.insert(tt, "Size: "..Locale.LookupBundle(entry.MapSizeName));
	table.insert(tt, "Ruleset: "..Locale.LookupBundle(entry.RulesetName));
	table.insert(tt, "Difficulty: "..Locale.LookupBundle(entry.HostDifficultyName));
	table.insert(tt, "Speed: "..Locale.LookupBundle(entry.GameSpeedName));
	return table.concat(tt, "[NEWLINE]");
end

----------------------------------------------------------------        
----------------------------------------------------------------   
function UpdateActionButtonText(isDirectory)

	if isDirectory then
		Controls.ActionButton:LocalizeAndSetText("LOC_OPEN_DIRECTORY");
	else
		if g_GameType == SaveTypes.WORLDBUILDER_MAP then
			if g_MenuType == SAVE_GAME then
				Controls.ActionButton:LocalizeAndSetText( "LOC_SAVE_MAP_BUTTON" );
			else
				Controls.ActionButton:LocalizeAndSetText( "LOC_LOAD_MAP" );
			end
        elseif g_GameType == SaveTypes.TILED_MAP then
            Controls.ActionButton:LocalizeAndSetText( "LOC_LOAD_TILED" );
		else
			if g_FileType == SaveFileTypes.GAME_CONFIGURATION then
				if g_MenuType == SAVE_GAME then
					Controls.ActionButton:LocalizeAndSetText( "LOC_SAVE_CONFIG" );
				else
					Controls.ActionButton:LocalizeAndSetText( "LOC_LOAD_CONFIG" );
				end
			else
				if g_MenuType == SAVE_GAME then
					Controls.ActionButton:LocalizeAndSetText( "LOC_SAVE_GAME" );
				else
					Controls.ActionButton:LocalizeAndSetText( "LOC_LOAD_GAME" );
				end
			end
		end
	end
end

----------------------------------------------------------------        
----------------------------------------------------------------   
function DismissCurrentSelected()   
    if( g_iSelectedFileEntry ~= -1 ) then
		local fileEntryInstance = g_FileEntryInstanceList[ g_iSelectedFileEntry ];
		if fileEntryInstance ~= nil then
			fileEntryInstance.SelectionAnimAlpha:Reverse();
			fileEntryInstance.SelectionAnimSlide:Reverse();
		end
		g_iSelectedFileEntry = -1;
    end  
end

----------------------------------------------------------------        
----------------------------------------------------------------   
function SetSelected( index )
	
	if( index == -1) then
		Controls.NoSelectedFile:SetHide(false);
		Controls.SelectedFile:SetHide(true);
	else

		if( g_iSelectedFileEntry == index) then
			-- Already selected
			return;
		end

		Controls.NoSelectedFile:SetHide(true);
		Controls.SelectedFile:SetHide(false);
	end
	
	DismissCurrentSelected();

    g_iSelectedFileEntry = index;
    if( g_iSelectedFileEntry ~= -1 ) then

		local fileEntryInstance = g_FileEntryInstanceList[ g_iSelectedFileEntry ];
		if fileEntryInstance == nil then
			return;
		end

		fileEntryInstance.SelectionAnimAlpha:SetToBeginning();
		fileEntryInstance.SelectionAnimAlpha:Play();
		fileEntryInstance.SelectionAnimSlide:SetToBeginning();
		fileEntryInstance.SelectionAnimSlide:Play();

		local kSelectedFile = g_FileList[ g_iSelectedFileEntry ];
		if kSelectedFile == nil then
			return;
		end

		if kSelectedFile.IsDirectory then
			-- Selected a directory
			Controls.NoSelectedFile:SetHide(false);
			Controls.SelectedFile:SetHide(true);
			Controls.ActionButton:SetToolTipString(nil);
			Controls.ActionButton:SetDisabled(false);
			UpdateActionButtonText(true);
			Controls.Delete:SetHide( false );
		else
			-- Selected a save game
			local displayName = GetDisplayName(kSelectedFile); 

			local mods;

			-- Configuration files depend on the Enabled mods while other types depend on Required mods.
			if(g_FileType == SaveFileTypes.GAME_CONFIGURATION) then
				mods = kSelectedFile.EnabledMods or {};
			else 
				mods = kSelectedFile.RequiredMods or {};
			end

			local mod_errors = Modding.CheckRequirements(mods, g_GameType);
			local success = (mod_errors == nil or mod_errors.Success);

			-- Populate details of the save, include list of mod errors so the UI can reflect.
			PopulateInspectorData(kSelectedFile, displayName, mod_errors);

			if (g_MenuType == LOAD_GAME) then
				-- Assume the filename is valid when loading.
				g_FilenameIsValid = true;
			else
				g_FilenameIsValid = ValidateFileName(displayName);
			end

			UpdateActionButtonText(false);
			UpdateActionButtonState();
			Controls.Delete:SetHide( false );

			-- Presume there are no errors if the table is nil.
			Controls.ActionButton:SetDisabled(not success);
		end
	else
		if (g_MenuType == LOAD_GAME) then
			Controls.ActionButton:SetDisabled( true );
			Controls.ActionButton:SetToolTipString(nil);
			g_FilenameIsValid = false;
		end

		UpdateActionButtonText(false);
		UpdateActionButtonState();

		Controls.Delete:SetHide( true );
    end

	if g_GameType == SaveTypes.WORLDBUILDER_MAP or g_GameType == SaveTypes.TILED_MAP then
		Controls.GameDetailIconsArea:SetHide(true);
	else
		Controls.GameDetailIconsArea:SetHide(false);
	end
end

-- ===========================================================================
--	Create the default filename.
-- ===========================================================================
function CreateDefaultFileName( playerID:number, turnNumber:number )
	local displayTurnNumber :number = turnNumber;
	if GameCapabilities.HasCapability("CAPABILITY_DISPLAY_NORMALIZED_TURN") then
		displayTurnNumber = (displayTurnNumber - GameConfiguration.GetStartTurn()) + 1; -- Keep turns starting at 1.
	end
	local player		:object = Players[playerID];
	local playerConfig	:object = PlayerConfigurations[player:GetID()];
	local strDate		:string = Calendar.MakeYearStr(turnNumber);

	return Locale.ToUpper( Locale.Lookup(playerConfig:GetLeaderName())).." "..displayTurnNumber.. " ".. strDate;
end

-- ===========================================================================
function PopulateInspectorData(fileInfo, fileName, mod_errors)

	function LookupBundleOrText(value)
		if(value) then
			local text = Locale.LookupBundle(value);
			if(text == nil) then
				text = Locale.Lookup(value);
			end
			return text;
		end
	end

	local name = fileInfo.DisplayName or fileName;
	if(name ~= nil) then
		if not g_DontUpdateFileName then
			Controls.FileName:SetText(name);
		end
	else
		-- Set default file data for save game...
		local defaultFileName: string = "";
		if g_GameType == SaveTypes.WORLDBUILDER_MAP then
			-- For World Builder, use the last name
			defaultFileName = UI.GetLastSaveName();
		else
			if g_FileType == SaveFileTypes.GAME_STATE then
				local turnNumber	:number = Game.GetCurrentGameTurn();
				local localPlayer	:number = Game.GetLocalPlayer();
				if localPlayer ~= PlayerTypes.NONE and localPlayer ~= PlayerTypes.OBSERVER then
					defaultFileName = CreateDefaultFileName( localPlayer, turnNumber );
				end
				
			end
		end
		if not g_DontUpdateFileName then
			Controls.FileName:SetText(defaultFileName);
		end
	end
		
	-- Preview image
	local bHasPreview = g_FileType == SaveFileTypes.GAME_STATE and UI.ApplyFileQueryPreviewImage( g_LastFileQueryRequestID, fileInfo.Id, Controls.SavedMinimap);
	Controls.SavedMinimapContainer:SetShow(bHasPreview);
	Controls.SavedMinimap:SetShow(bHasPreview);
	Controls.NoMapDataLabel:SetHide(bHasPreview);

	local hostCivilizationName = LookupBundleOrText(fileInfo.HostCivilizationName);
	Controls.CivIcon:SetToolTipString(hostCivilizationName);
		
	local hostLeaderName = LookupBundleOrText(fileInfo.HostLeaderName);
	Controls.LeaderIcon:SetToolTipString(hostLeaderName);

	if (fileInfo.HostLeader ~= nil or fileInfo.HostCivilization ~= nil) then

		if (fileInfo.HostBackgroundColorValue ~= nil and fileInfo.HostForegroundColorValue ~= nil) then

			local m_secondaryColor = fileInfo.HostBackgroundColorValue;
			local m_primaryColor = fileInfo.HostForegroundColorValue;

			-- Icon colors
			Controls.CivIconBacking:SetColor(m_primaryColor);
			Controls.CivIcon:SetColor(m_secondaryColor);
		end

		if (fileInfo.HostLeader ~= nil) then
			if (not UI.ApplyFileQueryLeaderImage( g_LastFileQueryRequestID, fileInfo.Id, Controls.LeaderIcon)) then
				if(not Controls.LeaderIcon:SetIcon("ICON_"..fileInfo.HostLeader)) then
					Controls.LeaderIcon:SetIcon("ICON_LEADER_DEFAULT")
				end
			end
		else
			Controls.LeaderIcon:SetIcon("ICON_LEADER_DEFAULT")
		end

		if (fileInfo.HostCivilization ~= nil) then
			if (not UI.ApplyFileQueryCivImage( g_LastFileQueryRequestID, fileInfo.Id, Controls.CivIcon)) then
				if(not Controls.CivIcon:SetIcon("ICON_"..fileInfo.HostCivilization)) then
					Controls.CivIcon:SetIcon("ICON_CIVILIZATION_UNKNOWN")
				end
			end
		else
			Controls.CivIcon:SetIcon("ICON_CIVILIZATION_UNKNOWN")
		end
	else
		Controls.CivIconBacking:SetColorByName("LoadSaveGameInfoIconBackingBase");
		Controls.CivIcon:SetColorByName("White");			

		Controls.CivIcon:SetIcon("ICON_CIVILIZATION_UNKNOWN");
		Controls.LeaderIcon:SetIcon("ICON_LEADER_DEFAULT");
	end

	-- Difficulty
	local gameDifficulty = LookupBundleOrText(fileInfo.HostDifficultyName);
	Controls.GameDifficulty:SetToolTipString(gameDifficulty);
	if (fileInfo.HostDifficulty ~= nil) then
		if(not Controls.GameDifficulty:SetIcon("ICON_"..fileInfo.HostDifficulty)) then
			Controls.GameDifficulty:SetIcon("ICON_DIFFICULTY_SETTLER");
		end
	else
		Controls.GameDifficulty:SetIcon("ICON_DIFFICULTY_SETTLER");
	end

	-- Game speed
	local gameSpeedName = LookupBundleOrText(fileInfo.GameSpeedName);
	Controls.GameSpeed:SetToolTipString(gameSpeedName);

	if (fileInfo.GameSpeed ~= nil) then
		if(not Controls.GameSpeed:SetIcon("ICON_"..fileInfo.GameSpeed)) then
			Controls.GameSpeed:SetIcon("ICON_GAMESPEED_STANDARD");
		end
	else
		Controls.GameSpeed:SetIcon("ICON_GAMESPEED_STANDARD");
	end
		
	if (fileInfo.CurrentTurn ~= nil) then
		Controls.SelectedCurrentTurnLabel:LocalizeAndSetText("LOC_LOADSAVE_CURRENT_TURN", fileInfo.CurrentTurn);
	else
		Controls.SelectedCurrentTurnLabel:SetText("");
	end
	
	-- 230412 DisplaySaveTime uses format dependent on the game language
	-- change into European ISO 8601 i.e. YYYY-MM-DD hh:mm when 24-hour clock is used together with English
	if (fileInfo.DisplaySaveTime ~= nil) then
		if UserConfiguration.GetValue("ClockFormat") == 1 and Locale.GetCurrentLanguage().Type == "en_US" then
			-- 230412 actual save time is stored in SaveTime which is Unix epoch
			-- for start just do a text conversion which is much easier
			local m, d, y, h, n, t = string.match(fileInfo.DisplaySaveTime, "(%d+)/(%d+)/(%d+), (%d+):(%d+) (%a+)");
			Controls.SelectedTimeLabel:SetText(string.format("%d-%02d-%02d %d:%02d", tonumber(y)+2000, tonumber(m), tonumber(d), t == "PM" and tonumber(h)+12 or tonumber(h), tonumber(n)));
		else
			-- default behavior for other languages and 12-hour English
			Controls.SelectedTimeLabel:SetText(fileInfo.DisplaySaveTime);
		end
	else
		Controls.SelectedTimeLabel:SetText("");
	end

	local hostEraName : string = LookupBundleOrText(fileInfo.HostEraName);
	Controls.SelectedHostEraLabel:SetText(hostEraName);

	g_DescriptionTextManager:ResetInstances();
	g_DescriptionHeaderManager:ResetInstances();
	g_DescriptionItemManager:ResetInstances();

	m_GameModeNameIM:ResetInstances();
	m_GameModeDetailsIM:ResetInstances();

	optionsHeader = g_DescriptionHeaderManager:GetInstance();
	optionsHeader.HeadingTitle:LocalizeAndSetText("LOC_LOADSAVE_GAME_OPTIONS_HEADER_TITLE");
	
	if(fileInfo.RulesetName) then
		local rulesetName : string = LookupBundleOrText(fileInfo.RulesetName);
		if(rulesetName) then
			local item = g_DescriptionItemManager:GetInstance();
			item.Title:LocalizeAndSetText("LOC_LOADSAVE_GAME_OPTIONS_RULESET_TYPE_TITLE");
			item.Description:SetText(rulesetName);
		end
	end

	if(fileInfo.EnabledGameModes)then
		local enabledGameModeNames = Modding.GetGameModesFromConfigurationString(fileInfo.EnabledGameModes);
		if(#enabledGameModeNames > 0)then
			local uiGameModeInfo : table = m_GameModeDetailsIM:GetInstance();
			for k, v in ipairs(enabledGameModeNames)do
				local uiGameModeName : table = m_GameModeNameIM:GetInstance(uiGameModeInfo.GameModeNamesStack);
				uiGameModeName.Description:SetText(v.Name);
			end
		end
	end

	local mapScriptName = LookupBundleOrText(fileInfo.MapScriptName);
	if(mapScriptName) then
		local maptype : table = g_DescriptionItemManager:GetInstance();
		maptype.Title:LocalizeAndSetText("LOC_LOADSAVE_GAME_OPTIONS_MAP_TYPE_TITLE");
		maptype.Description:SetText(mapScriptName);
	end

	local mapSizeName = LookupBundleOrText(fileInfo.MapSizeName);
	if (mapSizeName) then
		local mapsize : table = g_DescriptionItemManager:GetInstance();
		mapsize.Title:LocalizeAndSetText("LOC_LOADSAVE_GAME_OPTIONS_MAP_SIZE_TITLE");
		mapsize.Description:SetText(mapSizeName);
	end

	if (fileInfo.SavedByVersion ~= nil) then
		local savedByVersion : table = g_DescriptionItemManager:GetInstance();
		savedByVersion.Title:LocalizeAndSetText("LOC_LOADSAVE_SAVED_BY_VERSION_TITLE");
		savedByVersion.Description:SetText(fileInfo.SavedByVersion);
	end

	if (fileInfo.TunerActive ~= nil and fileInfo.TunerActive == true) then
		local tunerActive : table = g_DescriptionItemManager:GetInstance();
		tunerActive.Title:LocalizeAndSetText("LOC_LOADSAVE_TUNER_ACTIVE_TITLE");
		tunerActive.Description:LocalizeAndSetText("LOC_YES_BUTTON");
	end

	-- advanced = g_DescriptionItemManager:GetInstance();
	-- advanced.Title:LocalizeAndSetText("LOC_LOADSAVE_GAME_OPTIONS_ADVANCED_TITLE");
	-- advanced.Description:SetText("Quick Combat[NEWLINE]Quick Movement[NEWLINE]No City Razing[NEWLINE]No Barbarians");

	-- List mods.
	local mods;

	-- Configuration files depend on the Enabled mods while other types depend on Required mods.
	if(g_FileType == SaveFileTypes.GAME_CONFIGURATION) then
		mods = fileInfo.EnabledMods or {};
	else 
		mods = fileInfo.RequiredMods or {};
	end

	local mod_titles = {};
	local dev_titles = {};

	for i,v in ipairs(mods) do
		local title;
			
		local mod_handle = Modding.GetModHandle(v.Id);
		if(mod_handle) then
			local mod_info = Modding.GetModInfo(mod_handle);
			title = Locale.Lookup(mod_info.Name);
		else
			title = Locale.LookupBundle(v.Title);
			if(title == nil or #title == 0) then
				title = Locale.Lookup(v.Title);
			end
		end
		local temp = mod_titles;
		if Modding.IsModOfficial(v.Id) then temp = dev_titles; end
		if(mod_errors and mod_errors[v.Id]) then
			table.insert(temp, "[ICON_BULLET] [COLOR_RED]" .. title .. "[ENDCOLOR]");
		else
			table.insert(temp, "[ICON_BULLET] " .. title);
		end
	end
	table.sort(mod_titles, function(a,b) return Locale.Compare(a,b) == -1 end);
	table.sort(dev_titles, function(a,b) return Locale.Compare(a,b) == -1 end);
	
	if(#mod_titles > 0) then		
		spacer = g_DescriptionTextManager:GetInstance();
		spacer.Text:SetText(" ");

		local header = g_DescriptionHeaderManager:GetInstance();
		header.HeadingTitle:LocalizeAndSetText("LOC_MULTIPLAYER_LOBBY_MODS_COMMUNITY");
		for i,v in ipairs(mod_titles) do
			local instance = g_DescriptionTextManager:GetInstance();
			instance.Text:SetText(v);	
		end
	end
	
	if(#dev_titles > 0) then		
		spacer = g_DescriptionTextManager:GetInstance();
		spacer.Text:SetText(" ");

		local header = g_DescriptionHeaderManager:GetInstance();
		header.HeadingTitle:LocalizeAndSetText("LOC_MULTIPLAYER_LOBBY_MODS_OFFICIAL");
		for i,v in ipairs(dev_titles) do
			local instance = g_DescriptionTextManager:GetInstance();
			instance.Text:SetText(v);	
		end
	end

	--Controls.SelectedGameInfoStack1:CalculateSize();
	--Controls.SelectedGameInfoStack1:ReprocessAnchoring();
	--Controls.SelectedGameInfoStack2:CalculateSize();
	--Controls.SelectedGameInfoStack2:ReprocessAnchoring();

	Controls.Root:CalculateVisibilityBox();
	Controls.Root:ReprocessAnchoring();

	Controls.SavedMinimap:SetSizeX(249);
	Controls.SavedMinimap:ReprocessAnchoring();
	Controls.SavedMinimapContainer:ReprocessAnchoring();

	Controls.InspectorTopAreaStack:CalculateSize();
	Controls.InspectorTopAreaStack:ReprocessAnchoring();

	--Controls.InspectorTopAreaGrid:DoAutoSize();
	--Controls.InspectorTopAreaGrid:ReprocessAnchoring();

	Controls.InspectorTopAreaGridContainer:DoAutoSize();
	Controls.InspectorTopAreaGridContainer:ReprocessAnchoring();

	Controls.InspectorTopAreaBox:DoAutoSize();
	Controls.InspectorTopAreaBox:ReprocessAnchoring();

	Controls.InspectorTopArea:DoAutoSize();
	Controls.InspectorTopArea:ReprocessAnchoring();

	Controls.GameInfoStack:CalculateSize();
	ResizeGameInfoScrollPanel();
	Controls.GameInfoScrollPanel:CalculateSize();
end

----------------------------------------------------------------   
function ResizeGameInfoScrollPanel()
	Controls.GameInfoScrollPanel:SetSizeY(Controls.SelectedFile:GetSizeY() - Controls.SelectedFileStack:GetSizeY());
end

----------------------------------------------------------------     
function BuildCascadingButtonList()

end

----------------------------------------------------------------     
-- Executes a function every frame so long as that function 
-- returns true.
----------------------------------------------------------------     
function UpdateOverTime(func)
	
end

----------------------------------------------------------------     
-- Returns an iterator function that will enumerate 'entries'
-- and execute 'per_entry_func' for each entry.  Each execution
-- will enumerate 'batch_count' entries or whatever is left.
-- After each batch, 'per_batch_func' will be executed.
-- When all entries are finished, post_process_func will be 
-- executed.
----------------------------------------------------------------   
function ProcessEntries(entries, batch_count, per_entry_func, per_batch_func, post_process_func)
	
	local it, a, i = ipairs(entries);

	return function()
		local num_processed = 0;
		repeat
			i,v = it(a, i);	
			if(v) then
				per_entry_func(v);
				num_processed = num_processed + 1;
			end
		until(v == nil or num_processed >= batch_count);
	
		if(per_batch_func) then per_batch_func(); end		

		if(v == nil and post_process_func) then post_process_func(); end

		return v ~= nil;
	end
end

--230518 #8 helper to find out if the file has community content required or not
function IsFileOfficialOnly(fileInfo: table)
	--print("IsFileOfficialOnly", fileInfo.Name);
	-- Configuration files depend on the Enabled mods while other types depend on Required mods.
	local mods: table = nil;
	if g_FileType == SaveFileTypes.GAME_CONFIGURATION then mods = fileInfo.EnabledMods or {};
	else                                                   mods = fileInfo.RequiredMods or {}; end
	-- Iterate thrugh all entries
	for i,v in ipairs(mods) do
		if not Modding.IsModOfficial(v.Id) then return false; end -- Community content found
	end
	return true;
end

function RebuildFileList()
	for i, v in ipairs(g_FileList) do
		if(v.IsQuicksave) then
			v.DisplayName = Locale.Lookup("LOC_LOADSAVE_QUICK_SAVE");
		else
			v.DisplayName = GetDisplayName(v); -- 230411 here is an actual name created
		end
		
		v.LastModified = UI.GetSaveGameModificationTimeRaw(v);
	end
	table.sort(g_FileList, g_CurrentSort);

	-- Destroying the instance, rather than resetting.
	-- This is needed because resetting only hides the instances, meaning SortChildren
	-- will sort the hidden instances, but the sort compare function in lua uses a parallel lua table (g_SortTable)
	-- which will be indexed only by the visible ones.
    g_FileEntryInstanceManager:DestroyInstances();
	local pauseAccumulator = PAUSE_INCREMENT;

	-- Predefine functions out of loop.
	function OnMouseEnter() UI.PlaySound("Main_Menu_Mouse_Over"); end

	function OnDoubleClick(i)
		SetSelected(i);
		OnActionButton();
	end
	
	g_FileEntryInstanceList = {}; -- 230411 to speed up use this table and just show on/off

	local instance_index = 1;
	function per_entry(entry)
		-- 230518 #8 apply filters here
		local filterOfficial: boolean = not g_ShowOfficialOnly or IsFileOfficialOnly(entry);
		local filterTuner: boolean = (g_ShowTuner == 1) or ( (g_ShowTuner == 2 and entry.TunerActive) or (g_ShowTuner == 3 and not entry.TunerActive) );
		if filterOfficial and filterTuner then
			-- 230515 #5 Here the entry table contains the file data
			local controlTable = g_FileEntryInstanceManager:GetInstance();
			g_FileEntryInstanceList[instance_index] = controlTable;
			TruncateString(controlTable.ButtonText, controlTable.Button:GetSizeX()-60, entry.DisplayName);
			controlTable.Button:SetVoid1( instance_index );
			controlTable.Button:RegisterCallback( Mouse.eMouseEnter, OnMouseEnter);
			controlTable.Button:RegisterCallback( Mouse.eLClick, SetSelected );
			controlTable.Button:RegisterCallback( Mouse.eLDblClick, OnDoubleClick);
			controlTable.Button:SetToolTipString( GetFileToolTip(entry) ); -- 230515 #5 File tooltip
		end -- if filter
		instance_index = instance_index + 1;
	end

	function per_batch()
		RefreshFileListWithFilter(); -- 230411 search bar
		Controls.FileListEntryStack:CalculateSize();
        Controls.ScrollPanel:SetScrollValue(0.0);
		Controls.ScrollPanel:CalculateSize();
		Controls.FileListEntryStack:ReprocessAnchoring();
	end

	function post_process()
		ContextPtr:ClearUpdate();
	end

	local iterator = ProcessEntries(g_FileList, 100, per_entry, per_batch, post_process);
	
	ContextPtr:SetUpdate(function() iterator(); end);	
	
	Controls.NoGames:SetHide( #g_FileList > 0 );
	
end

----------------------------------------------------------------        
function UpdateActionButtonState()

	-- Valid filename?
	local bIsValid = g_FilenameIsValid;

	local bWaitingForFileList = false;
	local bAtMaximumSaves = false;

	if (g_ShowCloudSaves) then
		-- If we are doing a cloud save, the file query for the cloud save must be complete.
		if (not UI.IsFileListQueryComplete(g_LastFileQueryRequestID)) then
			bIsValid = false;
			bWaitingForFileList = true;
		end

		if (g_MenuType == SAVE_GAME) then
			local gameFile = {};
			gameFile.Location = UI.GetDefaultCloudSaveLocation();
			gameFile.Type = g_GameType;

			if (UI.IsAtMaxSaveCount(gameFile)) then
				bIsValid = false;
				bAtMaximumSaves = true;
			end
		end
	end

	Controls.ActionButton:SetHide(false);
	if(not bIsValid) then
		-- Set the reason for the control being disabled.
		if (bWaitingForFileList) then
			Controls.ActionButton:SetToolTipString(Locale.Lookup("LOC_SAVE_WAITING_FOR_CLOUD_SAVE_LIST_TOOLTIP"));
		elseif (bAtMaximumSaves) then
			Controls.ActionButton:SetToolTipString(Locale.Lookup("LOC_SAVE_AT_MAXIMUM_CLOUD_SAVES_TOOLTIP"));
		elseif ((not g_FilenameIsValid) and (g_MenuType == SAVE_GAME)) then
			Controls.ActionButton:SetToolTipString(Locale.Lookup("LOC_SAVE_INVALID_FILE_NAME_TOOLTIP"));
		else
			Controls.ActionButton:SetToolTipString(nil);
		end

		Controls.ActionButton:SetDisabled(true);
	else
		Controls.ActionButton:SetToolTipString(nil);
		Controls.ActionButton:SetDisabled(false);
	end	
end

g_LastFileQueryRequestID = 0;

----------------------------------------------------------------        
-- Can we show cloud saves?
function CanShowCloudSaves()

	if (not UI.IsFileListQueryComplete(g_LastFileQueryRequestID)) then
		return false;
	end

	return true;
end

----------------------------------------------------------------        
function SetupFileList()

	g_iSelectedFileEntry = -1;

	if(g_MenuType == SAVE_GAME) then
		Controls.NoSelectedFile:SetHide(true);
		Controls.SelectedFile:SetHide(false);
		if (g_CurrentGameMetaData == nil) then
			g_CurrentGameMetaData = UI.MakeSaveGameMetaData(g_FileType);
		end

		if (g_CurrentGameMetaData ~= nil and g_CurrentGameMetaData[1] ~= nil) then
			PopulateInspectorData(g_CurrentGameMetaData[1]);
		end
		UpdateActionButtonText(false);
	else
		SetSelected( -1 );
		UpdateActionButtonText(false);
	end
    -- build a table of all save file names that we found
    g_FileList = {};
    g_InstanceList = {};
    	
	local saveLocation = SaveLocations.LOCAL_STORAGE;
    if (g_ShowCloudSaves) then
		saveLocation = UI.GetDefaultCloudSaveLocation();
    end

	-- Query for the files, this is asynchronous

	UI.CloseFileListQuery( g_LastFileQueryRequestID );

	local saveLocationOptions = SaveLocationOptions.NO_OPTIONS;
	if (g_ShowAutoSaves) then
		saveLocationOptions = SaveLocationOptions.AUTOSAVE;
	else
		-- Don't include quick saves when saving, but do when loading.
		if(g_MenuType == SAVE_GAME) then
			saveLocationOptions = SaveLocationOptions.NORMAL;
		else
			saveLocationOptions = SaveLocationOptions.NORMAL + SaveLocationOptions.QUICKSAVE;
		end
	end

	if ((g_GameType == SaveTypes.WORLDBUILDER_MAP) or (g_GameType == SaveTypes.TILED_MAP)) then
		saveLocationOptions = SaveLocationOptions.DIRECTORIES;
	end

	saveLocationOptions = saveLocationOptions + SaveLocationOptions.LOAD_METADATA;

	g_LastFileQueryRequestID = UI.QuerySaveGameList( saveLocation, g_GameType, saveLocationOptions, g_FileType, g_CurrentDirectoryPath );
	
	RebuildFileList();	-- It will be empty at this time

end


--[[ g_FileList single entry example
LoadGameMenu: FileType	0
LoadGameMenu: MapScriptName	{"LOC_MAP_CONTINENTS":[{"locale":"en_US","text":"Continents"},{"locale":"fr_FR","text":"Continents"},{"locale":"de_DE","text":"Kontinente"},{"locale":"it_IT","text":"Continenti"},{"locale":"es_ES","text":"Continentes"},{"locale":"ja_JP","text":"大陸"},{"locale":"ru_RU","text":"Континенты"},{"locale":"pl_PL","text":"Kontynenty"},{"locale":"ko_KR","text":"대륙"},{"locale":"zh_Hant_HK","text":"大陸"},{"locale":"zh_Hans_CN","text":"大陆"},{"locale":"pt_BR","text":"Continentes"}]}
LoadGameMenu: CurrentTurn	121
LoadGameMenu: MapSizeName	{"LOC_MAPSIZE_SMALL_NAME":[{"locale":"en_US","text":"Small"},{"locale":"fr_FR","text":"Petite"},{"locale":"de_DE","text":"Klein"},{"locale":"it_IT","text":"Piccola"},{"locale":"es_ES","text":"Pequeño"},{"locale":"ja_JP","text":"小"},{"locale":"ru_RU","text":"Маленькая"},{"locale":"pl_PL","text":"Mała"},{"locale":"ko_KR","text":"소형"},{"locale":"zh_Hant_HK","text":"小"},{"locale":"zh_Hans_CN","text":"小"},{"locale":"pt_BR","text":"Pequeno"}]}
LoadGameMenu: HostCivilizationName	{"LOC_CIVILIZATION_MACEDON_NAME":[{"locale":"en_US","text":"Macedon"},{"locale":"fr_FR","text":"Macédoine","plurality":"1","gender":"feminine"},{"locale":"de_DE","text":"Makedonien|Makedonien|Makedonien|Makedoniens|Makedonien","plurality":"1","gender":"neuter:no_article"},{"locale":"it_IT","text":"Macedonia|della Macedonia|alla Macedonia|la Macedonia|dalla Macedonia","plurality":"1","gender":"feminine"},{"locale":"es_ES","text":"Macedonia","plurality":"1","gender":"feminine"},{"locale":"ja_JP","text":"マケドニア"},{"locale":"ru_RU","text":"Македония|Македонии|Македонии|Македонию|Македонией|Македонии","plurality":"1","gender":"feminine"},{"locale":"pl_PL","text":"Macedonia|Macedonii|Macedonii|Macedonię|Macedonią|Macedonii|Macedonia|Macedonii|Macedonii|Macedonię|Macedonią|Macedonii","plurality":"1","gender":"feminine"},{"locale":"ko_KR","text":"마케도니아"},{"locale":"zh_Hant_HK","text":"馬其頓"},{"locale":"zh_Hans_CN","text":"马其顿"},{"locale":"pt_BR","text":"Macedônia","plurality":"1","gender":"feminine"}]}
LoadGameMenu: RequiredMods	table: 000000001EB27BC0
LoadGameMenu: Slot	0
LoadGameMenu: HostEra	ERA_MEDIEVAL
LoadGameMenu: IsDirectory	false
LoadGameMenu: MapSize	MAPSIZE_SMALL
LoadGameMenu: SavedByVersion	1.0.12.41 (887696)
LoadGameMenu: EnabledMods	table: 000000001EB2C170
LoadGameMenu: DisplaySaveTime	3/29/23, 3:35 AM
LoadGameMenu: Name	ALEXANDER 121 med.Civ6Save
LoadGameMenu: Type	1
LoadGameMenu: GameSpeed	GAMESPEED_STANDARD
LoadGameMenu: RulesetName	{"LOC_EXPANSION2_NAME":[{"locale":"en_US","text":"Expansion: Gathering Storm"},{"locale":"fr_FR","text":"Extension : Gathering Storm"},{"locale":"de_DE","text":"Erweiterung: Gathering Storm"},{"locale":"it_IT","text":"Espansione: Gathering Storm"},{"locale":"es_ES","text":"Expansión: Gathering Storm"},{"locale":"ja_JP","text":"拡張パック: 嵐の訪れ"},{"locale":"ru_RU","text":"Дополнение: Gathering Storm"},{"locale":"pl_PL","text":"Rozszerzenie: Gathering Storm"},{"locale":"ko_KR","text":"확장팩: 몰려드는 폭풍"},{"locale":"zh_Hant_HK","text":"資料片：風雲際會"},{"locale":"zh_Hans_CN","text":"资料片：风云变幻"},{"locale":"pt_BR","text":"Expansão: Gathering Storm"}]}
LoadGameMenu: SaveTime	1680053745
LoadGameMenu: Ruleset	RULESET_EXPANSION_2
LoadGameMenu: GameSpeedName	{"LOC_GAMESPEED_STANDARD_NAME":[{"locale":"en_US","text":"Standard"},{"locale":"fr_FR","text":"Normale"},{"locale":"de_DE","text":"Standard"},{"locale":"it_IT","text":"Standard"},{"locale":"es_ES","text":"Estándar"},{"locale":"ja_JP","text":"標準"},{"locale":"ru_RU","text":"Стандартная"},{"locale":"pl_PL","text":"Zwykła"},{"locale":"ko_KR","text":"보통"},{"locale":"zh_Hant_HK","text":"標準"},{"locale":"zh_Hans_CN","text":"标准"},{"locale":"pt_BR","text":"Padrão"}]}
LoadGameMenu: Id	8
LoadGameMenu: EnabledGameModes	{
    "modes": [
        {
            "name": "{\"LOC_GAMEMODE_BARBARIAN_CLANS_NAME\":[{\"locale\":\"en_US\",\"text\":\"Barbarian Clans Mode\"},{\"locale\":\"fr_FR\",\"text\":\"Mode Clans barbares\"},{\"locale\":\"de_DE\",\"text\":\"Barbaren-Clans-Modus\"},{\"locale\":\"it_IT\",\"text\":\"Modalità Clan di barbari\"},{\"locale\":\"es_ES\",\"text\":\"Modo Clanes bárbaros\"},{\"locale\":\"ja_JP\",\"text\":\"「蛮族の部族」モード\"},{\"locale\":\"ru_RU\",\"text\":\"Режим «Варварские кланы»\"},{\"locale\":\"pl_PL\",\"text\":\"Tryb barbarzyńskich klanów\"},{\"locale\":\"ko_KR\",\"text\":\"야만인 부족 모드\"},{\"locale\":\"zh_Hant_HK\",\"text\":\"蠻族部族模式\"},{\"locale\":\"zh_Hans_CN\",\"text\":\"蛮族氏族模式\"},{\"locale\":\"pt_BR\",\"text\":\"Modo Clãs Bárbaros\"}]}"
        }
    ]
}
LoadGameMenu: HostCivilization	CIVILIZATION_MACEDON
LoadGameMenu: HostBackgroundColorValue	-16656137
LoadGameMenu: IsQuicksave	false
LoadGameMenu: IsPrevious	false
LoadGameMenu: HostEraName	{"LOC_ERA_MEDIEVAL_NAME":[{"locale":"en_US","text":"Medieval Era"},{"locale":"fr_FR","text":"Ère médiévale","plurality":"1","gender":"feminine:vowel"},{"locale":"de_DE","text":"Mittelalter|Mittelalter|Mittelalter|Mittelalters|Mittelalter","plurality":"1","gender":"neuter"},{"locale":"it_IT","text":"Epoca medievale"},{"locale":"es_ES","text":"Época Medieval","plurality":"1","gender":"feminine"},{"locale":"ja_JP","text":"中世"},{"locale":"ru_RU","text":"Средневековье|Средневековья|Средневековью|Средневековье|Средневековьем|Средневековье","plurality":"1","gender":"neuter"},{"locale":"pl_PL","text":"Średniowiecze|Średniowiecza|Średniowieczu|Średniowiecze|Średniowieczem|Średniowieczu|średniowiecze|średniowiecza|średniowieczu|średniowiecze|średniowieczem|średniowieczu","plurality":"1","gender":"neuter"},{"locale":"ko_KR","text":"중세 시대"},{"locale":"zh_Hant_HK","text":"中世紀"},{"locale":"zh_Hans_CN","text":"中世纪"},{"locale":"pt_BR","text":"Era Medieval","plurality":"1","gender":"feminine"}]}
LoadGameMenu: HostLeaderName	{"LOC_LEADER_ALEXANDER_NAME":[{"locale":"en_US","text":"Alexander"},{"locale":"fr_FR","text":"Alexandre","plurality":"1","gender":"masculine:no_article"},{"locale":"de_DE","text":"Alexander","plurality":"1","gender":"masculine:no_article"},{"locale":"it_IT","text":"Alessandro|di Alessandro|ad Alessandro|Alessandro|da Alessandro","plurality":"1","gender":"masculine"},{"locale":"es_ES","text":"Alejandro","plurality":"1","gender":"masculine"},{"locale":"ja_JP","text":"アレキサンドロス"},{"locale":"ru_RU","text":"Александр|Александра|Александру|Александра|Александром|Александре","plurality":"1","gender":"masculine"},{"locale":"pl_PL","text":"Aleksander|Aleksandra|Aleksandrowi|Aleksandra|Aleksandrem|Aleksandrze|Aleksander|Aleksandra|Aleksandrowi|Aleksandra|Aleksandrem|Aleksandrze","plurality":"1","gender":"masculine"},{"locale":"ko_KR","text":"알렉산더"},{"locale":"zh_Hant_HK","text":"亞歷山大"},{"locale":"zh_Hans_CN","text":"亚历山大"},{"locale":"pt_BR","text":"Alexandre","plurality":"1","gender":"masculine"}]}
LoadGameMenu: HostDifficultyName	{"LOC_DIFFICULTY_PRINCE_NAME":[{"locale":"en_US","text":"Prince"},{"locale":"fr_FR","text":"Prince"},{"locale":"de_DE","text":"Prinz"},{"locale":"it_IT","text":"Principe"},{"locale":"es_ES","text":"Príncipe","plurality":"1","gender":"masculine"},{"locale":"ja_JP","text":"王子"},{"locale":"ru_RU","text":"Князь|князя|князю|князя|князем|князе","plurality":"1","gender":"masculine"},{"locale":"pl_PL","text":"Książę|Księcia|Księciu|Księcia|Księciem|Księciu|książę|księcia|księciu|księcia|księciem|księciu","plurality":"1","gender":"masculine"},{"locale":"ko_KR","text":"왕자"},{"locale":"zh_Hant_HK","text":"王子"},{"locale":"zh_Hans_CN","text":"王子"},{"locale":"pt_BR","text":"Príncipe","plurality":"1","gender":"masculine"}]}
LoadGameMenu: HostDifficulty	DIFFICULTY_PRINCE
LoadGameMenu: Location	1
LoadGameMenu: HostForegroundColorValue	-5329234
LoadGameMenu: HostLeader	LEADER_ALEXANDER
LoadGameMenu: IsAutosave	false
LoadGameMenu: Path	D:/Users/Grzegorz/Documents/My Games/Sid Meier's Civilization VI/Saves/Single/ALEXANDER 121 med.Civ6Save
LoadGameMenu: AccountReference	0
LoadGameMenu: TunerActive true
--]]

----------------------------------------------------------------        
-- The callback for file queries
function OnFileListQueryResults( fileList : table, id : number )
	g_FileList = fileList;
	RebuildFileList();
	LuaEvents.FileListQueryComplete( id );
end

----------------------------------------------------------------        
-- This should be called by the show handler FIRST.
function LoadSaveMenu_OnShow()
	LuaEvents.FileListQueryResults.Add( OnFileListQueryResults );
	Controls.ScrollPanel:SetScrollValue(0);
end

----------------------------------------------------------------        
-- This should be called by the hide handler LAST.
function LoadSaveMenu_OnHide()
	LuaEvents.FileListQueryResults.Remove( OnFileListQueryResults );

	UI.CloseAllFileListQueries();

	g_FileEntryInstanceManager:DestroyInstances();
	g_FileEntryInstanceList = nil;
	g_iSelectedFileEntry = -1;
	g_FileList = nil;
	g_CurrentGameMetaData = nil;
	g_LastFileQueryRequestID = 0;
end

----------------------------------------------------------------        
function SetDontUpdateFileName( newValue )
	g_DontUpdateFileName = newValue;
end

----------------------------------------------------------------        
-- 230411 Search bar support

-- https://www.lua.org/pil/20.4.html
function nocase(s)
	return string.gsub(s, "%a",
		function (c)
			return string.format("[%s%s]", string.lower(c), string.upper(c))
		end)
end

function SearchBarStringChanged(str:string)
	local newSearch = nil;
	if str and string.len(str) > 1 then
		newSearch = nocase(str);
	end
	if newSearch ~= g_SearchQuery then
		g_SearchQuery = newSearch;
		RefreshFileListWithFilter();
	end
end

function RefreshFileListWithFilter()
	if g_FileEntryInstanceList == nil then return; end -- nothing to filter
	for idx,instance in pairs(g_FileEntryInstanceList) do
		if g_SearchQuery == nil
			or string.find(instance.ButtonText:GetText(), g_SearchQuery) ~= nil
			or string.find(instance.Button:GetToolTipString(), g_SearchQuery) ~= nil then -- 230515 #5 Search by various game parameters
			instance.InstanceRoot:SetShow(true);
		else
			instance.InstanceRoot:SetHide(true);
		end
	end
end

print("BFE: Loaded loadsavemenu_shared.lua");
