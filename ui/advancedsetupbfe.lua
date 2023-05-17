print("BFE: Loading advancedsetupbfe.lua from Better FrontEnd (UI) v1.0");

-- ===========================================================================
-- Better FrontEnd by Infixo
-- AdvancedSetup enhancements, created 2023-05-17
-- ===========================================================================

include("AdvancedSetup"); -- this will either load a vanilla game version or YnAMP's one

-- Check if YnAMP is enabled
local m_isYnAMP: boolean = (InitializeYnAMP ~= nil); -- Modding.IsModActive("36e88483-48fe-4545-b85f-bafc50dde315");
print("YnAMP:", m_isYnAMP and "YES" or "no");

local m_BasicTooltipData: table = {}; -- This is a local variable in the main file


-- ===========================================================================
-- CQUI full override
g_ParameterFactories["Ruleset"] = function(o, parameter)
	
	local drivers = {};
	-- Basic setup version.
	-- Use an explicit table.
	table.insert(drivers, CreatePulldownDriver(o, parameter, Controls.CreateGame_GameRuleset, Controls.CreateGame_RulesetContainer));
	-- 230515 #4 Attach an extra call to update search data when the ruleset is updated
	drivers[1].BaseUpdateValue = drivers[1].UpdateValue;
	drivers[1].UpdateValue = function (value)
		drivers[1].BaseUpdateValue(value); -- call the base function
		PopulateSearchData();
	end

	-- Advanced setup version.
	-- Create the parameter dynamically like we normally would...
	table.insert(drivers, GameParameters_UI_CreateParameterDriver(o, parameter));

	return drivers;
end

-- ===========================================================================
-- CQUI full override
g_ParameterFactories["Map"] = function(o, parameter)

	local drivers = {};

    if (m_WorldBuilderImport) then
        return drivers;
    end
	
	-- 230515 #3 Pulldown version
	table.insert(drivers, CreatePulldownDriver(o, parameter, Controls.CreateGame_MapType, Controls.CreateGame_MapTypeContainer));
	drivers[1].BaseUpdateValues = drivers[1].UpdateValues; -- store original pulldown function - it is quite complex
	drivers[1].UpdateValues = function(values)
		table.sort(values, SortMapsByName); -- add sorting before calling the actual update
		drivers[1].BaseUpdateValues(values);
	end

	-- Basic setup version.
	--table.insert(drivers, CreateSimpleMapPopupDriver(o, parameter) ); -- 230515 #3 not used anymore
	
	-- Advanced setup version.	
	table.insert( drivers, CreateButtonPopupDriver(o, parameter, OnMapSelect) );
	if m_isYnAMP then
		-- YNAMP <<<<<
		-- Restore pulldown menu for map selection
		--for k, v in pairs(parameter) do print(k, v) end
		if parameter.SortIndex then
			parameter.SortIndex = parameter.SortIndex + 1
		end
		table.insert(drivers, GameParameters_UI_CreateParameterDriver(o, parameter));
		-- YNAMP >>>>>
	end

	return drivers;
end

-- ===========================================================================
-- CQUI addition, 230517 #6

BASE_RefreshPlayerSlots = RefreshPlayerSlots;

function RefreshPlayerSlots()
	BASE_RefreshPlayerSlots();
	
	Controls.BasicTooltipContainer2:DestroyAllChildren();
	Controls.BasicPlacardContainer2:DestroyAllChildren();
	
	local basicTooltip: table = {};
	ContextPtr:BuildInstanceForControl( "CivToolTip", basicTooltip, Controls.BasicTooltipContainer2 );
	local basicPlacard: table = {};
	ContextPtr:BuildInstanceForControl( "LeaderPlacard", basicPlacard, Controls.BasicPlacardContainer2 );

	m_BasicTooltipData = {
		InfoStack			= basicTooltip.InfoStack,
		InfoScrollPanel		= basicTooltip.InfoScrollPanel;
		CivToolTipSlide		= basicTooltip.CivToolTipSlide;
		CivToolTipAlpha		= basicTooltip.CivToolTipAlpha;
		UniqueIconIM		= InstanceManager:new("IconInfoInstance",	"Top",	basicTooltip.InfoStack );		
		HeaderIconIM		= InstanceManager:new("IconInstance",		"Top",	basicTooltip.InfoStack );
		CivHeaderIconIM		= InstanceManager:new("CivIconInstance",	"Top",	basicTooltip.InfoStack );
		HeaderIM			= InstanceManager:new("HeaderInstance",		"Top",	basicTooltip.InfoStack );
		HasLeaderPlacard	= true;
		LeaderBG			= basicPlacard.LeaderBG;
		LeaderImage			= basicPlacard.LeaderImage;
		DummyImage			= basicPlacard.DummyImage;
		CivLeaderSlide		= basicPlacard.CivLeaderSlide;
		CivLeaderAlpha		= basicPlacard.CivLeaderAlpha;
	};
end


-- ===========================================================================
-- 230416 #4 Search feature; original code from Civilopedia
-- ===========================================================================

local LL = Locale.Lookup;
local LOC_TREE_SEARCH_W_DOTS = LL("LOC_TREE_SEARCH_W_DOTS");
local _SearchQuery = nil;
local _SearchResultsManager = InstanceManager:new("SearchResultInstance", "Root", Controls.SearchResultsStack);

-------------------------------------------------------------------------------
-- Indexes cached data into a search database.
-------------------------------------------------------------------------------

function PopulateSearchData()
	
	-- Populate Full Text Search
	local searchContext = "Leaders";
	if Search.HasContext(searchContext) then Search.DestroyContext(searchContext); end
	if not Search.CreateContext(searchContext, "[COLOR_LIGHTBLUE]", "[ENDCOLOR]", "...") then
		print("BFE: Failed to create a search context.");
		return;
	end
	
	OnSearchBarGainFocus(); -- hide any ongoing searches
	
	-- 230516 #4 Update the seach data with a proper ruleset
	local domain = "Players:StandardPlayers"; -- 250515 #4 Default ruleset
	if g_GameParameters then 
		local ruleset: string = g_GameParameters.Parameters.Ruleset.Value.Value; -- yes, 1st Value is a table and 2nd Value is the actual value
		-- maybe there is a programmatic way of getting this...
		local results: table = CachedQuery("SELECT Domain FROM RulesetDomainOverrides WHERE Ruleset = ? AND ParameterId = 'PlayerLeader' LIMIT 1", ruleset);
		if results and results[1] then domain = results[1].Domain; end
	end
	local info_query = "SELECT LeaderType FROM Players WHERE Domain = ?";
	local info_results = CachedQuery(info_query, domain);

	if not info_results then
		print("BFE: Failed to read Leaders from Players config table.");
		return;
	end

	for i,row in ipairs(info_results) do
		local info = GetPlayerInfo(domain, row.LeaderType);
		-- Fields: LeaderType, LeaderName, CivilizationName, Uniques[Name,Description], LeaderAbility[Name,Description], CivilizationAbility[Name,Description]
		local line1:string = string.format("%s (%s)", LL(info.LeaderName), LL(info.CivilizationName));
		local uniques:table = {};
		for _,item in ipairs(info.Uniques) do
			table.insert(uniques, LL(item.Name));
		end
		table.sort(uniques);
		local line2:string = table.concat(uniques, ", ");
		Search.AddData(searchContext, info.LeaderType, line1, line2);
		-- v[1] == LeaderType
		-- v[2] == Name and Civilization
		-- v[3] == Uniques
	end
	Search.Optimize(searchContext);
end

-------------------------------------------------------------------------------
-- UI callbacks
-------------------------------------------------------------------------------

function OnSearchBarGainFocus()
	Controls.SearchEditBox:ClearString();
	Controls.SearchResultsPanelContainer:SetHide(true);
end

function OnSearchCharCallback()
	local str = Controls.SearchEditBox:GetText();
	local has_found = {};
	if str ~= nil and #str > 0 and str ~= LOC_TREE_SEARCH_W_DOTS then
		_SearchQuery = str;
		local results = Search.Search("Leaders", str);
		_SearchResultsManager:DestroyInstances();
		if (results and #results > 0) then
			-- prepare parameter call
			local parameters = GetPlayerParameters(0); -- TODO: 0 is default for single player game, what about MP?
			
			-- 230517 #4 Update the seach data with a proper ruleset
			local domain = "Players:StandardPlayers"; -- 250515 #4 Default ruleset
			if g_GameParameters then 
				local ruleset: string = g_GameParameters.Parameters.Ruleset.Value.Value; -- yes, 1st Value is a table and 2nd Value is the actual value
				-- maybe there is a programmatic way of getting this...
				local results: table = CachedQuery("SELECT Domain FROM RulesetDomainOverrides WHERE Ruleset = ? AND ParameterId = 'PlayerLeader' LIMIT 1", ruleset);
				if results and results[1] then domain = results[1].Domain; end
			end
		
			for i, v in ipairs(results) do
				if has_found[v[1]] == nil then
					-- v[1] LeaderType
					-- v[2] Line1 leader & civ
					-- v[3] Line2 uniques
					local instance = _SearchResultsManager:GetInstance();
					local leaderParam:table = g_leaderParameters[v[1]];

					-- Search results already localized.
					if leaderParam then
						instance.Text:SetText(v[2].." "..leaderParam.VictoryIcons.."[NEWLINE]"..v[3]);
					else
						instance.Text:SetText(v[2].."[NEWLINE]"..v[3]);
					end
					
					local icons = GetPlayerIcons(domain, v[1]);
					instance.Icon:SetIcon(icons.LeaderIcon);
					
					if leaderParam then
						instance.Button:RegisterCallback(Mouse.eLClick, function() 
							Controls.SearchResultsPanelContainer:SetHide(true);
							_SearchQuery = nil;
							local parameter = parameters.Parameters["PlayerLeader"];
							parameters:SetParameterValue(parameter, leaderParam);
						end);
					end
					
					instance.Button:RegisterCallback( Mouse.eMouseEnter, function() 
						local info = GetPlayerInfo(domain, v[1]);
						DisplayCivLeaderToolTip(info, m_BasicTooltipData, false);
						Controls.BasicTooltipContainer2:SetHide(false);
						Controls.BasicPlacardContainer2:SetHide(false);
					end);
					
					instance.Button:RegisterCallback( Mouse.eMouseExit, function()
						DisplayCivLeaderToolTip(nil, m_BasicTooltipData, true); 
						Controls.BasicTooltipContainer2:SetHide(true);
						Controls.BasicPlacardContainer2:SetHide(true);
					end);
					
					has_found[v[1]] = true;
				end
			end

			Controls.SearchResultsStack:CalculateSize();
			Controls.SearchResultsStack:ReprocessAnchoring();
			Controls.SearchResultsPanel:CalculateSize();
			Controls.SearchResultsPanelContainer:SetHide(false);
		else
			Controls.SearchResultsPanelContainer:SetHide(true);
		end
	elseif(str == nil) then
		Controls.SearchResultsPanelContainer:SetHide(true);
	end
end

function OnSearchCommitCallback()
	if(_SearchQuery and #_SearchQuery > 0 and _SearchQuery ~= LOC_TREE_SEARCH_W_DOTS) then
		Controls.SearchEditBox:SetText(LOC_TREE_SEARCH_W_DOTS);
		OnOpenCivilopedia(_SearchQuery); -- open the first found result or just the start page if nothing found
		Controls.SearchResultsPanelContainer:SetHide(true);
		_SearchQuery = nil;	-- clear query.
	end
end

-- ===========================================================================
--
-- ===========================================================================
function InitializeBFE()
	-- 230515 #3 Open map selector when R-click on the pulldown
	Controls.CreateGame_MapType:GetButton():RegisterCallback( Mouse.eRClick, OnMapSelect )
	Controls.CreateGame_MapType:GetButton():RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	-- 230515 #3 The old button is hidden anyway
	Controls.MapSelectButton:ClearCallback( Mouse.eLClick );
	Controls.MapSelectButton:ClearCallback( Mouse.eMouseEnter );
	-- 230416 #4 Search feature
	Controls.SearchEditBox:RegisterStringChangedCallback(OnSearchCharCallback);
	Controls.SearchEditBox:RegisterHasFocusCallback(OnSearchBarGainFocus);
	Controls.SearchEditBox:RegisterCommitCallback(OnSearchCommitCallback); -- EditMode also automatically calls the commit callback when the EditBox loses focus.
end
InitializeBFE();

print("BFE: Loaded advancedsetup.lua");
