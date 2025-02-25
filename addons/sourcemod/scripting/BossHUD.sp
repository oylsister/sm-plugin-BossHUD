#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <BossHP>
#include <loghelper>
#include <BossHUD>
#include <LagReducer>
#include <multicolors>

#define PLUGIN_VERSION "3.6"

#pragma newdecls required

#define MAX_TEXT_LENGTH	64

ConVar g_cVHudPosition, g_cVHudColor, g_cVHudSymbols;
ConVar g_cVDisplayType;
ConVar g_cVTopHitsPos, g_cVTopHitsColor, g_cVPlayersInTable;
ConVar g_cVStatsReward, g_cVBossHitMoney;
ConVar g_cVHudMinHealth, g_cVHudMaxHealth;
ConVar g_cVHudTimeout;
ConVar g_cVIgnoreFakeClients;
ConVar g_cVHudHealthPercentageSquares;

Handle g_hShowDmg = INVALID_HANDLE, g_hShowHealth = INVALID_HANDLE;
Handle g_hHudSync = INVALID_HANDLE, g_hHudTopHitsSync = INVALID_HANDLE;

StringMap g_smBossMap = null;
ArrayList g_aEntity = null;

bool g_bShowDmg[MAXPLAYERS + 1] =  { true, ... };
bool g_bShowHealth[MAXPLAYERS + 1] =  { true, ... };
bool g_bHudSymbols;

int g_iEntityId[MAXPLAYERS+1] = { -1, ... };
int g_iHudColor[3], g_iTopHitsColor[3];

float g_fHudPos[2], g_fTopHitsPos[2];

bool g_bLate = false;
bool g_bIsCSGO = false;

char g_sHUDText[256];
char g_sHUDTextSave[256];

bool g_bLastBossHudPrinted = true;
bool g_bLastHudPrinted = true;

float g_fTimeout = 0.5;

int g_iMinHealthDetect = 1000;
int g_iMaxHealthDetect = 100000;

DisplayType g_iDisplayType;

public Plugin myinfo = {
	name = "BossHUD",
	author = "AntiTeal, Cloud Strife, maxime1907",
	description = "Show the health of bosses and breakables",
	version = PLUGIN_VERSION,
	url = "antiteal.com"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bIsCSGO = (GetEngineVersion() == Engine_CSGO);
	g_bLate = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("sm_bhud_version", PLUGIN_VERSION, "BHud Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);

	g_hShowDmg = RegClientCookie("bhud_showdamage", "Enable/Disable show damage", CookieAccess_Private);
	g_hShowHealth = RegClientCookie("bhud_showhealth", "Enabled/Disable show health", CookieAccess_Private);

	SetCookieMenuItem(CookieMenu_BHud, INVALID_HANDLE, "BHud Settings");

	RegConsoleCmd("sm_bhud", Command_BHud, "Toggle BHud");

	RegAdminCmd("sm_currenthp", Command_CHP, ADMFLAG_GENERIC, "See Current HP");
	RegAdminCmd("sm_subtracthp", Command_SHP, ADMFLAG_GENERIC, "Subtract Current HP");
	RegAdminCmd("sm_addhp", Command_AHP, ADMFLAG_GENERIC, "Add Current HP");

	RegConsoleCmd("sm_showdamage", Command_ShowDamage, "Toggle seeing boss damages inflicted");
	RegConsoleCmd("sm_showdmg", Command_ShowDamage, "Toggle seeing boss damages inflicted");
	RegConsoleCmd("sm_showhealth", Command_ShowHealth, "Toggle seeing boss health");
	RegConsoleCmd("sm_showhp", Command_ShowHealth, "Toggle seeing boss health");

	HookEntityOutput("func_physbox", "OnHealthChanged", Hook_OnDamage);
	HookEntityOutput("func_physbox_multiplayer", "OnHealthChanged", Hook_OnDamage);
	HookEntityOutput("func_breakable", "OnHealthChanged", Hook_OnDamage);
	HookEntityOutput("math_counter", "OutValue", Hook_OnDamage);

	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Pre);
	HookEvent("round_end", Event_OnRoundEnd, EventHookMode_PostNoCopy);

	g_cVHudPosition = CreateConVar("sm_bhud_position", "-1.0 0.09", "The X and Y position for the hud.");
	g_cVHudColor = CreateConVar("sm_bhud_color", "255 0 0", "RGB color value for the hud.");
	g_cVHudSymbols = CreateConVar("sm_bhud_symbols", "0", "Determines whether >> and << are wrapped around the text.", _, true, 0.0, true, 1.0);
	g_cVHudHealthPercentageSquares = CreateConVar("sm_bhud_health_percentage_squares", "0", "Determines how much squares are displayed base on health percentage.", _, true, 0.0, true, 100.0);
	g_cVDisplayType = CreateConVar("sm_bhud_displaytype", "2", "Display type of HUD. (0 = center, 1 = game, 2 = hint)", _, true, 0.0, true, 2.0);
	g_cVHudMinHealth = CreateConVar("sm_bhud_health_min", "1000", "Determines what minimum hp entities should have to be detected.", _, true, 0.0, true, 1000000.0);
	g_cVHudMaxHealth = CreateConVar("sm_bhud_health_max", "100000", "Determines what maximum hp entities should have to be detected.", _, true, 0.0, true, 1000000.0);
	g_cVHudTimeout = CreateConVar("sm_bhud_timeout", "0.5", "Determines when the entity health is supposed to fade away when it doesnt change.", _, true, 0.0, true, 10.0);

	g_cVTopHitsPos = CreateConVar("sm_bhud_tophits_position", "0.02 0.3", "The X and Y position for the hud.");
	g_cVTopHitsColor = CreateConVar("sm_bhud_tophits_color", "255 255 0", "RGB color value for the hud.");
	g_cVPlayersInTable = CreateConVar("sm_bhud_tophits_players", "3", "Amount players on the top hits table", _, true, 1.0, true, 10.0);
	g_cVBossHitMoney = CreateConVar("sm_bhud_tophits_money", "1", "Enable/Disable payment of boss hits", _, true, 0.0, true, 1.0);
	g_cVStatsReward = CreateConVar("sm_bhud_tophits_reward", "0", "Enable/Disable give of the stats points.", _, true, 0.0, true, 1.0);
	g_cVIgnoreFakeClients = CreateConVar("sm_bhud_ignore_fakeclients", "1", "Enable/Disable not filtering fake clients.", _, true, 0.0, true, 1.0);

	g_cVHudMinHealth.AddChangeHook(OnConVarChange);
	g_cVHudMaxHealth.AddChangeHook(OnConVarChange);
	g_cVHudPosition.AddChangeHook(OnConVarChange);
	g_cVHudColor.AddChangeHook(OnConVarChange);
	g_cVHudSymbols.AddChangeHook(OnConVarChange);
	g_cVDisplayType.AddChangeHook(OnConVarChange);
	g_cVHudTimeout.AddChangeHook(OnConVarChange);
	g_cVTopHitsPos.AddChangeHook(OnConVarChange);
	g_cVTopHitsColor.AddChangeHook(OnConVarChange);

	AutoExecConfig(true);
	GetConVars();

	CleanupAndInit();

	// Late load
	if (g_bLate)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if(IsClientConnected(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
}

public void OnPluginEnd()
{
	// Late unload
	if (g_bLate)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if(IsClientConnected(i))
			{
				OnClientDisconnect(i);
			}
		}
	}

	Cleanup(true);
}

public void OnClientPutInServer(int client)
{
	if (AreClientCookiesCached(client))
		ReadClientCookies(client);
}

public void OnClientDisconnect(int client)
{
	SetClientCookies(client);
}

public void Event_OnRoundEnd(Handle event, const char[] name, bool dontBroadcast) 
{ 
	CleanupAndInit();
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	int dmg = -GetEventInt(event, "dmg_health");
	int hp = GetEventInt(event, "health") + dmg;

	if (IsValidClient(client, g_cVIgnoreFakeClients.BoolValue) && IsValidClient(attacker, g_cVIgnoreFakeClients.BoolValue))
	{
		if(GetClientTeam(client) == 2)
		{
			if(g_bShowHealth[attacker])
			{
				char szMessage[128] = "Dead";
				if(hp > 0) IntToString(hp, szMessage, sizeof(szMessage));
				Format(szMessage, sizeof(szMessage), "%N: %s", client, szMessage);
				SendHudMsg(attacker, szMessage, g_iDisplayType);
			}
			if(g_bShowDmg[attacker])
			{
				char szMessage[128];
				Format(szMessage, sizeof(szMessage), "%i HP", dmg);
				SendHudMsg(attacker, szMessage);
			}
		}
	}
}

public void OnConVarChange(ConVar convar, char[] oldValue, char[] newValue)
{
	GetConVars();
}

public void OnMapStart()
{
	CleanupAndInit();
}

public void OnMapEnd()
{
	Cleanup();
}

public void OnClientCookiesCached(int client)
{
	ReadClientCookies(client);
}

//  888b     d888 8888888888 888b    888 888     888
//  8888b   d8888 888        8888b   888 888     888
//  88888b.d88888 888        88888b  888 888     888
//  888Y88888P888 8888888    888Y88b 888 888     888
//  888 Y888P 888 888        888 Y88b888 888     888
//  888  Y8P  888 888        888  Y88888 888     888
//  888   "   888 888        888   Y8888 Y88b. .d88P
//  888       888 8888888888 888    Y888  "Y88888P"

public void DisplayCookieMenu(int client)
{
	Menu menu = new Menu(MenuHandler_BHud, MENU_ACTIONS_DEFAULT | MenuAction_DisplayItem);
	menu.ExitBackButton = true;
	menu.ExitButton = true;
	SetMenuTitle(menu, "Bhud Settings");
	AddMenuItem(menu, NULL_STRING, "Show damage ");
	AddMenuItem(menu, NULL_STRING, "Show health ");
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public void CookieMenu_BHud(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	switch(action)
	{
		case CookieMenuAction_SelectOption:
		{
			DisplayCookieMenu(client);
		}
	}
}

public int MenuHandler_BHud(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			if(param1 != MenuEnd_Selected)
				delete menu;
		}
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				ShowCookieMenu(param1);
		}
		case MenuAction_Select:
		{
			switch(param2)
			{
				case 0:
				{
					g_bShowDmg[param1] = !g_bShowDmg[param1];
				}
				case 1:
				{
					g_bShowHealth[param1] = !g_bShowHealth[param1];
				}
				default:return 0;
			}
			DisplayMenu(menu, param1, MENU_TIME_FOREVER);
		}
		case MenuAction_DisplayItem:
		{
			char buffer[32];
			switch(param2)
			{
				case 0:
				{
					Format(buffer, sizeof(buffer), "Show damage: %s", (g_bShowDmg[param1]) ? "Enabled":"Disabled");
				}
				case 1:
				{
					Format(buffer, sizeof(buffer), "Show health: %s", (g_bShowHealth[param1]) ? "Enabled":"Disabled");
				}
			}
			return RedrawMenuItem(buffer);
		}
	}
	return 0;
}


// ##     ##  #######   #######  ##    ##  ######  
// ##     ## ##     ## ##     ## ##   ##  ##    ## 
// ##     ## ##     ## ##     ## ##  ##   ##       
// ######### ##     ## ##     ## #####     ######  
// ##     ## ##     ## ##     ## ##  ##         ## 
// ##     ## ##     ## ##     ## ##   ##  ##    ## 
// ##     ##  #######   #######  ##    ##  ######  

public void Hook_OnDamage(const char[] output, int caller, int activator, float delay)
{
	if (!IsValidClient(activator, g_cVIgnoreFakeClients.BoolValue))
		return;

	CBoss boss;
	bool bIsBoss = BossHP_IsBossEnt(caller, boss);

	if (!bIsBoss)
	{
		for (int i = 0; i < g_aEntity.Length; i++)
		{
			CEntity _Entity = g_aEntity.Get(i);
			if (_Entity.iIndex == caller)
			{
				_Entity.bActive = true;
				_Entity.fLastHitTime = GetGameTime();
				break;
			}
		}
		g_iEntityId[activator] = caller;
	}
	else if (bIsBoss && !boss.dConfig.bIgnore)
	{
		char szBossName[64];
		BuildName(boss, szBossName, sizeof(szBossName));

		int iHits[MAXPLAYERS + 1];
		g_smBossMap.GetArray(szBossName, iHits, MAXPLAYERS + 1);
		iHits[activator]++;
		if(g_cVBossHitMoney.BoolValue)
		{
			int cash = GetClientMoney(activator);
			SetClientMoney(activator, ++cash);
		}
		g_smBossMap.SetArray(szBossName, iHits, MAXPLAYERS + 1, true);
		g_iEntityId[activator] = caller;
	}
	delete boss;
}

public void BossHP_OnBossInitialized(CBoss boss)
{
	if (boss.dConfig != INVALID_HANDLE && boss.dConfig.bIgnore)
		return;

	char szName[300];
	BuildName(boss, szName, sizeof(szName));

	int hits[MAXPLAYERS + 1] =  { 0, ... };
	g_smBossMap.SetArray(szName, hits, MAXPLAYERS + 1, false);
}

public void BossHP_OnBossDead(CBoss boss)
{
	if (boss.dConfig != INVALID_HANDLE && boss.dConfig.bIgnore)
		return;

	char szName[300];
	BuildName(boss, szName, sizeof(szName));

	int iHits[MAXPLAYERS + 1], iHits_Sorted[MAXPLAYERS + 1];
	g_smBossMap.GetArray(szName, iHits, MAXPLAYERS + 1);
	CopyArray(iHits_Sorted, MAXPLAYERS + 1, iHits, MAXPLAYERS + 1);
	g_smBossMap.Remove(szName);
	SortIntegers(iHits_Sorted, MAXPLAYERS + 1, Sort_Descending);

	int hitlen = GetHitArraySize(iHits, MAXPLAYERS + 1);

	if (hitlen <= 0)
		return;

	int players_in_table = GetConVarInt(g_cVPlayersInTable);
	int tophitlen = (players_in_table < hitlen) ? players_in_table:hitlen;
	int[] TopHits = new int[tophitlen];
	GetTopHits(TopHits, iHits, iHits_Sorted, tophitlen, MAXPLAYERS+1);

	int len = 300 + 128 * tophitlen;
	char[] szMessage = new char[len];
	BuildMessage(boss, TopHits, tophitlen, iHits, szMessage, len);

	SendHudMsgAll(szMessage, DISPLAY_GAME, g_hHudTopHitsSync, g_iTopHitsColor, g_fTopHitsPos, 4.0, 255, true);
	CPrintToChatAll("{yellow}%s", szMessage);

	if (g_cVStatsReward.BoolValue)
	{
		for (int i = 0; i < tophitlen; i++)
		{
			LogPlayerEvent(TopHits[i], "triggered", "top_boss_dmg");
		}
	}
}

public void BossHP_OnAllBossProcessStart()
{
	g_sHUDText[0] = 0;
}

public void BossHP_OnBossProcessed(CBoss _Boss, bool bHealthChanged, bool bShow)
{
	if (!bShow)
		return;

	CConfig _Config = _Boss.dConfig;
	float fLastChange = _Boss.fLastChange;
	int iBaseHealth = _Boss.iBaseHealth;
	int iHealth = _Boss.iHealth;
	float fTimeout = _Config.fTimeout;

	float fGameTime = GetGameTime();
	if (fTimeout < 0.0 || fGameTime - fLastChange < fTimeout)
	{
		char sFormat[MAX_TEXT_LENGTH];
		if(g_sHUDText[0])
		{
			sFormat[0] = '\n';
			_Config.GetName(sFormat[1], sizeof(sFormat) - 1);
		}
		else
			_Config.GetName(sFormat, sizeof(sFormat));

		int FormatLen = strlen(sFormat);
		sFormat[FormatLen++] = ':';
		sFormat[FormatLen++] = ' ';

		if (g_cVHudHealthPercentageSquares.IntValue > 1)
		{
			char sPercentText[MAX_TEXT_LENGTH];
			int iHPPercentage = RoundToFloor((float(iHealth)/float(iBaseHealth))*100.0);
			CreateHPIconPercent(iHPPercentage, g_cVHudHealthPercentageSquares.IntValue, sPercentText, MAX_TEXT_LENGTH);
			FormatLen += StrCat(sFormat, sizeof(sFormat), sPercentText);
		}
		else
			FormatLen += IntToString(iHealth, sFormat[FormatLen], sizeof(sFormat) - FormatLen);

		sFormat[FormatLen] = 0;

		StrCat(g_sHUDText, sizeof(g_sHUDText), sFormat);

		g_bLastBossHudPrinted = false;
	}
}

public void BossHP_OnAllBossProcessEnd()
{
	/*
	if (!g_bLastBossHudPrinted)
		g_bLastBossHudPrinted = true;
	*/
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "SDKHook_OnEntitySpawned") == FeatureStatus_Available)
		return;

	SDKHook(entity, SDKHook_SpawnPost, OnEntitySpawnedPost);
}

public void OnEntitySpawnedPost(int entity)
{
	if (!IsValidEntity(entity))
		return;

	// 1 frame later required to get some properties
	RequestFrame(ProcessEntitySpawned, entity);
}

public void OnEntitySpawned(int entity, const char[] classname)
{
	RequestFrame(ProcessEntitySpawned, entity);
}

public void OnEntityDestroyed(int entity)
{
	RequestFrame(ProcessEntityDestroyed, entity);

	if (CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "SDKHook_OnEntitySpawned") == FeatureStatus_Available)
		return;

	SDKUnhook(entity, SDKHook_SpawnPost, OnEntitySpawnedPost);
}

public void LagReducer_OnStartGameFrame()
{
	if (g_bLastBossHudPrinted)
		g_sHUDText[0] = 0;

	if (g_aEntity)
	{
		float fGameTime = GetGameTime();
		for (int i = 0; i < g_aEntity.Length; i++)
		{
			CEntity _Entity = g_aEntity.Get(i);
			if (_Entity.bActive)
			{
				int iHealth = GetEntityHealth(_Entity.iIndex, _Entity);

				_Entity.iHealth = iHealth;

				char szString[128];

				char szName[64];
				_Entity.GetName(szName, sizeof(szName));

				if (g_bHudSymbols)
					Format(szString, sizeof(szString), ">> %s: %i <<", szName, _Entity.iHealth);
				else
					Format(szString, sizeof(szString), "%s: %i", szName, _Entity.iHealth);

				if (g_sHUDText[0])
					StrCat(g_sHUDText, sizeof(g_sHUDText), "\n");
				StrCat(g_sHUDText, sizeof(g_sHUDText), szString);

				g_bLastHudPrinted = false;

				if (fGameTime - _Entity.fLastHitTime >= g_fTimeout)
					_Entity.bActive = false;
			}
		}
	}

	g_sHUDTextSave[0] = '\0';

	if (g_sHUDText[0] || !g_bLastHudPrinted)
	{
		if (!g_sHUDTextSave[0])
			g_sHUDTextSave = g_sHUDText;

		g_bLastHudPrinted = true;
		g_bLastBossHudPrinted = true;
	}
}

public void LagReducer_OnClientGameFrame(int iClient)
{
	if (g_sHUDTextSave[0] && IsValidClient(iClient) && g_bShowHealth[iClient])
	{
		if (IsValidClient(iClient) && g_bShowHealth[iClient])
			SendHudMsg(iClient, g_sHUDTextSave, g_iDisplayType, INVALID_HANDLE, g_iHudColor, g_fHudPos, 3.0, 255);
	}
}

// ######## ##     ## ##    ##  ######  ######## ####  #######  ##    ##  ######  
// ##       ##     ## ###   ## ##    ##    ##     ##  ##     ## ###   ## ##    ## 
// ##       ##     ## ####  ## ##          ##     ##  ##     ## ####  ## ##       
// ######   ##     ## ## ## ## ##          ##     ##  ##     ## ## ## ##  ######  
// ##       ##     ## ##  #### ##          ##     ##  ##     ## ##  ####       ## 
// ##       ##     ## ##   ### ##    ##    ##     ##  ##     ## ##   ### ##    ## 
// ##        #######  ##    ##  ######     ##    ####  #######  ##    ##  ######

public void CreateHPIconPercent(int hpPercent, int squareCount, char[] sText, int iSize)
{
	if (squareCount <= 1)
		return;

	int i = 0;
	int howMuchHealthPerSquare = 100 / squareCount;
	while (i < squareCount)
	{
		if (hpPercent > 0)
		{
			StrCat(sText, iSize, "⬛");
			hpPercent = hpPercent - howMuchHealthPerSquare;
		}
		else
			StrCat(sText, iSize, "⬜");
		i++;
	}
}

public void ColorStringToArray(const char[] sColorString, int aColor[3])
{
	char asColors[4][4];
	ExplodeString(sColorString, " ", asColors, sizeof(asColors), sizeof(asColors[]));

	aColor[0] = StringToInt(asColors[0]);
	aColor[1] = StringToInt(asColors[1]);
	aColor[2] = StringToInt(asColors[2]);
}

public void GetConVars()
{
	char StringPos[2][8];
	char ColorValue[64];
	char PosValue[16];

	g_cVHudPosition.GetString(PosValue, sizeof(PosValue));
	ExplodeString(PosValue, " ", StringPos, sizeof(StringPos), sizeof(StringPos[]));

	g_fHudPos[0] = StringToFloat(StringPos[0]);
	g_fHudPos[1] = StringToFloat(StringPos[1]);

	g_cVTopHitsPos.GetString(PosValue, sizeof(PosValue));
	ExplodeString(PosValue, " ", StringPos, sizeof(StringPos), sizeof(StringPos[]));

	g_fTopHitsPos[0] = StringToFloat(StringPos[0]);
	g_fTopHitsPos[1] = StringToFloat(StringPos[1]);

	g_cVHudColor.GetString(ColorValue, sizeof(ColorValue));
	ColorStringToArray(ColorValue, g_iHudColor);

	g_cVTopHitsColor.GetString(ColorValue, sizeof(ColorValue));
	ColorStringToArray(ColorValue, g_iTopHitsColor);

	g_fTimeout = g_cVHudTimeout.FloatValue;

	g_bHudSymbols = g_cVHudSymbols.BoolValue;
	g_iDisplayType = view_as<DisplayType>(g_cVDisplayType.IntValue);

	g_iMinHealthDetect = g_cVHudMinHealth.IntValue;
	g_iMaxHealthDetect = g_cVHudMaxHealth.IntValue;
}

public void ReadClientCookies(int client)
{
	char sValue[8];

	GetClientCookie(client, g_hShowDmg, sValue, sizeof(sValue));
	g_bShowDmg[client] = (sValue[0] == '\0' ? true : StringToInt(sValue) == 1);

	GetClientCookie(client, g_hShowHealth, sValue, sizeof(sValue));
	g_bShowHealth[client] = (sValue[0] == '\0' ? true : StringToInt(sValue) == 1);
}

public void SetClientCookies(int client)
{
	char sValue[8];

	Format(sValue, sizeof(sValue), "%i", g_bShowDmg[client]);
	SetClientCookie(client, g_hShowDmg, sValue);

	Format(sValue, sizeof(sValue), "%i", g_bShowHealth[client]);
	SetClientCookie(client, g_hShowHealth, sValue);
}

bool CEntityRemove(int entity)
{
	if (!g_aEntity)
		return false;

	for (int i = 0; i < g_aEntity.Length; i++)
	{
		CEntity _Entity = g_aEntity.Get(i);
		if (_Entity.iIndex == entity)
		{
			g_aEntity.Erase(i);
			i--;
			return true;
		}
	}

	return false;
}

void ProcessEntitySpawned(int entity)
{
	if (!IsValidEntity(entity))
		return;

	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));

	int iHealth = GetEntityHealth(entity);
	if (iHealth <= g_iMinHealthDetect || iHealth >= g_iMaxHealthDetect)
		return;

	char szName[64];
	GetEntityName(entity, szName);

	if (strlen(szName) == 0)
		Format(szName, sizeof(szName), "Health");

	if(StrEqual(classname, "math_counter"))
	{
		CEntity _Entity = new CEntity();
		_Entity.SetName(szName);
		_Entity.iIndex = entity;
		_Entity.iMaxHealth = RoundFloat(GetEntPropFloat(entity, Prop_Data, "m_flMax"));
		_Entity.iHealth = iHealth;

		g_aEntity.Push(_Entity);
	}
	else if (StrEqual(classname, "func_physbox") || StrEqual(classname, "func_physbox_multiplayer")
		|| StrEqual(classname, "func_breakable"))
	{
		CEntity _Entity = new CEntity();
		_Entity.SetName(szName);
		_Entity.iIndex = entity;
		_Entity.iHealth = iHealth;

		g_aEntity.Push(_Entity);
	}
}

void ProcessEntityDestroyed(int entity)
{
	if(IsValidEntity(entity))
	{
		char szName[64];
		GetEntityName(entity, szName);

		char classname[64];
		GetEntityClassname(entity, classname, sizeof(classname));

		if(StrEqual(classname, "math_counter") || StrEqual(classname, "func_physbox") 
			|| StrEqual(classname, "func_physbox_multiplayer") || StrEqual(classname, "func_breakable"))
		{
			CEntityRemove(entity);
		}
	}
}

public void CleanupAndInit()
{
	Cleanup();
	Init();
}

public void Init()
{
	g_aEntity = new ArrayList();
	g_smBossMap = CreateTrie();

	g_hHudSync = CreateHudSynchronizer();
	g_hHudTopHitsSync = CreateHudSynchronizer();
}

void Cleanup(bool bPluginEnd = false)
{
	if (g_aEntity != null)
	{
		for (int i = 0; i < g_aEntity.Length; i++)
		{
			CEntity _Entity = g_aEntity.Get(i);
			delete _Entity;
		}
		delete g_aEntity;
	}

	if (g_smBossMap != null)
	{
		g_smBossMap.Clear();
		delete g_smBossMap;
	}

	if (g_hHudSync != INVALID_HANDLE)
	{
		CloseHandle(g_hHudSync);
		g_hHudSync = INVALID_HANDLE;
	}
	if (g_hHudTopHitsSync != INVALID_HANDLE)
	{
		CloseHandle(g_hHudTopHitsSync);
		g_hHudTopHitsSync = INVALID_HANDLE;
	}

	if (bPluginEnd)
	{
		if (g_hShowDmg != INVALID_HANDLE)
		{
			CloseHandle(g_hShowDmg);
			g_hShowDmg = INVALID_HANDLE;
		}
		if (g_hShowHealth != INVALID_HANDLE)
		{
			CloseHandle(g_hShowHealth);
			g_hShowHealth = INVALID_HANDLE;
		}

		delete g_cVHudPosition;
		delete g_cVHudColor;
		delete g_cVHudSymbols;
		delete g_cVDisplayType;
		delete g_cVTopHitsPos;
		delete g_cVTopHitsColor;
		delete g_cVPlayersInTable;
		delete g_cVBossHitMoney;
		delete g_cVStatsReward;
	}
}

void GetEntityName(int entity, char szName[64])
{
	GetEntPropString(entity, Prop_Data, "m_iName", szName, sizeof(szName));
}

int GetEntityHealth(int entity, CEntity _Entity = null)
{
	int health = 0;

	if (!IsValidEntity(entity))
		return health;

	char szType[64];
	GetEntityClassname(entity, szType, sizeof(szType));

	if (StrEqual(szType, "math_counter", false))
	{
		static int offset = -1;
		if (offset == -1)
			offset = FindDataMapInfo(entity, "m_OutValue");

		health = RoundFloat(GetEntDataFloat(entity, offset));

		char szName[64];
		GetEntPropString(entity, Prop_Data, "m_iName", szName, sizeof(szName));

		if (_Entity == null && g_aEntity)
		{
			int i = 0;
			while (i < g_aEntity.Length)
			{
				_Entity = g_aEntity.Get(i);
				if (_Entity.iIndex == entity)
					break;
				i++;
			}
			if (i >= g_aEntity.Length)
				_Entity = null;
		}

		int max;
		if (_Entity != null && max != _Entity.iMaxHealth)
			health = RoundFloat(GetEntPropFloat(entity, Prop_Data, "m_flMax")) - health;
	}
	else
	{
		health = GetEntProp(entity, Prop_Data, "m_iHealth");
	}

	if (health < 0)
		health = 0;

	return health;
}

Action Timer_SendHudMsgAll(Handle timer, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	char szMessage[256];
	pack.ReadString(szMessage, sizeof(szMessage));

	DisplayType type = view_as<DisplayType>(pack.ReadCell());

	Handle hHudSync = pack.ReadCell();

	int amount = pack.ReadCell();
	int iColors[3];
	for (int i = 0; i < amount; i++)
		iColors[i] = pack.ReadCell();

	amount = pack.ReadCell();
	float fPosition[2];
	for (int i = 0; i < amount; i++)
		fPosition[i] = pack.ReadFloat();

	float fDuration = pack.ReadFloat();
	int iTransparency = pack.ReadCell();

	CloseHandle(pack);

	SendHudMsgAll(szMessage, type, hHudSync, iColors, fPosition, fDuration, iTransparency);

	KillTimer(timer);
	return Plugin_Stop;
}

void SendHudMsgAll(
	char[] szMessage,
	DisplayType type = DISPLAY_CENTER,
	Handle hHudSync = INVALID_HANDLE,
	int iColors[3] = g_iHudColor,
	float fPosition[2] = g_fHudPos,
	float fDuration = 3.0,
	int iTransparency = 255,
	bool bDelayFastPrint = false,
	bool bFilterClients = false
)
{
	if (bDelayFastPrint)
	{
		int currentTime = GetTime();

		static int lastTime = 0;
		static float fLastDuration = 0.0;

		int iLastDuration = RoundFloat(fLastDuration);

		if (lastTime + iLastDuration > currentTime)
		{
			DataPack pack = new DataPack();
			pack.WriteString(szMessage);
			pack.WriteCell(type);
			pack.WriteCell(hHudSync);

			pack.WriteCell(sizeof(iColors));
			for (int i = 0; i < sizeof(iColors); i++)
				pack.WriteCell(iColors[i]);

			pack.WriteCell(sizeof(fPosition));
			for (int i = 0; i < sizeof(fPosition); i++)
				pack.WriteFloat(fPosition[i]);

			pack.WriteFloat(fDuration);
			pack.WriteCell(iTransparency);

			float fWaitTime = float(lastTime + iLastDuration - currentTime);
			CreateTimer(fWaitTime, Timer_SendHudMsgAll, pack);

			fLastDuration = fWaitTime + fDuration;
			lastTime = currentTime;
			return;
		}

		fLastDuration = fDuration;
		lastTime = currentTime;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			if (bFilterClients && !g_bShowHealth[i])
				continue;
			SendHudMsg(i, szMessage, type, hHudSync, iColors, fPosition, fDuration, iTransparency);
		}
	}
}

void SendHudMsg(
	int client,
	char[] szMessage,
	DisplayType type = DISPLAY_CENTER,
	Handle hHudSync = INVALID_HANDLE,
	int iColors[3] = g_iHudColor,
	float fPosition[2] = g_fHudPos,
	float fDuration = 3.0,
	int iTransparency = 255
)
{
	if(type == DISPLAY_GAME)
	{
		if (hHudSync == INVALID_HANDLE)
			hHudSync = g_hHudSync;

		if (hHudSync != INVALID_HANDLE)
		{
			SetHudTextParams(fPosition[0], fPosition[1], fDuration, iColors[0], iColors[1], iColors[2], iTransparency, 0, 0.0, 0.0, 0.0);
			ClearSyncHud(client, hHudSync);
			ShowSyncHudText(client, hHudSync, "%s", szMessage);
		}
	}
	else if (type == DISPLAY_HINT && !IsVoteInProgress())
	{
		if (g_bIsCSGO)
		{
			int rgb;
			rgb |= ((g_iHudColor[0] & 0xFF) << 16);
			rgb |= ((g_iHudColor[1] & 0xFF) << 8 );
			rgb |= ((g_iHudColor[2] & 0xFF) << 0 );
			ReplaceString(szMessage, 256, "\n", "<br/>");
			PrintHintTextRGB(client, "<font color='#%06X'>%s</font>", rgb, szMessage);
		}
		else
		{
			PrintHintText(client, "%s", szMessage);
		}
	}
	else
	{
		if (g_bIsCSGO)
		{
			int rgb;
			rgb |= ((g_iHudColor[0] & 0xFF) << 16);
			rgb |= ((g_iHudColor[1] & 0xFF) << 8 );
			rgb |= ((g_iHudColor[2] & 0xFF) << 0 );
			ReplaceString(szMessage, 256, "\n", "<br/>");
			PrintCenterText(client, "<font color='#%06X'>%s</font>", rgb, szMessage);
		}
		else
			PrintCenterText(client, "%s", szMessage);
	}
}

stock void PrintHintTextRGB(int client, const char[] format, any ...)
{
	char buff[2048];
	VFormat(buff, sizeof(buff), format, 3);
	Format(buff, sizeof(buff), "</font>%s ", buff);

	for(int i = strlen(buff); i < sizeof(buff); i++)
	{
		buff[i] = ' ';
	}

	Handle hMessage = StartMessageOne("TextMsg", client, USERMSG_RELIABLE);
	
	if(hMessage != INVALID_HANDLE)
	{
		PbSetInt(hMessage, "msg_dst", 4);
		PbAddString(hMessage, "params", "#SFUI_ContractKillStart");
		PbAddString(hMessage, "params", buff);
		PbAddString(hMessage, "params", NULL_STRING);
		PbAddString(hMessage, "params", NULL_STRING);
		PbAddString(hMessage, "params", NULL_STRING);
		PbAddString(hMessage, "params", NULL_STRING);
		
		EndMessage();
	}
}

public void BuildName(CBoss boss, char[] szName, int maxlen)
{
	CConfig config = boss.dConfig;
	config.GetName(szName, maxlen);
	if(config.IsBreakable)
	{
		CBossBreakable _boss = view_as<CBossBreakable>(boss);
		Format(szName, maxlen, "%s%i", szName, _boss.iBreakableEnt);
	}
	else if(config.IsCounter)
	{
		CBossCounter _boss = view_as<CBossCounter>(boss);
		Format(szName, maxlen, "%s%i", szName, _boss.iCounterEnt);
	}
	else if(config.IsHPBar)
	{
		CBossHPBar _boss = view_as<CBossHPBar>(boss);
		Format(szName, maxlen, "%s%i", szName, _boss.iBackupEnt);
	}
}

public void GetTopHits(int[] TopHits, int[] iHits, int[] iHits_Sorted, int maxlen, int maxhitslen)
{
	for (int i = 0; i < maxlen && i < maxhitslen; i++)
	{
		for (int j = 1; j < maxhitslen; j++)
		{
			if (iHits_Sorted[i] == iHits[j])
			{
				int k = 0;
				while (k < i)
				{
					if (TopHits[k] == j)
						break;
					k++;
				}
				if (k >= i)
				{
					TopHits[i] = j;
					break;
				}
			}
		}
	}
}

public void CopyArray(int[] dest, int destlen, int[] source, int sourcelen)
{
	int len = (destlen < sourcelen) ? destlen:sourcelen;
	for (int i = 0; i < len; i++)
	{
		dest[i] = source[i];
	}
}

public int GetHitArraySize(int[] arr, int maxlen)
{
	int res = 0;
	for (int i = 0; i < maxlen; i++)
	{
		res += (arr[i] > 0) ? 1:0;
	}
	return res;
}

public void BuildMessage(CBoss boss, int[] TopHits, int tophitslen, int[] iHits, char[] szMessage, int len)
{
	char szName[256];
	
	boss.dConfig.GetName(szName, sizeof(szName));
	Format(szMessage, len, "BOSS HITS [%s]\n", szName);

	for (int i = 0; i < tophitslen; i++)
	{
		int client = TopHits[i];
		char tmp[142];

		char clientName[64];
		if (!IsValidClient(client) || !GetClientName(client, clientName, sizeof(clientName)))
			Format(clientName, sizeof(clientName), "Disconnected (#%d)", client);

		Format(tmp, sizeof(tmp), "%i. %s: %i hits\n", i + 1, clientName, iHits[client]);
		StrCat(szMessage, len, tmp);
	}
}

public int GetClientMoney(int client)
{
	if(IsValidClient(client))
		return GetEntProp(client, Prop_Send, "m_iAccount");
	return -1;
}

public bool SetClientMoney(int client, int money)
{
	if(IsValidClient(client))
	{
		SetEntProp(client, Prop_Send, "m_iAccount", money);
		return true;
	}
	return false;
}

bool IsValidClient(int client, bool nobots = true)
{
	if (client <= 0 || client > MaxClients || !IsClientConnected(client) || (nobots && IsFakeClient(client)))
	{
		return false;
	}
	return IsClientInGame(client);
}

//   .d8888b.   .d88888b.  888b     d888 888b     d888        d8888 888b    888 8888888b.   .d8888b.
//  d88P  Y88b d88P" "Y88b 8888b   d8888 8888b   d8888       d88888 8888b   888 888  "Y88b d88P  Y88b
//  888    888 888     888 88888b.d88888 88888b.d88888      d88P888 88888b  888 888    888 Y88b.
//  888        888     888 888Y88888P888 888Y88888P888     d88P 888 888Y88b 888 888    888  "Y888b.
//  888        888     888 888 Y888P 888 888 Y888P 888    d88P  888 888 Y88b888 888    888     "Y88b.
//  888    888 888     888 888  Y8P  888 888  Y8P  888   d88P   888 888  Y88888 888    888       "888
//  Y88b  d88P Y88b. .d88P 888   "   888 888   "   888  d8888888888 888   Y8888 888  .d88P Y88b  d88P
//   "Y8888P"   "Y88888P"  888       888 888       888 d88P     888 888    Y888 8888888P"   "Y8888P"
//

public Action Command_BHud(int client, int argc)
{
	DisplayCookieMenu(client);
	return Plugin_Handled;
}

public Action Command_ShowDamage(int client, int args)
{
	g_bShowDmg[client] = !g_bShowDmg[client];
	PrintToChat(client, "\x05[SM]\x01Show damage has been %s", (g_bShowDmg[client]) ? "enabled":"disabled");
	return Plugin_Handled;
}

public Action Command_ShowHealth(int client, int args)
{
	g_bShowHealth[client] = !g_bShowHealth[client];
	PrintToChat(client, "\x05[SM]\x01Show health has been %s", (g_bShowHealth[client]) ? "enabled":"disabled");
	return Plugin_Handled;
}

public Action Command_CHP(int client, int argc)
{
	if (!IsValidEntity(g_iEntityId[client]))
	{
		PrintToChat(client, "[SM] Current entity is invalid (id %i)", g_iEntityId[client]);
		return Plugin_Handled;
	}

	char szName[64], szType[64];
	GetEntityName(g_iEntityId[client], szName);
	GetEntityClassname(g_iEntityId[client], szType, sizeof(szType));

	int health = GetEntityHealth(g_iEntityId[client]);

	PrintToChat(client, "[SM] Entity %s %i (%s): %i HP", szName, g_iEntityId[client], szType, health);
	return Plugin_Handled;
}

public Action Command_SHP(int client, int argc)
{
	if(!IsValidEntity(g_iEntityId[client]))
	{
		PrintToChat(client, "[SM] Current entity is invalid (id %i)", g_iEntityId[client]);
		return Plugin_Handled;
	}

	if (argc < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_subtracthp <health>");
		return Plugin_Handled;
	}

	char arg[8];
	GetCmdArg(1, arg, sizeof(arg));

	int value = StringToInt(arg);

	int health = EntitySetHealth(client, g_iEntityId[client], value, false);

	PrintToChat(client, "[SM] %i health subtracted. (%i HP to %i HP)", value, health, health - value);

	return Plugin_Handled;
}

public Action Command_AHP(int client, int argc)
{
	if(!IsValidEntity(g_iEntityId[client]))
	{
		PrintToChat(client, "[SM] Current entity is invalid (id %i)", g_iEntityId[client]);
		return Plugin_Handled;
	}

	if (argc < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_addhp <health>");
		return Plugin_Handled;
	}

	char arg[8];
	GetCmdArg(1, arg, sizeof(arg));

	int value = StringToInt(arg);

	int health = EntitySetHealth(client, g_iEntityId[client], value);

	PrintToChat(client, "[SM] %i health added. (%i HP to %i HP)", value, health, health + value);

	return Plugin_Handled;
}

int EntitySetHealth(int client, int entity, int value, bool bAdd = true)
{
	int health = GetEntityHealth(entity);
	int max;

	char szType[64];
	GetEntityClassname(entity, szType, sizeof(szType));

	SetVariantInt(value);

	if(StrEqual(szType, "math_counter", false))
	{
		char sValue[64] = "Add";
		if (bAdd)
			sValue = "Subtract";

		bool foundAndApplied = false;
		if (g_aEntity)
		{
			for (int i = 0; i < g_aEntity.Length; i++)
			{
				CEntity _Entity = g_aEntity.Get(i);
				if (_Entity.iIndex == entity)
				{
					if (max != _Entity.iMaxHealth)
					{
						AcceptEntityInput(entity, sValue, client, client);
						foundAndApplied = true;
					}
				}
			}
		}

		if (!foundAndApplied)
			AcceptEntityInput(entity, sValue, client, client);
	}
	else
	{
		char sValue[64] = "RemoveHealth";
		if (bAdd)
			sValue = "AddHealth";

		AcceptEntityInput(entity, sValue, client, client);
	}
	return health;
}